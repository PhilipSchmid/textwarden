# Quick Rewrite visual regression checks

The review uses the production `QuickRewriteStatus` panel, not a mock. Keep layout
checks separate from AI quality checks: deterministic input/output pairs make a
wrapping regression reproducible even when the model proposes different wording.

## Repeatable layout matrix

`QuickRewriteTests.testReviewLayoutMatrix` exercises short, wrapped, expanded,
multiline, emoji/ZWJ, mixed-script, unbroken, and overflow-length text at 10, 13,
and 20 points in light and dark appearance. It restores the original preferences.
The 48 combinations produce 60 optional captures: one settled image per case,
hover/resume/hold states at 13 points, and each overflow case scrolled to the end.
The full command below also captures the one-second countdown and five compact
feedback states, for 66 images in total.

Run with optional retained native-view captures:

```sh
TEST_RUNNER_TEXTWARDEN_REWRITE_SCREENSHOTS=/tmp/textwarden-rewrite-layout \
  xcodebuild test -scheme TextWarden -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:TextWardenTests/QuickRewriteTests \
  -resultBundlePath /tmp/textwarden-rewrite-layout.xcresult
```

Captures contain synthetic fixtures only and are also attached to the test result.
Run these native-window checks serially: they share the desktop and temporarily
change application preferences. Avoid interacting with the test windows during a run.
These AppKit view captures do not require screen-recording permission. Supplement
them with desktop window screenshots during real editor testing: view captures
alone do not prove screen position, animation, focus, or replacement behavior.

## Live editor checks

Use a disposable TextEdit document, with unchanged text before and after the
selected passage. Never use someone else's conversation or send a message.

Capture the loading status, opening transition, settled review, hover-paused
countdown, resumed countdown, keyboard-held review, and completion feedback.
Confirm Return applies, Escape cancels, Space removes the time limit, and expiry
never applies a rewrite. For overflow text, scroll to the end and verify the
decision buttons remain visible. Check both short and long selections, emoji,
paragraph breaks, and text containing combining marks.

## What a passing layout means

- Width is established before measuring wrapped height.
- Labels and decision buttons fit inside the native window, not just inside
  SwiftUI's reported ideal size.
- Short and ordinary wrapped passages need no scroll area.
- Long passages scroll within a bounded area; decision buttons do not scroll away.
- Opening motion must not compress a fully laid-out review into a status-sized
  window. Respect Reduce Motion.
- The Return shortcut uses the native symbol, centered beside Apply.
- Countdown digits reserve a minimum width so Cancel does not shift when the
  remaining time drops below ten seconds.

## No-op proposals

Select the example sentence with its trailing separator space as well as without
it. An exact echo or a result differing only in leading/trailing whitespace must
show **No rewrite suggested**, never the review panel. Do not modify the editor
or strip whitespace from a genuinely changed proposal as part of this check.

`testRewriteSuppressesUnchangedTextAndBoundaryWhitespace` covers ordinary spaces,
tabs, line endings, nonbreaking spaces, all review reasons, and canonical Unicode
equivalence. `testRewriteKeepsRealEditsSignificant` prevents over-filtering wording,
numbers, negation, case, punctuation, internal spacing, paragraph breaks, accents,
or emoji changes. These are change-detection checks, not quality endorsements.

Live regression verified on 11 September: selecting `It is important to note that
we will send the summary tomorrow. ` (including the trailing space) produced the
text-free diagnostic `Ignored boundary-whitespace-only result` and the compact
**No rewrite suggested** status, with no review. The complete 130-UTF-16-unit
sentinel document remained unchanged. The historical focused suite passed 13
tests; seven opt-in model/benchmark tests were skipped. Experimental collectors
are now kept separately; these counts describe the original combined suite.

The original flexible-width implementation passed a fitting-size-only assertion
while captured text and buttons were visibly clipped. The regression assertion now
compares against an independent render at the actual window width. Retain both
that constraint check and visual inspection; either alone is insufficient.

## Validation record — 11 September 2026

The focused run passed 10 tests, with seven opt-in model/benchmark tests skipped.
One parallel run was interrupted by a test-host process exiting with code 0 before
completion; the subsequent serial run passed. The exit's cause was not established.
All 48 layout combinations passed the fixed-width height assertion. Visual review
covered light/dark appearance at 10, 13, and 20 points, including emoji clusters,
combining accents, mixed left-to-right/right-to-left scripts, bullets, blank lines,
long URLs, and overflow. The scroll-end captures retain the decision buttons.

Live TextEdit checks used synthetic text only:

- Loading, opening, settled review, hover pause, resumed countdown, and completion
  feedback were captured as native windows. The wrapped review measured 440 × 179
  points, including during opening; it no longer squeezes into a shorter frame.
- Pointer hover held the timer at 33 seconds; leaving resumed it. Space kept a
  review open. Escape cancelled without changing the selected text.
- Both Apply and Return replaced only the selected passage. Prefix/suffix markers
  survived, and native Undo restored the source.
- An unattended live review counted down to cancellation, showed the neutral X
  feedback, and left the complete document unchanged. A preceding attempt was
  interrupted by source focus/selection changing and is not counted as expiry
  evidence. The isolated one-second timeout test also returned false.
- A separate model-quality issue remains: one Concise response removed an emoji
  and normalized an apostrophe without making the sentence more concise. That
  proposal was cancelled. Rendering an emoji correctly is not proof that the model
  preserves it; this UI fix does not change model prompts or rewrite acceptance.

Native-view snapshots do not establish behavior on every display arrangement,
with VoiceOver, or with Reduce Motion enabled. Those remain manual environment
checks; do not infer them from the layout matrix.
