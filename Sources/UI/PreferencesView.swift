//
//  PreferencesView.swift
//  TextWarden
//
//  Settings/Preferences window
//

import SwiftUI
import LaunchAtLogin
import KeyboardShortcuts
import UniformTypeIdentifiers
import Charts
import AppKit

struct PreferencesView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @ObservedObject private var windowController = PreferencesWindowController.shared

    var body: some View {
        TabView(selection: $windowController.selectedTab) {
            GeneralPreferencesView(preferences: preferences)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general.rawValue)
                .accessibilityLabel("General settings tab")

            SpellCheckingView()
                .tabItem {
                    Label("Grammar", systemImage: "text.badge.checkmark")
                }
                .tag(SettingsTab.grammar.rawValue)
                .accessibilityLabel("Grammar checking settings tab")

            StyleCheckingSettingsView()
                .tabItem {
                    Label("Style", systemImage: "sparkles")
                }
                .tag(SettingsTab.style.rawValue)
                .accessibilityLabel("Style checking settings tab")

            ApplicationSettingsView(preferences: preferences)
                .tabItem {
                    Label("Applications", systemImage: "app.badge")
                }
                .tag(SettingsTab.applications.rawValue)
                .accessibilityLabel("Application settings tab")

            WebsiteSettingsView(preferences: preferences)
                .tabItem {
                    Label("Websites", systemImage: "globe")
                }
                .tag(SettingsTab.websites.rawValue)
                .accessibilityLabel("Website settings tab")

            StatisticsView()
                .tabItem {
                    Label("Statistics", systemImage: "chart.bar.fill")
                }
                .tag(SettingsTab.statistics.rawValue)
                .accessibilityLabel("Usage statistics tab")

            DiagnosticsView(preferences: preferences)
                .tabItem {
                    Label("Diagnostics", systemImage: "wrench.and.screwdriver")
                }
                .tag(SettingsTab.diagnostics.rawValue)
                .accessibilityLabel("Diagnostics and troubleshooting tab")

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about.rawValue)
                .accessibilityLabel("About TextWarden tab")
        }
        .frame(minWidth: 750, minHeight: 600)
        // Theme is managed via NSApp.appearance in PreferencesWindowController
        // This provides seamless theme switching without view recreation or scroll position reset
    }
}

// MARK: - Spell Checking (combines Categories and Dictionary)

struct SpellCheckingView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @ObservedObject private var vocabulary = CustomVocabulary.shared
    @State private var newWord = ""
    @State private var searchText = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            // MARK: Grammar Categories Group
            FilteringPreferencesContent(preferences: preferences)

            // MARK: Language Settings
            Section {
                Picker("English dialect:", selection: $preferences.selectedDialect) {
                    ForEach(UserPreferences.availableDialects, id: \.self) { dialect in
                        Text(dialect).tag(dialect)
                    }
                }
                .help("Select the English dialect for grammar checking")

                Text("Choose your preferred English variant for spelling and grammar rules")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Language")
                    .font(.headline)
            }

            // MARK: Custom Dictionary Group
            CustomVocabularyContent(
                vocabulary: vocabulary,
                preferences: preferences,
                newWord: $newWord,
                searchText: $searchText,
                errorMessage: $errorMessage
            )
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Filtering Preferences Content (extracted from FilteringPreferencesView)

private struct FilteringPreferencesContent: View {
    @ObservedObject var preferences: UserPreferences

    /// Helper to create toggle binding for a category
    private func categoryBinding(_ category: String) -> Binding<Bool> {
        Binding(
            get: { preferences.enabledCategories.contains(category) },
            set: { enabled in
                var categories = preferences.enabledCategories
                if enabled {
                    categories.insert(category)
                } else {
                    categories.remove(category)
                }
                preferences.enabledCategories = categories
            }
        )
    }

