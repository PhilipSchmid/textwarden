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

/// The last reply from the external source, with the text it describes.
///
/// Held because the source answers after a round trip. Without it, every reply
/// that lands a keystroke late is lost in full, and on a slow server or a long
/// document the user would see external results only when they stopped typing
/// altogether.
struct ExternalGrammarResultCache {
    let text: String
    let errors: [GrammarErrorModel]
    let element: AXUIElement?

    /// Results belong to the field they were collected from; a different field
    /// has different text at the same offsets.
    func describes(element current: AXUIElement?) -> Bool {
        switch (element, current) {
        case (nil, nil):
            true
        case let (expected?, current?):
            CFEqual(expected, current)
        default:
            false
        }
    }
}

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
            timeout: LanguageToolConfiguration.defaultTimeout,
            characterLimit: userPreferences.languageToolCharacterLimit
        )
    }

    /// Drop any pending or in-flight external query. Called when monitoring
    /// stops, and on every new dispatch, so a request cannot outlive the field
    /// it was collected from.
    func cancelExternalGrammarSource() {
        externalGrammarSourceTimer?.invalidate()
        externalGrammarSourceTimer = nil
        externalGrammarSourceTask?.cancel()
        externalGrammarSourceTask = nil
        externalGrammarSourceInFlight = false
        externalGrammarResultCache = nil
    }

    /// Add back whatever the previous external reply still says about `text`.
    ///
    /// Called on the Harper path, which is the one place holding both fresh
    /// primary results and the current text. The results it revives are
    /// replaced wholesale when the next reply arrives, so a stale judgement
    /// never outlives the round trip that supersedes it.
    func withRevivedExternalResults(
        _ primary: [GrammarErrorModel],
        text: String,
        element: AXUIElement?
    ) -> [GrammarErrorModel] {
        guard userPreferences.enableLanguageToolSource,
              let cache = externalGrammarResultCache,
              cache.describes(element: element)
        else {
            return primary
        }

        let revived = GrammarResultRebaser.surviving(
            cache.errors,
            computedFor: cache.text,
            stillValidIn: text
        )
        guard !revived.isEmpty else { return primary }

        Logger.debug(
            "AnalysisCoordinator: Revived \(revived.count) of \(cache.errors.count) external result(s)",
            category: Logger.analysis
        )
        return GrammarResultMerger.merge(
            primary: primary,
            secondary: revived,
            limit: userPreferences.maxErrorsForUnderlines
        )
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
        // Supersede a query that has not been sent yet. A request already in
        // flight is deliberately left running; see armExternalGrammarSourceTimer.
        externalGrammarSourceTimer?.invalidate()
        externalGrammarSourceTimer = nil

        guard captureLanguageToolConfiguration() != nil else { return }

        // Identity of the analysis this request belongs to, taken while it is
        // still current. Checked again before sending and before applying.
        let snapshot = GrammarAnalysisRequest(
            generation: grammarAnalysisGeneration,
            sourceText: text,
            context: segment.context,
            element: element
        )

        armExternalGrammarSourceTimer(
            after: TimingConstants.externalGrammarSourceDebounce,
            primary: primary,
            snapshot: snapshot,
            text: text,
            element: element
        )
    }

    /// Wait for a pause in typing, then send, unless a request is still in
    /// flight, in which case wait again.
    ///
    /// Only one request is ever outstanding. Cancelling an HTTP request does
    /// not stop the server working on it: a LanguageTool worker has already
    /// read the body by then and discovers the closed socket only when it tries
    /// to write the reply, having performed the whole check in the meantime.
    /// Overlapping requests would therefore queue real work on someone's Mac
    /// for answers that are obsolete before they arrive.
    private func armExternalGrammarSourceTimer(
        after delay: TimeInterval,
        primary: [GrammarErrorModel],
        snapshot: GrammarAnalysisRequest,
        text: String,
        element: AXUIElement?
    ) {
        externalGrammarSourceTimerGeneration &+= 1
        let generation = externalGrammarSourceTimerGeneration
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Clear the property only if this is still the newest timer; a
                // newer one may have replaced it before this ran. Comparing
                // generations rather than timer identity keeps the non-Sendable
                // `Timer` from crossing into the `@Sendable` closure.
                if externalGrammarSourceTimerGeneration == generation {
                    externalGrammarSourceTimer = nil
                }

                // Stop rather than wait again once the analysis is stale: the
                // next edit arms its own timer with current text.
                guard isCurrentGrammarAnalysis(snapshot) else { return }

                guard !externalGrammarSourceInFlight else {
                    armExternalGrammarSourceTimer(
                        after: TimingConstants.externalGrammarSourceRetryDelay,
                        primary: primary,
                        snapshot: snapshot,
                        text: text,
                        element: element
                    )
                    return
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

        externalGrammarSourceInFlight = true
        externalGrammarSourceTask = Task { [weak self] in
            let result = await Self.fetchExternalResults(text: text, configuration: configuration)

            // Released on every path, so a failed or empty check does not wedge
            // the source shut until monitoring restarts.
            Task { @MainActor in
                self?.externalGrammarSourceInFlight = false
            }

            guard let external = result, let self else { return }

            // Cached even when empty: "this text is clean" is an answer, and
            // reviving a stale error over it would be a regression.
            Task { @MainActor [weak self] in
                self?.externalGrammarResultCache = ExternalGrammarResultCache(
                    text: text,
                    errors: external,
                    element: element
                )
            }

            guard !external.isEmpty else { return }
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

    /// Run one external check, turning every failure into `nil` after logging
    /// it at the level its cause deserves.
    private static func fetchExternalResults(
        text: String,
        configuration: LanguageToolConfiguration
    ) async -> [GrammarErrorModel]? {
        do {
            return try await LanguageToolClient.shared.check(text: text, configuration: configuration)
        } catch LanguageToolError.cancelled {
            return nil
        } catch let LanguageToolError.textTooLong(characters, limit) {
            Logger.debug(
                "AnalysisCoordinator: Skipping external source, \(characters) characters exceeds the \(limit) limit",
                category: Logger.analysis
            )
            return nil
        } catch LanguageToolError.cooldown {
            Logger.debug(
                "AnalysisCoordinator: Skipping external source, server is in failure cooldown",
                category: Logger.analysis
            )
            return nil
        } catch {
            Logger.info("AnalysisCoordinator: External grammar source failed: \(error)", category: Logger.analysis)
            return nil
        }
    }
}
