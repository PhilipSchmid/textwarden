import AppKit
@preconcurrency import ApplicationServices

/// Captures identity as well as text: two identical phrases are not the same selection.
struct QuickRewriteSelection {
    let target: TextGenerationInsertionTarget
    let text: String
    let range: CFRange?

    @MainActor
    static func capture(element: AXUIElement, context: ApplicationContext, usesMarkers: Bool) -> QuickRewriteSelection? {
        let marker = usesMarkers ? MailContentParser.selectionSnapshot(in: element) : nil
        let range = AccessibilityBridge.getSelectedTextRange(element)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
        guard let text = marker?.text ?? (result == .success ? value as? String : nil),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              marker != nil || (range?.length ?? 0) > 0
        else { return nil }
        return QuickRewriteSelection(
            target: .init(element: element, context: context, mailSelection: marker),
            text: text,
            range: range
        )
    }

    @MainActor
    func isCurrent(allowingPreviewFocus: Bool = false) -> Bool {
        let context = target.context
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard foreground == context.processID || (allowingPreviewFocus && foreground == ProcessInfo.processInfo.processIdentifier),
              AccessibilityBridge.isElement(target.element, inFocusedWindowOf: context) == true,
              allowingPreviewFocus || AccessibilityBridge.isFocusedElement(target.element, in: context) == true ||
              (target.mailSelection != nil && AccessibilityBridge.isElement(target.element, inFocusedWebAreaOf: context) == true),
              let current = Self.capture(element: target.element, context: context, usesMarkers: target.mailSelection != nil),
              current.text == text
        else { return false }

        if let marker = target.mailSelection {
            guard let currentMarker = current.target.mailSelection else { return false }
            return marker.matches(currentMarker)
        }
        return Self.rangesMatch(range, current.range)
    }

    static func rangesMatch(_ original: CFRange?, _ current: CFRange?) -> Bool {
        guard let original, let current, original.location >= 0, original.length > 0 else { return false }
        return original.location == current.location && original.length == current.length
    }
}

extension AnalysisCoordinator {
    func quickRewriteSelection() {
        Logger.debug("Quick Rewrite: Shortcut requested", category: Logger.llm)
        if let task = quickRewriteTask {
            Logger.debug("Quick Rewrite: Cancelling pending request", category: Logger.llm)
            task.cancel()
            QuickRewriteStatus.shared.show("Rewrite cancelled", completion: .cancelled)
            return
        }
        guard userPreferences.isEnabled, userPreferences.enableStyleChecking,
              let context = monitoredContext ?? textMonitor.currentContext,
              userPreferences.effectivePauseScope(for: context.bundleIdentifier) == nil,
              let element = textMonitor.monitoredElement,
              textMonitor.isEditableElement(element)
        else {
            Logger.debug("Quick Rewrite: App or Style checking is inactive, or no editable context", category: Logger.llm)
            QuickRewriteStatus.shared.show("Enable TextWarden and Style checking in this app to rewrite")
            return
        }
        guard capabilities(for: context).contains(.safeReplacement) else {
            Logger.debug("Quick Rewrite: Safe replacement unavailable", category: Logger.llm)
            QuickRewriteStatus.shared.show("Quick Rewrite is unavailable in this app's safe trial")
            return
        }
        let config = appRegistry.effectiveConfiguration(for: context.bundleIdentifier)
        guard let selection = QuickRewriteSelection.capture(element: element, context: context, usesMarkers: config.features.usesWebKitMarkerSelection),
              selection.isCurrent()
        else {
            Logger.debug("Quick Rewrite: Selection missing or no longer current", category: Logger.llm)
            QuickRewriteStatus.shared.show("Select text to rewrite")
            return
        }
        // ponytail: bound input for the on-device context window; add chunking only for a document rewrite feature.
        guard selection.text.utf8.count <= GenerationContext.maximumSelectionBytes else {
            Logger.debug("Quick Rewrite: Selection exceeds input limit", category: Logger.llm)
            QuickRewriteStatus.shared.show("Select a shorter passage to rewrite")
            return
        }
        guard #available(macOS 26.0, *) else {
            Logger.debug("Quick Rewrite: Unsupported macOS version", category: Logger.llm)
            QuickRewriteStatus.shared.show("Quick Rewrite requires macOS 26 and Apple Intelligence")
            return
        }
        let engine = FoundationModelsEngine()
        guard engine.status.isAvailable else {
            Logger.debug("Quick Rewrite: Model unavailable", category: Logger.llm)
            QuickRewriteStatus.shared.show(engine.status.userMessage)
            return
        }
        let style = WritingStyle.allCases.first { $0.displayName == userPreferences.selectedWritingStyle } ?? .default
        let preset = StyleTemperaturePreset(rawValue: userPreferences.styleTemperaturePreset) ?? .balanced
        let vocabulary = customVocabulary.allWords().filter { selection.text.localizedCaseInsensitiveContains($0) }
        QuickRewriteStatus.shared.show("Rewriting · \(style.displayName)", busy: true)
        floatingIndicator.updateQuickRewrite(isGenerating: true)

        quickRewriteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            Logger.debug("Quick Rewrite: Generation started", category: Logger.llm)
            // Once focus or selection changes, returning to it must not revive an old request.
            let watcher = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                    guard selection.isCurrent(allowingPreviewFocus: QuickRewriteStatus.shared.previewHasKeyboardFocus) else {
                        Logger.debug("Quick Rewrite: Source focus or selection changed", category: Logger.llm)
                        self?.quickRewriteTask?.cancel()
                        return
                    }
                }
            }
            defer {
                watcher.cancel()
                quickRewriteTask = nil
                floatingIndicator.updateQuickRewrite(isGenerating: false)
            }
            do {
                let rewrite = try await engine.rewriteSelection(selection.text, style: style, preset: preset, customVocabulary: vocabulary)
                let result = rewrite.text
                try Task.checkCancellation()
                guard userPreferences.isEnabled, userPreferences.enableStyleChecking,
                      userPreferences.effectivePauseScope(for: context.bundleIdentifier) == nil,
                      capabilities(for: context).contains(.safeReplacement),
                      selection.isCurrent()
                else { throw CancellationError() }
                guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    Logger.debug("Quick Rewrite: Empty result", category: Logger.llm)
                    QuickRewriteStatus.shared.show("No rewrite returned. Please try again.")
                    return
                }
                guard rewrite.hasChanges(comparedTo: selection.text) else {
                    Logger.debug(result == selection.text ? "Quick Rewrite: Result unchanged" : "Quick Rewrite: Ignored boundary-whitespace-only result", category: Logger.llm)
                    QuickRewriteStatus.shared.show("No rewrite suggested")
                    return
                }
                Logger.debug("Quick Rewrite: Awaiting review", category: Logger.llm)
                guard await QuickRewriteStatus.shared.confirmReplacement(original: selection.text, proposed: result, reason: rewrite.reason) else {
                    Logger.debug("Quick Rewrite: Review cancelled", category: Logger.llm)
                    QuickRewriteStatus.shared.show("Rewrite cancelled", completion: .cancelled)
                    return
                }
                Logger.debug("Quick Rewrite: Review accepted", category: Logger.llm)
                watcher.cancel()
                // The review panel held keyboard focus, but must never retarget a changed editor.
                try Task.checkCancellation()
                guard selection.isCurrent(allowingPreviewFocus: true) else { throw CancellationError() }
                NSRunningApplication(processIdentifier: context.processID)?.activate()
                try await Task.sleep(for: .milliseconds(100))
                try Task.checkCancellation()
                guard userPreferences.isEnabled, userPreferences.enableStyleChecking,
                      userPreferences.effectivePauseScope(for: context.bundleIdentifier) == nil,
                      capabilities(for: context).contains(.safeReplacement), selection.isCurrent()
                else { throw CancellationError() }
                watcher.cancel()
                lastReplacementTime = Date()
                let outcome = TextReplacementCoordinator.replaceCurrentSelection(result, element: element, appConfig: config, validate: { selection.isCurrent() })
                switch outcome {
                case .success, .unverified:
                    refreshAfterGeneratedInsertion(in: context, element: element)
                    QuickRewriteStatus.shared.show(outcome == .success ? "Text rewritten" : "Rewrite pasted", completion: outcome == .success ? .applied : nil)
                    Logger.info("Quick Rewrite: Applied selection rewrite", category: Logger.analysis)
                case .failed:
                    Logger.debug("Quick Rewrite: Replacement failed", category: Logger.llm)
                    QuickRewriteStatus.shared.show("Could not replace the selection. Please try again.")
                }
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError
                QuickRewriteStatus.shared.show(QuickRewriteStatus.failureMessage(for: error, cancelled: cancelled), completion: cancelled ? .cancelled : nil)
                Logger.debug("Quick Rewrite: Request ended without replacement", category: Logger.llm)
            }
        }
    }
}
