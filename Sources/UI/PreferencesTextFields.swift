//
//  PreferencesTextFields.swift
//  TextWarden
//
//  Native macOS text field wrappers for use in preferences UI.
//

import SwiftUI
import AppKit

// MARK: - Native macOS Text Field (left-aligned)

/// A native macOS text field wrapper for SwiftUI with left-aligned text
struct LeftAlignedTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var onSubmit: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .exterior
        textField.alignment = .left
        textField.lineBreakMode = .byTruncatingTail
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onSubmit: (() -> Void)?

        init(text: Binding<String>, onSubmit: (() -> Void)?) {
            self._text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit?()
                return true
            }
            return false
        }
    }
}

// MARK: - Native macOS Search Field

/// A native macOS search field wrapper for SwiftUI
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = "Search..."

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = placeholder
        searchField.delegate = context.coordinator
        searchField.bezelStyle = .roundedBezel
        searchField.focusRingType = .exterior
        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            if let searchField = obj.object as? NSSearchField {
                text = searchField.stringValue
            }
        }
    }
}
