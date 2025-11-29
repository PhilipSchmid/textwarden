// StyleTypes.swift
// Swift models for LLM style checking

import Foundation

// MARK: - Style Template

/// Writing style template for LLM suggestions
public enum WritingStyle: String, CaseIterable, Identifiable {
    case `default` = "default"
    case formal = "formal"
    case informal = "informal"
    case business = "business"
    case concise = "concise"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .default: return "Default"
        case .formal: return "Formal"
        case .informal: return "Casual"
        case .business: return "Business"
        case .concise: return "Concise"
        }
    }

    public var description: String {
        switch self {
        case .default: return "Balanced style improvements"
        case .formal: return "Professional tone, complete sentences"
        case .informal: return "Friendly, conversational writing"
        case .business: return "Clear, action-oriented communication"
        case .concise: return "Brief and to the point, no filler"
        }
    }

    /// Convert to FFI StyleTemplate
    var ffiStyle: StyleTemplate {
        switch self {
        case .default: return .Default
        case .formal: return .Formal
        case .informal: return .Informal
        case .business: return .Business
        case .concise: return .Concise
        }
    }

    /// Convert from FFI StyleTemplate
    init(ffiStyle: StyleTemplate) {
        switch ffiStyle {
        case .Default: self = .default
        case .Formal: self = .formal
        case .Informal: self = .informal
        case .Business: self = .business
        case .Concise: self = .concise
        }
    }
}

// MARK: - Diff Segment

/// Kind of change in a diff
public enum DiffChangeKind: Equatable {
    case unchanged
    case added
    case removed

    init(ffiKind: DiffKind) {
        switch ffiKind {
        case .Unchanged: self = .unchanged
        case .Added: self = .added
        case .Removed: self = .removed
        }
    }
}

/// A segment of text in a diff
public struct DiffSegmentModel: Identifiable {
    public let id = UUID()
    public let text: String
    public let kind: DiffChangeKind

    init(ffiSegment: FfiDiffSegmentRef) {
        self.text = ffiSegment.text().toString()
        self.kind = DiffChangeKind(ffiKind: ffiSegment.kind())
    }

    public init(text: String, kind: DiffChangeKind) {
        self.text = text
        self.kind = kind
    }
}

// MARK: - Style Suggestion

/// A style improvement suggestion from the LLM
public struct StyleSuggestionModel: Identifiable {
    public let id: String
    public let originalStart: Int
    public let originalEnd: Int
    public let originalText: String
    public let suggestedText: String
    public let explanation: String
    public let confidence: Float
    public let style: WritingStyle
    public let diff: [DiffSegmentModel]

    init(ffiSuggestion: FfiStyleSuggestionRef) {
        self.id = ffiSuggestion.id().toString()
        self.originalStart = Int(ffiSuggestion.original_start())
        self.originalEnd = Int(ffiSuggestion.original_end())
        self.originalText = ffiSuggestion.original_text().toString()
        self.suggestedText = ffiSuggestion.suggested_text().toString()
        self.explanation = ffiSuggestion.explanation().toString()
        self.confidence = ffiSuggestion.confidence()
        self.style = WritingStyle(ffiStyle: ffiSuggestion.style())

        let ffiDiff = ffiSuggestion.diff()
        self.diff = ffiDiff.map { DiffSegmentModel(ffiSegment: $0) }
    }

    public init(
        id: String = UUID().uuidString,
        originalStart: Int,
        originalEnd: Int,
        originalText: String,
        suggestedText: String,
        explanation: String,
        confidence: Float = 0.8,
        style: WritingStyle = .default,
        diff: [DiffSegmentModel] = []
    ) {
        self.id = id
        self.originalStart = originalStart
        self.originalEnd = originalEnd
        self.originalText = originalText
        self.suggestedText = suggestedText
        self.explanation = explanation
        self.confidence = confidence
        self.style = style
        self.diff = diff
    }

    /// Range of the original text
    public var range: Range<Int> {
        originalStart..<originalEnd
    }
}

// MARK: - Style Analysis Result

/// Result of LLM style analysis
public struct StyleAnalysisResultModel {
    public let suggestions: [StyleSuggestionModel]
    public let analysisTimeMs: UInt64
    public let modelId: String
    public let style: WritingStyle
    public let error: String?

    public var isError: Bool {
        error != nil
    }

    init(ffiResult: FfiStyleAnalysisResultRef) {
        let ffiSuggestions = ffiResult.suggestions()
        self.suggestions = ffiSuggestions.map { StyleSuggestionModel(ffiSuggestion: $0) }
        self.analysisTimeMs = ffiResult.analysis_time_ms()
        self.modelId = ffiResult.model_id().toString()
        self.style = WritingStyle(ffiStyle: ffiResult.style())
        self.error = ffiResult.is_error() ? ffiResult.error_message().toString() : nil
    }

    public init(
        suggestions: [StyleSuggestionModel] = [],
        analysisTimeMs: UInt64 = 0,
        modelId: String = "",
        style: WritingStyle = .default,
        error: String? = nil
    ) {
        self.suggestions = suggestions
        self.analysisTimeMs = analysisTimeMs
        self.modelId = modelId
        self.style = style
        self.error = error
    }

    public static var empty: StyleAnalysisResultModel {
        StyleAnalysisResultModel()
    }

    public static func failure(_ message: String) -> StyleAnalysisResultModel {
        StyleAnalysisResultModel(error: message)
    }
}

