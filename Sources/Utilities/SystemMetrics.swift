// SystemMetrics.swift
// System resource monitoring using macOS Mach APIs

import Foundation
import Darwin.Mach

/// Utility for collecting system resource metrics using native macOS APIs
public enum SystemMetrics {

    // MARK: - Memory Monitoring

    /// Get current memory usage in bytes (physical footprint)
    /// Uses task_vm_info which matches Xcode's Debug Navigator
    public static func getMemoryUsage() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return 0
        }

        return info.phys_footprint
    }

    /// Get virtual memory size in bytes
    public static func getVirtualMemorySize() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return 0
        }

        return info.virtual_size
    }

    // MARK: - CPU Monitoring

    /// Get system load averages (1-minute, 5-minute, 15-minute)
    /// Returns the average number of processes in the run queue
    /// Similar to Unix top/uptime commands
    public static func getSystemLoadAverages() -> (load1m: Double, load5m: Double, load15m: Double) {
        var loadavg = [Double](repeating: 0, count: 3)

        // getloadavg returns the number of samples retrieved (should be 3)
        guard getloadavg(&loadavg, 3) == 3 else {
            return (0, 0, 0)
        }

        return (loadavg[0], loadavg[1], loadavg[2])
    }

    /// Get process-specific CPU load (number of active threads using CPU)
    /// This represents the process's contribution to system load
    public static func getProcessCPULoad() -> Double {
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        var activeThreads: Double = 0

        guard task_threads(mach_task_self_, &threadsList, &threadsCount) == KERN_SUCCESS else {
            return 0
        }

        if let threadsList = threadsList {
            for i in 0..<Int(threadsCount) {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)

                let result = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: Int(threadInfoCount)) {
                        thread_info(threadsList[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }

                if result == KERN_SUCCESS {
                    if threadInfo.flags & TH_FLAGS_IDLE == 0 {
                        let cpuUsage = Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE)
                        activeThreads += cpuUsage
                    }
                }
            }

            // Deallocate thread list
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: threadsList)),
                vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride)
            )
        }

        return activeThreads
    }

    // MARK: - Combined Snapshot

    /// Get a complete snapshot of current resource usage
    /// Returns process CPU load and system load averages
    public static func getResourceSnapshot() -> (
        processLoad: Double,
        systemLoad1m: Double,
        systemLoad5m: Double,
        systemLoad15m: Double,
        memory: UInt64,
        virtualMemory: UInt64
    ) {
        let loads = getSystemLoadAverages()
        return (
            processLoad: getProcessCPULoad(),
            systemLoad1m: loads.load1m,
            systemLoad5m: loads.load5m,
            systemLoad15m: loads.load15m,
            memory: getMemoryUsage(),
            virtualMemory: getVirtualMemorySize()
        )
    }
}
