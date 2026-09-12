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

The original flexible-width implementation passed a fitting-size-only assertion
while captured text and buttons were visibly clipped. The regression assertion now
compares against an independent render at the actual window width. Retain both
that constraint check and visual inspection; either alone is insufficient.

Native-view snapshots do not establish behavior on every display arrangement,
with VoiceOver, or with Reduce Motion enabled. Verify those separately.
