import AppKit
@testable import TextWarden
import XCTest

final class TextInputPanelTests: XCTestCase {
    @MainActor
    func testEditShortcutsWithAndWithoutTextFocus() throws {
        let panel = TextInputPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let editor = EditCommandRecorder(frame: panel.contentView?.bounds ?? .zero)
        panel.contentView = editor

        for key in ["c", "v", "x"] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                                       timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                                                       characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0))
            XCTAssertTrue(panel.makeFirstResponder(panel))
            // A review panel can have keyboard focus without an active text editor.
            _ = panel.performKeyEquivalent(with: event)
            XCTAssertTrue(editor.commands.isEmpty)

            XCTAssertTrue(panel.makeFirstResponder(editor))
            XCTAssertTrue(panel.performKeyEquivalent(with: event))
            XCTAssertEqual(editor.commands, [key])
            editor.commands.removeAll()
        }
    }
}

private final class EditCommandRecorder: NSTextView {
    var commands: [String] = []
    override func copy(_: Any?) {
        commands.append("c")
    }

    override func paste(_: Any?) {
        commands.append("v")
    }

    override func cut(_: Any?) {
        commands.append("x")
    }
}
