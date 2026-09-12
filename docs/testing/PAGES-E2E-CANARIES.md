# Apple Pages live E2E canaries

These scenarios use a new local Pages document and the shared [macOS E2E workflow](README.md). Do not accept a Pages license agreement on the user's behalf. Clear the fixture before closing and do not retain the document.

## Fixtures

Single-line fixture:

```text
This are a definitly bad sentnce with wrong worrds zqxvtestt
```

For scrolling, append enough correct filler lines to create more than one page. Derive the expected UTF-16 segment length from Pages' current AX value: Pages can expose a trailing paragraph or layout unit that is not visible as fixture text.

## Scenarios

| ID | Actions | Required observations |
|---|---|---|
| PAGES-01 | Type the single-line fixture into Body. | Pages and TextWarden identify `com.apple.iWork.Pages` and `AXTextArea`; four findings, four underlines, indicator count `4`, `RangeBounds`, and usable confidence appear after convergence. |
| PAGES-02 | Append and remove ` badspelll` ten times. | Every cycle advances analysis, changes all three counts from four to five and back, and keeps the same body identity. |
| PAGES-03 | Type an invalid word in Left Header, remove it, then return to Body. | Monitored identity follows Header and Body; header findings clear; the original body findings return without stale header geometry. |
| PAGES-04 | Open a TextWarden suggestion for `definitly` and choose `definitely`. | The host value changes exactly once; finding count drops by one; unrelated findings remain; replacement time advances; stale highlight and popover clear or advance to the next current finding. |
| PAGES-05 | Change zoom from 125% to 100% and back. | Bounds and hit points are recomputed at both scales and underlines remain attached to their ranges. |
| PAGES-06 | In a multi-page fixture, scroll the first-line findings off screen and return. | Off-screen underline count becomes zero while indicator count stays four; returning to page one restores four underlines. A native global wheel event must pass the driver preflight. |
| PAGES-07 | Activate another app, then return to the Pages body three times. | Every return reacquires the same body, segment, four findings, four underlines, and indicator count `4`. |
| PAGES-08 | Move and resize the Pages window, minimize it, then restore it. | Overlay frame follows the editor, presentation clears while unavailable, and all visible state recovers without stale geometry. |
