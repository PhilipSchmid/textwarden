//
//  ReplacementContext.swift
//  TextWarden
//
//  Context object carrying all information needed for a text replacement operation.
//  Built once at the start of replacement with resolved indices.
//

@preconcurrency import ApplicationServices
import Foundation

// MARK: - Index System

/// The indexing system used by the target application
enum IndexSystem {
    /// UTF-16 code units (Chromium/Electron/WebKit apps, JavaScript-based)
    case utf16

    /// Grapheme clusters (native macOS apps, Swift String indices)
    case grapheme
}

// MARK: - Replacement Context

/// Complete context for a text replacement operation.
/// Captures everything needed upfront to avoid re-reading element state during replacement.
struct ReplacementContext {
    // MARK: - Core Elements

    /// The AX element where replacement will occur
    let element: AXUIElement

    /// Application configuration from AppRegistry
    let appConfig: AppConfiguration

    // MARK: - Text Content

    /// The full text content of the element at time of context creation
    let currentText: String

    /// The text that will be replaced (extracted using errorRange)
    let errorText: String

    /// The replacement text to insert
    let replacement: String

    // MARK: - Harper Indices (Source)

    /// Harper's Unicode scalar range for the error
    /// This is the authoritative source - all other ranges derive from this
    let harperRange: Range<Int>

    // MARK: - Resolved Indices (Target)

    /// Range converted for the target application's AX API.
    /// For Electron/WebKit apps: UTF-16 code units.
    /// For native apps: Grapheme cluster count.
    let resolvedRange: CFRange

    /// The index system used for resolvedRange
    let indexSystem: IndexSystem

    // MARK: - Initialization

    /// Create a replacement context with resolved indices.
    /// - Parameters:
    ///   - element: The AX element to replace text in
    ///   - appConfig: Configuration for the target application
    ///   - currentText: Current text content of the element
    ///   - harperStart: Start of error range (Unicode scalar index)
    ///   - harperEnd: End of error range (Unicode scalar index)
    ///   - replacement: The replacement text
    /// - Returns: Configured context, or nil if indices cannot be resolved
    init?(
        element: AXUIElement,
        appConfig: AppConfiguration,
        currentText: String,
        harperStart: Int,
        harperEnd: Int,
        replacement: String
    ) {
        self.element = element
        self.appConfig = appConfig
        self.currentText = currentText
        self.replacement = replacement
        harperRange = harperStart ..< harperEnd

        // Extract error text using Harper's scalar indices
        guard let extractedText = TextIndexConverter.extractErrorText(
            start: harperStart,
            end: harperEnd,
            from: currentText
        ) else {
            Logger.warning(
                "ReplacementContext: Failed to extract error text at \(harperStart)..<\(harperEnd)",
                category: Logger.analysis
            )
            return nil
        }
        errorText = extractedText

        // Determine index system based on app category
        let indexSystem = Self.determineIndexSystem(for: appConfig)
        self.indexSystem = indexSystem

        // Convert Harper indices to target system
        guard let resolvedRange = Self.resolveRange(
            harperStart: harperStart,
            harperEnd: harperEnd,
            text: currentText,
            indexSystem: indexSystem
        ) else {
            Logger.warning(
                "ReplacementContext: Failed to resolve range for \(appConfig.identifier)",
                category: Logger.analysis
            )
            return nil
        }
        self.resolvedRange = resolvedRange
    }

    // MARK: - Index Resolution

    /// Determine which index system an app uses
    private static func determineIndexSystem(for appConfig: AppConfiguration) -> IndexSystem {
        // Use AppBehaviorRegistry to get the explicit per-app index system setting
        let appBehavior = AppBehaviorRegistry.shared.behavior(for: appConfig)
        return appBehavior.usesUTF16TextIndices ? .utf16 : .grapheme
    }

    /// Convert Harper's scalar range to the target index system
    private static func resolveRange(
        harperStart: Int,
        harperEnd: Int,
        text: String,
        indexSystem: IndexSystem
    ) -> CFRange? {
        switch indexSystem {
        case .utf16:
            return TextIndexConverter.scalarRangeToUTF16CFRange(
                start: harperStart,
                end: harperEnd,
                in: text
            )

        case .grapheme:
            // Convert scalars to String.Index, then count graphemes
            guard let startIndex = TextIndexConverter.scalarIndexToStringIndex(harperStart, in: text),
                  let endIndex = TextIndexConverter.scalarIndexToStringIndex(harperEnd, in: text)
            else {
                return nil
            }
            let startOffset = text.distance(from: text.startIndex, to: startIndex)
            let length = text.distance(from: startIndex, to: endIndex)
            return CFRange(location: startOffset, length: max(1, length))
        }
    }
}
