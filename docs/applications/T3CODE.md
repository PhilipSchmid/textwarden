# TextWarden for T3 Code on macOS

TextWarden checks draft prompts in the T3 Code desktop composer. The composer can report empty bounds for a text range even when its accessibility call succeeds. TextWarden matches child text runs to the draft in reading order and uses the range of each occurrence within its run. Suggestions whose position cannot be measured remain available in the indicator.

The integration matches the macOS bundle identifier `com.t3tools.t3code`. For a FreeT3 build, look up its bundle identifier in **TextWarden → Preferences → Applications**, then run the checks below. A build with the same identifier uses the T3 Code configuration. Checking also requires the TipTap prompt editor (exposed to accessibility as `composer-tiptap`) and its child text runs. A build with a different identifier needs its own registration for dedicated support.

Corrections select the word in the composer using macOS UTF-16 offsets, including when an emoji precedes it. T3 Code handles the pasted correction and Undo.

Tested with T3 Code (Beta) 0.1.13 on macOS. Three copies of `recieve` produced three separate underlines, including one after `👩🏽‍💻`. Correcting that occurrence preserved both earlier ones, and Undo restored it. In a 32-paragraph draft with a typo at each end, the indicator counted two throughout. The clean middle paragraphs had no underlines. Sending the prompt cleared the overlay, and checking resumed in the next draft.

## Manual checks

1. Grant Accessibility permission to the TextWarden build under test, then open a fresh thread in the desktop app. Use a disposable draft for the editing checks.
2. Paste the sample below into the prompt composer. Verify that `sentnce` and `recieve` are underlined in their respective paragraphs and that the indicator lists both suggestions.
3. Click the underline under `recieve` and apply `receive`. Verify that only that word changes, the paragraph break and emoji remain, and the suggestion clears. Try Undo and verify that the original draft and underline return.
4. Repeat with `recieve` in both paragraphs. Verify that each underline and each correction targets its own occurrence. Narrow the window to wrap a long line, then scroll the composer and switch away and back. Check that underlines track visible text and clear when the composer loses focus.
5. Paste enough paragraphs to scroll inside the composer. Put a different misspelling at each end. Scroll to the top, middle, and bottom. The indicator should keep the total while the overlay shows only the visible errors. Focus the thread search, then return to the draft and check the visible words again.
6. Clear the draft. To test submission, enter a short disposable prompt such as `Please reply only OK. This sentnce is a test.` Wait for an underline, submit the prompt, and confirm that the empty composer and the sent message have no TextWarden underlines. Type a fresh misspelling to verify that checking resumes. For a FreeT3 run, record the app version and bundle identifier with the results.

```text
This sentnce needs an edit.

📎 We will recieve the package tomorrow.
```

The app profile lives in [`AppRegistry.swift`](../../Sources/AppConfiguration/AppRegistry.swift) and the child-element positioning logic lives in [`TextRunStrategy.swift`](../../Sources/Positioning/Strategies/TextRunStrategy.swift). See [macOS live end-to-end testing](../testing/README.md) for the TextWarden state snapshot and input preflights.
