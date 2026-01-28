//
//  STTextViewWrapper.swift
//  TextWarden
//
//  SwiftUI wrapper for STTextView with markdown editing support
//  Provides text binding, layout info for underlines, and keyboard shortcuts
//

import AppKit
import STTextView
import SwiftUI

/// Layout info from STTextView for underline geometry calculations
@MainActor
struct STTextLayoutInfo {
    let textLayoutManager: NSTextLayoutManager
    let textContentManager: NSTextContentManager
    /// Reference to the text view for coordinate conversion
    weak var textView: STTextView?
    /// Reference to the scroll view for scroll offset handling
    weak var scrollView: NSScrollView?

    /// Get the gutter width (line number column width) if visible
    var gutterWidth: CGFloat {
        guard let textView, textView.showsLineNumbers else { return 0 }
        return textView.gutterView?.frame.width ?? 0
    }

    /// Get font metrics for proper underline positioning
    /// Returns (ascender, descender) where ascender is positive and descender is negative
    var fontMetrics: (ascender: CGFloat, descender: CGFloat) {
        guard let font = textView?.font else {
            // Fallback values for system font at 16pt
            return (ascender: 12.0, descender: -4.0)
        }
        return (ascender: font.ascender, descender: font.descender)
    }

    /// The offset from the top of a line rect to position an underline
    /// Underline should be at: origin.y + ascender - descender + small gap
    /// This positions it just below the text baseline where descenders reach
    var underlineYOffset: CGFloat {
        let metrics = fontMetrics
        // Position at baseline (origin + ascender) then below descenders (+ |descender|) + gap
        return metrics.ascender + abs(metrics.descender) + 1.0
    }

    /// Calculate rects for a character range, in the scroll view's coordinate space
    func rectsForRange(_ range: NSRange) -> [CGRect] {
        guard textView != nil,
              let textContentStorage = textContentManager as? NSTextContentStorage,
              let documentLocation = textContentStorage.documentRange.location as NSTextLocation?
        else {
            return []
        }

        // NOTE: We intentionally do NOT force layout here.
        // Forcing layout (layoutSubtreeIfNeeded/layoutViewport) from within a layout callback
        // or notification handler causes an infinite loop because:
        // 1. rectsForRange() is called from updateUnderlineRects()
        // 2. updateUnderlineRects() is called from frameDidChangeNotification
        // 3. Forcing layout triggers more frameDidChangeNotification
        // Instead, we rely on the layout already being valid when this is called.
        // If positions are stale, we'll get updated positions on the next layout pass.

        // Convert NSRange to NSTextRange
        guard let startLocation = textContentStorage.location(documentLocation, offsetBy: range.location),
              let endLocation = textContentStorage.location(startLocation, offsetBy: range.length),
              let textRange = NSTextRange(location: startLocation, end: endLocation)
        else {
            return []
        }

        var rects: [CGRect] = []

        // Get scroll offset
        let scrollOffset = scrollView?.contentView.bounds.origin ?? .zero

        // Get gutter offset (line numbers column width)
        let gutterOffset = gutterWidth

        textLayoutManager.enumerateTextSegments(
            in: textRange,
            type: .standard,
            options: []
        ) { segmentRange, segmentFrame, _, _ in
            guard segmentRange != nil else { return true }

            // Skip invalid frames (can happen if layout isn't ready)
            guard segmentFrame.width > 0, segmentFrame.height > 0 else { return true }

            // Convert the segment frame from text layout coordinates to scroll view coordinates
            // Add gutter offset for line numbers, subtract scroll offset for scroll position
            let adjustedRect = CGRect(
                x: segmentFrame.origin.x + gutterOffset - scrollOffset.x,
                y: segmentFrame.origin.y - scrollOffset.y,
                width: segmentFrame.width,
                height: segmentFrame.height
            )
            rects.append(adjustedRect)
            return true
        }

        return rects
    }
}

/// Custom scroll view that ensures the text view becomes first responder on click
class ClickableScrollView: NSScrollView {
    override func mouseDown(with event: NSEvent) {
        // Make the document view (STTextView) the first responder when clicked
        if let textView = documentView {
            window?.makeFirstResponder(textView)
        }
        super.mouseDown(with: event)
    }

