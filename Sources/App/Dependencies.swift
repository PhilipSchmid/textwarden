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

import AppKit
@preconcurrency import ApplicationServices
import Foundation

// MARK: - Service Protocols

/// Protocol for grammar analysis engine
/// Thread-safe: implementations must be safe to call from any thread
protocol GrammarAnalyzing: Sendable {
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
        enforceOxfordComma: Bool,
        checkEllipsis: Bool,
        checkUnclosedQuotes: Bool,
        checkDashes: Bool
    ) -> GrammarAnalysisResult
}

/// Protocol for user preferences access
@MainActor
protocol UserPreferencesProviding: AnyObject {
    // Global state
    var isEnabled: Bool { get }
    var disabledApplications: Set<String> { get }

    // Grammar settings
    var selectedDialect: String { get }
    var enableInternetAbbreviations: Bool { get }
    var enableGenZSlang: Bool { get }
    var enableITTerminology: Bool { get }
    var enableBrandNames: Bool { get }
    var enablePersonNames: Bool { get }
    var enableLastNames: Bool { get }
    var enableMacOSDictionary: Bool { get }
    var enableLanguageDetection: Bool { get }
    var excludedLanguages: Set<String> { get }

    // Individual rule toggles
    var enforceOxfordComma: Bool { get }
    var checkEllipsis: Bool { get }
    var checkUnclosedQuotes: Bool { get }
    var checkDashes: Bool { get }

    // Filtering settings
    var enabledCategories: Set<String> { get }
    var ignoredRules: Set<String> { get }
    var ignoredErrorTexts: Set<String> { get }

    // Style settings (Apple Intelligence)
    var enableStyleChecking: Bool { get }
    var autoStyleChecking: Bool { get }
    var selectedWritingStyle: String { get }
    var styleConfidenceThreshold: Double { get }
    var styleMinSentenceWords: Int { get }
    var styleTemperaturePreset: String { get }

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
    func allWords() -> [String]
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
    func clearCache()
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
    func recordWordAddedToDictionary()
    func recordStyleSuggestions(count: Int, latencyMs: Double, modelId: String, preset: String)
}

/// Protocol for content parser factory
@MainActor
protocol ContentParserProviding {
    func parser(for bundleID: String) -> ContentParser
}

// Note: TextReplacementCoordinating is defined in TextReplacementCoordinator.swift

/// Protocol for typing detection
@MainActor
protocol TypingDetecting: AnyObject {
    var onTypingStarted: (() -> Void)? { get set }
    var onTypingStopped: (() -> Void)? { get set }
    var currentBundleID: String? { get set }
    var isCurrentlyTyping: Bool { get }
    func notifyTextChange()
    func reset()
    func cleanup()
}

// MARK: - Protocol Conformance

extension GrammarEngine: GrammarAnalyzing {}
extension CustomVocabulary: CustomVocabularyProviding {}
extension AppRegistry: AppConfigurationProviding {}
extension BrowserURLExtractor: BrowserURLExtracting {}
extension PositionResolver: PositionResolving {}
extension UserStatistics: StatisticsTracking {}
extension ContentParserFactory: ContentParserProviding {}
extension TypingDetector: TypingDetecting {}
// Note: TextReplacementCoordinator conforms to TextReplacementCoordinating in its own file

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

    // Configuration and preferences
    let userPreferences: UserPreferencesProviding
    let appRegistry: AppConfigurationProviding
    let customVocabulary: CustomVocabularyProviding

    // Utilities
    let browserURLExtractor: BrowserURLExtracting
    let positionResolver: PositionResolving
    let statistics: StatisticsTracking
    let contentParserFactory: ContentParserProviding
    let typingDetector: TypingDetecting
    let textReplacementCoordinator: TextReplacementCoordinating

    // UI components (concrete types - less commonly mocked)
    let suggestionPopover: SuggestionPopover
    let floatingIndicator: FloatingErrorIndicator

    /// Production container with all real dependencies
    static let production = DependencyContainer(
        textMonitor: TextMonitor(),
        applicationTracker: .shared,
        permissionManager: .shared,
        grammarEngine: GrammarEngine.shared,
        userPreferences: UserPreferences.shared,
        appRegistry: AppRegistry.shared,
        customVocabulary: CustomVocabulary.shared,
        browserURLExtractor: BrowserURLExtractor.shared,
        positionResolver: PositionResolver.shared,
        statistics: UserStatistics.shared,
        contentParserFactory: ContentParserFactory.shared,
        typingDetector: TypingDetector.shared,
        textReplacementCoordinator: TextReplacementCoordinator(),
        suggestionPopover: .shared,
        floatingIndicator: .shared
    )

    init(
        textMonitor: TextMonitor,
        applicationTracker: ApplicationTracker,
        permissionManager: PermissionManager,
        grammarEngine: GrammarAnalyzing,
        userPreferences: UserPreferencesProviding,
        appRegistry: AppConfigurationProviding,
        customVocabulary: CustomVocabularyProviding,
        browserURLExtractor: BrowserURLExtracting,
        positionResolver: PositionResolving,
        statistics: StatisticsTracking,
        contentParserFactory: ContentParserProviding,
        typingDetector: TypingDetecting,
        textReplacementCoordinator: TextReplacementCoordinating,
        suggestionPopover: SuggestionPopover,
        floatingIndicator: FloatingErrorIndicator
    ) {
        self.textMonitor = textMonitor
        self.applicationTracker = applicationTracker
        self.permissionManager = permissionManager
        self.grammarEngine = grammarEngine
        self.userPreferences = userPreferences
        self.appRegistry = appRegistry
        self.customVocabulary = customVocabulary
        self.browserURLExtractor = browserURLExtractor
        self.positionResolver = positionResolver
        self.statistics = statistics
        self.contentParserFactory = contentParserFactory
        self.typingDetector = typingDetector
        self.textReplacementCoordinator = textReplacementCoordinator
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
