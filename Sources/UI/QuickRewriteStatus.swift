import AppKit
import Combine
import SwiftUI

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Feedback for a shortcut that must leave keyboard focus in the source editor.
@MainActor
final class QuickRewriteStatus: ObservableObject {
    enum Completion {
        case applied, cancelled
    }

    static let shared = QuickRewriteStatus()
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?
    private(set) var previewPanel: TextInputPanel?
    private var previewDecision: ((Bool) -> Void)?
    private var previewID: UUID?
    private var reviewTimeout: Task<Void, Never>?
    @Published private(set) var reviewSecondsRemaining = 45
    @Published private(set) var reviewIsKeptOpen = false
    @Published var reviewIsHovered = false

    var previewHasKeyboardFocus: Bool {
        previewPanel?.isKeyWindow == true
    }

    func confirmReplacement(original: String, proposed: String, reason: SelectionRewriteResult.PreviewReason, timeoutSeconds: Int = 45) async -> Bool {
        let id = UUID()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return false }
            return await withCheckedContinuation { continuation in
                finishPreview(accepted: false)
                dismissal?.cancel()
                previewID = id
                previewDecision = { continuation.resume(returning: $0) }
                reviewSecondsRemaining = max(1, timeoutSeconds)
                reviewIsKeptOpen = NSWorkspace.shared.isVoiceOverEnabled
                reviewIsHovered = false
                let panel = TextInputPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.level = .floating
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = true
                panel.hidesOnDeactivate = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
                guard let screen else { finishPreview(accepted: false); return }
                let view = QuickRewritePreviewContent(original: original, proposed: proposed, reason: reason, status: self,
                                                      maximumHeight: max(80, min(320, screen.visibleFrame.height - 180)))
                { [weak self] accepted in
                    guard self?.previewID == id else { return }
                    self?.finishPreview(accepted: accepted)
                }
                // Establish wrapping width before asking SwiftUI for its ideal height.
                // A flexible-width fittingSize measures unwrapped text and clips the final layout.
                let font = NSFont.systemFont(ofSize: UserPreferences.shared.suggestionTextSize)
                let textWidth = max((original as NSString).size(withAttributes: [.font: font]).width,
                                    (proposed as NSString).size(withAttributes: [.font: font]).width)
                let width = min(max(320, ceil(textWidth) + 24), min(440, screen.visibleFrame.width - 32))
                let hosting = NSHostingView(rootView: view.frame(width: width).fixedSize(horizontal: false, vertical: true))
                panel.contentView = hosting
                let size = hosting.fittingSize
                let target = NSRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 24, width: size.width, height: size.height)
                let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                panel.setFrame(reduceMotion ? target : target.offsetBy(dx: 0, dy: -8), display: true)
                panel.alphaValue = reduceMotion ? 1 : 0
                previewPanel = panel
                panel.orderFrontRegardless()
                panel.makeKey()
                self.panel?.orderOut(nil)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = reduceMotion ? 0 : 0.2
                    panel.animator().setFrame(target, display: true)
                    panel.animator().alphaValue = 1
                }
                if !reviewIsKeptOpen {
                    reviewTimeout = Task { @MainActor [weak self] in
                        while !Task.isCancelled {
                            do { try await Task.sleep(for: .seconds(1)) } catch { return }
                            guard let self, previewID == id else { return }
                            guard !reviewIsHovered else { continue }
                            reviewSecondsRemaining -= 1
                            if reviewSecondsRemaining == 0 {
                                finishPreview(accepted: false)
                                return
                            }
                        }
                    }
                }
                NSAccessibility.post(element: panel, notification: .announcementRequested,
                                     userInfo: [.announcement: "Review rewrite. Enter applies, Escape cancels, Space keeps this review open.", .priority: NSAccessibilityPriorityLevel.high.rawValue])
            }
        } onCancel: {
            Task { @MainActor in
                guard self.previewID == id else { return }
                self.finishPreview(accepted: false)
            }
        }
    }

    func finishPreview(accepted: Bool) {
        reviewTimeout?.cancel()
        reviewTimeout = nil
        previewPanel?.orderOut(nil)
        previewPanel?.contentView = nil
        previewPanel = nil
        previewID = nil
        let decision = previewDecision
        previewDecision = nil
        decision?(accepted)
    }

    func keepReviewOpen() {
        guard previewID != nil else { return }
        reviewIsKeptOpen = true
        reviewTimeout?.cancel()
        reviewTimeout = nil
    }

    /// Never display the framework's debug description: it can contain source text.
    static func failureMessage(for error: Error, cancelled: Bool) -> String {
        if cancelled || error is CancellationError {
            return "Rewrite cancelled"
        }
        if let error = error as? FoundationModelsError {
            switch error {
            case .uncertainRewriteLanguage, .rewriteLanguageChanged:
                return error.localizedDescription
            default:
                break
            }
        }
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *), let error = error as? LanguageModelSession.GenerationError {
                switch error {
                case .guardrailViolation, .refusal:
                    return "Apple Intelligence could not process this selection · text left unchanged"
                case .exceededContextWindowSize:
                    return "Select a shorter passage · text left unchanged"
                case .unsupportedLanguageOrLocale:
                    return "Apple Intelligence does not support this language · text left unchanged"
                case .assetsUnavailable:
                    return "Apple Intelligence is unavailable · text left unchanged"
                default:
                    break
                }
            }
        #endif
        return "Could not rewrite. Please try again · text left unchanged"
    }

    func show(_ message: String, busy: Bool = false, completion: Completion? = nil) {
        dismissal?.cancel()
        if panel == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = panel
        }
        guard let panel, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let content = HStack(spacing: 6) {
            ZStack {
                if busy {
                    ProgressView().controlSize(.small)
                } else if let completion {
                    Image(systemName: completion == .applied ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(completion == .applied ? Color.green : Color.secondary)
                }
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Image("FeatherLogo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: min(280, screen.visibleFrame.width - 32))
        .fixedSize(horizontal: true, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        panel.contentView = hosting
        panel.setFrame(NSRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 24, width: size.width, height: size.height), display: true)
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16
            panel.animator().alphaValue = 1
        }
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        if !busy {
            dismissal = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard let panel = self?.panel else { return }
                let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.0 : 0.16
                await NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    panel.animator().alphaValue = 0
                }
                guard !Task.isCancelled else { return }
                panel.orderOut(nil)
            }
        }
    }
}

