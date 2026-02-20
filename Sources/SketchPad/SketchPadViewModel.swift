//
//  SketchPadViewModel.swift
//  TextWarden
//
//  Central state management for the Sketch Pad feature
//

import AppKit
import Combine
import STTextView
import SwiftUI

/// Save status for the current document
enum SketchSaveStatus: Equatable {
    case saved
    case saving
    case unsaved
    case error(String)

    var displayText: String {
        switch self {
        case .saved:
            "Saved"
        case .saving:
            "Saving..."
        case .unsaved:
            "Unsaved"
        case let .error(message):
            "Error: \(message)"
        }
    }
}

/// Identifier for a dismissed suggestion (persisted per document)
struct DismissedSuggestionId: Codable, Hashable {
    let documentId: UUID
    let originalText: String
    let identifier: String // lintId for grammar errors, or message hash for style suggestions

    /// Create identifier from a unified suggestion
    static func from(_ suggestion: UnifiedSuggestion, documentId: UUID) -> DismissedSuggestionId {
        let identifier = suggestion.lintId ?? String(suggestion.message.hashValue)
        return DismissedSuggestionId(
            documentId: documentId,
            originalText: suggestion.originalText.lowercased(),
            identifier: identifier
        )
    }
}

/// Storage for dismissed suggestions (persisted to UserDefaults)
@MainActor
class DismissedSuggestionsStore {
    static let shared = DismissedSuggestionsStore()

    private let storageKey = "SketchPad.DismissedSuggestions"
    private var dismissedIds: Set<DismissedSuggestionId> = []

    private init() {
        load()
    }

    /// Check if a suggestion is dismissed for a document
    func isDismissed(_ suggestion: UnifiedSuggestion, documentId: UUID) -> Bool {
        let id = DismissedSuggestionId.from(suggestion, documentId: documentId)
        return dismissedIds.contains(id)
    }

    /// Dismiss a suggestion for a document
    func dismiss(_ suggestion: UnifiedSuggestion, documentId: UUID) {
        let id = DismissedSuggestionId.from(suggestion, documentId: documentId)
        dismissedIds.insert(id)
        save()
    }

    /// Clear all dismissals for a document (e.g., when document is deleted)
    func clearDismissals(for documentId: UUID) {
        dismissedIds = dismissedIds.filter { $0.documentId != documentId }
        save()
    }

    /// Count dismissed suggestions for a document
    func dismissedCount(for documentId: UUID) -> Int {
        dismissedIds.count(where: { $0.documentId == documentId })
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let ids = try? JSONDecoder().decode(Set<DismissedSuggestionId>.self, from: data)
        else {
            return
        }
        dismissedIds = ids
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(dismissedIds) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

/// Central view model for Sketch Pad
/// Manages document state, analysis results, and UI state
@MainActor
class SketchPadViewModel: ObservableObject {
    static let shared = SketchPadViewModel()

    /// Flag to prevent triggering save during initialization
    private var isInitializing = true

    /// Flag to prevent triggering analysis during document load (cache handles it)
    private var isLoadingDocument = false

    // MARK: - Document State

    /// Currently loaded document
    @Published var currentDocument: SketchDocument?

    /// Document IDs for which analysis is currently running in background
    /// This allows analysis to continue after switching documents
    private var analysisInProgressForDocuments: Set<UUID> = []

    /// Editable document title
    @Published var documentTitle: String = "Untitled" {
        didSet {
            if !isInitializing, documentTitle != oldValue {
                markAsUnsaved()
            }
        }
    }

    /// Current save status
    @Published var saveStatus: SketchSaveStatus = .saved

    /// Document content as attributed string
    @Published var attributedContent: NSAttributedString = .init() {
        didSet {
            if !isInitializing, !isLoadingDocument, attributedContent != oldValue {
                markAsUnsaved()
                scheduleAnalysis()
            }
        }
    }

    /// Plain text content - uses STTextView content if available, otherwise attributed content
    var plainTextContent: String {
        get {
            if stTextView != nil {
                return plainTextContentInternal
            }
            return attributedContent.string
        }
        set {
            plainTextContentInternal = newValue
        }
    }

    // MARK: - Analysis State

    /// Grammar errors from analysis
    @Published var grammarErrors: [GrammarErrorModel] = []

    /// Style suggestions from analysis
    @Published var styleSuggestions: [StyleSuggestionModel] = []

    /// Readability analysis result for the full document
    @Published var readabilityResult: ReadabilityResult?

    /// Readability analysis result for the current selection (nil if no meaningful selection)
    @Published var selectionReadabilityResult: ReadabilityResult?

    /// Whether we're currently showing selection readability (vs document readability)
    @Published var isShowingSelectionReadability: Bool = false

    /// The currently selected text (for readability calculation)
    @Published var selectedText: String = ""

    /// AI-generated readability tips for the document
    @Published var documentReadabilityTips: [String] = []

    /// AI-generated readability tips for the current selection
    @Published var selectionReadabilityTips: [String] = []

    /// Whether AI tips are currently being generated
    @Published var isLoadingReadabilityTips: Bool = false

    /// Unified insights combining all suggestion types
    @Published var unifiedInsights: [UnifiedSuggestion] = []

    /// Number of dismissed suggestions for current document
    @Published var dismissedSuggestionsCount: Int = 0

    /// AI Assistant prompt for the current document
    /// Cached per document so switching documents preserves the prompt
    @Published var aiAssistantPrompt: String = ""

    /// Cache of AI prompts per document ID
    private var aiPromptCache: [UUID: String] = [:]

    /// Cached analysis results for a document
    private struct CachedAnalysisResults {
        var grammarErrors: [GrammarErrorModel]
        var styleSuggestions: [StyleSuggestionModel]
        var unifiedInsights: [UnifiedSuggestion]
        var readabilityResult: ReadabilityResult?
        var documentReadabilityTips: [String]
        /// Hash of the text content when analysis was performed (to detect if re-analysis is needed)
        var contentHash: Int
    }

    /// Cache of analysis results per document ID
    private var analysisCache: [UUID: CachedAnalysisResults] = [:]

    // MARK: - UI State

    /// Currently selected insight (for highlighting)
    @Published var selectedInsightId: String?

    /// Range to highlight in the editor
    @Published var highlightedRange: NSRange?

    /// All available drafts
    @Published var drafts: [SketchDocument] = []

    /// Whether the sidebar is visible
    @Published var sidebarVisible: Bool = true

    /// Reference to STTextView for markdown editing
    weak var stTextView: STTextView?

    // MARK: - Undo/Redo Support

    /// Check if undo is available
    var canUndo: Bool {
        stTextView?.undoManager?.canUndo ?? false
    }

    /// Check if redo is available
    var canRedo: Bool {
        stTextView?.undoManager?.canRedo ?? false
    }

    /// Perform undo action
    func undo() {
        stTextView?.undoManager?.undo()
    }

    /// Perform redo action
    func redo() {
        stTextView?.undoManager?.redo()
    }

    /// Layout info from STTextView for underline positioning
    var stLayoutInfo: STTextLayoutInfo? {
        didSet {
            if stLayoutInfo != nil {
                updateUnderlineRects()
            }
        }
    }

    /// Internal plain text content for STTextView binding
    var plainTextContentInternal: String = "" {
        didSet {
            if !isInitializing, !isLoadingDocument, plainTextContentInternal != oldValue {
                markAsUnsaved()

                // When text becomes empty, immediately clear all analysis results
                // Don't wait for the debounced analysis - stale data looks like a bug
                if plainTextContentInternal.isEmpty {
                    clearAnalysisResults()
                } else {
                    // When text is shortened (deletion), immediately filter out insights
                    // that are now out of range - don't show stale positions
                    if plainTextContentInternal.count < oldValue.count {
                        filterStaleAnalysisResults()
                    }
                    scheduleAnalysis()
                }

                // Notify tracker if this is a genuine user edit (not from applying a suggestion)
                // This re-enables auto style analysis after user makes their own changes
                if !isApplyingStyleSuggestion {
                    suggestionTracker.notifyTextChanged(isGenuineEdit: true)
                }
            }
        }
    }

    // MARK: - SwiftUI TextEditor Support (macOS 26)

    /// AttributedString version of content for SwiftUI TextEditor binding
    var textEditorContent: AttributedString {
        get {
            AttributedString(attributedContent)
        }
        set {
            let nsAttributed = NSAttributedString(newValue)
            if nsAttributed != attributedContent {
                attributedContent = nsAttributed
            }
        }
    }

    /// Underline rects calculated from analysis results
    @Published var underlineRects: [SketchUnderlineRect] = []

    /// Y offset from top of text line rect to position underlines correctly
    /// Calculated from font metrics for proper baseline positioning
    @Published var underlineYOffset: CGFloat = 16.0 // Default, will be updated from layout info

    /// Currently hovered underline for popover display
    @Published var hoveredUnderline: SketchUnderlineRect?

    // MARK: - Scroll State (for edge fade indicators)

    /// Whether there's content beyond the right edge (when line wrapping is disabled)
    @Published var hasContentRight: Bool = false

    /// Whether there's content beyond the bottom edge
    @Published var hasContentBottom: Bool = false

    /// Update scroll state based on scroll view position
    func updateScrollState(contentSize: CGSize, visibleRect: CGRect, scrollOffset: CGPoint) {
        // Check if content extends beyond visible area
        hasContentRight = contentSize.width > visibleRect.width && scrollOffset.x + visibleRect.width < contentSize.width - 1
        hasContentBottom = contentSize.height > visibleRect.height && scrollOffset.y + visibleRect.height < contentSize.height - 1
    }

    // MARK: - Word Count

    /// Word count of current document
    var wordCount: Int {
        let words = plainTextContent.split { $0.isWhitespace || $0.isNewline }
        return words.count
    }

    /// Character count of current document (excluding whitespace)
    var characterCount: Int {
        plainTextContent.count(where: { !$0.isWhitespace && !$0.isNewline })
    }

    /// Line count of current document
    var lineCount: Int {
        let lines = plainTextContent.components(separatedBy: .newlines)
        return max(1, lines.count)
    }

    /// Estimated reading time in minutes
    var readingTimeMinutes: Int {
        max(1, wordCount / 200) // Average reading speed: 200 wpm
    }

    /// Minimum word count for selection readability calculation
    private let minimumSelectionWords = 5

    /// Cache for AI-generated readability tips
    private let readabilityTipsCache = ReadabilityTipsCache()

    /// Tracks accepted/dismissed suggestions to prevent endless re-analysis loops
    private let suggestionTracker = SuggestionTracker()

    /// Flag to track when a style suggestion is being applied (not a user edit)
    private var isApplyingStyleSuggestion = false

    /// Task for generating AI tips (cancelable)
    private var tipsGenerationTask: Task<Void, Never>?

    // MARK: - Style Analysis Rate Limiting

    /// Separate debounce task for style analysis (longer delay than grammar)
    private var styleAnalysisDebounceTask: Task<Void, Never>?

    /// Timestamp of last style analysis run
    private var lastStyleAnalysisTime: Date?

    /// Text hash of last style analysis (to avoid re-analyzing identical text)
    private var lastStyleAnalysisTextHash: Int?

    /// Minimum interval between style analyses (seconds)
    private let styleAnalysisMinInterval: TimeInterval = 15.0

    /// Debounce delay for style analysis (seconds) - user must stop typing for this long
    private let styleAnalysisDebounceDelay: TimeInterval = 2.0

    /// Minimum text length for style analysis
    private let styleAnalysisMinTextLength: Int = 50

    // MARK: - Readability Tips Rate Limiting

    /// Timestamp of last readability tips generation
    private var lastReadabilityTipsTime: Date?

    /// Text hash of last readability tips generation (to avoid re-generating for identical text)
    private var lastReadabilityTipsTextHash: Int?

    /// Minimum interval between readability tips generations (seconds)
    private let readabilityTipsMinInterval: TimeInterval = 10.0

    // MARK: - Selection Readability

    /// Update readability for the current text selection
    /// Called when selection changes in the text view
    func updateSelectionReadability(selectedRange: NSRange) {
        guard let stTextView, let text = stTextView.text else {
            clearSelectionReadability()
            return
        }

        // Get the selected text
        guard selectedRange.length > 0,
              let swiftRange = Range(selectedRange, in: text)
        else {
            clearSelectionReadability()
            return
        }

        let selection = String(text[swiftRange])

        // Count words in selection
        let words = selection.split { $0.isWhitespace || $0.isNewline }
        let wordCount = words.count

        // Only calculate if selection has enough words
        guard wordCount >= minimumSelectionWords else {
            clearSelectionReadability()
            return
        }

        selectedText = selection

        // Calculate readability for the selection
        if let result = ReadabilityCalculator.shared.fleschReadingEase(for: selection) {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectionReadabilityResult = result
                isShowingSelectionReadability = true
            }
            Logger.debug("Selection readability: \(Int(result.score)) (\(wordCount) words)", category: Logger.analysis)
            // Generate AI tips for selection (async, cached)
            generateSelectionReadabilityTips()
        } else {
            // Selection might not have proper sentence structure - calculate anyway for fragments
            // Treat the selection as a single sentence for calculation purposes
            let syllables = ReadabilityCalculator.shared.totalSyllables(selection)
            let syllablesPerWord = Double(syllables) / Double(wordCount)
            // Use average sentence length of the selection as the "words per sentence"
            let score = max(0, min(100, 206.835 - (1.015 * Double(wordCount)) - (84.6 * syllablesPerWord)))
            let result = ReadabilityResult(
                score: score,
                label: ReadabilityCalculator.shared.labelForScore(score),
                color: ReadabilityCalculator.shared.colorForScore(score),
                algorithm: .fleschReadingEase
            )
            withAnimation(.easeInOut(duration: 0.2)) {
                selectionReadabilityResult = result
                isShowingSelectionReadability = true
            }
            Logger.debug("Selection readability (fragment): \(Int(score)) (\(wordCount) words)", category: Logger.analysis)
            // Generate AI tips for selection (async, cached)
            generateSelectionReadabilityTips()
        }
    }

    /// Clear selection readability and revert to document readability
    private func clearSelectionReadability() {
        guard isShowingSelectionReadability else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            selectedText = ""
            selectionReadabilityResult = nil
            selectionReadabilityTips = []
            isShowingSelectionReadability = false
        }
    }