    // Also handle mouse down in empty areas of the scroll view
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        // If click is in the scroll view but not on any subview, still activate the document view
        if result === self || result === contentView {
            window?.makeFirstResponder(documentView)
        }
        return result
    }
}

/// Helper class to handle mouse tracking for underline hover detection
/// Added to the text view to detect when mouse hovers over underlines
@MainActor
class UnderlineHoverTracker: NSObject {
    weak var textView: STTextView?
    weak var viewModel: SketchPadViewModel?
    /// Stores the BASE ID (without line segment suffix) of the currently hovered underline
    private var currentHoveredBaseId: String?

    /// Extract base ID from underline ID (removes line index suffix like "-0", "-1", etc.)
    private func baseId(from id: String) -> String {
        if let lastDashIndex = id.lastIndex(of: "-"),
           let suffix = Int(String(id[id.index(after: lastDashIndex)...]))
        {
            _ = suffix
            return String(id[..<lastDashIndex])
        }
        return id
    }

    /// Handle mouse moved - called synchronously from main thread
    func handleMouseMoved(at windowPoint: CGPoint) {
        processMouseMoved(at: windowPoint)
    }

    private func processMouseMoved(at windowPoint: CGPoint) {
        guard let textView, let viewModel else { return }

        // Convert window point to text view coordinates (document coordinates)
        // This already includes the gutter offset since it's in the text view's coordinate space
        let documentPoint = textView.convert(windowPoint, from: nil)

        // The underline rects are in viewport-relative coordinates:
        // underlineRect.x = segmentFrame.x + gutterWidth - scrollOffset.x
        // The documentPoint.x already includes gutterWidth (it's in text view coords)
        // So we just subtract scrollOffset to get viewport-relative coords
        let scrollOffset = textView.enclosingScrollView?.contentView.bounds.origin ?? .zero
        let viewportPoint = CGPoint(
            x: documentPoint.x - scrollOffset.x,
            y: documentPoint.y - scrollOffset.y
        )

        // Find underline at this viewport-relative point
        let found = findUnderline(at: viewportPoint, in: viewModel.underlineRects)

        if let underline = found {
            let newBaseId = baseId(from: underline.id)
            // Only show new popover if this is a different underline (by base ID)
            // This prevents re-showing when moving between line segments of the same underline
            if currentHoveredBaseId != newBaseId {
                currentHoveredBaseId = newBaseId
                // The underline rect is in viewport-relative coordinates:
                // underlineRect.x = segmentFrame.x + gutterWidth - scrollOffset.x
                // To get document (text view) coordinates for popover positioning,
                // we add scrollOffset back. The gutterWidth is already included.
                let scrollOffset = textView.enclosingScrollView?.contentView.bounds.origin ?? .zero
                let documentRect = CGRect(
                    x: underline.rect.origin.x + scrollOffset.x,
                    y: underline.rect.origin.y + scrollOffset.y,
                    width: underline.rect.width,
                    height: underline.rect.height
                )
                // Create a temporary underline with document coordinates for the popover
                let popoverUnderline = SketchUnderlineRect(
                    id: underline.id,
                    rect: documentRect,
                    category: underline.category,
                    message: underline.message,
                    range: underline.range,
                    scalarRange: underline.scalarRange,
                    suggestions: underline.suggestions,
                    originalText: underline.originalText,
                    lintId: underline.lintId
                )
                SketchPopoverController.shared.show(
                    for: popoverUnderline,
                    in: textView,
                    viewModel: viewModel
                )
            }
        } else {
            if currentHoveredBaseId != nil {
                currentHoveredBaseId = nil
                SketchPopoverController.shared.scheduleHide()
            }
        }
    }

    /// Handle mouse exited - called synchronously from main thread
    func handleMouseExited() {
        if currentHoveredBaseId != nil {
            currentHoveredBaseId = nil
            SketchPopoverController.shared.scheduleHide()
        }
    }

    private func findUnderline(at point: CGPoint, in underlines: [SketchUnderlineRect]) -> SketchUnderlineRect? {
        for underline in underlines {
            if underline.hitTestRect.contains(point) {
                return underline
            }
        }
        return nil
    }
}

