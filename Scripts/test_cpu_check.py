#!/usr/bin/env python3
"""Deterministic checks for the local CPU gate; no Mail or Xcode required."""
import contextlib
import copy
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
import subprocess
import sys

SPEC = importlib.util.spec_from_file_location("cpu_check", Path(__file__).with_name("cpu-check.py"))
C = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(C)


def report(kind="app", scenario="short"):
    return {"schemaVersion": 1, "kind": kind,
            "environment": dict.fromkeys(("machine", "model", "arch", "os", "xcode"), "test"),
            "settings": "test", "scenario": scenario, "executableSHA256": "test-binary",
            "fixtureSHA256": C.hashlib.sha256(C.fixture(scenario).encode()).hexdigest(),
            "results": ({name: {"cpuMs": [10, 10, 10]} for name in C.TESTS} if kind == "benchmark" else
                        {scenario: {"cpuPercent": [4, 4, 4], "wakeupsPerSecond": [100, 100, 100]}})}


class GateTests(unittest.TestCase):
    def test_cli_exit_codes(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder) / "base"
            base.mkdir()
            C.save(base / "benchmark.json", report("benchmark"))
            for value, expected in [(10, 0), (15, 1), (None, 2)]:
                after = Path(folder) / str(expected)
                after.mkdir()
                data = report("benchmark")
                if value is None:
                    data["results"].pop("testQuoteLarge")
                else:
                    data["results"]["testQuoteLarge"]["cpuMs"] = [value] * 5
                C.save(after / "benchmark.json", data)
                result = subprocess.run([sys.executable, "-B", str(Path(__file__).with_name("cpu-check.py")),
                                         "compare", str(base), str(after), "--suite", "benchmark"], capture_output=True)
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_thresholds(self):
        before = report()
        for cpu, wakeups, expected in [(4, 100, False), (5, 110, False), (7, 100, True), (4, 130, True)]:
            after = copy.deepcopy(before)
            after["results"]["short"] = {"cpuPercent": [cpu] * 3, "wakeupsPerSecond": [wakeups] * 3}
            self.assertEqual(any(r["status"] == "REGRESSION" for r in C.compare_reports(before, after)), expected)
        before = report("benchmark")
        after = copy.deepcopy(before)
        after["results"]["testQuoteLarge"]["cpuMs"] = [15] * 3
        self.assertEqual(sum(r["status"] == "REGRESSION" for r in C.compare_reports(before, after)), 1)

    def test_invalid_or_noisy_samples(self):
        for values in ([], [1, 1], [True, 1, 1], [-1, 1, 1], [float("nan")] * 3,
                       [float("inf")] * 3, ["1"] * 3, [1, 10, 1]):
            with self.subTest(values=values), self.assertRaises(C.Inconclusive):
                C.series(values, 2)

    def test_incompatible_or_incomplete_reports(self):
        before = report()
        for key, value in [("schemaVersion", 2), ("environment", {}), ("settings", "other"),
                           ("results", {}), ("results", {"short": {"wakeupsPerSecond": [1, 1, 1]}})]:
            after = copy.deepcopy(before)
            after[key] = value
            with self.subTest(key=key), self.assertRaises(C.Inconclusive):
                C.compare_reports(before, after)

    def test_native_metrics_parser(self):
        native = [{"testIdentifier": f"CPURegressionTests/{name}()", "testRuns": [{"metrics": [
            {"displayName": "CPU Time", "unitOfMeasurement": "s", "measurements": [0.01] * 5}]}]}
                  for name in C.TESTS]
        self.assertEqual(C.benchmark_metrics(native)["testQuoteShort"]["cpuMs"], [10] * 5)
        for invalid in ([], native[:-1], native + native[:1]):
            with self.assertRaises(C.Inconclusive):
                C.benchmark_metrics(invalid)
        for values in ([0.01] * 2, [True] * 5, [float("nan")] * 5):
            broken = copy.deepcopy(native)
            broken[0]["testRuns"][0]["metrics"][0]["measurements"] = values
            with self.assertRaises(C.Inconclusive):
                C.benchmark_metrics(broken)

    def test_suite_and_safe_evidence(self):
        with tempfile.TemporaryDirectory() as folder:
            base, after = Path(folder) / "base", Path(folder) / "after"
            base.mkdir()
            after.mkdir()
            with self.assertRaises(C.Inconclusive):
                C.compare(base, base, "benchmark")
            for target in (base, after):
                for name in ("benchmark", *C.SCENARIOS):
                    C.save(target / f"{name}.json", report("benchmark" if name == "benchmark" else "app", "short" if name == "benchmark" else name))
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(C.compare(base, after, "full"), 0)
            path = after / "short.json"
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                C.save(path, {})
            path.unlink()
            changed = report()
            changed["executableSHA256"] = "different-build"
            C.save(path, changed)
            with self.assertRaises(C.Inconclusive):
                C.compare(base, after, "smoke")
            (after / "medium.json").unlink()
            with self.assertRaises(FileNotFoundError):
                C.compare(base, after, "smoke")

    def test_ui_health_required(self):
        presentation = dict.fromkeys(("hiddenDueToMovement", "hiddenDueToScroll", "hiddenDueToWindowOffScreen",
                                     "suggestionPopoverVisible", "readabilityPopoverVisible", "textGenerationPopoverVisible"), False)
        presentation.update(indicatorVisible=True, indicatorGrammarErrorCount=2,
                            grammarUnderlineCount=2, overlayVisible=True, overlayAlpha=1)
        state = {"schemaVersion": 1, "textWardenProcessID": 123, "state": {
            "activeApplication": {"bundleIdentifier": "com.apple.mail"},
            "monitoredApplication": {"bundleIdentifier": "com.apple.mail"},
            "monitoredElement": {"identity": "field"}, "runtimeHealth": {"state": "active"},
            "replacement": {"isApplying": False}, "presentation": presentation,
            "analysis": {"generation": 5, "segmentLength": len(C.fixture("short")), "grammarErrors": [{}, {}]}}}
        self.assertEqual(C.check_state(state, 123, "short"), (5, "field"))
        with self.assertRaises(C.Inconclusive):
            C.check_state(state, 124, "short")
        for section, key, value in [("runtimeHealth", "state", "recovering"), ("analysis", "segmentLength", 1),
                                    ("activeApplication", "bundleIdentifier", "other"), ("monitoredElement", "identity", None),
                                    ("presentation", "grammarUnderlineCount", 0), ("presentation", "overlayAlpha", 0),
                                    ("presentation", "indicatorVisible", False), ("presentation", "hiddenDueToScroll", True)]:
            broken = copy.deepcopy(state)
            broken["state"][section][key] = value
            with self.subTest(section=section, key=key), self.assertRaises(C.Inconclusive):
                C.check_state(broken, 123, "short")


if __name__ == "__main__":
    unittest.main()