    var body: some View {
        Group {
            // Quick Actions
            Section {
                HStack {
                    Button("Enable All") {
                        preferences.enabledCategories = UserPreferences.allCategories
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Disable All") {
                        preferences.enabledCategories = []
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Grammar Categories")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("Enable or disable specific types of grammar and style checks")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Quick Actions")
                        .font(.headline)
                        .padding(.top, 8)
                }
            }

            // Core Grammar Checks
            Section {
                Toggle("Spelling", isOn: categoryBinding("Spelling"))
                    .help("When your brain doesn't know the right spelling")

                Toggle("Typos", isOn: categoryBinding("Typo"))
                    .help("When your brain knows the right spelling but your fingers made a mistake")

                Toggle("Grammar", isOn: categoryBinding("Grammar"))
                    .help("Detect grammatical errors and incorrect sentence structure")

                Toggle("Agreement", isOn: categoryBinding("Agreement"))
                    .help("Check subject-verb and pronoun agreement (e.g., 'he go' → 'he goes')")

                Toggle("Punctuation", isOn: categoryBinding("Punctuation"))
                    .help("Check punctuation usage, including hyphenation in compound adjectives")

                Toggle("Capitalization", isOn: categoryBinding("Capitalization"))
                    .help("Check proper capitalization of words and sentences")
            } header: {
                Text("Core Checks")
                    .font(.headline)
            }

            // Writing Style
            Section {
                Toggle("Style", isOn: categoryBinding("Style"))
                    .help("Check cases where multiple options are correct but one is preferred")

                Toggle("Readability", isOn: categoryBinding("Readability"))
                    .help("Improve text flow and make writing easier to understand")

                Toggle("Enhancement", isOn: categoryBinding("Enhancement"))
                    .help("Suggest improvements that enhance clarity or impact without fixing errors")

                Toggle("Redundancy", isOn: categoryBinding("Redundancy"))
                    .help("Detect cases where words duplicate meaning that's already expressed")

                Toggle("Repetition", isOn: categoryBinding("Repetition"))
                    .help("Detect repeated words or phrases in nearby sentences")
            } header: {
                Text("Style & Clarity")
                    .font(.headline)
            }

            // Word Usage
            Section {
                Toggle("Word Choice", isOn: categoryBinding("WordChoice"))
                    .help("Suggest choosing between different words or phrases in a given context")

                Toggle("Usage", isOn: categoryBinding("Usage"))
                    .help("Check conventional word usage and standard collocations")

                Toggle("Eggcorns", isOn: categoryBinding("Eggcorn"))
                    .help("Detect cases where a word or phrase is misused for a similar-sounding word or phrase (e.g., 'for all intensive purposes' → 'for all intents and purposes')")

                Toggle("Malapropisms", isOn: categoryBinding("Malapropism"))
                    .help("Detect cases where a word is mistakenly used for a similar-sounding word with a different meaning (e.g., 'escape goat' → 'scapegoat')")
            } header: {
                Text("Word Usage")
                    .font(.headline)
            }

            // Advanced
            Section {
                Toggle("Formatting", isOn: categoryBinding("Formatting"))
                    .help("Check text formatting issues such as spacing and special characters")

                Toggle("Boundary Errors", isOn: categoryBinding("BoundaryError"))
                    .help("Detect errors where words are joined or split at the wrong boundaries (e.g., 'each and everyone' → 'each and every one')")

                Toggle("Regionalism", isOn: categoryBinding("Regionalism"))
                    .help("Detect variations that are standard in some regions or dialects but not others")

                Toggle("Nonstandard", isOn: categoryBinding("Nonstandard"))
                    .help("Detect non-standard language usage that may be informal or colloquial")

                Toggle("Miscellaneous", isOn: categoryBinding("Miscellaneous"))
                    .help("Check for any other grammar issues that don't fit neatly into other categories")
            } header: {
                Text("Advanced")
                    .font(.headline)
            }

            Section {
                if preferences.ignoredRules.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        Text("No ignored rules")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(Array(preferences.ignoredRules).sorted(), id: \.self) { ruleId in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formatRuleName(ruleId))
                                    .font(.subheadline)
                                Text(ruleId)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Re-enable") {
                                preferences.enableRule(ruleId)
                            }
                            .buttonStyle(.borderless)
                            .help("Allow this rule to show grammar suggestions again")
                        }
                        .padding(.vertical, 4)
                    }

                    Divider()