/// NSViewRepresentable wrapper for STTextView
struct STTextViewWrapper: NSViewRepresentable {
    @ObservedObject var viewModel: SketchPadViewModel
    @ObservedObject private var preferences = UserPreferences.shared

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Use STTextView's factory method to get a properly configured text view with gutter
        let scrollView = STTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? STTextView else {
            return scrollView
        }

        // Configure scroll view
        // Respect macOS system preferences for scrollbar appearance
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        // Configure text view
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false

        // Apply user preferences for editor features
        let preferences = UserPreferences.shared
        textView.highlightSelectedLine = preferences.sketchPadHighlightLine
        textView.showsLineNumbers = preferences.sketchPadShowLineNumbers
        textView.showsInvisibleCharacters = preferences.sketchPadShowInvisibles

        // Line wrapping: when enabled, text wraps; when disabled, text scrolls horizontally
        textView.isHorizontallyResizable = !preferences.sketchPadLineWrapping

        // Configure gutter (line numbers column) when enabled
        if let gutterView = textView.gutterView {
            gutterView.drawSeparator = preferences.sketchPadShowLineNumbers
            // Use a compact gutter - 22pt is enough for 2-3 digit line numbers
            // The gutter auto-expands for larger numbers
            gutterView.minimumThickness = 22
        }

        // Typography settings
        let bodyFont = NSFont.systemFont(ofSize: 16)
        textView.font = bodyFont
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor

        // Create paragraph style with spacing
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.paragraphSpacing = 4
        textView.defaultParagraphStyle = paragraphStyle

        // Set delegate
        textView.textDelegate = context.coordinator

        // Store references
        context.coordinator.stTextView = textView
        viewModel.stTextView = textView

        // Set up hover tracking for underlines
        context.coordinator.setupHoverTracking(for: textView)

        // Set initial content
        if !viewModel.plainTextContent.isEmpty {
            textView.text = viewModel.plainTextContent
        }

        // Capture layout info for underline positioning
        viewModel.stLayoutInfo = STTextLayoutInfo(
            textLayoutManager: textView.textLayoutManager,
            textContentManager: textView.textContentManager,
            textView: textView,
            scrollView: scrollView
        )

        // Listen for frame changes to recalculate underline positions
        // Also use this to trigger initial layout when view gets valid frame
        textView.postsFrameChangedNotifications = true

