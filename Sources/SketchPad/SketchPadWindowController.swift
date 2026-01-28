//
//  SketchPadWindowController.swift
//  TextWarden
//
//  Manages the Sketch Pad window lifecycle and toggle behavior
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Controller for the Sketch Pad window
/// Follows the singleton pattern used by other window controllers in TextWarden
@MainActor
class SketchPadWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    static let shared = SketchPadWindowController()

    private var window: NSWindow?
    private weak var copyToolbarItem: NSToolbarItem?

    // Toolbar item identifiers
    private let sidebarToggleIdentifier = NSToolbarItem.Identifier("sidebarToggle")
    private let titleIdentifier = NSToolbarItem.Identifier("title")
    private let copyItemIdentifier = NSToolbarItem.Identifier("copy")
    private let exportItemIdentifier = NSToolbarItem.Identifier("export")

    /// Whether the Sketch Pad window is currently visible
    var isVisible: Bool {
        window?.isVisible ?? false
    }

    /// Whether the Sketch Pad window is the key window (has focus)
    var isKeyWindow: Bool {
        window?.isKeyWindow ?? false
    }

    override private init() {
        super.init()
    }

    /// Toggle the Sketch Pad window visibility
    /// If visible, hides it. If hidden, shows it.
    func toggleWindow() {
        if isVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }

    /// Show the Sketch Pad window, creating it if necessary
    func showWindow() {
        Logger.debug("SketchPadWindowController.showWindow() called", category: Logger.ui)

        // If window exists, just show it
        if let window {
            Logger.debug("Reusing existing Sketch Pad window", category: Logger.ui)
            NSApp.setActivationPolicy(.regular)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            // Ensure text view becomes first responder for keyboard shortcuts
            if let textView = SketchPadViewModel.shared.stTextView {
                window.makeFirstResponder(textView)
            }
            return
        }

        // Create new window
        Logger.debug("Creating new Sketch Pad window", category: Logger.ui)

        let sketchPadView = SketchPadView()
        let hostingController = NSHostingController(rootView: sketchPadView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "TextWarden - Sketch Pad"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false // Keep window alive when closed
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.minSize = NSSize(width: 900, height: 600)
        window.center()
        window.delegate = self
        window.level = .normal

        // Add toolbar for modern macOS "Toolbar window" style
        let toolbar = NSToolbar(identifier: "SketchPadToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = false
        // Hide system title - we'll use a custom centered title toolbar item
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .automatic

        // Store reference
        self.window = window

        // Show window
        NSApp.setActivationPolicy(.regular)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Set first responder after a short delay to allow SwiftUI view to create the text view
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if let textView = SketchPadViewModel.shared.stTextView {
                self?.window?.makeFirstResponder(textView)
                Logger.debug("Set STTextView as first responder", category: Logger.ui)
            }
        }

        Logger.info("Sketch Pad window displayed", category: Logger.ui)
    }

    /// Hide the Sketch Pad window
    func hideWindow() {
        Logger.debug("SketchPadWindowController.hideWindow() called", category: Logger.ui)

        window?.orderOut(nil)

        // Return to accessory mode if no other windows are visible
        DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.accessoryModeReturnDelay) {
            // Only return to accessory if settings window is also not visible
            let settingsVisible = NSApp.windows.contains { $0.title == "TextWarden Settings" && $0.isVisible }
            if !settingsVisible {
                NSApp.setActivationPolicy(.accessory)
                Logger.debug("Returned to menu bar only mode", category: Logger.ui)
            }
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_: Notification) {
        Logger.debug("Sketch Pad window will close", category: Logger.ui)

        // Save document immediately on window close
        Task {
            await SketchPadViewModel.shared.saveCurrentDocument()
        }

        // Return to accessory mode after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.accessoryModeReturnDelay) {
            // Only return to accessory if settings window is also not visible
            let settingsVisible = NSApp.windows.contains { $0.title == "TextWarden Settings" && $0.isVisible }
            if !settingsVisible {
                NSApp.setActivationPolicy(.accessory)
                Logger.debug("Returned to menu bar only mode after Sketch Pad close", category: Logger.ui)
            }
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        // Sidebar toggle on left, centered title, actions on right
        [sidebarToggleIdentifier, .flexibleSpace, titleIdentifier, .flexibleSpace, copyItemIdentifier, exportItemIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [sidebarToggleIdentifier, .flexibleSpace, titleIdentifier, copyItemIdentifier, exportItemIdentifier]
    }

    func toolbar(_: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar _: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case sidebarToggleIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Sidebar"
            item.paletteLabel = "Toggle Sidebar"
            item.toolTip = "Show or hide the sidebar"
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle Sidebar")
            item.target = self
            item.action = #selector(toggleSidebar)
            item.isBordered = true
            return item

        case titleIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Title"
            item.paletteLabel = "Title"

            // Create a simple text label for the title
            let titleLabel = NSTextField(labelWithString: "Sketch Pad")
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            titleLabel.textColor = NSColor.labelColor
            titleLabel.alignment = .center
            item.view = titleLabel
            return item

        case copyItemIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Copy"
            item.paletteLabel = "Copy"
            item.toolTip = "Copy document to clipboard"
            item.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
            item.target = self
            item.action = #selector(copyDocument)
            item.isBordered = true
            copyToolbarItem = item
            return item

        case exportItemIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Export"
            item.paletteLabel = "Export"
            item.toolTip = "Export as Markdown"
            item.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Export")
            item.target = self
            item.action = #selector(exportDocument)
            item.isBordered = true
            return item

        default:
            return nil
        }
    }

    @objc private func toggleSidebar() {
        SketchPadViewModel.shared.sidebarVisible.toggle()
        Logger.debug("Toggled sidebar: \(SketchPadViewModel.shared.sidebarVisible)", category: Logger.ui)
    }

    // MARK: - Toolbar Actions

    /// Copy document content to clipboard
    @objc private func copyDocument() {
        let viewModel = SketchPadViewModel.shared
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(viewModel.plainTextContent, forType: .string)

        // Show visual feedback - briefly change icon to checkmark
        if let item = copyToolbarItem {
            let originalImage = item.image
            item.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")

            // Revert to original icon after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak item] in
                item?.image = originalImage
            }
        }

        Logger.info("Copied document to clipboard", category: Logger.ui)
    }

    /// Export document as markdown file
    @objc private func exportDocument() {
        let viewModel = SketchPadViewModel.shared

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "\(viewModel.documentTitle).md"
        savePanel.title = "Export as Markdown"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            Task { @MainActor in
                do {
                    // Content is already markdown, write directly
                    try viewModel.plainTextContent.write(to: url, atomically: true, encoding: .utf8)
                    Logger.info("Exported document to: \(url.path)", category: Logger.ui)
                } catch {
                    Logger.error("Failed to export: \(error.localizedDescription)", category: Logger.ui)
                }
            }
        }
    }
}
