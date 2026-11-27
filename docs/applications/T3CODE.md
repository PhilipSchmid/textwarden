# TextWarden for T3 Code on macOS

TextWarden checks draft prompts in the T3 Code desktop composer. The composer can report empty bounds for a text range even when its accessibility call succeeds. TextWarden tries the bounds of the composer's child text elements first, then falls back to estimated positions when needed.

The integration matches the macOS bundle identifier `com.t3tools.t3code`. For a FreeT3 build, look up its bundle identifier in **TextWarden → Preferences → Applications**, then run the checks below. A build with the same identifier uses the T3 Code configuration. A different identifier needs its own registration for dedicated support.

When the same misspelled word appears in more than one paragraph, the indicator can report both occurrences while the underlines overlap at the first one.

## Manual checks

1. Grant Accessibility permission to the TextWarden build under test, then open a fresh thread in the desktop app. Use an unsent draft throughout.
2. Paste the sample below into the prompt composer. Verify that `sentnce` and `recieve` are underlined in their respective paragraphs and that the indicator lists both suggestions.
3. Click the underline under `recieve` and apply `receive`. Verify that only that word changes, the paragraph break and emoji remain, and the suggestion clears. Try Undo and verify that the original draft and underline return.
4. Repeat with `recieve` in both paragraphs. Verify that each underline and each correction targets its own occurrence. Narrow the window to wrap a long line, then scroll the composer and switch away and back. Check that underlines track visible text and clear when the composer loses focus.
5. Clear the disposable draft without submitting it. For a FreeT3 run, record the app version and bundle identifier with the results.

```text
This sentnce needs an edit.

📎 We will recieve the package tomorrow.
```

The app profile lives in [`AppRegistry.swift`](../../Sources/AppConfiguration/AppRegistry.swift) and the child-element positioning logic lives in [`ElementTreeStrategy.swift`](../../Sources/Positioning/Strategies/ElementTreeStrategy.swift). See [macOS live end-to-end testing](../testing/README.md) for the TextWarden state snapshot and input preflights.
