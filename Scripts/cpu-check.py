#!/usr/bin/env python3
"""Local-only CPU regression gate. Native measurements; no dependencies or uploads."""

import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("e2e_state", ROOT / "Scripts/e2e-state.py")
STATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STATE)
TESTS = {"testQuoteShort", "testQuoteMedium", "testQuoteLarge", "testFilterFewErrors",
         "testFilterManyErrors", "testGrammarClean", "testGrammarManyErrors"}
SCENARIOS = {"short": (3, 1), "medium": (49, 1), "switches": (3, 1),
             "large-clean": (1300, 0), "large-errors": (0, 1300)}


class Inconclusive(Exception):
    pass


def run(*args, **kwargs):
    return subprocess.check_output(args, cwd=ROOT, text=True, **kwargs).strip()


def fixture(scenario):
    clean, errors = SCENARIOS[scenario]
    return ("This is a sentnce with a spelling mistke. " * errors
            + "We are reviewing the report tomorrow. " * clean).strip()


def environment():
    return {"machine": hashlib.sha256(platform.node().encode()).hexdigest(),
            "model": run("sysctl", "-n", "hw.model"), "arch": platform.machine(),
            "os": run("sw_vers", "-buildVersion"), "xcode": run("xcodebuild", "-version")}


def report(kind, settings):
    return {"schemaVersion": 1, "kind": kind, "environment": environment(),
            "capturedAt": time.time(),
            "revision": run("git", "rev-parse", "HEAD"),
            "dirty": bool(run("git", "status", "--porcelain")),
            "settings": settings, "results": {}}


def save(path, data):
    # Never silently accept a new baseline or overwrite existing evidence.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as stream:
        json.dump(data, stream, indent=2, allow_nan=False)
        stream.write("\n")


def read(path):
    if path.stat().st_size > 10_000_000:
        raise Inconclusive("oversized result file")
    with path.open() as stream:
        return json.load(stream)


