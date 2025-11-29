//
//  StyleCheckingSettingsView.swift
//  TextWarden
//
//  Settings view for LLM-powered style checking
//

import SwiftUI

struct StyleCheckingSettingsView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @StateObject private var modelManager = ModelManager.shared

    var body: some View {
        Form {
            // MARK: - Enable Section
            Section {
                Toggle(isOn: $preferences.enableStyleChecking) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Style Checking")
                        Text("Analyze your writing for style improvements alongside grammar checking")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if preferences.enableStyleChecking {
                    Toggle(isOn: $preferences.styleAutoLoadModel) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-load model on launch")
                            Text("Automatically load the selected model when the app starts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundColor(.purple)
                        Text("Style Checking")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("Style checking uses a local AI model to suggest improvements to your writing style. All processing happens on your device - no data is sent to the cloud.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if preferences.enableStyleChecking {
                // MARK: - Writing Style Section
                Section {
                    // Custom segmented control with tooltips
                    HStack(spacing: 0) {
                        ForEach(UserPreferences.writingStyles, id: \.self) { style in
                            Button {
                                preferences.selectedWritingStyle = style
                            } label: {
                                Text(style)
                                    .font(.system(size: 12, weight: preferences.selectedWritingStyle == style ? .semibold : .regular))
                                    .foregroundColor(preferences.selectedWritingStyle == style ? .white : .primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(
                                        preferences.selectedWritingStyle == style
                                            ? Color.accentColor
                                            : Color.clear
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(styleDescription(for: style))
                        }
                    }
                    .background(Color(.separatorColor).opacity(0.2))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(.separatorColor), lineWidth: 0.5)
                    )
                } header: {
                    Text("Writing Style")
                        .font(.headline)
                }

                // MARK: - AI Model Section
                Section {
                    if modelManager.models.isEmpty {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading models...")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(modelManager.models) { model in
                            ModelRowView(
                                model: model,
                                isSelected: preferences.selectedModelId == model.id,
                                isLoaded: modelManager.loadedModelId == model.id,
                                isLoading: modelManager.isLoadingModel && preferences.selectedModelId == model.id,
                                isAnyModelLoading: modelManager.isLoadingModel,
                                isDownloading: modelManager.isDownloading(model.id),
                                downloadProgress: modelManager.downloadProgress(for: model.id),
                                lastError: modelManager.error(for: model.id),
                                onSelect: { selectModel(model) },
                                onDownload: { downloadModel(model) },
                                onDelete: { deleteModel(model) },
                                onCancelDownload: { modelManager.cancelDownload(model.id) },
                                onDismissError: { modelManager.clearError(for: model.id) }
                            )
                        }
                    }
                } header: {
                    HStack {
                        Text("AI Model")
                            .font(.headline)
                        Spacer()
                        Button {
                            openModelsFolder()
                        } label: {
                            Label("Open in Finder", systemImage: "folder")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }
                }

                // MARK: - Advanced Settings Section
                Section {
                    // Minimum sentence words
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Minimum sentence length")
                            Spacer()
                            Text("\(preferences.styleMinSentenceWords) words")
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(preferences.styleMinSentenceWords) },
                                set: { preferences.styleMinSentenceWords = Int($0) }
                            ),
                            in: 3...10,
                            step: 1
                        )
                        Text("Only analyze sentences with at least this many words")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    // Confidence threshold
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Confidence threshold")
                            Spacer()
                            Text("\(Int(preferences.styleConfidenceThreshold * 100))%")
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: $preferences.styleConfidenceThreshold,
                            in: 0.5...0.95,
                            step: 0.05
                        )
                        Text("The AI model assigns a confidence score (0-100%) to each suggestion based on how certain it is. Higher thresholds show fewer but more reliable suggestions.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Advanced Settings")
                        .font(.headline)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Style Descriptions

    private func styleDescription(for style: String) -> String {
        switch style {
        case "Default":
            return "Balanced style improvements that work for most situations. Suggests clarity and readability enhancements without changing your tone."
        case "Concise":
            return "Brief and to the point. Removes filler words, redundant phrases, and unnecessary verbosity."
        case "Formal":
            return "Professional tone with complete sentences. Ideal for business emails, reports, and official documents."
        case "Casual":
            return "Friendly and conversational. Great for personal messages, social media, and informal communication."
        case "Business":
            return "Clear, action-oriented communication. Perfect for professional correspondence and presentations."
        default:
            return "Balanced style improvements that work for most situations."
        }
    }

    // MARK: - Actions

    private func selectModel(_ model: LLMModelInfo) {
        // Block selection while any model is loading
        guard !modelManager.isLoadingModel else { return }

        preferences.selectedModelId = model.id
        if model.isDownloaded && modelManager.loadedModelId != model.id {
            Task {
                await modelManager.loadModel(model.id)
            }
        }
    }

    private func downloadModel(_ model: LLMModelInfo) {
        modelManager.startDownload(model.id)
    }

    private func deleteModel(_ model: LLMModelInfo) {
        modelManager.deleteModel(model.id)
    }

    private func openModelsFolder() {
        // Get or create the models directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appSupport.appendingPathComponent("TextWarden/Models", isDirectory: true)

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        // Open in Finder
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: modelsDir.path)
    }
}

// MARK: - Model Row View

struct ModelRowView: View {
    let model: LLMModelInfo
    let isSelected: Bool
    let isLoaded: Bool
    let isLoading: Bool
    let isAnyModelLoading: Bool
    let isDownloading: Bool
    let downloadProgress: ModelDownloadProgress?
    let lastError: String?
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onCancelDownload: () -> Void
    let onDismissError: () -> Void

    @State private var showError = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .purple : .secondary)
                .font(.title3)
                .padding(.top, 2)

            // Model info
            VStack(alignment: .leading, spacing: 6) {
                // Header row
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .semibold))

                    tierBadge

                    if model.isDownloaded && !isLoaded && !isLoading {
                        Text("Downloaded")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            .foregroundColor(.secondary)
                    }

                    if isLoaded {
                        Text("Active")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.2)))
                            .foregroundColor(.green)
                    }
                }

                // Metadata row
                HStack(spacing: 12) {
                    if !model.vendor.isEmpty {
                        Label(model.vendor, systemImage: "building.2")
                    }
                    Label(model.isMultilingual ? "Multilingual" : "English", systemImage: "globe")
                    Label(model.formattedSize, systemImage: "internaldrive")
                    HStack(spacing: 3) {
                        Text("Speed")
                        progressDots(value: model.speedRating)
                        Text(String(format: "%.1f", model.speedRating))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    HStack(spacing: 3) {
                        Text("Accuracy")
                        progressDots(value: model.qualityRating)
                        Text(String(format: "%.1f", model.qualityRating))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)

                // Description
                Text(model.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action buttons
            actionSection
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(isSelected ? Color.purple.opacity(0.08) : Color.clear)
        .cornerRadius(8)
        .onChange(of: lastError) { _, newValue in
            showError = newValue != nil
        }
    }

    private var tierBadge: some View {
        Text(model.tier.displayName)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tierColor.opacity(0.2)))
            .foregroundColor(tierColor)
    }

    private var tierColor: Color {
        switch model.tier {
        case .balanced:
            return .blue
        case .accurate:
            return .purple
        case .lightweight:
            return .green
        case .custom:
            return .orange
        }
    }

    // Unified button style dimensions
    private let buttonMinWidth: CGFloat = 82
    private let buttonHeight: CGFloat = 24

    private var buttonFont: Font {
        .system(size: 11, weight: .medium)
    }

    @ViewBuilder
    private var actionSection: some View {
        if isSelected && isLoading && model.isDownloaded {
            // Loading state - show spinner on the button
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text("Loading")
            }
            .font(buttonFont)
            .foregroundColor(.white)
            .frame(minWidth: buttonMinWidth, maxWidth: buttonMinWidth, minHeight: buttonHeight, maxHeight: buttonHeight)
            .background(
                Capsule()
                    .fill(Color.orange.opacity(0.75))
            )
        } else if isSelected && model.isDownloaded {
            // Selected state - show green "Selected" button with menu
            Menu {
                Button {
                    // Show in Finder
                    if let modelsDir = modelManager.modelsDirectory {
                        let modelPath = modelsDir.appendingPathComponent(model.filename)
                        NSWorkspace.shared.selectFile(modelPath.path, inFileViewerRootedAtPath: "")
                    }
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.downloadUrl, forType: .string)
                } label: {
                    Label("Copy Download URL", systemImage: "doc.on.doc")
                }

                // Note: Delete option is intentionally hidden for the selected model.
                // Users must select a different model before deleting this one.
            } label: {
                HStack(spacing: 3) {
                    Text("Selected")
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(buttonFont)
                .foregroundColor(.white)
                .frame(minWidth: buttonMinWidth, minHeight: buttonHeight)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.75))
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        } else if model.isDownloaded {
            Menu {
                Button(action: onSelect) {
                    Label("Select", systemImage: "checkmark")
                }
                .disabled(isAnyModelLoading)

                Divider()

                Button {
                    // Show in Finder
                    if let modelsDir = modelManager.modelsDirectory {
                        let modelPath = modelsDir.appendingPathComponent(model.filename)
                        NSWorkspace.shared.selectFile(modelPath.path, inFileViewerRootedAtPath: "")
                    }
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.downloadUrl, forType: .string)
                } label: {
                    Label("Copy Download URL", systemImage: "doc.on.doc")
                }

                Divider()

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Text("Options")
                    .font(buttonFont)
                    .foregroundColor(.primary)
                    .frame(minWidth: buttonMinWidth, minHeight: buttonHeight)
                    .background(
                        Capsule()
                            .fill(Color(NSColor.systemGray).opacity(0.3))
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        } else {
            // Download button / Progress / Error state
            downloadStateView
        }
    }

    @ViewBuilder
    private var downloadStateView: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if lastError != nil, !model.isDownloaded {
                // Error state
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text("Download failed")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.red)
                    )

                    HStack(spacing: 8) {
                        Button("Retry") {
                            onDismissError()
                            onDownload()
                        }
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)

                        Button("Dismiss") {
                            onDismissError()
                        }
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else if isDownloading {
                // Downloading state
                VStack(alignment: .trailing, spacing: 6) {
                    if let progress = downloadProgress {
                        // Show progress bar with cancel button
                        HStack(spacing: 8) {
                            VStack(alignment: .trailing, spacing: 2) {
                                ProgressView(value: progress.percentage / 100)
                                    .frame(width: 100)
                                    .tint(.accentColor)

                                Text(progress.formattedProgress)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            // Cancel button (X icon)
                            Button(action: onCancelDownload) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Cancel download")
                        }
                    } else {
                        // Starting download
                        HStack(spacing: 8) {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Starting...")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            // Cancel button
                            Button(action: onCancelDownload) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Cancel download")
                        }
                    }
                }
            } else {
                // Ready to download
                HStack(spacing: 8) {
                    Button(action: onDownload) {
                        HStack(spacing: 3) {
                            Text("Download")
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .font(buttonFont)
                        .foregroundColor(.white)
                        .frame(minWidth: buttonMinWidth, minHeight: buttonHeight)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.85))
                        )
                    }
                    .buttonStyle(.plain)

                    // Copy URL button
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.downloadUrl, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy download URL to clipboard")
                }
            }
        }
    }

    private func progressDots(value: Float) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                Circle()
                    .fill(index < Int(value / 2) ? performanceColor(value: value) : Color(.quaternaryLabelColor))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func performanceColor(value: Float) -> Color {
        switch value {
        case 8.0...10.0: return Color(.systemGreen)
        case 6.0..<8.0: return Color(.systemYellow)
        case 4.0..<6.0: return Color(.systemOrange)
        default: return Color(.systemRed)
        }
    }

    @StateObject private var modelManager = ModelManager.shared
}

#Preview {
    StyleCheckingSettingsView()
        .frame(width: 700, height: 700)
}
