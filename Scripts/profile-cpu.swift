// Developer-only CPU measurements. No document content, AX access, or uploads.
// swift Scripts/profile-cpu.swift counters|trace PID [seconds]
import AppKit
import Darwin
import Foundation

enum CaptureError: Error, CustomStringConvertible {
    case invalidArguments
    case failed(String)

    var description: String {
        switch self {
        case .invalidArguments:
            "Usage: swift Scripts/profile-cpu.swift counters|trace PID [seconds: 2...300]\n       swift Scripts/profile-cpu.swift self-test"
        case let .failed(message): message
        }
    }
}

struct Usage {
    let user: UInt64
    let system: UInt64
    let wakeups: UInt64
    let started: UInt64

    init(pid: Int32) throws {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard result == 0 else { throw CaptureError.failed("Cannot read PID \(pid): \(String(cString: strerror(errno)))") }
        user = info.ri_user_time
        system = info.ri_system_time
        wakeups = info.ri_interrupt_wkups
        started = info.ri_proc_start_abstime
    }
}

struct Sample: Codable {
    let elapsedSeconds: Double
    let cpuMillisecondsPerSecond: Double
    let cpuPercentOfOneCore: Double
    let interruptWakeupsPerSecond: Double
    let foregroundBundleID: String?
}

func cpuRate(userDelta: UInt64, systemDelta: UInt64, seconds: Double, timebase: mach_timebase_info_data_t) -> Double {
    // proc_pid_rusage CPU times are Mach absolute ticks, not nanoseconds on Apple Silicon.
    (Double(userDelta) + Double(systemDelta)) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000 / seconds
}

struct Capture: Codable {
    let pid: Int32
    let startedAt: Date
    let osVersion: String
    let logicalCPUCount: Int
    let samples: [Sample]
}

func counters(pid: Int32, seconds: Int) throws {
    var timebase = mach_timebase_info_data_t()
    guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 else {
        throw CaptureError.failed("Cannot read Mach clock timebase")
    }
    let startedAt = Date()
    let start = ProcessInfo.processInfo.systemUptime
    var previousTime = start
    var previous = try Usage(pid: pid)
    var samples: [Sample] = []
    while previousTime - start < Double(seconds) {
        Thread.sleep(forTimeInterval: min(2, Double(seconds) - (previousTime - start)))
        let current = try Usage(pid: pid)
        let now = ProcessInfo.processInfo.systemUptime
        guard current.started == previous.started,
              current.user >= previous.user, current.system >= previous.system, current.wakeups >= previous.wakeups
        else { throw CaptureError.failed("Process restarted or counters moved backwards; discard this capture") }
        let interval = now - previousTime
        let rate = cpuRate(userDelta: current.user - previous.user, systemDelta: current.system - previous.system, seconds: interval, timebase: timebase)
        samples.append(Sample(elapsedSeconds: interval, cpuMillisecondsPerSecond: rate,
                              cpuPercentOfOneCore: rate / 10,
                              interruptWakeupsPerSecond: Double(current.wakeups - previous.wakeups) / interval,
                              foregroundBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier))
        previous = current
        previousTime = now
    }
    let capture = Capture(pid: pid, startedAt: startedAt, osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                          logicalCPUCount: ProcessInfo.processInfo.processorCount, samples: samples)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try FileHandle.standardOutput.write(encoder.encode(capture))
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func trace(pid: Int32, seconds: Int) throws {
    _ = try Usage(pid: pid)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("textwarden-profile-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let output = folder.appendingPathComponent("cpu.trace")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["xctrace", "record", "--template", "Time Profiler", "--instrument", "os_signpost",
                         "--attach", String(pid), "--time-limit", "\(seconds)s", "--output", output.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CaptureError.failed("Instruments recording failed. Check its permission prompt and Xcode installation. Partial capture: \(folder.path)")
    }
    print("Open in Instruments: \(output.path)")
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    if args == ["self-test"] {
        let base = mach_timebase_info_data_t(numer: 125, denom: 3)
        precondition(abs(cpuRate(userDelta: 12_000_000, systemDelta: 12_000_000, seconds: 2, timebase: base) - 500) < 0.001)
        precondition(cpuRate(userDelta: 0, systemDelta: 0, seconds: 2, timebase: base) == 0)
        _ = try Usage(pid: getpid())
        print("CPU counter conversion and process read passed")
    } else {
        guard (2 ... 3).contains(args.count), ["counters", "trace"].contains(args[0]),
              let pid = Int32(args[1]), pid > 0,
              let seconds = Int(args.count == 3 ? args[2] : "30"), (2 ... 300).contains(seconds)
        else { throw CaptureError.invalidArguments }
        if args[0] == "trace" { try trace(pid: pid, seconds: seconds) }
        else { try counters(pid: pid, seconds: seconds) }
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