def benchmark(output):
    output.mkdir(mode=0o700, parents=False, exist_ok=False)
    harness = hashlib.sha256((ROOT / "Tests/Performance/CPURegressionTests.swift").read_bytes()).hexdigest()
    result = report("benchmark", "release-v1-" + harness)
    bundle = output.resolve() / "benchmarks.xcresult"
    env = dict(os.environ, TEST_RUNNER_TEXTWARDEN_CPU_BENCHMARKS="1", CONFIGURATION="Release", CI="")
    with (output / "build.log").open("w") as log:
        # Xcode can skip its Rust phase when an earlier Debug archive is newer.
        subprocess.run([str(ROOT / "Scripts/build-rust.sh")], cwd=ROOT, env=env,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
        subprocess.run(["xcodebuild", "test", "-scheme", "TextWarden", "-configuration", "Release",
                        "-destination", "platform=macOS", "-parallel-testing-enabled", "NO", "ENABLE_TESTABILITY=YES",
                        "-enableCodeCoverage", "NO",
                        "-only-testing:TextWardenTests/CPURegressionTests", "-resultBundlePath", str(bundle)],
                       cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    metrics = json.loads(run("xcrun", "xcresulttool", "get", "test-results", "metrics", "--path", str(bundle)))
    result["results"] = benchmark_metrics(metrics)
    save(output / "benchmark.json", result)
    print(f"Recorded CPU benchmarks: {output / 'benchmark.json'}")


def benchmark_metrics(metrics):
    results = {}
    for test in metrics:
        name = test["testIdentifier"].split("/")[-1].removesuffix("()")
        if name not in TESTS:
            continue
        runs = test["testRuns"]
        if len(runs) != 1:
            raise Inconclusive("expected one device and one test configuration")
        for metric in runs[0]["metrics"]:
            if metric["displayName"] == "CPU Time":
                scale = {"s": 1000, "ms": 1}.get(metric["unitOfMeasurement"])
                if scale is None:
                    raise Inconclusive("unsupported CPU time unit")
                if name in results:
                    raise Inconclusive("duplicate CPU metrics")
                values = metric["measurements"]
                if len(values) != 5 or any(type(v) not in (int, float) or not math.isfinite(v) or v < 0 for v in values):
                    raise Inconclusive("expected five valid CPU measurements")
                results[name] = {"cpuMs": [v * scale for v in values]}
    if set(results) != TESTS:
        raise Inconclusive("CPU metrics missing; skipped tests are not a passing benchmark")
    return results


def check_state(snapshot, pid, scenario):
    if snapshot.get("schemaVersion") != 1 or snapshot.get("textWardenProcessID") != pid:
        raise Inconclusive("stale state or wrong TextWarden process")
    s = snapshot["state"]
    a, p = s["analysis"], s["presentation"]
    for key in ("activeApplication", "monitoredApplication"):
        if (s.get(key) or {}).get("bundleIdentifier") != "com.apple.mail":
            raise Inconclusive("Mail is not the active monitored application")
    if s["runtimeHealth"]["state"] != "active" or s["replacement"]["isApplying"]:
        raise Inconclusive("checking is inactive/recovering or a replacement is in flight")
    expected = SCENARIOS[scenario][1] * 2
    if a.get("segmentLength") != len(fixture(scenario)) or len(a["grammarErrors"]) != expected:
        raise Inconclusive("fixture length/error count does not match; wait for analysis or check settings")
    if any(p[k] for k in ("hiddenDueToMovement", "hiddenDueToScroll", "hiddenDueToWindowOffScreen",
                           "suggestionPopoverVisible", "readabilityPopoverVisible", "textGenerationPopoverVisible")):
        raise Inconclusive("UI is moving, suppressed, or a popover is open")
    if p["indicatorGrammarErrorCount"] != expected or (expected and not p["indicatorVisible"]):
        raise Inconclusive("error indicator is unavailable")
    if not expected and p["grammarUnderlineCount"] != 0:
        raise Inconclusive("stale underlines on clean text")
    if 0 < expected <= 10 and (p["grammarUnderlineCount"] != expected or not p["overlayVisible"] or p["overlayAlpha"] <= 0):
        raise Inconclusive("expected underlines are unavailable")
    identity = (s.get("monitoredElement") or {}).get("identity")
    if not identity:
        raise Inconclusive("no monitored field")
    return (a["generation"], identity)


def capture(args):
    if args.output.exists():
        raise Inconclusive("output already exists; choose a fresh evidence file")
    result = report("app", args.settings)
    result["scenario"] = args.scenario
    result["fixtureSHA256"] = hashlib.sha256(fixture(args.scenario).encode()).hexdigest()
    # Only activate apps; the operator owns draft preparation and visual verification.
    # No automatic text replacement, send action, preference changes, or app termination.
    with tempfile.TemporaryDirectory(prefix="textwarden-cpu-") as folder:
        driver, counter = Path(folder) / "driver", Path(folder) / "counter"
        for source, target in [("macos-e2e-driver.swift", driver), ("profile-cpu.swift", counter)]:
            run("swiftc", str(ROOT / "Scripts" / source), "-o", str(target))
        started = time.time()
        for _ in range(10 if args.scenario == "switches" else 1):
            run(str(driver), "activate", "com.apple.TextEdit")
            time.sleep(1)
            run(str(driver), "activate", "com.apple.mail")
            time.sleep(1)
        time.sleep(3)

        def state():
            snapshot = STATE.read_snapshot(args.state)
            STATE.validate_snapshot(args.state, snapshot)
            if not started * 1000 <= snapshot["capturedAt"] <= time.time() * 1000 + 1000:
                raise Inconclusive("state was not refreshed after activating Mail")
            return check_state(snapshot, args.pid, args.scenario)

        identity = state()
        cpu, wakeups = [], []
        executable = None
        for _ in range(3):
            with tempfile.TemporaryFile(mode="w+") as output:
                process = subprocess.Popen([str(counter), "counters", str(args.pid), "10"], stdout=output)
                try:
                    deadline = time.monotonic() + 20
                    while process.poll() is None:
                        if state() != identity:
                            raise Inconclusive("analysis generation or focused field changed during capture")
                        if time.monotonic() > deadline:
                            raise Inconclusive("counter capture timed out")
                        time.sleep(0.25)
                    if process.returncode:
                        raise Inconclusive("counter capture failed")
                    output.seek(0)
                    data = json.load(output)
                finally:
                    if process.poll() is None:
                        process.terminate()
                        process.wait(timeout=5)
            if state() != identity:
                raise Inconclusive("analysis changed at capture completion")
            if executable is not None and executable != data["executableSHA256"]:
                raise Inconclusive("executable changed between repeats")
            executable = data["executableSHA256"]
            samples = data["samples"]
            if any(s["foregroundBundleID"] != "com.apple.mail" or s["thermalState"] != 0 for s in samples):
                raise Inconclusive("focus changed or thermal state was not nominal")
            elapsed = sum(s["elapsedSeconds"] for s in samples)
            if not 9.5 <= elapsed <= 12:
                raise Inconclusive("unexpected measurement duration")
            cpu.append(sum(s["cpuPercentOfOneCore"] * s["elapsedSeconds"] for s in samples) / elapsed)
            wakeups.append(sum(s["interruptWakeupsPerSecond"] * s["elapsedSeconds"] for s in samples) / elapsed)
        result["executableSHA256"] = executable
        result["results"][args.scenario] = {"cpuPercent": cpu, "wakeupsPerSecond": wakeups}
    save(args.output, result)
    print(f"Recorded {args.scenario}: CPU {statistics.median(cpu):.2f}% of one core; {args.output}")


def series(values, floor):
    if not isinstance(values, list) or len(values) < 3 or any(
            type(v) not in (int, float) or not math.isfinite(v) or v < 0 for v in values):
        raise Inconclusive("need at least three finite nonnegative measurements")
    median = statistics.median(values)
    if max(values) - min(values) > max(floor, median * 0.5):
        raise Inconclusive("measurements are noisy; repeat under stable conditions")
    return median


def compare_reports(base, candidate):
    for key in ("schemaVersion", "kind", "environment", "settings", "scenario", "fixtureSHA256"):
        if base.get(key) != candidate.get(key) or (key in ("schemaVersion", "kind", "environment", "settings") and key not in base):
            raise Inconclusive(f"incompatible {key}")
    if base["schemaVersion"] != 1 or base["kind"] not in ("benchmark", "app"):
        raise Inconclusive("unsupported report")
    if set(base["environment"]) != {"machine", "model", "arch", "os", "xcode"} or not all(base["environment"].values()) or not base["settings"]:
        raise Inconclusive("missing environment or settings")
    if not base["results"] or base["results"].keys() != candidate["results"].keys():
        raise Inconclusive("missing or mismatched scenarios")
    rows = []
    # Both relative AND absolute growth must exceed the initial investigation thresholds.
    floors = {"cpuMs": 2, "cpuPercent": 2, "wakeupsPerSecond": 20}
    for name, before in base["results"].items():
        after = candidate["results"][name]
        required = {"cpuMs"} if base["kind"] == "benchmark" else {"cpuPercent", "wakeupsPerSecond"}
        if set(before) != required or set(after) != required:
            raise Inconclusive("missing metrics")
        for metric, values in before.items():
            a, b = series(values, floors[metric]), series(after[metric], floors[metric])
            regression = b > a * 1.2 and b - a > floors[metric]
            rows.append({"case": name, "metric": metric, "baseline": a, "candidate": b,
                         "status": "REGRESSION" if regression else "PASS"})
    return rows


def compare(base, candidate, suite):
    if base.resolve() == candidate.resolve():
        raise Inconclusive("baseline and candidate must be separate captures")
    names = ["benchmark"] if suite == "benchmark" else ["benchmark", "short", "medium", "switches"]
    if suite == "full":
        names += ["large-clean", "large-errors"]
    rows = []
    identities = [None, None]
    environments = [None, None]
    for name in names:
        a, b = read(base / f"{name}.json"), read(candidate / f"{name}.json")
        for i, data in enumerate((a, b)):
            if environments[i] is not None and data["environment"] != environments[i]:
                raise Inconclusive("environment changed within suite")
            environments[i] = data["environment"]
            if name != "benchmark":
                identity = (data["executableSHA256"], data["settings"])
                if not identity[0] or (identities[i] is not None and identities[i] != identity):
                    raise Inconclusive("app executable or settings changed within suite")
                identities[i] = identity
                if data["kind"] != "app" or data["scenario"] != name or data["fixtureSHA256"] != hashlib.sha256(fixture(name).encode()).hexdigest():
                    raise Inconclusive("incorrect app scenario")
            elif data["kind"] != "benchmark":
                raise Inconclusive("incorrect benchmark kind")
        expected = TESTS if name == "benchmark" else {name}
        if set(a["results"]) != expected or set(b["results"]) != expected:
            raise Inconclusive(f"incomplete {name} results")
        rows += compare_reports(a, b)
    print(json.dumps(rows, indent=2, allow_nan=False))
    return 1 if any(r["status"] == "REGRESSION" for r in rows) else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    f = commands.add_parser("fixture", help="print synthetic draft body; never sends or edits mail")
    f.add_argument("scenario", choices=SCENARIOS)
    b = commands.add_parser("benchmark", help="run opt-in Release XCTest CPU metrics into a new directory")
    b.add_argument("output", type=Path)
    c = commands.add_parser("capture", help="capture a prepared Mail fixture; activates Mail/TextEdit")
    c.add_argument("scenario", choices=SCENARIOS)
    c.add_argument("--pid", type=int, required=True)
    c.add_argument("--output", type=Path, required=True)
    c.add_argument("--settings", required=True, help="same reviewed settings/display setup identifier for both builds")
    c.add_argument("--ui-verified", action="store_true", required=True, help="attest exact fixture, empty recipients, visible working UI")
    c.add_argument("--state", type=Path, default=STATE.DEFAULT_STATE_FILE)
    d = commands.add_parser("compare")
    d.add_argument("baseline", type=Path)
    d.add_argument("candidate", type=Path)
    d.add_argument("--suite", choices=["benchmark", "smoke", "full"], default="smoke")
    args = parser.parse_args()
    try:
        if args.command == "fixture":
            print(fixture(args.scenario))
        elif args.command == "benchmark":
            benchmark(args.output)
        elif args.command == "capture":
            if not 0 < args.pid <= 2**31 - 1:
                raise Inconclusive("invalid PID")
            capture(args)
        else:
            return compare(args.baseline, args.candidate, args.suite)
        return 0
    except (Inconclusive, STATE.StateError, OSError, ValueError, KeyError, TypeError,
            AttributeError, OverflowError, subprocess.SubprocessError) as error:
        print(f"INCONCLUSIVE: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
