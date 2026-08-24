// LanguageSelectorView.swift
// Shared searchable selector for detector-supported languages.

import SwiftUI

struct LanguageSelectorView: View {
    @Binding var selectedLanguageCodes: Set<String>
    let maxHeight: CGFloat

    @State private var searchText = ""

    init(selectedLanguageCodes: Binding<Set<String>>, maxHeight: CGFloat = 260) {
        _selectedLanguageCodes = selectedLanguageCodes
        self.maxHeight = maxHeight
    }

    private var selectedLanguages: [SupportedLanguage] {
        UserPreferences.availableLanguages.filter { selectedLanguageCodes.contains($0.code) }
    }

    private var availableLanguages: [SupportedLanguage] {
        UserPreferences.availableLanguages.filter { !selectedLanguageCodes.contains($0.code) }
    }

    private var matchingLanguages: [SupportedLanguage] {
        UserPreferences.availableLanguages.filter { $0.matches(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField("Search by language or code", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search languages")

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                    .accessibilityLabel("Clear language search")
                }

                Text("\(selectedLanguageCodes.count) selected")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityLabel("\(selectedLanguageCodes.count) languages selected")
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if !selectedLanguages.isEmpty {
                            languageSection("Selected", languages: selectedLanguages)

                            Divider()
                                .padding(.vertical, 6)
                        }

                        languageSection("Available", languages: availableLanguages)
                    } else if matchingLanguages.isEmpty {
                        Text("No languages found")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 72)
                    } else {
                        languageRows(matchingLanguages)
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: maxHeight)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func languageSection(_ title: String, languages: [SupportedLanguage]) -> some View {
        if !languages.isEmpty {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
                .padding(.bottom, 4)

            languageRows(languages)
        }
    }

    private func languageRows(_ languages: [SupportedLanguage]) -> some View {
        ForEach(languages) { language in
            Toggle(isOn: selectionBinding(for: language.code)) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(language.englishName)
                            .font(.body)

                        if let secondaryName = language.secondaryName {
                            Text(secondaryName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 12)

                    Text(language.code.uppercased())
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .toggleStyle(.checkbox)
            .accessibilityLabel(accessibilityLabel(for: language))
            .accessibilityHint("Skip English grammar checks in confidently detected passages")
        }
    }

    private func selectionBinding(for code: String) -> Binding<Bool> {
        Binding(
            get: { selectedLanguageCodes.contains(code) },
            set: { isSelected in
                if isSelected {
                    selectedLanguageCodes.insert(code)
                } else {
                    selectedLanguageCodes.remove(code)
                }
            }
        )
    }

    private func accessibilityLabel(for language: SupportedLanguage) -> String {
        if let secondaryName = language.secondaryName {
            return "\(language.englishName), \(secondaryName), \(language.code.uppercased())"
        }
        return "\(language.englishName), \(language.code.uppercased())"
    }
}