struct QuickRewritePreviewContent: View {
    let original: String
    let proposed: String
    let reason: SelectionRewriteResult.PreviewReason
    @ObservedObject var status: QuickRewriteStatus
    let maximumHeight: CGFloat
    let onDecision: (Bool) -> Void
    @ObservedObject private var preferences = UserPreferences.shared
    @Environment(\.colorScheme) private var systemColorScheme

    private var scheme: ColorScheme {
        preferences.overlayTheme == "Light" ? .light : preferences.overlayTheme == "Dark" ? .dark : systemColorScheme
    }

    private var reviewWarning: String? {
        switch reason {
        case .standard:
            nil
        case .transformation:
            "Generated using transformation mode after a blocked attempt. Check the meaning."
        case .quotationExtraction:
            "This rewrite omits text around a quotation. Check the meaning."
        }
    }

    var body: some View {
        let colors = AppColors(for: scheme)
        let size = CGFloat(preferences.suggestionTextSize)
        VStack(alignment: .leading, spacing: 10) {
            if let reviewWarning {
                Text(reviewWarning)
                    .font(.system(size: size * 0.9)).foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .vertical) {
                comparison(colors: colors, size: size)
                ScrollView { comparison(colors: colors, size: size) }
            }
            .frame(maxHeight: maximumHeight)
            Divider()
            HStack(spacing: 8) {
                Image("FeatherLogo").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 16, height: 16).foregroundStyle(colors.textSecondary).accessibilityHidden(true)
                Spacer()
                Button { onDecision(false) } label: {
                    HStack(spacing: 6) {
                        Text("Cancel")
                        if !status.reviewIsKeptOpen {
                            HStack(spacing: 3) {
                                Image(systemName: "pause.fill")
                                    .font(.system(size: 8))
                                    .opacity(status.reviewIsHovered ? 1 : 0)
                                Text("\(status.reviewSecondsRemaining)s").monospacedDigit()
                                    .frame(minWidth: 24, alignment: .trailing)
                            }
                            .foregroundStyle(.secondary)
                        }
                        Text("Esc").foregroundStyle(.secondary)
                    }
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel rewrite")
                .accessibilityValue(status.reviewIsKeptOpen ? "No time limit" : "\(status.reviewIsHovered ? "Timer paused at" : "Cancels without applying in") \(status.reviewSecondsRemaining) seconds")
                .help("Cancel (Escape). Hover to pause the countdown; press Space to keep this review open.")
                Button { onDecision(true) } label: {
                    HStack(spacing: 8) {
                        Text("Apply")
                        Image(systemName: "return").font(.system(size: 11, weight: .medium))
                            .frame(width: 14, height: 14).accessibilityHidden(true)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Apply rewrite")
                .help("Replace the original selection (Return)")
            }
            .controlSize(.small)
        }
        .padding(12)
        .writingAssistantSurface(colors: colors)
        .colorScheme(scheme)
        .onHover { status.reviewIsHovered = $0 }
        .background(Button("") { onDecision(false) }.keyboardShortcut(.escape, modifiers: .option).hidden())
        .background(Button("Keep review open") { status.keepReviewOpen() }.keyboardShortcut(.space, modifiers: []).hidden())
    }

    private func comparison(colors: AppColors, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Original").font(.system(size: size * 0.9, weight: .semibold)).foregroundStyle(colors.textSecondary)
            Text(original).foregroundStyle(colors.textPrimary)
            Text("Rewrite").font(.system(size: size * 0.9, weight: .semibold)).foregroundStyle(.blue).padding(.top, 4)
            Text(proposed).foregroundStyle(colors.textPrimary)
        }
        .font(.system(size: size))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
