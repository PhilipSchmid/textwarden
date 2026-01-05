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
            // MARK: - Readability Section (always visible)

            Section {
                Toggle(isOn: $preferences.readabilityEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Readability Analysis")
                        Text("Show readability score and analyze sentence complexity")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if preferences.readabilityEnabled {
                    // Target audience segmented control
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target Audience")
                            .font(.headline)

                        HStack(spacing: 0) {
                            ForEach(UserPreferences.targetAudienceOptions, id: \.self) { audience in
                                Button {
                                    preferences.selectedTargetAudience = audience
                                } label: {
                                    Text(audience)
                                        .font(.system(size: 12, weight: preferences.selectedTargetAudience == audience ? .semibold : .regular))
                                        .foregroundColor(preferences.selectedTargetAudience == audience ? .white : .primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(
                                            preferences.selectedTargetAudience == audience
                                                ? Color.accentColor
                                                : Color.clear
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(audienceDescription(for: audience))
                            }
                        }
                        .background(Color(.separatorColor).opacity(0.2))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(.separatorColor), lineWidth: 0.5)
                        )
                    }

                    Toggle(isOn: $preferences.showReadabilityUnderlines) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Show Complexity Underlines")
                            Text("Violet dashed underlines under complex sentences")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "text.book.closed")
                            .font(.title2)
                            .foregroundColor(.purple)
                        Text("Readability")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("Analyze text complexity based on your target audience. Works independently of Apple Intelligence.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // MARK: - AI Style Suggestions Section

            Section {
                // Availability status (always visible at top)
                HStack(spacing: 12) {
                    Image(systemName: fmStatus.symbolName)
                        .font(.title2)
                        .foregroundColor(fmStatus.isAvailable ? .green : .orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(fmStatus.isAvailable ? "Ready" : "Not Available")
                            .font(.system(size: 13, weight: .semibold))

                        Text(fmStatus.userMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if fmStatus == .appleIntelligenceNotEnabled {
                        Button("Open Settings") {
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

                Toggle(isOn: $preferences.enableStyleChecking) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable AI Style Suggestions")
                        Text("Get suggestions for clarity, tone, and conciseness")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .disabled(!fmStatus.isAvailable)

                if preferences.enableStyleChecking {
                    // Writing Style segmented control
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Writing Style")
                            .font(.headline)

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
                    }

                    // Creativity segmented control
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Creativity")
                            .font(.headline)

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
                }
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundColor(.purple)
                        Text("AI Style Suggestions")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("AI-powered suggestions to improve your writing. Includes AI Compose for generating text from instructions. All processing happens on your device.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .onAppear {
                checkFMAvailability()
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Audience Descriptions

    private func audienceDescription(for audience: String) -> String {
        switch audience {
        case "Accessible":
            "Text should be easy for everyone to understand. Flags sentences that may be too complex for casual readers."
        case "General":
            "Text should be clear for the average adult reader. Good balance for most writing."
        case "Professional":
            "Text can be moderately complex. Suitable for business and professional contexts."
        case "Technical":
            "Text can use specialized language. Appropriate for technical documentation and formal writing."
        case "Academic":
            "Text can be highly complex. Suitable for academic papers and graduate-level content."
        default:
            "Text should be clear for the average adult reader."
        }
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
