#!/usr/bin/env python3

"""Inspect and wait for TextWarden's opt-in, text-free E2E state."""

from __future__ import annotations

import argparse
import json
import os
import stat
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


DEFAULT_STATE_FILE = Path(tempfile.gettempdir()) / "textwarden-e2e-state.json"
FORBIDDEN_KEYS = {"content", "sourceText", "lintID", "message", "suggestions"}
MISSING = object()


class StateError(Exception):
    pass


def read_snapshot(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as state_file:
        snapshot = json.load(state_file)
    if not isinstance(snapshot, dict):
        raise StateError("state root must be a JSON object")
    return snapshot


def value_at(root: Any, key_path: str) -> Any:
    value = root
    for component in key_path.split("."):
        if isinstance(value, list) and component == "length":
            value = len(value)
        elif isinstance(value, dict) and component in value:
            value = value[component]
        else:
            return MISSING
    return value


def parse_literal(raw: str) -> Any:
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return raw


def parse_expectations(specifications: list[str]) -> list[tuple[str, Any]]:
    expectations = []
    for specification in specifications:
        key_path, separator, raw_value = specification.partition("=")
        if not separator or not key_path:
            raise StateError(f"invalid expectation {specification!r}; use path=value")
        expectations.append((key_path, parse_literal(raw_value)))
    return expectations


def expectation_mismatches(
    snapshot: dict[str, Any], expectations: list[tuple[str, Any]]
) -> list[str]:
    mismatches = []
    for key_path, expected in expectations:
        actual = value_at(snapshot, key_path)
        if actual is MISSING and expected is None:
            continue
        if actual != expected:
            actual_description = "<missing>" if actual is MISSING else repr(actual)
            mismatches.append(f"{key_path}: expected {expected!r}, got {actual_description}")
    return mismatches


def collect_forbidden_keys(value: Any) -> set[str]:
    found: set[str] = set()
    if isinstance(value, dict):
        for key, nested_value in value.items():
            if key in FORBIDDEN_KEYS:
                found.add(key)
            found.update(collect_forbidden_keys(nested_value))
    elif isinstance(value, list):
        for nested_value in value:
            found.update(collect_forbidden_keys(nested_value))
    return found


def validate_snapshot(path: Path, snapshot: dict[str, Any]) -> None:
    mode = stat.S_IMODE(path.stat().st_mode)
    if mode != 0o600:
        raise StateError(f"state file permissions are {mode:o}; expected 600")
    if path.stat().st_uid != os.getuid():
        raise StateError("state file is not owned by the current user")
    if snapshot.get("schemaVersion") != 1:
        raise StateError(f"unsupported schemaVersion {snapshot.get('schemaVersion')!r}")
    if not isinstance(snapshot.get("textWardenProcessID"), int):
        raise StateError("textWardenProcessID is missing")

    forbidden = sorted(collect_forbidden_keys(snapshot))
    if forbidden:
        raise StateError(f"text-bearing keys found: {', '.join(forbidden)}")


def summary(snapshot: dict[str, Any]) -> dict[str, Any]:
    state = snapshot.get("state", {})
    analysis = state.get("analysis", {})
    presentation = state.get("presentation", {})
    errors = analysis.get("grammarErrors", [])

    def optional_value(key_path: str) -> Any:
        value = value_at(state, key_path)
        return None if value is MISSING else value

    return {
        "activeApp": optional_value("activeApplication.bundleIdentifier"),
        "monitoredApp": optional_value("monitoredApplication.bundleIdentifier"),
        "role": optional_value("monitoredElement.role"),
        "generation": analysis.get("generation"),
        "segmentLength": analysis.get("segmentLength"),
        "errors": len(errors) if isinstance(errors, list) else None,
        "underlines": presentation.get("grammarUnderlineCount"),
        "indicator": presentation.get("indicatorGrammarErrorCount"),
        "popover": presentation.get("suggestionPopoverVisible"),
        "runtime": optional_value("runtimeHealth.state"),
    }


def wait_for_snapshot(
    path: Path,
    expectations: list[tuple[str, Any]],
    timeout: float,
    interval: float,
) -> tuple[dict[str, Any], float]:
    start = time.monotonic()
    deadline = start + timeout
    last_snapshot: dict[str, Any] | None = None
    last_error: Exception | None = None

    while time.monotonic() <= deadline:
        try:
            last_snapshot = read_snapshot(path)
            last_error = None
            if not expectation_mismatches(last_snapshot, expectations):
                validate_snapshot(path, last_snapshot)
                return last_snapshot, time.monotonic() - start
        except (FileNotFoundError, json.JSONDecodeError) as error:
            last_error = error
        time.sleep(interval)

    if last_snapshot is not None:
        details = "; ".join(expectation_mismatches(last_snapshot, expectations))
        raise StateError(f"timed out after {timeout:g}s: {details}")
    raise StateError(f"timed out after {timeout:g}s waiting for {path}: {last_error}")


def self_test() -> None:
    snapshot = {
        "schemaVersion": 1,
        "textWardenProcessID": 123,
        "state": {
            "activeApplication": {"bundleIdentifier": "com.example.Editor"},
            "analysis": {"grammarErrors": [{"start": 1, "end": 2}]},
        },
    }
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "state.json"
        path.write_text(json.dumps(snapshot), encoding="utf-8")
        path.chmod(0o600)
        validate_snapshot(path, snapshot)
        expectations = parse_expectations(
            [
                "state.activeApplication.bundleIdentifier=com.example.Editor",
                "state.analysis.grammarErrors.length=1",
                "state.monitoredElement=null",
            ]
        )
        assert not expectation_mismatches(snapshot, expectations)
        assert expectation_mismatches(snapshot, [("schemaVersion", 2)])
        json.dumps(summary(snapshot))

        unsafe_snapshot = dict(snapshot, message="captured text")
        try:
            validate_snapshot(path, unsafe_snapshot)
        except StateError:
            pass
        else:
            raise AssertionError("privacy validation accepted a forbidden key")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-file", type=Path, default=DEFAULT_STATE_FILE)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("show", help="print the current snapshot")
    subparsers.add_parser("check", help="validate privacy and file permissions")

    wait_parser = subparsers.add_parser("wait", help="wait for key-path expectations")
    wait_parser.add_argument(
        "--expect",
        action="append",
        default=[],
        metavar="PATH=VALUE",
        help="JSON key path and expected JSON literal; repeat as needed",
    )
    wait_parser.add_argument("--timeout", type=float, default=8.0)
    wait_parser.add_argument("--interval", type=float, default=0.1)
    subparsers.add_parser("self-test", help=argparse.SUPPRESS)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "self-test":
            self_test()
            print("PASS: e2e-state self-test")
            return 0

        if args.command == "wait":
            expectations = parse_expectations(args.expect)
            snapshot, elapsed = wait_for_snapshot(
                args.state_file, expectations, args.timeout, args.interval
            )
            print(f"PASS in {elapsed:.2f}s: {json.dumps(summary(snapshot), sort_keys=True)}")
            return 0

        snapshot = read_snapshot(args.state_file)
        validate_snapshot(args.state_file, snapshot)
        if args.command == "show":
            print(json.dumps(snapshot, indent=2, sort_keys=True))
        else:
            print(f"PASS: {json.dumps(summary(snapshot), sort_keys=True)}")
        return 0
    except (OSError, StateError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