                    HStack {
                        Spacer()
                        Button("Clear All") {
                            preferences.ignoredRules = []
                        }
                        .buttonStyle(.bordered)
                        .help("Re-enable all ignored grammar rules")
                    }
                }
            } header: {
                HStack {
                    Text("Ignored Rules")
                        .font(.headline)
                    Spacer()
                    if !preferences.ignoredRules.isEmpty {
                        Text("\(preferences.ignoredRules.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func formatRuleName(_ ruleId: String) -> String {
        let components = ruleId.split(separator: ":", maxSplits: 1)
        var nameToFormat = components.count > 1 ? String(components[1]) : ruleId
        nameToFormat = nameToFormat.trimmingCharacters(in: CharacterSet(charactersIn: ":"))

        let words = nameToFormat.split(separator: "_")
        if !words.isEmpty {
            return words.map { word in
                word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }.joined(separator: " ")
        }

        var result = ""
        for (index, char) in nameToFormat.enumerated() {
            if index > 0 && char.isUppercase {
                result += " "
            }
            result.append(char)
        }
        return result.isEmpty ? ruleId : result
    }
}

// MARK: - Custom Vocabulary Content (extracted from CustomVocabularyView)

private struct CustomVocabularyContent: View {
    @ObservedObject var vocabulary: CustomVocabulary
    @ObservedObject var preferences: UserPreferences
    @Binding var newWord: String
    @Binding var searchText: String
    @Binding var errorMessage: String?
    @State private var ignoredSearchText: String = ""
    @State private var showClearDictionaryAlert: Bool = false
    @State private var showClearIgnoredAlert: Bool = false

    private var filteredWords: [String] {
        let allWords = Array(vocabulary.words).sorted()
        if searchText.isEmpty {
            return allWords
        }
        return allWords.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredIgnoredTexts: [String] {
        let allTexts = Array(preferences.ignoredErrorTexts).sorted()
        if ignoredSearchText.isEmpty {
            return allTexts
        }
        return allTexts.filter { $0.localizedCaseInsensitiveContains(ignoredSearchText) }
    }

    @ViewBuilder
    var body: some View {
        Group {
            // MARK: - Predefined Wordlists Section
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Internet Abbreviations", isOn: $preferences.enableInternetAbbreviations)
                        .help("Accept common abbreviations like BTW, FYI, LOL, ASAP, etc.")

                    Text("3,200+ abbreviations (BTW, FYI, LOL, ASAP, AFAICT, etc.) • Case-insensitive")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Gen Z Slang", isOn: $preferences.enableGenZSlang)
                        .help("Accept modern slang words like ghosting, sus, slay, etc.")

                    Text("270+ modern terms (ghosting, sus, slay, vibe, etc.) • Case-insensitive")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("IT & Tech Terminology", isOn: $preferences.enableITTerminology)
                        .help("Accept technical terms like kubernetes, docker, API, JSON, localhost, etc.")

                    Text("10,000+ technical terms (kubernetes, docker, nginx, API, JSON, etc.) • Case-insensitive")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Brand & Company Names", isOn: $preferences.enableBrandNames)
                        .help("Accept brand names like Apple, Microsoft, Google, Amazon, etc.")

                    Text("2,400+ brand/company names (Fortune 500, Forbes 2000, global brands) • Case-insensitive")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Person Names (First Names)", isOn: $preferences.enablePersonNames)
                        .help("Accept common first names like James, Maria, Chen, Fatima, etc.")

                    Text("100,000+ international first names (US SSA + worldwide sources) • Case-insensitive")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Surnames (Last Names)", isOn: $preferences.enableLastNames)
                        .help("Accept common surnames like Smith, Garcia, Johnson, etc.")

                    Text("150,000+ surnames from US Census data • Case-insensitive")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }
            } header: {
                Text("Predefined Wordlists")
                    .font(.headline)
            }

            // MARK: - Language Detection Section
            Section {
                Toggle("Detect non-English words", isOn: $preferences.enableLanguageDetection)
                    .help("Automatically detect and ignore errors in non-English words")

                Text("Skip grammar checking for words detected in selected languages")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if preferences.enableLanguageDetection {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Languages to ignore:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

                        LazyVGrid(columns: [
                            GridItem(.fixed(150), alignment: .leading),
                            GridItem(.fixed(150), alignment: .leading),
                            GridItem(.fixed(150), alignment: .leading),
                            GridItem(.fixed(150), alignment: .leading)
                        ], alignment: .leading, spacing: 6) {
                            ForEach(UserPreferences.availableLanguages.filter { $0 != "English" }.sorted(), id: \.self) { language in
                                Toggle(language, isOn: Binding(
                                    get: { preferences.excludedLanguages.contains(language) },
                                    set: { isSelected in
                                        if isSelected {
                                            preferences.excludedLanguages.insert(language)
                                        } else {
                                            preferences.excludedLanguages.remove(language)
                                        }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .font(.system(size: 11))
                            }
                        }
                        .padding(.leading, 20)

                        if !preferences.excludedLanguages.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                    .font(.caption2)
                                Text("Words detected as \(preferences.excludedLanguages.sorted().joined(separator: ", ")) will not be marked as errors")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            } header: {
                Text("Language Detection")
                    .font(.headline)
            }

            // MARK: - Custom Dictionary Section
            Section {
                // Add word input row
                HStack(spacing: 8) {
                    Text("Add new word:")
                        .foregroundColor(.secondary)

                    LeftAlignedTextField(
                        text: $newWord,
                        placeholder: "",
                        onSubmit: { addWord() }
                    )
                    .frame(minHeight: 22, maxHeight: 22)

                    Button("Add") {
                        addWord()
                    }
                    .buttonStyle(.bordered)
                    .disabled(newWord.isEmpty)
                    .help("Add word to dictionary")

                    // Error message inline
                    if let errorMessage = errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                // Search field (only show when there are words)
                if !vocabulary.words.isEmpty {
                    SearchField(text: $searchText, placeholder: "Search \(vocabulary.words.count) words...")
                        .frame(height: 22)
                }

                // Word list
                if vocabulary.words.isEmpty {
                    Text("No words added yet")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                        .padding(.vertical, 8)
                } else if filteredWords.isEmpty && !searchText.isEmpty {
                    Text("No matching words")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                        .padding(.vertical, 8)
                } else {
                    ForEach(filteredWords, id: \.self) { word in
                        HStack {
                            Text(word)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                removeWord(word)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove from dictionary")
                        }
                    }
                }
            } header: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom Dictionary")
                            .font(.headline)
                        Text("Words added here won't be flagged as spelling errors")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !vocabulary.words.isEmpty {
                        Button {
                            showClearDictionaryAlert = true
                        } label: {
                            Label("Clear list", systemImage: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }
                }
            }
            .alert("Clear Custom Dictionary?", isPresented: $showClearDictionaryAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    clearAll()
                }
            } message: {
                Text("This will remove all \(vocabulary.words.count) words from your custom dictionary. This action cannot be undone.")
            }

            // MARK: - Ignored Words Section
            Section {
                // Search field (only show when there are ignored words)
                if !preferences.ignoredErrorTexts.isEmpty {
                    SearchField(text: $ignoredSearchText, placeholder: "Search \(preferences.ignoredErrorTexts.count) words...")
                        .frame(height: 22)
                }

                // Word list
                if preferences.ignoredErrorTexts.isEmpty {
                    Text("No ignored words")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                        .padding(.vertical, 8)
                } else if filteredIgnoredTexts.isEmpty && !ignoredSearchText.isEmpty {
                    Text("No matching words")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                        .padding(.vertical, 8)
                } else {
                    ForEach(filteredIgnoredTexts, id: \.self) { ignoredText in
                        HStack {
                            Text(ignoredText)
                                .lineLimit(1)
                            Spacer()

                            // Move to dictionary button
                            Button {
                                moveToCustomDictionary(ignoredText)
                            } label: {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help("Add to Custom Dictionary")

                            // Remove button
                            Button {
                                preferences.ignoredErrorTexts.remove(ignoredText)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Stop ignoring (will be checked again)")
                        }
                    }
                }
            } header: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ignored Words")
                            .font(.headline)
                        Text("Errors you've dismissed. Click + to add to dictionary instead.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !preferences.ignoredErrorTexts.isEmpty {
                        Button {
                            showClearIgnoredAlert = true
                        } label: {
                            Label("Clear list", systemImage: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }
                }
            }
            .alert("Clear Ignored Words?", isPresented: $showClearIgnoredAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    preferences.ignoredErrorTexts.removeAll()
                }
            } message: {
                Text("This will remove all \(preferences.ignoredErrorTexts.count) ignored words. These errors will be flagged again. This action cannot be undone.")
            }
        }
    }

    private func addWord() {
        guard !newWord.isEmpty else { return }

        do {
            try vocabulary.addWord(newWord)
            newWord = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeWord(_ word: String) {
        do {
            try vocabulary.removeWord(word)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearAll() {
        do {
            try vocabulary.clearAll()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Move an ignored word to the Custom Dictionary
    /// This adds it as a valid word and removes it from ignored list
    private func moveToCustomDictionary(_ text: String) {
        do {
            try vocabulary.addWord(text)
            preferences.ignoredErrorTexts.remove(text)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Category Preferences

struct FilteringPreferencesView: View {
    @ObservedObject var preferences: UserPreferences

    /// Helper to create toggle binding for a category
    private func categoryBinding(_ category: String) -> Binding<Bool> {
        Binding(
            get: { preferences.enabledCategories.contains(category) },
            set: { enabled in
                var categories = preferences.enabledCategories
                if enabled {
                    categories.insert(category)
                } else {
                    categories.remove(category)
                }
                preferences.enabledCategories = categories
            }
        )
    }

    var body: some View {
        Form {
            // Quick Actions
            Section {
                HStack {
                    Button("Enable All") {
                        preferences.enabledCategories = UserPreferences.allCategories
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Disable All") {
                        preferences.enabledCategories = []
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text("Quick Actions")
                    .font(.headline)
            }

            // Core Grammar Checks
            Section {
                Toggle("Spelling", isOn: categoryBinding("Spelling"))
                    .help("When your brain doesn't know the right spelling")

                Toggle("Typos", isOn: categoryBinding("Typo"))
                    .help("When your brain knows the right spelling but your fingers made a mistake")

                Toggle("Grammar", isOn: categoryBinding("Grammar"))
                    .help("Detect grammatical errors and incorrect sentence structure")

                Toggle("Agreement", isOn: categoryBinding("Agreement"))
                    .help("Check subject-verb and pronoun agreement (e.g., 'he go' → 'he goes')")

                Toggle("Punctuation", isOn: categoryBinding("Punctuation"))
                    .help("Check punctuation usage, including hyphenation in compound adjectives")

                Toggle("Capitalization", isOn: categoryBinding("Capitalization"))
                    .help("Check proper capitalization of words and sentences")
            } header: {
                Text("Core Checks")
                    .font(.headline)
            }

            // Writing Style
            Section {
                Toggle("Style", isOn: categoryBinding("Style"))
                    .help("Check cases where multiple options are correct but one is preferred")

                Toggle("Readability", isOn: categoryBinding("Readability"))
                    .help("Improve text flow and make writing easier to understand")

                Toggle("Enhancement", isOn: categoryBinding("Enhancement"))
                    .help("Suggest improvements that enhance clarity or impact without fixing errors")

                Toggle("Redundancy", isOn: categoryBinding("Redundancy"))
                    .help("Detect cases where words duplicate meaning that's already expressed")

                Toggle("Repetition", isOn: categoryBinding("Repetition"))
                    .help("Detect repeated words or phrases in nearby sentences")
            } header: {
                Text("Style & Clarity")
                    .font(.headline)
            }

            // Word Usage
            Section {
                Toggle("Word Choice", isOn: categoryBinding("WordChoice"))
                    .help("Suggest choosing between different words or phrases in a given context")

                Toggle("Usage", isOn: categoryBinding("Usage"))
                    .help("Check conventional word usage and standard collocations")

                Toggle("Eggcorns", isOn: categoryBinding("Eggcorn"))
                    .help("Detect cases where a word or phrase is misused for a similar-sounding word or phrase (e.g., 'for all intensive purposes' → 'for all intents and purposes')")

                Toggle("Malapropisms", isOn: categoryBinding("Malapropism"))
                    .help("Detect cases where a word is mistakenly used for a similar-sounding word with a different meaning (e.g., 'escape goat' → 'scapegoat')")
            } header: {
                Text("Word Usage")
                    .font(.headline)
            }

            // Advanced
            Section {
                Toggle("Formatting", isOn: categoryBinding("Formatting"))
                    .help("Check text formatting issues such as spacing and special characters")

                Toggle("Boundary Errors", isOn: categoryBinding("BoundaryError"))
                    .help("Detect errors where words are joined or split at the wrong boundaries (e.g., 'each and everyone' → 'each and every one')")

                Toggle("Regionalism", isOn: categoryBinding("Regionalism"))
                    .help("Detect variations that are standard in some regions or dialects but not others")

                Toggle("Nonstandard", isOn: categoryBinding("Nonstandard"))
                    .help("Detect non-standard language usage that may be informal or colloquial")

                Toggle("Miscellaneous", isOn: categoryBinding("Miscellaneous"))
                    .help("Check for any other grammar issues that don't fit neatly into other categories")
            } header: {
                Text("Advanced")
                    .font(.headline)
            }

            Section {
                if preferences.ignoredRules.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        Text("No ignored rules")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(Array(preferences.ignoredRules).sorted(), id: \.self) { ruleId in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formatRuleName(ruleId))
                                    .font(.subheadline)
                                Text(ruleId)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Re-enable") {
                                preferences.enableRule(ruleId)
                            }
                            .buttonStyle(.borderless)
                            .help("Allow this rule to show grammar suggestions again")
                        }
                        .padding(.vertical, 4)
                    }

                    Divider()

                    HStack {
                        Spacer()
                        Button("Clear All") {
                            preferences.ignoredRules = []
                        }
                        .buttonStyle(.bordered)
                        .help("Re-enable all ignored grammar rules")
                    }
                }
            } header: {
                HStack {
                    Text("Ignored Rules")
                        .font(.headline)
                    Spacer()
                    if !preferences.ignoredRules.isEmpty {
                        Text("\(preferences.ignoredRules.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    /// Format rule ID from PascalCase/camelCase to readable text
    /// Examples: "SubjectVerbDisagreement" -> "Subject Verb Disagreement"
    ///           "Formatting::horizontal_ellipsis_must_have_3_dots" -> "Horizontal Ellipsis Must Have 3 Dots"
    private func formatRuleName(_ ruleId: String) -> String {
        // Handle new format with category prefix (e.g., "Formatting::rule_name")
        let components = ruleId.split(separator: ":", maxSplits: 1)
        var nameToFormat = components.count > 1 ? String(components[1]) : ruleId
        nameToFormat = nameToFormat.trimmingCharacters(in: CharacterSet(charactersIn: ":"))

        // Replace underscores with spaces and capitalize each word
        let words = nameToFormat.split(separator: "_")
        if !words.isEmpty {
            return words.map { word in
                word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }.joined(separator: " ")
        }

        // Fallback: Insert spaces before uppercase letters (for PascalCase/camelCase)
        var result = ""
        for (index, char) in nameToFormat.enumerated() {
            if index > 0 && char.isUppercase {
                result += " "
            }
            result.append(char)
        }
        return result.isEmpty ? ruleId : result
    }
}

// MARK: - Custom Vocabulary View

struct CustomVocabularyView: View {
    @ObservedObject private var vocabulary = CustomVocabulary.shared
    @ObservedObject private var preferences = UserPreferences.shared
    @State private var newWord = ""
    @State private var searchText = ""
    @State private var errorMessage: String?

    /// Filtered words based on search text
    private var filteredWords: [String] {
        let allWords = Array(vocabulary.words).sorted()
        if searchText.isEmpty {
            return allWords
        }
        return allWords.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Predefined Wordlists section
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Predefined Wordlists")
                            .font(.headline)
                    }

                    Text("Enable recognition of specialized vocabulary and informal language")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)

                    Divider()

                    // Internet Abbreviations
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Internet Abbreviations", isOn: $preferences.enableInternetAbbreviations)
                            .help("Accept common abbreviations like BTW, FYI, LOL, ASAP, etc.")

                        Text("3,200+ abbreviations (BTW, FYI, LOL, ASAP, AFAICT, etc.) • Case-insensitive")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }

                    Divider()

                    // Gen Z Slang
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Gen Z Slang", isOn: $preferences.enableGenZSlang)
                            .help("Accept modern slang words like ghosting, sus, slay, etc.")

                        Text("270+ modern terms (ghosting, sus, slay, vibe, etc.) • Case-insensitive")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }

                    Divider()

                    // IT Terminology
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("IT & Tech Terminology", isOn: $preferences.enableITTerminology)
                            .help("Accept technical terms like kubernetes, docker, API, JSON, localhost, etc.")

                        Text("10,000+ technical terms (kubernetes, docker, nginx, API, JSON, etc.) • Case-insensitive")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }

                    // Brand Names
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Brand & Company Names", isOn: $preferences.enableBrandNames)
                            .help("Accept brand names like Apple, Microsoft, Google, Amazon, etc.")

                        Text("2,400+ brand/company names (Fortune 500, Forbes 2000, global brands) • Case-insensitive")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }

                    // Person Names
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Person Names (First Names)", isOn: $preferences.enablePersonNames)
                            .help("Accept common first names like James, Maria, Chen, Fatima, etc.")

                        Text("100,000+ international first names (US SSA + worldwide sources) • Case-insensitive")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }

                    // Surnames
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Surnames (Last Names)", isOn: $preferences.enableLastNames)
                            .help("Accept common surnames like Smith, Garcia, Johnson, etc.")

                        Text("150,000+ surnames from US Census data • Case-insensitive")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }
                }
                .padding(.vertical, 4)
            }
            .padding()

            Divider()

            // Language Detection section
            HStack {
                Image(systemName: "globe")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Language Detection")
                    .font(.headline)
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Detect non-English words", isOn: $preferences.enableLanguageDetection)
                    .help("Automatically detect and ignore errors in non-English words")

                Text("Skip grammar checking for words detected in selected languages")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if preferences.enableLanguageDetection {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Languages to ignore:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)

                        // Language selection grid with fixed columns
                        LazyVGrid(columns: [
                            GridItem(.fixed(150), alignment: .leading),
                            GridItem(.fixed(150), alignment: .leading),
                            GridItem(.fixed(150), alignment: .leading),
                            GridItem(.fixed(150), alignment: .leading)
                        ], alignment: .leading, spacing: 6) {
                            ForEach(UserPreferences.availableLanguages.filter { $0 != "English" }.sorted(), id: \.self) { language in
                                Toggle(language, isOn: Binding(
                                    get: { preferences.excludedLanguages.contains(language) },
                                    set: { isSelected in
                                        if isSelected {
                                            preferences.excludedLanguages.insert(language)
                                        } else {
                                            preferences.excludedLanguages.remove(language)
                                        }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .font(.system(size: 11))
                            }
                        }
                        .padding(.leading, 20)

                        if !preferences.excludedLanguages.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                    .font(.caption2)
                                Text("Words detected as \(preferences.excludedLanguages.sorted().joined(separator: ", ")) will not be marked as errors")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal)

            Divider()

            // Custom Dictionary header
            HStack {
                Image(systemName: "plus.circle")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Custom Dictionary")
                    .font(.headline)
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)

            GroupBox {
                HStack(spacing: 12) {
                    TextField("Add word...", text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addWord()
                        }

                    Button("Add") {
                        addWord()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newWord.isEmpty)
                    .controlSize(.large)
                }
            }
            .padding()

            // Info section
            HStack {
                Label("\(vocabulary.words.count) of 1,000 words", systemImage: "list.number")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if vocabulary.words.count >= 1000 {
                    Label("Limit reached", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            // Error message
            if let errorMessage = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()

            // Search field - inline, modern style (only show if there are words)
            if !vocabulary.words.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.body)

                    TextField("Search words", text: $searchText)
                        .textFieldStyle(.plain)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }

            // Word list
            if vocabulary.words.isEmpty {
                ContentUnavailableView {
                    Label("No Custom Words", systemImage: "text.book.closed")
                } description: {
                    Text("Add words to ignore during grammar checking")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredWords.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredWords, id: \.self) { word in
                        HStack(spacing: 12) {
                            Text(word)
                                .font(.body)

                            Spacer()

                            Button {
                                removeWord(word)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Remove \"\(word)\" from dictionary")
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            // Clear all button - only show if there are words
            if !vocabulary.words.isEmpty {
                Divider()

                HStack {
                    Spacer()

                    Button(role: .destructive) {
                        clearAll()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding()
            }
        }
    }

    private func addWord() {
        guard !newWord.isEmpty else { return }

        do {
            try vocabulary.addWord(newWord)
            newWord = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeWord(_ word: String) {
        do {
            try vocabulary.removeWord(word)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearAll() {
        do {
            try vocabulary.clearAll()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

