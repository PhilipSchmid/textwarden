//
//  AnalysisCoordinator+ExternalGrammarSource.swift
//  TextWarden
//
//  Optional external grammar source, kept apart from the Harper analysis path
//  so the two evolve independently.
//

import AppKit
@preconcurrency import ApplicationServices
import Foundation

extension AnalysisCoordinator {
    /// Build the external source configuration from preferences.
    ///
    /// Returns nil when the feature is off or the stored endpoint is not a
    /// loopback URL. Read this immediately before use, never from a cached
    /// copy: the user can disable the source or change servers at any time.
    func captureLanguageToolConfiguration() -> LanguageToolConfiguration? {
        guard userPreferences.enableLanguageToolSource else { return nil }
        return LanguageToolConfiguration(
            endpointString: userPreferences.languageToolEndpoint,
            language: userPreferences.languageToolLanguage,
            timeout: LanguageToolConfiguration.defaultTimeout
        )
    }

    /// Drop any pending external query. Called when monitoring stops so a
    /// debounced request cannot outlive the field it was collected from.
    func cancelExternalGrammarSource() {
        externalGrammarSourceTimer?.invalidate()
        externalGrammarSourceTimer = nil
    }

    /// Ask an external LanguageTool-compatible server for additional results.
    ///
    /// Harper has already published its results by the time this runs, so a
    /// slow, missing, or failing server costs only the results it would have
    /// added.
    func dispatchExternalGrammarSource(
        primary: [GrammarErrorModel],
        segment: TextSegment,
        text: String,
        element: AXUIElement?
    ) {
        cancelExternalGrammarSource()
        guard captureLanguageToolConfiguration() != nil else { return }

        // Identity of the analysis this request belongs to, taken while it is
        // still current. Checked again before sending and before applying.
        let snapshot = GrammarAnalysisRequest(
            generation: grammarAnalysisGeneration,
            sourceText: text,
            context: segment.context,
            element: element
        )

        // Wait for a pause in typing. Each keystroke replaces the pending
        // request rather than adding one, so a long edit costs one round trip
        // instead of dozens of discarded ones.
        let timer = Timer.scheduledTimer(
            withTimeInterval: TimingConstants.externalGrammarSourceDebounce,
            repeats: false
        ) { [weak self] firedTimer in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Clear the property only if it still refers to the timer that
                // fired; a newer one may have replaced it before this ran.
                if externalGrammarSourceTimer === firedTimer {
                    externalGrammarSourceTimer = nil
                }
                queryExternalGrammarSource(
                    primary: primary,
                    snapshot: snapshot,
                    text: text,
                    element: element
                )
            }
        }
        externalGrammarSourceTimer = timer
    }

    /// Perform the external request once typing has settled.
    private func queryExternalGrammarSource(
        primary: [GrammarErrorModel],
        snapshot: GrammarAnalysisRequest,
        text: String,
        element: AXUIElement?
    ) {
        // Re-read preferences rather than trusting the value captured when the
        // timer was armed: the user may have switched the source off, or
        // pointed it elsewhere, during the debounce.
        guard let configuration = captureLanguageToolConfiguration() else { return }

        // Nothing is sent once the analysis is stale. Monitoring may have
        // stopped, focus moved, or the text changed while the timer ran, and
        // checking only on the way back would transmit text regardless.
        guard isCurrentGrammarAnalysis(snapshot) else { return }

        Logger.debug(
            "AnalysisCoordinator: Querying external source (primary=\(primary.count))",
            category: Logger.analysis
        )

        Task { [weak self] in
            let external: [GrammarErrorModel]
            do {
                external = try await LanguageToolClient.shared.check(text: text, configuration: configuration)
            } catch {
                Logger.info("AnalysisCoordinator: External grammar source failed: \(error)", category: Logger.analysis)
                return
            }

            guard !external.isEmpty, let self else { return }
            guard isCurrentGrammarAnalysis(snapshot) else {
                Logger.debug("AnalysisCoordinator: Discarding stale external grammar result", category: Logger.analysis)
                return
            }

            // The ceiling keeps a late addition from hiding underlines the
            // user is already reading; see GrammarResultMerger.merge.
            let merged = GrammarResultMerger.merge(
                primary: primary,
                secondary: external,
                limit: userPreferences.maxErrorsForUnderlines
            )
            Logger.debug(
                "AnalysisCoordinator: External source added \(merged.count - primary.count) result(s)",
                category: Logger.analysis
            )
            applyFilters(to: merged, sourceText: text, element: element)

            // Harper's session was recorded before this reply arrived, so fold
            // the additions into it rather than leaving statistics disagreeing
            // with what the user was shown.
            let additions = merged.filter { $0.lintId.hasPrefix("\(LanguageToolClient.lintIdPrefix)::") }
            var additionBreakdown: [String: Int] = [:]
            for addition in additions {
                additionBreakdown[addition.category, default: 0] += 1
            }
            statistics.amendLastAnalysisSession(
                additionalErrors: additions.count,
                categoryBreakdown: additionBreakdown,
                bundleIdentifier: monitoredContext?.bundleIdentifier
            )
        }
    }
}
