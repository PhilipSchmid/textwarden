//
//  StyleCheckingSettingsView.swift
//  TextWarden
//
//  Settings view for LLM-powered style checking
//

import SwiftUI

struct StyleCheckingSettingsView: View {
    @ObservedObject private var preferences = UserPreferences.shared

    // Foundation Models engine status - wrapped for availability
    @State private var fmStatus: StyleEngineStatus = .unknown("")

    var body: some View {
        Form {
            // MARK: - Enable Section

            Section {
                Toggle(isOn: $preferences.enableStyleChecking) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Apple Intelligence Features")
                        Text("Style suggestions and AI Compose for text generation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "apple.intelligence")
                            .font(.title2)
                            .foregroundColor(.purple)
                        Text("Apple Intelligence")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("Uses Apple Intelligence for style suggestions and AI Compose text generation. All processing happens on your device.")
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

                // MARK: - Creativity Section

                Section {
                    // Temperature Preset (Creativity vs Consistency)
                    VStack(alignment: .leading, spacing: 8) {
                        // Segmented control for temperature presets
                        HStack(spacing: 0) {
                            ForEach(StyleTemperaturePreset.allCases) { preset in
                                Button {
                                    preferences.styleTemperaturePreset = preset.rawValue
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(preset.label)
                                        Image(systemName: preset.symbolName)
                                            .font(.system(size: 10))
                                    }
                                    .font(.system(size: 12, weight: selectedTemperaturePreset == preset ? .semibold : .regular))
                                    .foregroundColor(selectedTemperaturePreset == preset ? .white : .primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(
                                        selectedTemperaturePreset == preset
                                            ? Color.accentColor
                                            : Color.clear
                                    )
                                }
                                .buttonStyle(.plain)
                                .help(preset.description)
                            }
                        }
                        .background(Color(.separatorColor).opacity(0.2))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(.separatorColor), lineWidth: 0.5)
                        )

                        Text(selectedTemperaturePreset.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Creativity")
                        .font(.headline)
                }

                // MARK: - Apple Intelligence Status Section

                Section {
                    HStack(spacing: 12) {
                        Image(systemName: fmStatus.symbolName)
                            .font(.title2)
                            .foregroundColor(fmStatus.isAvailable ? .green : .orange)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(fmStatus.isAvailable ? "Apple Intelligence Ready" : "Apple Intelligence")
                                .font(.system(size: 13, weight: .semibold))

                            Text(fmStatus.userMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if fmStatus == .appleIntelligenceNotEnabled {
                            Button("Open Settings") {
                                // Open System Settings → Apple Intelligence
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.appleintelli") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else if fmStatus.canRetry {
                            Button("Check Again") {
                                checkFMAvailability()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Status")
                        .font(.headline)
                }
                .onAppear {
                    checkFMAvailability()
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
            "Balanced style improvements that work for most situations. Suggests clarity and readability enhancements without changing your tone."
        case "Concise":
            "Brief and to the point. Removes filler words, redundant phrases, and unnecessary verbosity."
        case "Formal":
            "Professional tone with complete sentences. Ideal for business emails, reports, and official documents."
        case "Casual":
            "Friendly and conversational. Great for personal messages, social media, and informal communication."
        case "Business":
            "Clear, action-oriented communication. Perfect for professional correspondence and presentations."
        default:
            "Balanced style improvements that work for most situations."
        }
    }

    // MARK: - Temperature Preset Helpers

    /// Current selected temperature preset based on preferences
    private var selectedTemperaturePreset: StyleTemperaturePreset {
        StyleTemperaturePreset(rawValue: preferences.styleTemperaturePreset) ?? .balanced
    }

    // MARK: - Foundation Models Availability

    /// Check Foundation Models availability (requires macOS 26+)
    private func checkFMAvailability() {
        if #available(macOS 26.0, *) {
            let engine = FoundationModelsEngine()
            engine.checkAvailability()
            fmStatus = engine.status
        } else {
            fmStatus = .deviceNotEligible
        }
    }
}

#Preview {
    StyleCheckingSettingsView()
        .frame(width: 700, height: 700)
}
