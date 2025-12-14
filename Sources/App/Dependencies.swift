//
//  Dependencies.swift
//  TextWarden
//
//  Dependency injection infrastructure for testability.
//
//  This module provides:
//  1. Protocols defining the interfaces for key services
//  2. A DependencyContainer that holds all injectable dependencies
//  3. Protocol conformance extensions for production classes
//
//  Usage in production:
//    let coordinator = AnalysisCoordinator()  // Uses default production dependencies
//
//  Usage in tests:
//    let mockMonitor = MockTextMonitor()
//    let coordinator = AnalysisCoordinator(dependencies: .init(
//        textMonitor: mockMonitor,
//        ...
//    ))
//

import Foundation
import AppKit
@preconcurrency import ApplicationServices

// MARK: - Service Protocols

/// Protocol for grammar analysis engine
@MainActor
protocol GrammarAnalyzing {
    func analyzeText(
        _ text: String,
        dialect: String,
        enableInternetAbbrev: Bool,
        enableGenZSlang: Bool,
        enableITTerminology: Bool,
        enableBrandNames: Bool,
        enablePersonNames: Bool,
        enableLastNames: Bool,
        enableLanguageDetection: Bool,
        excludedLanguages: [String],
        enableSentenceStartCapitalization: Bool
    ) -> GrammarAnalysisResult
}

/// Protocol for LLM style analysis
@MainActor
protocol StyleAnalyzing {
    var isInitialized: Bool { get }
    func isModelLoaded() -> Bool
    func getLoadedModelId() -> String
    func analyzeStyle(_ text: String, style: WritingStyle) -> StyleAnalysisResultModel
}

/// Protocol for user preferences access
@MainActor
protocol UserPreferencesProviding: AnyObject {
    // Grammar settings
    var selectedDialect: String { get }
    var enableInternetAbbreviations: Bool { get }
    var enableGenZSlang: Bool { get }
    var enableITTerminology: Bool { get }
    var enableBrandNames: Bool { get }
    var enablePersonNames: Bool { get }
    var enableLastNames: Bool { get }
    var enableLanguageDetection: Bool { get }
    var excludedLanguages: Set<String> { get }
    var enableSentenceStartCapitalization: Bool { get }

    // Filtering settings
    var enabledCategories: Set<String> { get }
    var ignoredRules: Set<String> { get }
    var ignoredErrorTexts: Set<String> { get }

    // Style settings
    var enableStyleChecking: Bool { get }
    var autoStyleChecking: Bool { get }
    var selectedWritingStyle: String { get }
    var styleConfidenceThreshold: Double { get }
    var styleMinSentenceWords: Int { get }

    // Debug settings
    var showDebugBorderCGWindowCoords: Bool { get }
    var showDebugBorderCocoaCoords: Bool { get }
    var showDebugBorderTextFieldBounds: Bool { get }

    // Methods
    func isEnabled(forURL url: URL) -> Bool
    func ignoreErrorText(_ text: String)
    func ignoreRule(_ ruleId: String)
    static func languageCode(for displayName: String) -> String
}

/// Protocol for custom vocabulary access
@MainActor
protocol CustomVocabularyProviding {
    func containsAnyWord(in text: String) -> Bool
    func addWord(_ word: String) throws
}

/// Protocol for app configuration registry
@MainActor
protocol AppConfigurationProviding {
    func configuration(for bundleID: String) -> AppConfiguration
    func effectiveConfiguration(for bundleID: String) -> AppConfiguration
}

/// Protocol for browser URL extraction
@MainActor
protocol BrowserURLExtracting {
    func extractURL(processID: pid_t, bundleIdentifier: String) -> URL?
}

/// Protocol for position resolution
@MainActor
protocol PositionResolving {
    func resolvePosition(
        for errorRange: NSRange,
        in element: AXUIElement,
        text: String,
        parser: ContentParser,
        bundleID: String
    ) -> GeometryResult
}