// MARK: - Model Info

/// Tier classification for LLM models
public enum LLMModelTier: String, CaseIterable {
    case balanced
    case accurate  // Slower but higher quality (formerly "premium")
    case lightweight
    case custom

    public var displayName: String {
        switch self {
        case .balanced: return "Balanced"
        case .accurate: return "Accurate"
        case .lightweight: return "Lightweight"
        case .custom: return "Custom"
        }
    }

    init(ffiTier: ModelTier) {
        switch ffiTier {
        case .Balanced: self = .balanced
        case .Accurate: self = .accurate
        case .Lightweight: self = .lightweight
        case .Custom: self = .custom
        }
    }
}

/// Information about an available LLM model
public struct LLMModelInfo: Identifiable {
    public let id: String
    public let name: String
    public let vendor: String
    public let filename: String
    public let downloadUrl: String
    public let sizeBytes: UInt64
    public let speedRating: Float
    public let qualityRating: Float
    public let languages: [String]
    public let isMultilingual: Bool
    public let description: String
    public let tier: LLMModelTier
    public let isDownloaded: Bool
    public let isDefault: Bool

    init(ffiInfo: FfiModelInfoRef) {
        self.id = ffiInfo.id().toString()
        self.name = ffiInfo.name().toString()
        self.vendor = ""  // FFI models don't have vendor yet
        self.filename = ffiInfo.filename().toString()
        self.downloadUrl = ffiInfo.download_url().toString()
        self.sizeBytes = ffiInfo.size_bytes()
        self.speedRating = ffiInfo.speed_rating()
        self.qualityRating = ffiInfo.quality_rating()

        let ffiLanguages = ffiInfo.languages()
        self.languages = ffiLanguages.map { $0.as_str().toString() }

        self.isMultilingual = ffiInfo.is_multilingual()
        self.description = ffiInfo.description().toString()
        self.tier = LLMModelTier(ffiTier: ffiInfo.tier())
        self.isDownloaded = ffiInfo.is_downloaded()
        self.isDefault = ffiInfo.is_default()
    }

    public init(
        id: String,
        name: String,
        vendor: String = "",
        filename: String = "",
        downloadUrl: String = "",
        sizeBytes: UInt64 = 0,
        speedRating: Float = 5.0,
        qualityRating: Float = 5.0,
        languages: [String] = ["en"],
        isMultilingual: Bool = false,
        description: String = "",
        tier: LLMModelTier = .balanced,
        isDownloaded: Bool = false,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.filename = filename
        self.downloadUrl = downloadUrl
        self.sizeBytes = sizeBytes
        self.speedRating = speedRating
        self.qualityRating = qualityRating
        self.languages = languages
        self.isMultilingual = isMultilingual
        self.description = description
        self.tier = tier
        self.isDownloaded = isDownloaded
        self.isDefault = isDefault
    }

    /// Formatted size string (e.g., "1.2 GB")
    public var formattedSize: String {
        let gb = Double(sizeBytes) / 1_000_000_000.0
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else {
            let mb = Double(sizeBytes) / 1_000_000.0
            return String(format: "%.0f MB", mb)
        }
    }
}

// MARK: - Download Progress

/// Status of a model download
public enum ModelDownloadStatus: Equatable {
    case starting
    case downloading
    case completed
    case failed
    case cancelled
}

/// Progress information for a model download
public struct ModelDownloadProgress {
    public let modelId: String
    public let bytesDownloaded: UInt64
    public let totalBytes: UInt64
    public let status: ModelDownloadStatus
    public let percentage: Double

    public init(
        modelId: String,
        bytesDownloaded: UInt64,
        totalBytes: UInt64,
        status: ModelDownloadStatus,
        percentage: Double
    ) {
        self.modelId = modelId
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.status = status
        self.percentage = percentage
    }

    /// Formatted progress string (e.g., "45.2 MB / 1.2 GB")
    public var formattedProgress: String {
        let downloadedMB = Double(bytesDownloaded) / 1_000_000.0
        let totalMB = Double(totalBytes) / 1_000_000.0

        if totalMB >= 1000 {
            return String(format: "%.0f MB / %.1f GB", downloadedMB, totalMB / 1000.0)
        } else {
            return String(format: "%.0f / %.0f MB", downloadedMB, totalMB)
        }
    }
}

// MARK: - Rejection Category

/// Category for why a suggestion was rejected
public enum SuggestionRejectionCategory: String, CaseIterable {
    case wrongMeaning = "wrong_meaning"
    case tooFormal = "too_formal"
    case tooInformal = "too_informal"
    case unnecessaryChange = "unnecessary_change"
    case wrongTerm = "wrong_term"
    case other = "other"

    public var displayName: String {
        switch self {
        case .wrongMeaning: return "Changes meaning"
        case .tooFormal: return "Too formal"
        case .tooInformal: return "Too informal"
        case .unnecessaryChange: return "Unnecessary change"
        case .wrongTerm: return "Wrong term/word"
        case .other: return "Other reason"
        }
    }

    /// Convert to FFI RejectionCategory
    var ffiCategory: RejectionCategory {
        switch self {
        case .wrongMeaning: return .WrongMeaning
        case .tooFormal: return .TooFormal
        case .tooInformal: return .TooInformal
        case .unnecessaryChange: return .UnnecessaryChange
        case .wrongTerm: return .WrongTerm
        case .other: return .Other
        }
    }
}