    // MARK: - AI Readability Tips

    /// Generate AI-powered readability tips for the document
    /// Called after document readability analysis completes
    func generateDocumentReadabilityTips() {
        guard let result = readabilityResult else {
            documentReadabilityTips = []
            return
        }

        let text = plainTextContent
        let score = Int(result.score)
        let targetAudienceName = UserPreferences.shared.selectedTargetAudience
        let targetAudience = TargetAudience(fromDisplayName: targetAudienceName) ?? .general

        // Check cache first (but don't use cached empty tips if score indicates text needs improvement)
        if let cached = readabilityTipsCache.get(text: text, targetAudience: targetAudienceName) {
            // If cache has tips OR score is good (70+), use cached result
            if !cached.isEmpty || score >= 70 {
                documentReadabilityTips = cached
                Logger.debug("Using cached document readability tips (\(cached.count) tips)", category: Logger.analysis)
                return
            }
            // Otherwise, cached empty tips but score < 70 - regenerate
            Logger.debug("Ignoring cached empty tips (score \(score) < 70 indicates issues)", category: Logger.analysis)
        }

        // Generate new tips asynchronously
        generateTipsAsync(for: text, score: score, targetAudience: targetAudience, isSelection: false)
    }

    /// Generate AI-powered readability tips for the current selection
    /// Called after selection readability is calculated
    private func generateSelectionReadabilityTips() {
        guard let result = selectionReadabilityResult, !selectedText.isEmpty else {
            selectionReadabilityTips = []
            return
        }

        let score = Int(result.score)
        let targetAudienceName = UserPreferences.shared.selectedTargetAudience
        let targetAudience = TargetAudience(fromDisplayName: targetAudienceName) ?? .general

        // Check cache first (but don't use cached empty tips if score indicates text needs improvement)
        if let cached = readabilityTipsCache.get(text: selectedText, targetAudience: targetAudienceName) {
            // If cache has tips OR score is good (70+), use cached result
            if !cached.isEmpty || score >= 70 {
                selectionReadabilityTips = cached
                Logger.debug("Using cached selection readability tips (\(cached.count) tips)", category: Logger.analysis)
                return
            }
            // Otherwise, cached empty tips but score < 70 - regenerate
            Logger.debug("Ignoring cached empty tips for selection (score \(score) < 70 indicates issues)", category: Logger.analysis)
        }

        // Generate new tips asynchronously
        generateTipsAsync(for: selectedText, score: score, targetAudience: targetAudience, isSelection: true)
    }

    /// Regenerate tips (user requested refresh)
    func regenerateReadabilityTips() {
        let isSelection = isShowingSelectionReadability
        let text = isSelection ? selectedText : plainTextContent
        let result = isSelection ? selectionReadabilityResult : readabilityResult

        guard let result, !text.isEmpty else { return }

        let score = Int(result.score)
        let targetAudienceName = UserPreferences.shared.selectedTargetAudience
        let targetAudience = TargetAudience(fromDisplayName: targetAudienceName) ?? .general

        // Force regeneration (bypass cache)
        generateTipsAsync(for: text, score: score, targetAudience: targetAudience, isSelection: isSelection, bypassCache: true)
    }

