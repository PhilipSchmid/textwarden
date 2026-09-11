# CPU profiling

Developer-only tools: no new settings, background recorder, or uploads.

## Capture CPU and wakeups

Find TextWarden's PID with `pgrep -x TextWarden`, then run:

```sh
swift Scripts/profile-cpu.swift counters 12345 30
```

The JSON output reports CPU milliseconds/second, CPU percentage of one core,
interrupt wakeups/second, and the foreground app at each two-second boundary.
CPU can exceed 100% when multiple cores are busy. Durations are limited to 2–300
seconds; the command fails if the process exits or its identity changes.

For repeated captures, compile once:

```sh
swiftc Scripts/profile-cpu.swift -o /tmp/textwarden-profile-cpu
/tmp/textwarden-profile-cpu counters 12345 30
```

## Find the expensive stacks

With full Xcode installed:

```sh
swift Scripts/profile-cpu.swift trace 12345 30
```

This attaches Instruments **Time Profiler + os_signpost** and prints a private
`.trace` path. Open it in Instruments, select TextWarden and the relevant time
range, then use **Call Tree / Flame Graph**. Inclusive weight includes descendants;
self weight does not. These are sampled CPU costs, not exact hardware cycles.

Filter signposts to subsystem `io.textwarden.TextWarden`, category `Performance`.
`Operation` intervals cover analysis, filtering, AX extraction, overlay rebuilding,
window checks/enumeration, and text validation. `Monitoring lifecycle` events show
window-monitor starts/stops.

Existing diagnostic exports include operation counts, lifetime elapsed totals/means,
calls/second since reset, and percentiles over the latest 1,000 samples. Elapsed
durations include waits and async suspension; nested intervals overlap. Do not sum
them as CPU percentages. Text-validation intervals cover scheduling, not completion
of queued extraction.

## Compare changes

1. Use the same Release build configuration, settings, and synthetic document.
   For Mail, leave recipients empty and never send the draft.
2. Measure settled CPU separately from typing/paste/analysis bursts. Test short,
   medium, and large text with zero, a few, and many errors.
3. Repeat after ten app switches to expose accumulating work. Keep the host app
   foreground; discard captures with focus changes or unfinished analysis.
4. Verify the indicator, underlines, corrections, scrolling, and window movement.
   Low CPU while the AX watchdog suppresses UI is not a successful result.
   The existing default hides underlines above ten errors.
5. Compare Instruments off/on/off to account for recording overhead. Keep optional
   E2E reporting consistent between runs; use a normal launch for production checks.

Examples found with this workflow: invalidate repeating timers before restarting
monitoring; anchor Mail quote expressions to avoid rescanning long-line suffixes;
build one Unicode-boundary lookup per error-filtering batch instead of walking the
document for every error. The profiler itself uses a bounded circular sample buffer.

## Local regression gate

Run on an unlocked Mac, on power, with the same displays, app settings, Xcode,
and macOS build. Close profilers and stop unrelated builds/downloads. Use the same
test harness for both revisions (copy the test/tool files into an older checkout
if needed). Capture the baseline **before** changing runtime code; never overwrite it.

```sh
mkdir -p .cpu-check
make cpu-benchmark CPU_OUTPUT=.cpu-check/baseline
# Repeat on the candidate revision:
make cpu-benchmark CPU_OUTPUT=.cpu-check/candidate
make cpu-check CPU_BASELINE=.cpu-check/baseline CPU_CANDIDATE=.cpu-check/candidate CPU_SUITE=benchmark
```

Seven opt-in XCTest cases measure CPU time for Mail quote parsing, filtering, and
grammar analysis, with short/large inputs and few/many errors. They warm up first,
then record five iterations in Release with testability enabled and coverage off.
The retained `.xcresult` also contains clock time and, when supported, CPU cycles
and instructions. Ordinary tests skip these benchmarks; GitHub runners do not gate
on CPU timing.

For each build, run `CONFIGURATION=Release make run` (also selects Rust Release), then enable the existing
[E2E state oracle](testing/MAIL-E2E-CANARIES.md#enable-the-state-oracle). Open TextEdit
and a synthetic Mail draft with **empty recipients**. Paste the exact output of
`python3 -B Scripts/cpu-check.py fixture short` into its body. Verify the body,
indicator, and underlines visually; leave the body focused and popovers closed.

```sh
python3 -B Scripts/cpu-check.py capture short --pid 12345 \
  --settings default-display-v1 --ui-verified \
  --output .cpu-check/baseline/short.json
```

Repeat for `medium` and `switches`, for both baseline and candidate directories.
The full suite adds `large-clean` (~49k characters, no errors) and `large-errors`
(~55k, 2,600 errors). Above ten errors, the default intentionally hides underlines;
the indicator must still work. `--settings` is your identifier for the unchanged
preferences/display setup, **not** an automatic settings check. `--ui-verified`
attests the exact fixture and functional UI; do not use it without checking.

Each capture activates TextEdit then Mail, settles, and records three ten-second
CPU/wakeup samples. `switches` does ten activation cycles first. It rejects stale
or mismatched state, analysis/focus changes, suppressed UI, and non-nominal thermals.
It measures **settled load**, not typing latency or the initial paste burst.

```sh
make cpu-check CPU_BASELINE=.cpu-check/baseline CPU_CANDIDATE=.cpu-check/candidate
# Analysis/AX/timer/overlay changes and performance work:
make cpu-check CPU_BASELINE=.cpu-check/baseline CPU_CANDIDATE=.cpu-check/candidate CPU_SUITE=full
make run-only # Restore normal launch without the E2E reporter.
```

Exit codes: **0** pass, **1** regression, **2** inconclusive. Compare medians on the
same machine; investigate growth exceeding **both 20% and** 2 ms per benchmark
batch, 2 CPU percentage points of one core, or 20 wakeups/sec. A repeat range above
the larger of 50% of its median or the absolute threshold is inconclusive. These
are initial investigation thresholds, not universal performance budgets. Repeat a
no-op comparison when calibrating a machine; never loosen thresholds to hide a failure.
Keep local evidence with the PR's baseline/candidate revisions and binary hashes.
Functional Mail canaries remain required for interaction changes.

## Checks and privacy

```sh
swift Scripts/profile-cpu.swift self-test
make test
```

Run builds, benchmarks, and app captures serially. CPU-counter JSON contains app
identifiers and executable hashes; traces and `.xcresult` bundles can contain paths,
process/environment metadata, and logs. Review before sharing. Keep evidence in
ignored `.cpu-check/`; never commit raw traces (`*.trace` is ignored).

References: [Apple CPU call trees](https://developer.apple.com/documentation/Xcode/analyzing-cpu-profiles-with-call-tree-views),
[OSSignposter](https://developer.apple.com/documentation/os/ossignposter).
