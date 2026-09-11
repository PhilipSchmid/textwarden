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

## Checks and privacy

```sh
swift Scripts/profile-cpu.swift self-test
make test
```

Run Xcode builds/tests serially. CPU-counter JSON contains app identifiers; raw
traces can contain paths, process/environment metadata, and log metadata. Review
before sharing and never commit raw traces (`*.trace` is ignored).

References: [Apple CPU call trees](https://developer.apple.com/documentation/Xcode/analyzing-cpu-profiles-with-call-tree-views),
[OSSignposter](https://developer.apple.com/documentation/os/ossignposter).