    /// Async helper to generate tips using Foundation Models
    private func generateTipsAsync(
        for text: String,
        score: Int,
        targetAudience: TargetAudience,
        isSelection: Bool,
        bypassCache: Bool = false
    ) {
        // Cancel any pending generation
        tipsGenerationTask?.cancel()

        let scope = isSelection ? "selection" : "document"
        let wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
        let contentHash = text.hashValue
        let documentId = currentDocument?.id.uuidString.prefix(8) ?? "nil"

        // Rate limiting (skip if bypassCache is true - manual regeneration)
        if !bypassCache {
            // Check minimum interval
            if let lastTime = lastReadabilityTipsTime {
                let elapsed = Date().timeIntervalSince(lastTime)
                if elapsed < readabilityTipsMinInterval {
                    Logger.debug("Sketch Pad: [Readability] Skipped - too soon (\(Int(elapsed))s < \(Int(readabilityTipsMinInterval))s)", category: Logger.analysis)
                    return
                }
            }

            // Check if text has changed since last generation
            if let lastHash = lastReadabilityTipsTextHash, lastHash == contentHash {
                Logger.debug("Sketch Pad: [Readability] Skipped - text unchanged", category: Logger.analysis)
                return
            }
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        Logger.debug("Sketch Pad: [Readability] Starting tips generation - scope=\(scope), words=\(wordCount), score=\(score), audience=\(targetAudience.displayName), doc=\(documentId)", category: Logger.analysis)

        tipsGenerationTask = Task {
            // Show loading state
            await MainActor.run {
                isLoadingReadabilityTips = true
                Logger.trace("Sketch Pad: [Readability] Set isLoadingReadabilityTips=true - doc=\(documentId)", category: Logger.analysis)
            }

            defer {
                Task { @MainActor in
                    isLoadingReadabilityTips = false
                    Logger.trace("Sketch Pad: [Readability] Set isLoadingReadabilityTips=false - doc=\(documentId)", category: Logger.analysis)
                }
            }

            // Check if Foundation Models is available
            guard #available(macOS 26.0, *) else {
                Logger.debug("Sketch Pad: [Readability] Aborted - macOS 26 required", category: Logger.analysis)
                return
            }

            // Check for early cancellation
            guard !Task.isCancelled else {
                Logger.debug("Sketch Pad: [Readability] Cancelled before starting - doc=\(documentId)", category: Logger.analysis)
                return
            }

            do {
                let engine = FoundationModelsEngine()
                let engineStatus = engine.status
                guard engineStatus == .available else {
                    Logger.warning("Sketch Pad: [Readability] Aborted - Apple Intelligence status=\(engineStatus.userMessage)", category: Logger.analysis)
                    return
                }

                // Small delay to avoid rapid-fire calls during typing
                try await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                guard !Task.isCancelled else {
                    Logger.debug("Sketch Pad: [Readability] Cancelled after debounce - doc=\(documentId)", category: Logger.analysis)
                    return
                }

                Logger.trace("Sketch Pad: [Readability] Calling Foundation Models engine - doc=\(documentId)", category: Logger.analysis)

                let tips = try await engine.generateReadabilityTips(
                    for: text,
                    score: score,
                    targetAudience: targetAudience
                )

                let elapsed = CFAbsoluteTimeGetCurrent() - startTime

                guard !Task.isCancelled else {
                    Logger.debug("Sketch Pad: [Readability] Cancelled after engine call - doc=\(documentId), elapsed=\(String(format: "%.2f", elapsed))s", category: Logger.analysis)
                    return
                }

                Logger.debug("Sketch Pad: [Readability] Engine returned \(tips.count) tips - doc=\(documentId), elapsed=\(String(format: "%.2f", elapsed))s", category: Logger.analysis)

                // Cache the result (only if tips are non-empty or score >= 70)
                // Don't cache empty tips for low scores since we'll want to retry
                if !bypassCache, !tips.isEmpty || score >= 70 {
                    readabilityTipsCache.set(
                        text: text,
                        targetAudience: targetAudience.displayName,
                        tips: tips,
                        score: score
                    )
                    Logger.trace("Sketch Pad: [Readability] Cached tips result - doc=\(documentId)", category: Logger.analysis)
                }

                // Update UI and rate limiting state
                await MainActor.run { [weak self] in
                    guard let self else { return }

                    // Update rate limiting state
                    lastReadabilityTipsTime = Date()
                    lastReadabilityTipsTextHash = contentHash

                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isSelection {
                            self.selectionReadabilityTips = tips
                        } else {
                            self.documentReadabilityTips = tips
                        }
                    }
                    Logger.info("Sketch Pad: [Readability] Complete - \(tips.count) tip(s) applied, scope=\(scope), doc=\(documentId)", category: Logger.analysis)
                }

            } catch {
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                let isCancellation = Task.isCancelled || error.localizedDescription.contains("cancel")
                if isCancellation {
                    Logger.debug("Sketch Pad: [Readability] Cancelled - doc=\(documentId), elapsed=\(String(format: "%.2f", elapsed))s", category: Logger.analysis)
                } else {
                    Logger.warning("Sketch Pad: [Readability] Failed - doc=\(documentId), elapsed=\(String(format: "%.2f", elapsed))s, error=\(error.localizedDescription)", category: Logger.analysis)
                }
                // Fail silently - static tips are shown as fallback
            }
        }
    }

    // MARK: - Private

    private var analysisTask: Task<Void, Never>?
    private var styleAnalysisTask: Task<Void, Never>?
    private var autoSaveTask: Task<Void, Never>?
    private var isSaving = false
    private var needsResaveAfterCurrentSave = false
    private var isUpdatingUnderlines = false

    /// Whether style analysis is in progress (published for UI loading state)
    @Published var isAnalyzingStyle = false

    private init() {
        loadDrafts()

        // Load most recent draft or create a new document
        if let mostRecent = drafts.first {
            currentDocument = mostRecent
            documentTitle = mostRecent.title
            // Load content from markdown-based document
            // Set both attributedContent (for legacy) and plainTextContentInternal (for STTextView)
            attributedContent = mostRecent.nsAttributedContent
            plainTextContentInternal = mostRecent.markdown
            Logger.info("Loaded most recent draft: \(mostRecent.title)", category: Logger.ui)
        } else {
            // Create initial empty document (using new markdown format)
            let newDoc = SketchDocument(
                id: UUID(),
                title: "Untitled",
                markdown: "",
                createdAt: Date(),
                modifiedAt: Date()
            )
            currentDocument = newDoc
            Logger.info("Created initial empty document", category: Logger.ui)
        }

        isInitializing = false

        // Run initial analysis if we have content
        if !attributedContent.string.isEmpty {
            scheduleAnalysis()
        }
    }

    // MARK: - Document Operations

    /// Create a new empty document
    func newDocument() {
        Logger.info("Creating new Sketch Pad document", category: Logger.ui)

        // Save current document first before switching (wait for completion to prevent data loss)
        if currentDocument != nil, !plainTextContent.isEmpty {
            Task {
                await saveCurrentDocument()
                await MainActor.run {
                    createNewDocumentInternal()
                }
            }
        } else {
            createNewDocumentInternal()
        }
    }

    /// Internal method to actually create the new document (after save completes)
    private func createNewDocumentInternal() {
        // Save current state to cache before switching
        if let previousDocId = currentDocument?.id {
            // Save AI prompt
            if !aiAssistantPrompt.isEmpty {
                aiPromptCache[previousDocId] = aiAssistantPrompt
            }
            // Save analysis results
            saveAnalysisToCache(for: previousDocId)
        }

        let newDoc = SketchDocument(
            id: UUID(),
            title: "Untitled",
            markdown: "",
            createdAt: Date(),
            modifiedAt: Date()
        )

        currentDocument = newDoc
        documentTitle = newDoc.title
        attributedContent = NSAttributedString()
        plainTextContentInternal = ""
        // Also clear the actual text view since we don't auto-sync in updateNSView
        stTextView?.text = ""
        saveStatus = .saved
        underlineRects = []
        hoveredUnderline = nil

        // Clear analysis (new document has no content)
        grammarErrors = []
        styleSuggestions = []
        readabilityResult = nil
        documentReadabilityTips = []
        unifiedInsights = []
        selectedInsightId = nil
        highlightedRange = nil
        selectionReadabilityResult = nil
        selectionReadabilityTips = []
        isShowingSelectionReadability = false

        // Clear AI prompt for new document
        aiAssistantPrompt = ""
    }

    /// Load a document from the drafts list
    func loadDocument(_ document: SketchDocument) {
        Logger.info("Loading Sketch Pad document: \(document.title)", category: Logger.ui)

        // Don't reload the same document
        if currentDocument?.id == document.id {
            return
        }

        // Save current document first before switching (wait for completion to prevent data loss)
        if currentDocument != nil, !plainTextContent.isEmpty {
            Task {
                await saveCurrentDocument()
                await MainActor.run {
                    loadDocumentInternal(document)
                }
            }
        } else {
            loadDocumentInternal(document)
        }
    }

    /// Internal method to actually load the document (after save completes)
    private func loadDocumentInternal(_ document: SketchDocument) {
        // Save current state to cache before switching
        if let previousDocId = currentDocument?.id {
            // Save AI prompt
            if !aiAssistantPrompt.isEmpty {
                aiPromptCache[previousDocId] = aiAssistantPrompt
            }
            // Save analysis results
            saveAnalysisToCache(for: previousDocId)
        }

        // Set flag to prevent didSet from triggering analysis during load
        isLoadingDocument = true
        defer { isLoadingDocument = false }

        currentDocument = document
        documentTitle = document.title

        // Cancel ALL running analysis tasks when switching documents
        // This prevents stale results from old documents affecting the new document
        Logger.debug("Sketch Pad: Switching document - cancelling all analysis tasks", category: Logger.analysis)
        analysisTask?.cancel()
        analysisTask = nil
        styleAnalysisTask?.cancel()
        styleAnalysisTask = nil
        tipsGenerationTask?.cancel()
        tipsGenerationTask = nil

        // Reset all analysis state flags immediately
        isAnalyzingStyle = false
        isLoadingReadabilityTips = false

        // Clear UI state immediately
        underlineRects = []
        hoveredUnderline = nil
        selectedInsightId = nil
        highlightedRange = nil
        selectionReadabilityResult = nil
        selectionReadabilityTips = []
        documentReadabilityTips = []
        isShowingSelectionReadability = false

        // Reset suggestion tracker for new document (clear suppression state)
        suggestionTracker.reset()

        // Reset style analysis rate limiting for new document
        styleAnalysisDebounceTask?.cancel()
        styleAnalysisDebounceTask = nil
        lastStyleAnalysisTime = nil
        lastStyleAnalysisTextHash = nil

        // Reset readability tips rate limiting for new document
        lastReadabilityTipsTime = nil
        lastReadabilityTipsTextHash = nil

        // Restore AI prompt from cache for this document (or clear if none)
        aiAssistantPrompt = aiPromptCache[document.id] ?? ""

        // Load content - use plain markdown for STTextView, or attributed for legacy
        if let stTextView {
            plainTextContentInternal = document.markdown
            // Also update the actual text view since we don't auto-sync in updateNSView
            stTextView.text = document.markdown

            // Force the text view to resize to fit its new content
            // This is needed because TextKit 2 does lazy layout
            stTextView.sizeToFit()

            // Reset scroll position to top when switching documents
            if let scrollView = stTextView.enclosingScrollView {
                scrollView.contentView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }

            // Force robust layout refresh after content load
            refreshTextViewLayout()
        } else {
            attributedContent = document.nsAttributedContent
        }

        saveStatus = .saved

        // Try to restore analysis from cache, otherwise run fresh analysis
        if !restoreAnalysisFromCache(for: document.id, contentHash: document.markdown.hashValue) {
            // No valid cache - clear analysis state and run fresh analysis
            grammarErrors = []
            styleSuggestions = []
            unifiedInsights = []
            readabilityResult = nil
            documentReadabilityTips = []
            scheduleAnalysis()
        } else {
            // Restored from cache - just need to recalculate underline positions
            // (underlineRects are not cached since they depend on layout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.updateUnderlineRects()
            }
        }
    }

    /// Save current analysis results to cache
    private func saveAnalysisToCache(for documentId: UUID) {
        let cached = CachedAnalysisResults(
            grammarErrors: grammarErrors,
            styleSuggestions: styleSuggestions,
            unifiedInsights: unifiedInsights,
            readabilityResult: readabilityResult,
            documentReadabilityTips: documentReadabilityTips,
            contentHash: plainTextContent.hashValue
        )
        analysisCache[documentId] = cached
        Logger.debug("Saved analysis cache for document \(documentId)", category: Logger.analysis)
    }

    /// Restore analysis results from cache if valid
    /// Returns true if cache was restored, false if analysis needs to run
    private func restoreAnalysisFromCache(for documentId: UUID, contentHash: Int) -> Bool {
        guard let cached = analysisCache[documentId] else {
            Logger.debug("No analysis cache for document \(documentId)", category: Logger.analysis)
            return false
        }

        // Check if content has changed since cache was created
        if cached.contentHash != contentHash {
            Logger.debug("Analysis cache invalidated (content changed) for document \(documentId)", category: Logger.analysis)
            analysisCache.removeValue(forKey: documentId)
            return false
        }

        // Restore from cache
        grammarErrors = cached.grammarErrors
        styleSuggestions = cached.styleSuggestions
        unifiedInsights = cached.unifiedInsights
        readabilityResult = cached.readabilityResult
        documentReadabilityTips = cached.documentReadabilityTips

        // If tips are empty but we have readability results, generate AI tips now
        // This happens when analysis completed in the background without generating tips
        if cached.documentReadabilityTips.isEmpty, cached.readabilityResult != nil {
            generateDocumentReadabilityTips()
        }

        Logger.debug("Restored analysis from cache for document \(documentId)", category: Logger.analysis)
        return true
    }

    /// Force a robust layout refresh of the STTextView and its scroll view
    /// This ensures content renders correctly, including line numbers gutter
    func refreshTextViewLayout() {
        guard let stTextView else { return }

        // Immediate layout pass
        stTextView.needsDisplay = true
        stTextView.needsLayout = true
        stTextView.layoutSubtreeIfNeeded()
        stTextView.textLayoutManager.textViewportLayoutController.layoutViewport()

        // Also refresh the scroll view and gutter
        if let scrollView = stTextView.enclosingScrollView {
            scrollView.needsLayout = true
            scrollView.layoutSubtreeIfNeeded()
        }

        // Refresh gutter if line numbers are enabled
        if stTextView.showsLineNumbers, let gutterView = stTextView.gutterView {
            gutterView.needsDisplay = true
            gutterView.needsLayout = true
        }

        // Schedule a delayed refresh to ensure everything settles
        // This handles cases where the view hierarchy isn't fully ready
        // Use a longer delay (200ms) when switching documents to ensure text layout is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak stTextView] in
            guard let self, let stTextView else { return }

            // First, force layout to ensure content size is calculated
            stTextView.needsDisplay = true
            stTextView.needsLayout = true
            stTextView.layoutSubtreeIfNeeded()
            stTextView.textLayoutManager.textViewportLayoutController.layoutViewport()

            // Force text view to resize to fit content
            stTextView.sizeToFit()

            if let scrollView = stTextView.enclosingScrollView {
                scrollView.needsLayout = true
                scrollView.layoutSubtreeIfNeeded()

                // Reset scroll to top after layout is complete
                scrollView.contentView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }

            if stTextView.showsLineNumbers, let gutterView = stTextView.gutterView {
                gutterView.needsDisplay = true
                gutterView.needsLayout = true
            }

            // Update underline positions after layout is fully settled
            updateUnderlineRects()

            // Update scroll state for edge fade indicators
            if let scrollView = stTextView.enclosingScrollView {
                let contentSize = stTextView.frame.size
                let visibleRect = scrollView.contentView.bounds
                let scrollOffset = scrollView.contentView.bounds.origin
                updateScrollState(
                    contentSize: contentSize,
                    visibleRect: visibleRect,
                    scrollOffset: scrollOffset
                )
            }
        }
    }

    /// Delete a document
    func deleteDocument(_ document: SketchDocument) async {
        Logger.info("Deleting Sketch Pad document: \(document.title)", category: Logger.ui)

        do {
            // If we're deleting the current document, clear it first to prevent re-saving
            let wasCurrentDocument = currentDocument?.id == document.id
            if wasCurrentDocument {
                currentDocument = nil
                plainTextContentInternal = ""
            }

            try await SketchDocumentStore.shared.delete(document.id)
            loadDrafts()

            // If we deleted the current document, create a new one
            if wasCurrentDocument {
                createNewDocumentInternal()
            }
        } catch {
            Logger.error("Failed to delete document: \(error.localizedDescription)", category: Logger.ui)
        }
    }

    /// Save the current document
    func saveCurrentDocument() async {
        guard var document = currentDocument else { return }
        guard !isSaving else { return } // Prevent concurrent saves

        // Get current content
        let currentContent: String = if stTextView != nil {
            plainTextContent
        } else {
            MarkdownExtractor.extract(from: attributedContent)
        }

        // Skip save if nothing has changed
        if document.title == documentTitle, document.markdown == currentContent {
            saveStatus = .saved
            Logger.debug("Document unchanged, skipping save: \(document.title)", category: Logger.ui)
            return
        }

        isSaving = true
        needsResaveAfterCurrentSave = false
        saveStatus = .saving

        // Update document with current content (using markdown format)
        document.title = documentTitle
        document.markdown = currentContent
        document.modifiedAt = Date()

        do {
            try await SketchDocumentStore.shared.save(document)
            currentDocument = document
            saveStatus = .saved
            loadDrafts()
            Logger.debug("Document saved: \(document.title)", category: Logger.ui)
        } catch {
            saveStatus = .error(error.localizedDescription)
            Logger.error("Failed to save document: \(error.localizedDescription)", category: Logger.ui)
        }

        isSaving = false

        // If changes were made during save, schedule another save
        if needsResaveAfterCurrentSave {
            needsResaveAfterCurrentSave = false
            scheduleAutoSave()
        }
    }

    /// Save immediately and synchronously - called on app termination
    /// This cancels any pending auto-save and saves right away
    func saveImmediately() {
        // Cancel any pending auto-save
        autoSaveTask?.cancel()

        guard var document = currentDocument else { return }

        // Update document with current content
        document.title = documentTitle
        if stTextView != nil {
            document.markdown = plainTextContent
        } else {
            document.markdown = MarkdownExtractor.extract(from: attributedContent)
        }
        document.modifiedAt = Date()

        // Save synchronously using semaphore to block until complete
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                try await SketchDocumentStore.shared.save(document)
                Logger.info("Document saved on termination: \(document.title)", category: Logger.ui)
            } catch {
                Logger.error("Failed to save document on termination: \(error.localizedDescription)", category: Logger.ui)
            }
            semaphore.signal()
        }
        // Wait up to 2 seconds for save to complete
        _ = semaphore.wait(timeout: .now() + 2.0)
    }

    // MARK: - Analysis

    /// Clear all analysis results immediately
    /// Called when text becomes empty or when we need to reset state
    private func clearAnalysisResults() {
        analysisTask?.cancel()
        grammarErrors = []
        styleSuggestions = []
        readabilityResult = nil
        unifiedInsights = []
        underlineRects = []
        Logger.debug("Cleared all analysis results", category: Logger.analysis)
    }

    /// Filter out stale analysis results that are now out of range
    /// Called when text is partially deleted to immediately remove invalid insights
    private func filterStaleAnalysisResults() {
        // Filter grammar errors - use scalar positions (Harper uses unicode scalars)
        let scalarLength = plainTextContentInternal.unicodeScalars.count
        let validGrammarErrors = grammarErrors.filter { $0.end <= scalarLength }
        if validGrammarErrors.count != grammarErrors.count {
            grammarErrors = validGrammarErrors
        }

        // Filter style suggestions - use grapheme cluster (character) positions
        let textLength = plainTextContentInternal.count
        let validStyleSuggestions = styleSuggestions.filter { $0.originalEnd <= textLength }
        if validStyleSuggestions.count != styleSuggestions.count {
            styleSuggestions = validStyleSuggestions
        }

        // Filter unified insights - these use scalar positions
        let validInsights = unifiedInsights.filter { $0.end <= scalarLength }
        if validInsights.count != unifiedInsights.count {
            unifiedInsights = validInsights
        }

        // Update underline rects after filtering
        updateUnderlineRects()
    }

    /// Schedule analysis after a delay (debounced)
    private func scheduleAnalysis() {
        analysisTask?.cancel()
        Logger.debug("Scheduling Sketch Pad analysis", category: Logger.analysis)
        analysisTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            runAnalysis()
        }
    }

    /// Run text analysis asynchronously in the background
    /// Results are stored in cache for the document they belong to,
    /// and only update UI if the document is still active
    private func runAnalysis() {
        guard let documentId = currentDocument?.id else { return }

        // Check if analysis is already running for this document
        guard !analysisInProgressForDocuments.contains(documentId) else {
            Logger.debug("Skipping analysis - already in progress for document", category: Logger.analysis)
            return
        }

        let text = plainTextContent
        Logger.debug("Running Sketch Pad analysis on \(text.count) characters", category: Logger.analysis)

        guard !text.isEmpty else {
            grammarErrors = []
            styleSuggestions = []
            readabilityResult = nil
            unifiedInsights = []
            Logger.debug("Sketch Pad analysis skipped: empty text", category: Logger.analysis)
            return
        }

        // Mark analysis as in progress for this document
        analysisInProgressForDocuments.insert(documentId)

        // Capture preferences on main thread before going to background
        let filterConfig = GrammarFilterConfig.fromPreferences(UserPreferences.shared)
        let targetAudienceName = UserPreferences.shared.selectedTargetAudience
        let targetAudience = TargetAudience(fromDisplayName: targetAudienceName) ?? .general
        let customVocab = CustomVocabulary.shared
        let contentHash = text.hashValue

        // Run analysis asynchronously - the async grammar analysis runs on a background thread
        // and returns to main actor after completion, allowing UI to remain responsive
        Task { [weak self] in
            guard let self else { return }

            // Run grammar analysis asynchronously (uses Task.detached internally for background processing)
            let grammarResult = await GrammarEngine.shared.analyzeText(text)

            // After await, we're back on main actor - apply filtering
            let filteredErrors = GrammarErrorFilter.filter(
                errors: grammarResult.errors,
                sourceText: text,
                config: filterConfig,
                customVocabulary: customVocab
            )

            // Run readability analysis (synchronous but fast)
            let readabilityAnalysis = ReadabilityCalculator.shared.analyzeForTargetAudience(text, targetAudience: targetAudience)

            // Remove from in-progress set
            analysisInProgressForDocuments.remove(documentId)

            // Check if this document is still active
            let isStillActiveDocument = currentDocument?.id == documentId

            if isStillActiveDocument {
                // Update UI state directly
                grammarErrors = filteredErrors
                Logger.debug("Grammar analysis: \(filteredErrors.count) errors after filtering", category: Logger.analysis)

                if let analysis = readabilityAnalysis {
                    readabilityResult = analysis.overallResult
                    // Generate AI tips for the document (async, cached)
                    generateDocumentReadabilityTips()
                } else {
                    readabilityResult = nil
                    documentReadabilityTips = []
                }

                // Convert to unified suggestions
                var insights: [UnifiedSuggestion] = []
                for error in filteredErrors {
                    insights.append(error.toUnifiedSuggestion(in: text))
                }
                for suggestion in styleSuggestions {
                    insights.append(suggestion.toUnifiedSuggestion())
                }

                // Filter out dismissed suggestions
                let store = DismissedSuggestionsStore.shared
                insights = insights.filter { !store.isDismissed($0, documentId: documentId) }
                grammarErrors = filteredErrors.filter { error in
                    !store.isDismissed(error.toUnifiedSuggestion(in: text), documentId: documentId)
                }

                unifiedInsights = insights

                // Force layout and update underlines
                if let stTextView {
                    stTextView.needsLayout = true
                    stTextView.layoutSubtreeIfNeeded()
                    stTextView.textLayoutManager.textViewportLayoutController.layoutViewport()
                }

                DispatchQueue.main.async { [weak self] in
                    self?.updateUnderlineRects()
                    self?.updateDismissedCount()
                }

                if let result = readabilityResult {
                    Logger.debug("Sketch Pad analysis complete: \(grammarErrors.count) errors, readability: \(result.score)", category: Logger.analysis)
                } else {
                    Logger.debug("Sketch Pad analysis complete: \(grammarErrors.count) errors", category: Logger.analysis)
                }

                // Schedule style analysis with debouncing and rate limiting
                scheduleStyleAnalysis(forDocumentId: documentId, text: text, contentHash: contentHash)
            } else {
                // Document was switched - save results to cache for later
                Logger.debug("Analysis completed for background document \(documentId), caching results", category: Logger.analysis)

                // Filter dismissed suggestions for the background document
                let store = DismissedSuggestionsStore.shared
                let filteredGrammarErrors = filteredErrors.filter { error in
                    !store.isDismissed(error.toUnifiedSuggestion(in: text), documentId: documentId)
                }

                var insights: [UnifiedSuggestion] = []
                for error in filteredGrammarErrors {
                    insights.append(error.toUnifiedSuggestion(in: text))
                }
                insights = insights.filter { !store.isDismissed($0, documentId: documentId) }

                // Save to cache
                let cached = CachedAnalysisResults(
                    grammarErrors: filteredGrammarErrors,
                    styleSuggestions: [], // Style will be added when it completes
                    unifiedInsights: insights,
                    readabilityResult: readabilityAnalysis?.overallResult,
                    documentReadabilityTips: [], // Will be generated when document is viewed
                    contentHash: contentHash
                )
                analysisCache[documentId] = cached

                // Schedule style analysis for background document (with rate limiting)
                scheduleStyleAnalysis(forDocumentId: documentId, text: text, contentHash: contentHash)
            }
        }
    }

    /// Manually trigger style analysis (called from keyboard shortcut)
    /// Bypasses rate limiting for user-initiated requests
    func triggerStyleAnalysis() {
        guard let documentId = currentDocument?.id else { return }
        let text = plainTextContent
        // Manual trigger bypasses rate limiting
        runStyleAnalysisInternal(forDocumentId: documentId, text: text, contentHash: text.hashValue, isManualTrigger: true)
    }

    /// Schedule style analysis with debouncing and rate limiting
    /// This prevents excessive LLM calls during rapid typing
    private func scheduleStyleAnalysis(forDocumentId documentId: UUID, text: String, contentHash: Int) {
        // Cancel any pending style analysis debounce
        styleAnalysisDebounceTask?.cancel()

        // Schedule with longer debounce than grammar analysis
        styleAnalysisDebounceTask = Task { [weak self] in
            // Wait for user to stop typing (2 second debounce)
            try? await Task.sleep(nanoseconds: UInt64(self?.styleAnalysisDebounceDelay ?? 2.0) * 1_000_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                self?.runStyleAnalysisInternal(forDocumentId: documentId, text: text, contentHash: contentHash, isManualTrigger: false)
            }
        }
    }

    /// Run style analysis using Apple Intelligence (async)
    /// Continues in background if document is switched and stores results in cache
    private func runStyleAnalysisInternal(forDocumentId documentId: UUID, text: String, contentHash: Int, isManualTrigger: Bool) {
        guard #available(macOS 26.0, *) else { return }

        // Guard: Don't run if suppressed (user just accepted/rejected a style suggestion)
        // This prevents the "endless suggestion loop" where applying a suggestion
        // triggers re-analysis that finds new suggestions for the same text
        guard suggestionTracker.shouldRunAutoStyleAnalysis() else {
            Logger.debug("Sketch Pad: Style analysis skipped - suppressed until user edit", category: Logger.analysis)
            if currentDocument?.id == documentId {
                isAnalyzingStyle = false
            }
            return
        }

        // Minimum text length for meaningful style analysis
        guard text.count >= styleAnalysisMinTextLength else {
            Logger.debug("Sketch Pad: Style analysis skipped - text too short (\(text.count) < \(styleAnalysisMinTextLength))", category: Logger.analysis)
            if currentDocument?.id == documentId {
                styleSuggestions = []
                isAnalyzingStyle = false
            }
            return
        }

        // Rate limiting for automatic analysis (manual triggers bypass this)
        if !isManualTrigger {
            // Check minimum interval between analyses
            if let lastTime = lastStyleAnalysisTime {
                let elapsed = Date().timeIntervalSince(lastTime)
                if elapsed < styleAnalysisMinInterval {
                    Logger.debug("Sketch Pad: Style analysis skipped - too soon (\(Int(elapsed))s < \(Int(styleAnalysisMinInterval))s)", category: Logger.analysis)
                    if currentDocument?.id == documentId {
                        isAnalyzingStyle = false
                    }
                    return
                }
            }

            // Check if text has changed since last analysis
            if let lastHash = lastStyleAnalysisTextHash, lastHash == contentHash {
                Logger.debug("Sketch Pad: Style analysis skipped - text unchanged", category: Logger.analysis)
                if currentDocument?.id == documentId {
                    isAnalyzingStyle = false
                }
                return
            }
        }

        // Capture preferences before going async
        let styleName = UserPreferences.shared.selectedWritingStyle
        let style = WritingStyle.allCases.first { $0.displayName == styleName } ?? .default
        let temperaturePresetName = UserPreferences.shared.styleTemperaturePreset
        let temperaturePreset = StyleTemperaturePreset(rawValue: temperaturePresetName) ?? .balanced
        let vocabulary = CustomVocabulary.shared.allWords()

        // Only show analyzing indicator if this is the current document
        if currentDocument?.id == documentId {
            isAnalyzingStyle = true
            Logger.trace("Sketch Pad: [Style] Set isAnalyzingStyle=true for document \(documentId.uuidString.prefix(8))", category: Logger.analysis)
        }

        // Update tracking for rate limiting
        lastStyleAnalysisTime = Date()
        lastStyleAnalysisTextHash = contentHash

        let startTime = CFAbsoluteTimeGetCurrent()
        let shortDocId = String(documentId.uuidString.prefix(8))
        Logger.info("Sketch Pad: [Style] Starting analysis - doc=\(shortDocId), chars=\(text.count), style=\(style.displayName), manual=\(isManualTrigger)", category: Logger.analysis)

        // Cancel any existing style analysis task before starting a new one
        styleAnalysisTask?.cancel()
        styleAnalysisTask = Task {
            // Check for early cancellation
            guard !Task.isCancelled else {
                Logger.debug("Sketch Pad: [Style] Task cancelled before starting - doc=\(shortDocId)", category: Logger.analysis)
                return
            }

            let engine = FoundationModelsEngine()
            let engineStatus = engine.status
            guard engineStatus == .available else {
                await MainActor.run { [weak self] in
                    if self?.currentDocument?.id == documentId {
                        self?.isAnalyzingStyle = false
                        Logger.trace("Sketch Pad: [Style] Set isAnalyzingStyle=false (engine unavailable) - doc=\(shortDocId)", category: Logger.analysis)
                    }
                }
                Logger.warning("Sketch Pad: [Style] Aborted - Apple Intelligence status=\(engineStatus.userMessage)", category: Logger.analysis)
                return
            }

            Logger.trace("Sketch Pad: [Style] Calling Foundation Models engine - doc=\(shortDocId)", category: Logger.analysis)

            do {
                let suggestions = try await engine.analyzeStyle(
                    text,
                    style: style,
                    temperaturePreset: temperaturePreset,
                    customVocabulary: vocabulary
                )

                // Check for cancellation after the async call
                guard !Task.isCancelled else {
                    let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                    Logger.debug("Sketch Pad: [Style] Task cancelled after engine call - doc=\(shortDocId), elapsed=\(String(format: "%.2f", elapsed))s", category: Logger.analysis)
                    return
                }

                // Filter by impact (high/medium only for cleaner UX)
                let filtered = suggestions.filter { $0.impact != .low }
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime

                Logger.debug("Sketch Pad: [Style] Engine returned \(suggestions.count) suggestions, \(filtered.count) after filter - doc=\(shortDocId), elapsed=\(String(format: "%.2f", elapsed))s", category: Logger.analysis)

                await MainActor.run { [weak self] in
                    guard let self else {
                        Logger.trace("Sketch Pad: [Style] Self deallocated, discarding results - doc=\(shortDocId)", category: Logger.analysis)
                        return
                    }

                    // Check if this document is still active
                    let isStillActiveDocument = currentDocument?.id == documentId
                    let currentDocId = currentDocument?.id.uuidString.prefix(8) ?? "nil"

                    if isStillActiveDocument {
                        // Check if content has changed since analysis started
                        // If so, discard these stale results - they're based on old text
                        let currentContentHash = plainTextContent.hashValue
                        if currentContentHash != contentHash {
                            Logger.debug("Sketch Pad: [Style] Discarding stale results (content changed) - doc=\(shortDocId)", category: Logger.analysis)
                            isAnalyzingStyle = false
                            return
                        }

                        // Update UI state directly
                        isAnalyzingStyle = false
                        styleSuggestions = filtered
                        Logger.trace("Sketch Pad: [Style] Applied \(filtered.count) suggestions, set isAnalyzingStyle=false - doc=\(shortDocId)", category: Logger.analysis)

                        // Update unified insights with style suggestions
                        var insights = unifiedInsights.filter { $0.source != .appleIntelligence }
                        for suggestion in filtered {
                            insights.append(suggestion.toUnifiedSuggestion())
                        }

                        // Filter out dismissed suggestions
                        let store = DismissedSuggestionsStore.shared
                        insights = insights.filter { !store.isDismissed($0, documentId: documentId) }
                        unifiedInsights = insights

                        // Force layout to ensure text positions are current before calculating underlines
                        if let stTextView {
                            stTextView.needsLayout = true
                            stTextView.layoutSubtreeIfNeeded()
                            stTextView.textLayoutManager.textViewportLayoutController.layoutViewport()
                        }

                        // Defer underline calculation to next run loop to ensure layout is committed
                        DispatchQueue.main.async { [weak self] in
                            self?.updateUnderlineRects()
                        }

                        Logger.info("Sketch Pad: [Style] Complete - \(filtered.count) suggestion(s) applied, doc=\(shortDocId)", category: Logger.analysis)
                    } else {
                        // Document was switched - update cache with style suggestions
                        Logger.debug("Sketch Pad: [Style] Document switched during analysis, caching results - analysisDoc=\(shortDocId), currentDoc=\(currentDocId)", category: Logger.analysis)

                        if var cached = analysisCache[documentId] {
                            // Check if content has changed since analysis started
                            if cached.contentHash != contentHash {
                                Logger.debug("Sketch Pad: Discarding stale style results for background document (content changed)", category: Logger.analysis)
                                return
                            }

                            // Update existing cache entry with style suggestions
                            cached.styleSuggestions = filtered

                            // Add style suggestions to unified insights
                            var insights = cached.unifiedInsights.filter { $0.source != .appleIntelligence }
                            for suggestion in filtered {
                                insights.append(suggestion.toUnifiedSuggestion())
                            }
                            let store = DismissedSuggestionsStore.shared
                            insights = insights.filter { !store.isDismissed($0, documentId: documentId) }
                            cached.unifiedInsights = insights

                            analysisCache[documentId] = cached
                        }
                    }
                }
            } catch {
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                let isCancellation = Task.isCancelled || error.localizedDescription.contains("cancel")
                await MainActor.run { [weak self] in
                    if self?.currentDocument?.id == documentId {
                        self?.isAnalyzingStyle = false
                        Logger.trace("Sketch Pad: [Style] Set isAnalyzingStyle=false (error) - doc=\(shortDocId)", category: Logger.analysis)
                    }
                }
                if isCancellation {
                    Logger.debug("Sketch Pad: [Style] Cancelled - doc=\(shortDocId), elapsed=\(String(format: "%.2f", elapsed))s", category: Logger.analysis)
                } else {
                    Logger.warning("Sketch Pad: [Style] Failed - doc=\(shortDocId), elapsed=\(String(format: "%.2f", elapsed))s, error=\(error.localizedDescription)", category: Logger.analysis)
                }
            }
        }
    }

    /// Update underline rects from current analysis results
    func updateUnderlineRects() {
        // Prevent reentrant calls - layout updates can trigger notifications
        // that would call this method again, causing an infinite loop
        guard !isUpdatingUnderlines else { return }
        isUpdatingUnderlines = true
        defer { isUpdatingUnderlines = false }

        guard let stLayoutInfo, let stTextView else {
            // No layout info yet - rects will be calculated when it becomes available
            return
        }

        // Ensure TextKit 2 viewport layout is up to date before calculating positions
        // This is necessary because text content changes may not have triggered a full layout pass
        stTextView.textLayoutManager.textViewportLayoutController.layoutViewport()

        // Update underline Y offset from font metrics
        underlineYOffset = stLayoutInfo.underlineYOffset

        underlineRects = UnderlineGeometryCalculator.calculateRectsFromSTLayout(
            for: grammarErrors,
            styleSuggestions: styleSuggestions,
            using: stLayoutInfo,
            sourceText: plainTextContent
        )
    }

    // MARK: - Fix Application

    /// Apply a fix from an insight
    /// - Parameters:
    ///   - insight: The unified suggestion containing the error/suggestion info
    ///   - specificSuggestion: Optional specific suggestion text to apply (from alternatives). If nil, uses insight.suggestedText.
    func applyFix(for insight: UnifiedSuggestion, withSuggestion specificSuggestion: String? = nil) {
        // Use specific suggestion if provided, otherwise fall back to default
        let replacement: String
        if let specific = specificSuggestion {
            replacement = specific
        } else if let suggested = insight.suggestedText {
            replacement = suggested
        } else {
            Logger.warning("No suggestion available to apply", category: Logger.ui)
            return
        }

        guard let stTextView else {
            Logger.warning("Cannot apply fix: no text view", category: Logger.ui)
            return
        }

        let text = stTextView.text ?? ""

        // insight.range uses scalar indices from Harper - validate before conversion
        let scalarRange = NSRange(location: insight.start, length: insight.end - insight.start)

        // Validate scalar range against Unicode scalar count
        let scalarCount = text.unicodeScalars.count
        guard scalarRange.location >= 0,
              scalarRange.length >= 0,
              scalarRange.location + scalarRange.length <= scalarCount
        else {
            Logger.warning(
                "Invalid scalar range for fix (scalar: \(scalarRange), scalarCount: \(scalarCount))",
                category: Logger.ui
            )
            return
        }

        // Convert scalar indices to UTF-16 for STTextView
        let utf16Range = TextIndexConverter.scalarToUTF16Range(scalarRange, in: text)

        // Bounds check using UTF-16 count (defensive - should pass if scalar check passed)
        guard utf16Range.location + utf16Range.length <= text.utf16.count else {
            Logger.warning(
                "Invalid UTF-16 range after conversion (utf16: \(utf16Range), text.utf16.count: \(text.utf16.count))",
                category: Logger.ui
            )
            return
        }

        stTextView.insertText(replacement, replacementRange: utf16Range)
        syncFromSTTextView()

        // Calculate position delta for adjusting subsequent suggestions
        let originalLength = insight.end - insight.start
        let newLength = replacement.unicodeScalars.count
        let delta = newLength - originalLength
        let acceptedEnd = insight.end
        let updatedText = stTextView.text ?? ""
        let textScalarCount = updatedText.unicodeScalars.count

        /// Validates and adjusts position for an item after a fix is applied.
        /// Returns adjusted (start, end) if valid, nil if item should be removed.
        func adjustAndValidate(
            start: Int,
            end: Int,
            originalText: String?,
            label: String
        ) -> (start: Int, end: Int)? {
            let needsAdjustment = start >= acceptedEnd
            let adjustedStart = needsAdjustment ? start + delta : start
            let adjustedEnd = needsAdjustment ? end + delta : end

            // Bounds check
            guard adjustedEnd <= textScalarCount else {
                Logger.debug("Removing stale \(label) - position out of bounds: \(adjustedEnd) > \(textScalarCount)", category: Logger.analysis)
                return nil
            }

            // Text match validation (only for items that store original text)
            if let expected = originalText {
                let extracted = TextIndexConverter.extractErrorText(start: adjustedStart, end: adjustedEnd, from: updatedText) ?? ""
                if extracted != expected {
                    Logger.debug("Removing stale \(label) - text mismatch at \(adjustedStart)", category: Logger.analysis)
                    return nil
                }
            }

            return (adjustedStart, adjustedEnd)
        }

        // Adjust grammar errors (no text validation - GrammarErrorModel doesn't store original text)
        grammarErrors = grammarErrors.compactMap { error in
            if error.start == insight.start, error.end == insight.end { return nil }
            guard let adjusted = adjustAndValidate(start: error.start, end: error.end, originalText: nil, label: "grammar error") else { return nil }
            if error.start >= acceptedEnd {
                return GrammarErrorModel(
                    start: adjusted.start, end: adjusted.end,
                    message: error.message, severity: error.severity, category: error.category,
                    lintId: error.lintId, suggestions: error.suggestions
                )
            }
            return error
        }

        // Adjust style suggestions (with text validation)
        styleSuggestions = styleSuggestions.compactMap { s in
            if s.originalStart == insight.start, s.originalEnd == insight.end { return nil }
            guard let adjusted = adjustAndValidate(start: s.originalStart, end: s.originalEnd, originalText: s.originalText, label: "style suggestion") else { return nil }
            if s.originalStart >= acceptedEnd {
                return StyleSuggestionModel(
                    id: s.id, originalStart: adjusted.start, originalEnd: adjusted.end,
                    originalText: s.originalText, suggestedText: s.suggestedText, explanation: s.explanation,
                    confidence: s.confidence, style: s.style, diff: s.diff,
                    isReadabilitySuggestion: s.isReadabilitySuggestion, readabilityScore: s.readabilityScore,
                    targetAudience: s.targetAudience
                )
            }
            return s
        }

        // Adjust unified insights (with text validation)
        unifiedInsights = unifiedInsights.compactMap { i in
            if i.id == insight.id { return nil }
            guard let adjusted = adjustAndValidate(start: i.start, end: i.end, originalText: i.originalText, label: "insight '\(i.category)'") else { return nil }
            if i.start >= acceptedEnd {
                return UnifiedSuggestion(
                    id: i.id, category: i.category, start: adjusted.start, end: adjusted.end,
                    originalText: i.originalText, suggestedText: i.suggestedText, message: i.message,
                    severity: i.severity, source: i.source, lintId: i.lintId, confidence: i.confidence,
                    diff: i.diff, readabilityScore: i.readabilityScore, targetAudience: i.targetAudience,
                    alternatives: i.alternatives, writingStyle: i.writingStyle
                )
            }
            return i
        }

        // Clear selection and update underlines
        selectedInsightId = nil
        updateUnderlineRects()

        Logger.info("Applied fix: '\(insight.originalText)' -> '\(replacement)' (delta: \(delta))", category: Logger.ui)
    }

    /// Ignore a suggestion (persisted per document)
    func ignoreSuggestion(_ insight: UnifiedSuggestion) {
        guard let documentId = currentDocument?.id else {
            Logger.warning("Cannot dismiss suggestion: no current document", category: Logger.ui)
            return
        }

        // Persist the dismissal
        DismissedSuggestionsStore.shared.dismiss(insight, documentId: documentId)

        // Remove from insights list with animation
        withAnimation(.easeOut(duration: 0.2)) {
            unifiedInsights.removeAll { $0.id == insight.id }
        }

        // Also remove from underlying error lists to prevent re-adding on next analysis
        if insight.lintId != nil {
            grammarErrors.removeAll { $0.start == insight.start && $0.end == insight.end }
        }
        styleSuggestions.removeAll { $0.originalStart == insight.start && $0.originalEnd == insight.end }

        // Update underlines and count
        updateUnderlineRects()
        updateDismissedCount()

        Logger.info("Dismissed suggestion permanently: '\(insight.originalText)' - \(insight.message)", category: Logger.ui)
    }

    /// Reset all dismissed suggestions for current document and re-run analysis
    func resetDismissedSuggestions() {
        guard let documentId = currentDocument?.id else {
            Logger.warning("Cannot reset dismissals: no current document", category: Logger.ui)
            return
        }

        DismissedSuggestionsStore.shared.clearDismissals(for: documentId)
        dismissedSuggestionsCount = 0

        // Re-run analysis to bring back dismissed suggestions
        runAnalysis()

        Logger.info("Reset all dismissed suggestions for document", category: Logger.ui)
    }

    /// Update the dismissed suggestions count
    private func updateDismissedCount() {
        guard let documentId = currentDocument?.id else {
            dismissedSuggestionsCount = 0
            return
        }
        dismissedSuggestionsCount = DismissedSuggestionsStore.shared.dismissedCount(for: documentId)
    }

    /// Ignore rule permanently (adds to user preferences)
    func ignoreRule(for insight: UnifiedSuggestion) {
        guard let lintId = insight.lintId else {
            Logger.warning("Cannot ignore rule: no lintId for insight", category: Logger.ui)
            return
        }

        // Add to ignored rules in user preferences
        var ignoredRules = UserPreferences.shared.ignoredRules
        ignoredRules.insert(lintId)
        UserPreferences.shared.ignoredRules = ignoredRules

        // Remove all insights with this rule
        unifiedInsights.removeAll { $0.lintId == lintId }
        grammarErrors.removeAll { $0.lintId == lintId }

        Logger.info("Ignored rule permanently: \(lintId)", category: Logger.ui)
    }

    /// Add word to custom dictionary
    func addToDictionary(for insight: UnifiedSuggestion) {
        let word = insight.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else {
            Logger.warning("Cannot add to dictionary: empty word", category: Logger.ui)
            return
        }

        // Use the CustomVocabulary system (same as the main app)
        do {
            try CustomVocabulary.shared.addWord(word)
            Logger.info("Added to dictionary: '\(word)'", category: Logger.ui)
        } catch {
            Logger.error("Failed to add word to dictionary: \(error.localizedDescription)", category: Logger.ui)
            return
        }

        // Remove insights for this word (same spelling)
        unifiedInsights.removeAll { $0.originalText.lowercased() == word.lowercased() }
        grammarErrors.removeAll {
            if let startIdx = plainTextContent.index(plainTextContent.startIndex, offsetBy: $0.start, limitedBy: plainTextContent.endIndex),
               let endIdx = plainTextContent.index(plainTextContent.startIndex, offsetBy: $0.end, limitedBy: plainTextContent.endIndex),
               startIdx < endIdx
            {
                let errorWord = String(plainTextContent[startIdx ..< endIdx])
                return errorWord.lowercased() == word.lowercased()
            }
            return false
        }
    }

    // MARK: - Popover Actions

    /// Apply a suggestion from the hover popover
    func applySuggestionFromPopover(_ suggestion: String, for underline: SketchUnderlineRect) {
        guard let stTextView else {
            Logger.warning("Cannot apply suggestion: no text view", category: Logger.ui)
            return
        }

        let text = stTextView.text ?? ""

        // Validate scalar range before conversion
        let scalarRange = underline.scalarRange
        let scalarCount = text.unicodeScalars.count
        guard scalarRange.location >= 0,
              scalarRange.length >= 0,
              scalarRange.location + scalarRange.length <= scalarCount
        else {
            Logger.warning(
                "Cannot apply suggestion: invalid scalar range (scalar: \(scalarRange), scalarCount: \(scalarCount))",
                category: Logger.ui
            )
            return
        }

        // Convert to UTF-16 for STTextView
        let utf16Range = TextIndexConverter.scalarToUTF16Range(scalarRange, in: text)

        // Bounds check using UTF-16 count (defensive - should pass if scalar check passed)
        guard utf16Range.location + utf16Range.length <= text.utf16.count else {
            Logger.warning(
                "Cannot apply suggestion: UTF-16 range out of bounds (utf16: \(utf16Range), text.utf16.count: \(text.utf16.count))",
                category: Logger.ui
            )
            return
        }

        stTextView.insertText(suggestion, replacementRange: utf16Range)
        syncFromSTTextView()
        Logger.info("Applied suggestion from popover: '\(suggestion)'", category: Logger.ui)
    }

    /// Remove an underline and its corresponding error/suggestion
    func ignoreUnderline(_ underline: SketchUnderlineRect) {
        // Remove from underlines
        underlineRects.removeAll { $0.id == underline.id }

        // Remove from analysis results based on scalar range (matches Harper's indices)
        grammarErrors.removeAll {
            $0.start == underline.scalarRange.location && $0.end == underline.scalarRange.location + underline.scalarRange.length
        }
        styleSuggestions.removeAll {
            $0.originalStart == underline.scalarRange.location && $0.originalEnd == underline.scalarRange.location + underline.scalarRange.length
        }

        // Update unified insights
        unifiedInsights.removeAll {
            $0.start == underline.scalarRange.location && $0.end == underline.scalarRange.location + underline.scalarRange.length
        }

        Logger.debug("Ignored underline: \(underline.id)", category: Logger.ui)
    }

    /// Ignore a rule from the popover
    func ignoreRuleFromPopover(lintId: String) {
        var ignoredRules = UserPreferences.shared.ignoredRules
        ignoredRules.insert(lintId)
        UserPreferences.shared.ignoredRules = ignoredRules

        // Remove all errors with this rule
        grammarErrors.removeAll { $0.lintId == lintId }
        unifiedInsights.removeAll { $0.lintId == lintId }

        // Update underlines
        updateUnderlineRects()

        Logger.info("Ignored rule from popover: \(lintId)", category: Logger.ui)
    }

    /// Add a word to dictionary from the popover
    func addToDictionaryFromPopover(word: String) {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return }

        // Use the CustomVocabulary system (same as the main app)
        do {
            try CustomVocabulary.shared.addWord(trimmedWord)
            Logger.info("Added to dictionary from popover: '\(trimmedWord)'", category: Logger.ui)
        } catch {
            Logger.error("Failed to add word to dictionary: \(error.localizedDescription)", category: Logger.ui)
            return
        }

        // Remove grammar errors for this word
        grammarErrors.removeAll {
            if let startIdx = plainTextContent.index(plainTextContent.startIndex, offsetBy: $0.start, limitedBy: plainTextContent.endIndex),
               let endIdx = plainTextContent.index(plainTextContent.startIndex, offsetBy: $0.end, limitedBy: plainTextContent.endIndex),
               startIdx < endIdx
            {
                let errorWord = String(plainTextContent[startIdx ..< endIdx])
                return errorWord.lowercased() == trimmedWord.lowercased()
            }
            return false
        }

        // Update underlines
        updateUnderlineRects()
    }

    // MARK: - Style Suggestion Actions

    /// Accept a style suggestion and apply the replacement
    func acceptStyleSuggestion(_ suggestion: StyleSuggestionModel) {
        guard let stTextView else {
            Logger.warning("Cannot accept style suggestion: no text view", category: Logger.ui)
            return
        }

        let text = stTextView.text ?? ""

        // Convert scalar range to UTF-16 for STTextView
        let scalarRange = NSRange(location: suggestion.originalStart, length: suggestion.originalEnd - suggestion.originalStart)
        let utf16Range = TextIndexConverter.scalarToUTF16Range(scalarRange, in: text)

        // Bounds check
        guard utf16Range.location + utf16Range.length <= text.utf16.count else {
            Logger.warning("Cannot accept style suggestion: range out of bounds", category: Logger.ui)
            return
        }

        // Mark that we're applying a suggestion (not a user edit)
        isApplyingStyleSuggestion = true

        stTextView.insertText(suggestion.suggestedText, replacementRange: utf16Range)
        syncFromSTTextView()

        isApplyingStyleSuggestion = false

        // Track the accepted suggestion to prevent re-analysis loop
        suggestionTracker.markSuggestionAccepted(
            originalText: suggestion.originalText,
            newText: suggestion.suggestedText,
            isReadability: suggestion.isReadabilitySuggestion
        )

        // Calculate position delta for adjusting subsequent suggestions
        // Use grapheme cluster count (scalar indices) since that's what suggestions use
        let originalLength = suggestion.originalText.count
        let newLength = suggestion.suggestedText.count
        let delta = newLength - originalLength
        let acceptedEnd = suggestion.originalEnd

        // Adjust positions of all suggestions that come AFTER the accepted one
        // This keeps their underlines and positions correct after the text change
        styleSuggestions = styleSuggestions.compactMap { s in
            if s.id == suggestion.id {
                return nil // Remove the accepted suggestion
            }
            if s.originalStart >= acceptedEnd {
                // This suggestion comes after the accepted one - create new instance with adjusted position
                return StyleSuggestionModel(
                    id: s.id,
                    originalStart: s.originalStart + delta,
                    originalEnd: s.originalEnd + delta,
                    originalText: s.originalText,
                    suggestedText: s.suggestedText,
                    explanation: s.explanation,
                    confidence: s.confidence,
                    style: s.style,
                    diff: s.diff,
                    isReadabilitySuggestion: s.isReadabilitySuggestion,
                    readabilityScore: s.readabilityScore,
                    targetAudience: s.targetAudience
                )
            }
            return s // Suggestion before the accepted one - keep as is
        }

        // Also adjust unified insights for style suggestions
        unifiedInsights = unifiedInsights.compactMap { insight in
            if insight.id == suggestion.id {
                return nil // Remove the accepted suggestion
            }
            if insight.source == .appleIntelligence, insight.start >= acceptedEnd {
                // Adjust position for subsequent style insights - create new instance
                return UnifiedSuggestion(
                    id: insight.id,
                    category: insight.category,
                    start: insight.start + delta,
                    end: insight.end + delta,
                    originalText: insight.originalText,
                    suggestedText: insight.suggestedText,
                    message: insight.message,
                    severity: insight.severity,
                    source: insight.source,
                    lintId: insight.lintId,
                    confidence: insight.confidence,
                    diff: insight.diff,
                    readabilityScore: insight.readabilityScore,
                    targetAudience: insight.targetAudience,
                    alternatives: insight.alternatives,
                    writingStyle: insight.writingStyle
                )
            }
            return insight
        }

        updateUnderlineRects()

        Logger.info("Applied style suggestion: '\(suggestion.originalText)' -> '\(suggestion.suggestedText)' (delta: \(delta))", category: Logger.ui)
    }

    /// Reject a style suggestion (remove from display)
    func rejectStyleSuggestion(_ suggestion: StyleSuggestionModel) {
        // Track the dismissed suggestion to prevent re-showing
        suggestionTracker.markSuggestionDismissed(originalText: suggestion.originalText)

        styleSuggestions.removeAll { $0.id == suggestion.id }
        unifiedInsights.removeAll { $0.id == suggestion.id }
        updateUnderlineRects()

        Logger.debug("Rejected style suggestion: '\(suggestion.originalText)'", category: Logger.ui)
    }

    /// Regenerate a style suggestion with different output
    func regenerateStyleSuggestion(_ suggestion: StyleSuggestionModel) async -> StyleSuggestionModel? {
        guard #available(macOS 26.0, *) else { return nil }

        let engine = FoundationModelsEngine()
        guard engine.status == .available else {
            Logger.warning("Cannot regenerate: Apple Intelligence not available", category: Logger.analysis)
            return nil
        }

        // Get the relevant text for regeneration
        let text = plainTextContent

        // Get writing style from preferences
        let styleName = UserPreferences.shared.selectedWritingStyle
        let style = WritingStyle.allCases.first { $0.displayName == styleName } ?? .default

        do {
            let newSuggestion = try await engine.regenerateStyleSuggestion(
                originalText: text,
                previousSuggestion: suggestion,
                style: style
            )

            guard let newSuggestion else {
                Logger.debug("Regenerate returned no alternative", category: Logger.analysis)
                return nil
            }

            // Replace in array
            await MainActor.run {
                if let index = styleSuggestions.firstIndex(where: { $0.id == suggestion.id }) {
                    styleSuggestions[index] = newSuggestion
                }

                // Update unified insights
                if let insightIndex = unifiedInsights.firstIndex(where: { $0.id == suggestion.id }) {
                    unifiedInsights[insightIndex] = newSuggestion.toUnifiedSuggestion()
                }

                updateUnderlineRects()
            }

            Logger.info("Regenerated style suggestion for: '\(suggestion.originalText)'", category: Logger.analysis)
            return newSuggestion

        } catch {
            Logger.error("Failed to regenerate style suggestion: \(error.localizedDescription)", category: Logger.analysis)
            return nil
        }
    }

    /// Find the StyleSuggestionModel for an underline
    func findStyleSuggestion(for underline: SketchUnderlineRect) -> StyleSuggestionModel? {
        styleSuggestions.first {
            $0.originalStart == underline.scalarRange.location &&
                $0.originalEnd == underline.scalarRange.location + underline.scalarRange.length
        }
    }

    /// Regenerate a style suggestion from a UnifiedSuggestion (insight card)
    /// Finds the corresponding StyleSuggestionModel and regenerates it
    func regenerateStyleSuggestionFromInsight(_ insight: UnifiedSuggestion) async {
        // Find the corresponding style suggestion by ID
        guard let suggestion = styleSuggestions.first(where: { $0.id == insight.id }) else {
            Logger.warning("Cannot regenerate: no matching style suggestion found for insight", category: Logger.analysis)
            return
        }

        _ = await regenerateStyleSuggestion(suggestion)
    }

    // MARK: - Text Formatting

    /// Toggle bold formatting - wraps selection in ** for markdown
    func toggleBold() {
        guard let stTextView else { return }
        toggleMarkdownWrapper(stTextView, prefix: "**", suffix: "**")
    }

    /// Toggle italic formatting - wraps selection in * for markdown
    func toggleItalic() {
        guard let stTextView else { return }
        toggleMarkdownWrapper(stTextView, prefix: "*", suffix: "*")
    }

    /// Toggle underline formatting - wraps selection in <u></u> for HTML-style markdown
    func toggleUnderline() {
        guard let stTextView else { return }
        toggleMarkdownWrapper(stTextView, prefix: "<u>", suffix: "</u>")
    }

    /// Toggle strikethrough formatting - wraps selection in ~~ for markdown
    func toggleStrikethrough() {
        guard let stTextView else { return }
        toggleMarkdownWrapper(stTextView, prefix: "~~", suffix: "~~")
    }

    /// Clear all formatting from selected text (or current line if no selection)
    /// Removes both markdown markers (**, *, ~~, etc.) and rich text attributes (font, color, background)
    func clearFormatting() {
        guard let stTextView, let text = stTextView.text else { return }
        let nsText = text as NSString

        let selectedRange = stTextView.selectedRange()
        let lineRange: NSRange

        if selectedRange.length > 0 {
            lineRange = selectedRange
        } else {
            let safeLocation = min(selectedRange.location, max(0, text.count - 1))
            lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
        }

        var lineText = nsText.substring(with: lineRange)

        // Remove line-level markdown prefixes
        let prefixPatterns = [
            "^#{1,6}\\s", // Headings
            "^-\\s", // Bullet list
            "^\\*\\s", // Alternative bullet
            "^\\d+\\.\\s", // Numbered list
            "^>\\s", // Block quote
            "^```.*$", // Code fence
        ]

        for pattern in prefixPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: lineText, range: NSRange(location: 0, length: lineText.count))
            {
                lineText = (lineText as NSString).replacingCharacters(in: match.range, with: "")
            }
        }

        // Remove inline formatting markers (**, *, ~~, `, <u></u>)
        let inlinePatterns = [
            ("\\*\\*(.+?)\\*\\*", "$1"), // Bold
            ("\\*(.+?)\\*", "$1"), // Italic
            ("~~(.+?)~~", "$1"), // Strikethrough
            ("`(.+?)`", "$1"), // Inline code
            ("<u>(.+?)</u>", "$1"), // Underline
        ]

        for (pattern, replacement) in inlinePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                lineText = regex.stringByReplacingMatches(
                    in: lineText,
                    range: NSRange(location: 0, length: lineText.count),
                    withTemplate: replacement
                )
            }
        }

        // Insert plain text (this replaces the content without formatting)
        stTextView.insertText(lineText, replacementRange: lineRange)

        // Also remove rich text attributes (font, color, background) from the text storage
        if let plainTextView = stTextView as? PlainTextSTTextView {
            plainTextView.removeFormatting(nil)
        }

        syncFromSTTextView()
        Logger.debug("Cleared markdown and rich text formatting", category: Logger.ui)
    }

    /// Toggle heading style on current line - adds/removes # prefix for markdown
    func toggleHeading(level: Int) {
        guard let stTextView else { return }
        let prefix = String(repeating: "#", count: level) + " "
        toggleMarkdownLinePrefix(stTextView, prefix: prefix)
    }

    // MARK: - Markdown Formatting Helpers (for STTextView)

    /// Wrap selected text with markdown prefix/suffix (e.g., **bold**, *italic*, `code`)
    private func toggleMarkdownWrapper(_ textView: STTextView, prefix: String, suffix: String) {
        let selectedRange = textView.selectedRange()
        guard let text = textView.text else { return }

        if selectedRange.length == 0 {
            // No selection - just insert the wrapper at cursor
            textView.insertText(prefix + suffix, replacementRange: selectedRange)
            // Cursor will be at the end of the inserted text, which is fine for now
            Logger.debug("Inserted markdown wrapper template: \(prefix)...\(suffix)", category: Logger.ui)
            return
        }

        guard let swiftRange = Range(selectedRange, in: text) else { return }
        let selectedText = String(text[swiftRange])

        // Check if already wrapped
        if selectedText.hasPrefix(prefix), selectedText.hasSuffix(suffix), selectedText.count > prefix.count + suffix.count {
            // Remove wrapper
            let startIndex = selectedText.index(selectedText.startIndex, offsetBy: prefix.count)
            let endIndex = selectedText.index(selectedText.endIndex, offsetBy: -suffix.count)
            let unwrapped = String(selectedText[startIndex ..< endIndex])
            textView.insertText(unwrapped, replacementRange: selectedRange)
            Logger.debug("Removed markdown wrapper: \(prefix)...\(suffix)", category: Logger.ui)
        } else {
            // Add wrapper
            let wrapped = prefix + selectedText + suffix
            textView.insertText(wrapped, replacementRange: selectedRange)
            Logger.debug("Added markdown wrapper: \(prefix)...\(suffix)", category: Logger.ui)
        }

        syncFromSTTextView()
    }

    /// Add/remove a line prefix (e.g., "# ", "- ", "> ")
    private func toggleMarkdownLinePrefix(_ textView: STTextView, prefix: String) {
        guard let text = textView.text else { return }
        let nsText = text as NSString

        let cursorLocation = textView.selectedRange().location
        let safeLocation = min(cursorLocation, max(0, text.count - 1))
        let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
        let lineText = nsText.substring(with: lineRange)

        // Handle different prefix types for matching
        let hasPrefix: Bool
        let prefixToRemove: String

        if prefix == "1. " {
            // For numbered lists, match any number followed by ". "
            if let match = lineText.range(of: "^\\d+\\.\\s", options: .regularExpression) {
                hasPrefix = true
                prefixToRemove = String(lineText[match])
            } else {
                hasPrefix = false
                prefixToRemove = prefix
            }
        } else if prefix.hasPrefix("#") {
            // For headings, only match exact heading level
            hasPrefix = lineText.hasPrefix(prefix)
            prefixToRemove = prefix
        } else {
            hasPrefix = lineText.hasPrefix(prefix)
            prefixToRemove = prefix
        }

        if hasPrefix {
            // Remove prefix
            let newLine = String(lineText.dropFirst(prefixToRemove.count))
            textView.insertText(newLine, replacementRange: lineRange)
            Logger.debug("Removed line prefix: \(prefix)", category: Logger.ui)
        } else {
            // Add prefix - first remove any conflicting prefix
            var cleanLine = lineText

            // Remove existing heading prefix if adding a different heading level
            if prefix.hasPrefix("#") {
                if let existingMatch = cleanLine.range(of: "^#{1,6}\\s", options: .regularExpression) {
                    cleanLine = String(cleanLine[existingMatch.upperBound...])
                }
            }

            // Remove bullet/numbered list prefix if switching
            if prefix == "- " || prefix == "1. " {
                if cleanLine.hasPrefix("- ") {
                    cleanLine = String(cleanLine.dropFirst(2))
                } else if let numMatch = cleanLine.range(of: "^\\d+\\.\\s", options: .regularExpression) {
                    cleanLine = String(cleanLine[numMatch.upperBound...])
                }
            }

            // Remove block quote prefix if adding other formatting
            if prefix == "> " {
                // Already handled
            } else if cleanLine.hasPrefix("> ") {
                cleanLine = String(cleanLine.dropFirst(2))
            }

            let newLine = prefix + cleanLine
            textView.insertText(newLine, replacementRange: lineRange)
            Logger.debug("Added line prefix: \(prefix)", category: Logger.ui)
        }

        syncFromSTTextView()
    }

    /// Sync content from STTextView to view model
    private func syncFromSTTextView() {
        guard let stTextView, let text = stTextView.text else { return }
        plainTextContentInternal = text
    }

    // MARK: - Private Helpers

    private func markAsUnsaved() {
        // If currently saving, mark that we need to re-save after current save completes
        if isSaving {
            needsResaveAfterCurrentSave = true
            saveStatus = .unsaved
            return
        }

        // Only schedule if not already unsaved (already scheduled)
        if saveStatus != .unsaved {
            saveStatus = .unsaved
            scheduleAutoSave()
        }
    }

    private func scheduleAutoSave() {
        // Don't cancel if a save is in progress
        if !isSaving {
            autoSaveTask?.cancel()
        }

        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
            guard !Task.isCancelled else { return }
            // Wait if save is in progress
            while isSaving {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            await saveCurrentDocument()
        }
    }

    private func loadDrafts() {
        drafts = SketchDocumentStore.shared.loadAll()
    }
}

// MARK: - NSAttributedString Extension

private extension NSAttributedString {
    /// Serialize to RTFD data
    var rtfdData: Data? {
        try? data(
            from: NSRange(location: 0, length: length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        )
    }
}