        // Capture viewModel and coordinator weakly
        let weakViewModel = viewModel
        let theCoordinator = context.coordinator
        let theTextView = textView
        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: textView,
            queue: .main
        ) { [weak theTextView, weak theCoordinator] _ in
            // Bind weak refs to local constants before entering async context
            guard let capturedTextView = theTextView else { return }
            let capturedCoordinator = theCoordinator

            Task { @MainActor in
                // Check if we have a valid frame (non-zero dimensions)
                guard capturedTextView.frame.width > 0, capturedTextView.frame.height > 0 else { return }

                // Trigger initial layout refresh once when we get a valid frame
                if let coordinator = capturedCoordinator, !coordinator.initialLayoutDone {
                    coordinator.initialLayoutDone = true
                    // Delay to ensure window layout is fully settled before refreshing
                    // The refreshTextViewLayout() will call updateUnderlineRects() after layout completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        weakViewModel.refreshTextViewLayout()
                    }
                    // Don't update underline rects here - wait for refreshTextViewLayout to do it
                    return
                }

                // For subsequent frame changes (not initial), update underlines immediately
                weakViewModel.updateUnderlineRects()
            }
        }

        // Listen for scroll changes to update underline positions and scroll state
        let theScrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak theScrollView, weak theTextView] _ in
            // Bind weak refs to local constants before entering async context
            let capturedScrollView = theScrollView
            let capturedTextView = theTextView

            Task { @MainActor in
                weakViewModel.updateUnderlineRects()

                // Update scroll state for edge fade indicators
                if let scrollView = capturedScrollView, let textView = capturedTextView {
                    let contentSize = textView.frame.size
                    let visibleRect = scrollView.contentView.bounds
                    let scrollOffset = scrollView.contentView.bounds.origin
                    weakViewModel.updateScrollState(
                        contentSize: contentSize,
                        visibleRect: visibleRect,
                        scrollOffset: scrollOffset
                    )
                }
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context _: Context) {
        guard let textView = scrollView.documentView as? STTextView else { return }

        // Note: We intentionally do NOT sync viewModel.plainTextContent -> textView.text here.
        // The STTextView is the source of truth during editing. Syncing here would cause
        // a race condition with the async textDidChange callback, potentially clearing user input.
        // Content is synced TO the text view only in makeNSView (initial load) and loadDocument().

        // Update editor features based on preferences
        textView.highlightSelectedLine = preferences.sketchPadHighlightLine
        textView.showsInvisibleCharacters = preferences.sketchPadShowInvisibles

        // Update line wrapping
        let wrappingChanged = textView.isHorizontallyResizable == preferences.sketchPadLineWrapping
        textView.isHorizontallyResizable = !preferences.sketchPadLineWrapping

        // Update line numbers and force layout refresh if changed
        let lineNumbersChanged = textView.showsLineNumbers != preferences.sketchPadShowLineNumbers
        textView.showsLineNumbers = preferences.sketchPadShowLineNumbers

        // Configure gutter separator when line numbers change
        textView.gutterView?.drawSeparator = preferences.sketchPadShowLineNumbers

        // Force layout update when line numbers or wrapping toggle
        if lineNumbersChanged || wrappingChanged {
            // Force setFrameSize() to be called, which updates contentView.frame.origin.x
            // to account for gutter width. This is necessary because toggling line numbers
            // adds/removes the gutter but doesn't automatically adjust the content view origin.
            let currentSize = textView.frame.size
            textView.setFrameSize(NSSize(width: currentSize.width, height: currentSize.height + 1))
            textView.setFrameSize(currentSize)

            textView.needsLayout = true
            textView.layoutSubtreeIfNeeded()
            scrollView.needsLayout = true
            scrollView.layoutSubtreeIfNeeded()

            // Update underline positions after layout settles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak viewModel] in
                viewModel?.updateUnderlineRects()
            }
        }

        // Update layout info if needed
        if viewModel.stLayoutInfo == nil {
            viewModel.stLayoutInfo = STTextLayoutInfo(
                textLayoutManager: textView.textLayoutManager,
                textContentManager: textView.textContentManager,
                textView: textView,
                scrollView: scrollView
            )
        }
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, STTextViewDelegate {
        var viewModel: SketchPadViewModel
        weak var stTextView: STTextView?
        let hoverTracker = UnderlineHoverTracker()
        private var mouseEventMonitor: Any?
        private var trackingArea: NSTrackingArea?
        /// Flag to track if initial layout has been completed
        var initialLayoutDone = false

        init(viewModel: SketchPadViewModel) {
            self.viewModel = viewModel
            super.init()
        }

        deinit {
            if let monitor = mouseEventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        /// Set up mouse tracking for underline hover detection
        func setupHoverTracking(for textView: STTextView) {
            hoverTracker.textView = textView
            hoverTracker.viewModel = viewModel

            // Use a local event monitor to catch mouse moved events
            // This is more reliable than NSTrackingArea in SwiftUI/AppKit hybrid environments
            mouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                guard let self,
                      let textView = stTextView,
                      let window = textView.window,
                      event.window === window
                else {
                    return event
                }

                // Check if mouse is within the text view's frame
                let locationInWindow = event.locationInWindow
                let locationInTextView = textView.convert(locationInWindow, from: nil)

                // Process hover on main actor (event monitors run on main thread)
                if textView.bounds.contains(locationInTextView) {
                    MainActor.assumeIsolated {
                        self.hoverTracker.handleMouseMoved(at: locationInWindow)
                    }
                } else {
                    MainActor.assumeIsolated {
                        self.hoverTracker.handleMouseExited()
                    }
                }

                return event
            }
        }

        // MARK: - STTextViewDelegate

        func textViewDidChangeText(_ notification: Notification) {
            guard let textView = notification.object as? STTextView else { return }
            let content = textView.text ?? ""
            viewModel.plainTextContentInternal = content
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? STTextView else { return }
            let selectedRange = textView.selectedRange()
            viewModel.updateSelectionReadability(selectedRange: selectedRange)
        }
    }
}
