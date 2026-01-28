//
//  PlainTextSTTextView.swift
//  TextWarden
//
//  Custom STTextView subclass that always pastes as plain text
//  Strips all rich text formatting to keep the Sketch Pad clean
//

import AppKit
import STTextView

/// STTextView subclass that enforces plain text pasting and provides formatting removal
///
/// Overrides paste() to always use pasteAsPlainText(), ensuring all paste operations
/// strip RTF/HTML formatting. Also provides removeFormatting() to clean up any
/// formatted text that may have been inserted through other means.
class PlainTextSTTextView: STTextView {
    // MARK: - Plain Text Only Pasting

    /// Override paste to always use plain text
    ///
    /// STTextView's default paste() checks for RTF content first and pastes with formatting.
    /// We override to always use pasteAsPlainText to strip all formatting.
    /// After paste, we trigger content size recalculation to ensure all content is visible.
    override func paste(_ sender: Any?) {
        Logger.debug("PlainTextSTTextView.paste() - redirecting to pasteAsPlainText", category: Logger.ui)
        pasteAsPlainText(sender)

        // Defer layout update to next run loop iteration to avoid layout reentrancy issues
        // sizeToFit() calls ensureLayout which can crash if called during an active layout pass
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            needsLayout = true
            needsDisplay = true
            sizeToFit()
        }
    }

    // MARK: - Remove Formatting

    /// Remove all formatting from selected text (or entire document if no selection)
    /// Strips font, color, background, and other rich text attributes
    @objc func removeFormatting(_: Any?) {
        guard let textContentStorage = textContentManager as? NSTextContentStorage,
              let storage = textContentStorage.textStorage
        else {
            return
        }

        let range: NSRange
        let currentSelection = selectedRange()

        if currentSelection.length > 0 {
            range = currentSelection
        } else {
            // No selection - apply to entire document
            range = NSRange(location: 0, length: storage.length)
        }

        guard range.length > 0 else { return }

        // Get the plain text
        let plainText = storage.attributedSubstring(from: range).string

        // Create a new attributed string with default attributes
        let defaultFont = font
        let defaultColor = textColor
        let defaultParaStyle = defaultParagraphStyle

        let cleanAttributes: [NSAttributedString.Key: Any] = [
            .font: defaultFont,
            .foregroundColor: defaultColor,
            .paragraphStyle: defaultParaStyle,
        ]

        let cleanString = NSAttributedString(string: plainText, attributes: cleanAttributes)

        // Replace the content
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: cleanString)
        storage.endEditing()

        Logger.debug("Removed formatting from \(range.length) characters", category: Logger.ui)
    }
}