/// Protocol for user statistics tracking
@MainActor
protocol StatisticsTracking {
    func recordDetailedAnalysisSession(
        wordsProcessed: Int,
        errorsFound: Int,
        bundleIdentifier: String?,
        categoryBreakdown: [String: Int],
        latencyMs: Double
    )
    func recordSuggestionApplied(category: String)
    func recordSuggestionDismissed()
}

// MARK: - Protocol Conformance

extension GrammarEngine: GrammarAnalyzing {}
extension LLMEngine: StyleAnalyzing {}
extension CustomVocabulary: CustomVocabularyProviding {}
extension AppRegistry: AppConfigurationProviding {}
extension BrowserURLExtractor: BrowserURLExtracting {}
extension PositionResolver: PositionResolving {}
extension UserStatistics: StatisticsTracking {}

// UserPreferences conformance (needs explicit declaration due to static method)
extension UserPreferences: UserPreferencesProviding {}

// MARK: - Dependency Container

/// Container holding all injectable dependencies for AnalysisCoordinator.
/// Production code uses `.production` which wires up all real singletons.
/// Tests can create custom containers with mock implementations.
@MainActor
struct DependencyContainer {
    // Core services
    let textMonitor: TextMonitor
    let applicationTracker: ApplicationTracker
    let permissionManager: PermissionManager

    // Analysis engines
    let grammarEngine: GrammarAnalyzing
    let llmEngine: StyleAnalyzing

    // Configuration and preferences
    let userPreferences: UserPreferencesProviding
    let appRegistry: AppConfigurationProviding
    let customVocabulary: CustomVocabularyProviding

    // Utilities
    let browserURLExtractor: BrowserURLExtracting
    let positionResolver: PositionResolving
    let statistics: StatisticsTracking

    // UI components (concrete types - less commonly mocked)
    let suggestionPopover: SuggestionPopover
    let floatingIndicator: FloatingErrorIndicator

    /// Production container with all real dependencies
    static let production = DependencyContainer(
        textMonitor: TextMonitor(),
        applicationTracker: .shared,
        permissionManager: .shared,
        grammarEngine: GrammarEngine.shared,
        llmEngine: LLMEngine.shared,
        userPreferences: UserPreferences.shared,
        appRegistry: AppRegistry.shared,
        customVocabulary: CustomVocabulary.shared,
        browserURLExtractor: BrowserURLExtractor.shared,
        positionResolver: PositionResolver.shared,
        statistics: UserStatistics.shared,
        suggestionPopover: .shared,
        floatingIndicator: .shared
    )

    init(
        textMonitor: TextMonitor,
        applicationTracker: ApplicationTracker,
        permissionManager: PermissionManager,
        grammarEngine: GrammarAnalyzing,
        llmEngine: StyleAnalyzing,
        userPreferences: UserPreferencesProviding,
        appRegistry: AppConfigurationProviding,
        customVocabulary: CustomVocabularyProviding,
        browserURLExtractor: BrowserURLExtracting,
        positionResolver: PositionResolving,
        statistics: StatisticsTracking,
        suggestionPopover: SuggestionPopover,
        floatingIndicator: FloatingErrorIndicator
    ) {
        self.textMonitor = textMonitor
        self.applicationTracker = applicationTracker
        self.permissionManager = permissionManager
        self.grammarEngine = grammarEngine
        self.llmEngine = llmEngine
        self.userPreferences = userPreferences
        self.appRegistry = appRegistry
        self.customVocabulary = customVocabulary
        self.browserURLExtractor = browserURLExtractor
        self.positionResolver = positionResolver
        self.statistics = statistics
        self.suggestionPopover = suggestionPopover
        self.floatingIndicator = floatingIndicator
    }
}

// MARK: - Lightweight Service Locator for Static Access

/// Provides access to shared dependencies for code that can't easily use DI.
/// This is a bridge pattern - prefer constructor injection where possible.
@MainActor
enum Services {
    private static var _container: DependencyContainer?

    /// Configure the global service container (call once at app startup)
    static func configure(with container: DependencyContainer) {
        _container = container
    }

    /// Access the configured container, falls back to production if not configured
    static var current: DependencyContainer {
        _container ?? .production
    }

    /// Reset to production (useful for test teardown)
    static func reset() {
        _container = nil
    }
}
