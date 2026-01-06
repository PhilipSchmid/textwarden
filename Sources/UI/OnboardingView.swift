//
//  OnboardingView.swift
//  TextWarden
//
//  First-time setup and Accessibility permission onboarding
//

import ApplicationServices
import LaunchAtLogin
import SwiftUI

#if canImport(FoundationModels)
    import FoundationModels
#endif

// MARK: - App URLs

private enum AppURLs {
    static let buyMeACoffee = URL(string: "https://buymeacoffee.com/textwarden")!
    static let appleIntelligenceSettings = URL(string: "x-apple.systempreferences:com.apple.preference.AppleIntelligence-Siri")!
    static let github = URL(string: "https://github.com/philipschmid/textwarden")!
    static let license = URL(string: "https://github.com/philipschmid/textwarden/blob/main/LICENSE")!
    static let issues = URL(string: "https://github.com/philipschmid/textwarden/issues")!
    static let discussions = URL(string: "https://github.com/philipschmid/textwarden/discussions")!
}

/// Onboarding view guiding users through Accessibility permission setup
struct OnboardingView: View {
    @ObservedObject private var permissionManager = PermissionManager.shared
    /// Access the singleton updater for auto-update settings
    @ObservedObject private var updaterViewModel = UpdaterViewModel.shared

    @State private var currentStep: OnboardingStep = .overview
    @State private var isPolling = false
    @State private var pollingTimer: Timer?
    @State private var elapsedTime: TimeInterval = 0
    @State private var showTimeoutWarning = false
    @State private var appleIntelligenceStatus: AppleIntelligenceStatus = .checking

    private let maxWaitTime: TimeInterval = TimingConstants.maxPermissionWait

    /// Steps that show the large header (logo and titles)
    private var isLargeHeaderStep: Bool {
        currentStep == .overview || currentStep == .sponsoring
    }

    /// Apple Intelligence availability status for onboarding
    private enum AppleIntelligenceStatus {
        case checking
        case available
        case notEnabled
        case notEligible
        case notSupported // macOS < 26
    }

    var body: some View {
        VStack(spacing: 0) {
            // Getting Started tutorial fills entire space with its own layout
            if currentStep == .gettingStarted {
                // Compact header for tutorial
                VStack(spacing: 8) {
                    Image("TextWardenLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .accessibilityHidden(true)

                    Text("Welcome to TextWarden")
                        .font(.title2)
                        .fontWeight(.bold)
                        .accessibilityAddTraits(.isHeader)

                    Text("Your Privacy-First Grammar Checker")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Welcome to TextWarden, Your Privacy-First Grammar Checker")

                Divider()
                    .padding(.top, 16)

                // Tutorial content fills remaining space
                gettingStartedStep
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Scrollable content area for all other steps
                ScrollView {
                    VStack(spacing: 16) {
                        // Header - larger on overview and sponsoring, compact on other steps
                        VStack(spacing: isLargeHeaderStep ? 12 : 8) {
                            Image("TextWardenLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: isLargeHeaderStep ? 100 : 80,
                                       height: isLargeHeaderStep ? 100 : 80)
                                .accessibilityHidden(true) // Decorative

                            Text("Welcome to TextWarden")
                                .font(isLargeHeaderStep ? .largeTitle : .title2)
                                .fontWeight(.bold)
                                .accessibilityAddTraits(.isHeader)

                            Text("Your Privacy-First Grammar Checker")
                                .font(isLargeHeaderStep ? .title3 : .subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, isLargeHeaderStep ? 12 : 8)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Welcome to TextWarden, Your Privacy-First Grammar Checker")

                        Divider()

                        // Content based on current step
                        Group {
                            switch currentStep {
                            case .overview:
                                overviewStep
                            case .welcome:
                                welcomeStep
                            case .permissionRequest:
                                permissionRequestStep
                            case .verification:
                                verificationStep
                            case .launchAtLogin:
                                launchAtLoginStep
                            case .writingEnhancements:
                                writingEnhancementsStep
                            case .languageDetection:
                                languageDetectionStep
                            case .websiteExclusion:
                                websiteExclusionStep
                            case .gettingStarted:
                                EmptyView() // Handled above
                            case .sponsoring:
                                sponsoringStep
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                    }
                    .frame(width: 580)
                }

                // Fixed footer with navigation buttons
                Divider()

                HStack {
                    // Back button (shown after overview, except during permission steps)
                    if canGoBack {
                        Button("Back") {
                            goBack()
                        }
                        .keyboardShortcut(.escape)
                    }

                    Spacer()

                    // Cancel button during timeout
                    if showTimeoutWarning {
                        Button("Cancel") {
                            closeOnboardingWindow()
                        }
                    }

                    // Continue/action button
                    navigationButton
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .frame(width: 640, height: 760)
        .onAppear {
            checkPermissionAndUpdateStep()
        }
        .onDisappear {
            stopPolling()
        }
    }

    // MARK: - Steps

    private var overviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Write with confidence, everywhere.")
                .font(.title2)
                .fontWeight(.semibold)

            Text("TextWarden is a privacy-first grammar checker that works across all your applications. Catch typos, fix grammar, and improve your writing style — all without your text ever leaving your Mac.")
                .font(.body)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "checkmark.circle.fill", title: "Grammar & Spelling", description: "Instant detection of typos, grammar errors, and punctuation issues")
                FeatureRow(icon: "sparkles", title: "AI Style Suggestions", description: "Apple Intelligence rewrites for clarity, tone, and readability")
                FeatureRow(icon: "pencil.and.outline", title: "AI Compose", description: "Generate text from natural language instructions")
                FeatureRow(icon: "textformat.size", title: "Readability Score", description: "Real-time Flesch Reading Ease score for your text")
                FeatureRow(icon: "lock.shield.fill", title: "100% Private", description: "Everything runs locally — your text never leaves your device")
                FeatureRow(icon: "macwindow.on.rectangle", title: "Works Everywhere", description: "Slack, Mail, Notes, browsers, and many more")
            }
            .padding(.vertical, 8)

            Text("Let's get you set up in just a few steps.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Setup Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("TextWarden needs Accessibility permissions to check grammar across all your applications.")
                .font(.title3)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(icon: "lock.shield.fill", title: "100% Local & Private", description: "All processing on your Mac — no cloud, no data leaves your device")
                FeatureRow(icon: "sparkles", title: "AI Style & Compose", description: "Apple Intelligence for style suggestions and text generation")
                FeatureRow(icon: "macwindow.on.rectangle", title: "Works in Every App", description: "Slack, Notion, Word, Mail, and many more")
            }
            .padding(.vertical, 8)

            Text("This permission allows TextWarden to read text from applications and provide grammar suggestions.")
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
    }

    @State private var showStaleEntryHelp = false

    private var permissionRequestStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Grant Accessibility Permission")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 14) {
                StepRow(number: 1, text: "Click 'Open System Settings' below")
                StepRow(number: 2, text: "Navigate to Privacy & Security → Accessibility")
                StepRow(number: 3, text: "Find 'TextWarden' in the list and enable it")
                StepRow(number: 4, text: "Return to TextWarden - we'll detect the change automatically")
            }
            .padding(.vertical, 8)

            if isPolling {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Waiting for permission...")
                            .font(.body)
                            .foregroundColor(.secondary)

                        if showTimeoutWarning {
                            Text("Taking longer than expected. Need help?")
                                .font(.body)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(.top, 8)
            }

            // Proactive help for users who already had TextWarden
            if !showTimeoutWarning, !showStaleEntryHelp {
                Button {
                    showStaleEntryHelp = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                        Text("Already enabled TextWarden before?")
                    }
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            if showTimeoutWarning || showStaleEntryHelp {
                VStack(alignment: .leading, spacing: 12) {
                    Text(showStaleEntryHelp && !showTimeoutWarning ? "Upgrading from a previous version?" : "Having trouble?")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("If you already see TextWarden enabled but it's not working, you likely have a **stale permission entry** from a previous installation.")
                        .font(.body)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("To fix this:")
                            .font(.body)
                            .fontWeight(.medium)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                Text("1.")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .frame(width: 20)
                                Text("In System Settings → Accessibility, **remove** TextWarden from the list (select it and click the minus button)")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            HStack(alignment: .top, spacing: 8) {
                                Text("2.")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .frame(width: 20)
                                Text("Click the **plus button** and add TextWarden from /Applications")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            HStack(alignment: .top, spacing: 8) {
                                Text("3.")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .frame(width: 20)
                                Text("Make sure the **new entry** is enabled")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Text("This happens when upgrading from a previous version with a different code signature.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
                .padding(.top, 12)
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    private var verificationStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Permission Granted!")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Grammar checking is now active")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("Why is this permission needed?")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Accessibility access allows TextWarden to read text from any application you're typing in - whether it's an email, a chat message, or a document.")
                    .font(.body)
                    .foregroundColor(.secondary)

                Text("TextWarden uses this to detect grammar and spelling errors in real-time, showing suggestions right where you're writing. All processing happens locally on your Mac - your text is never sent anywhere.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var launchAtLoginStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Startup & Updates")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Configure automatic behavior")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 20) {
                // Launch at Login
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Launch at Login")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("Start TextWarden automatically when you log in")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $enableLaunchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Divider()

                // Automatic Updates
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Automatic Update Checks")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("Check for new versions when the app launches")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $enableAutoUpdates)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Text("You can always check for updates manually in Settings → About.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }

    @State private var enableLaunchAtLogin: Bool = false
    @State private var enableAutoUpdates: Bool = true
    @State private var enableStyleChecking: Bool = true
    @State private var enableReadability: Bool = true

    private var writingEnhancementsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "text.badge.star")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Writing Enhancements")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Improve clarity, tone, and readability")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 20) {
                // Readability Analysis section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Readability Analysis")
                                .font(.body)
                                .fontWeight(.medium)
                            Text("Show a Flesch Reading Ease score and highlight complex sentences")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $enableReadability)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }

                Divider()

                // AI Style Suggestions section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("AI Style Suggestions")
                                    .font(.body)
                                    .fontWeight(.medium)
                                if appleIntelligenceStatus == .available {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                }
                            }
                            Text("Get AI-powered suggestions for clarity, tone, and conciseness")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if appleIntelligenceStatus == .available {
                            Toggle("", isOn: $enableStyleChecking)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }

                    // Status message for AI features
                    switch appleIntelligenceStatus {
                    case .checking:
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Checking availability...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    case .available:
                        if enableStyleChecking {
                            Text("Includes AI Compose for generating text from instructions. All processing happens on your device.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    case .notEnabled:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Requires Apple Intelligence to be enabled in System Settings.")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Button("Open Settings") {
                                NSWorkspace.shared.open(AppURLs.appleIntelligenceSettings)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    case .notEligible:
                        Text("Requires a Mac with Apple Silicon (M1 or later).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .notSupported:
                        Text("Requires macOS 26 (Tahoe) or later.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Text("You can change these settings anytime in Settings → Style.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            checkAppleIntelligenceStatus()
        }
    }

    private var languageDetectionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Language Settings")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Configure dialect and multilingual support")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                // Dialect Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("English Dialect")
                        .font(.body)
                        .fontWeight(.semibold)

                    Text("Choose your preferred spelling style (e.g., \"color\" vs \"colour\").")
                        .font(.body)
                        .foregroundColor(.secondary)

                    dialectSelectionPicker
                }

                Divider()

                // Multilingual Support
                VStack(alignment: .leading, spacing: 8) {
                    Text("Multilingual Writing")
                        .font(.body)
                        .fontWeight(.semibold)

                    Text("If you write in multiple languages, select them below. TextWarden detects when documents are primarily in another language and skips checking entirely, avoiding false positives on foreign text.")
                        .font(.body)
                        .foregroundColor(.secondary)

                    languageSelectionGrid
                }

                Text("You can change these settings anytime in Settings → Grammar.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }

    @State private var selectedDialect: String = UserPreferences.shared.selectedDialect

    private var dialectSelectionPicker: some View {
        HStack(spacing: 12) {
            ForEach(UserPreferences.availableDialects, id: \.self) { dialect in
                Button {
                    selectedDialect = dialect
                } label: {
                    HStack {
                        Image(systemName: selectedDialect == dialect ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedDialect == dialect ? .accentColor : .secondary)
                        Text(dialect)
                            .font(.body)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedDialect == dialect ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @State private var selectedLanguages: Set<String> = []

    private var languageSelectionGrid: some View {
        // All supported languages from UserPreferences.availableLanguages (excluding English)
        let supportedLanguages = UserPreferences.availableLanguages.filter { $0 != "English" }

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(supportedLanguages, id: \.self) { language in
                Button {
                    if selectedLanguages.contains(language) {
                        selectedLanguages.remove(language)
                    } else {
                        selectedLanguages.insert(language)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedLanguages.contains(language) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedLanguages.contains(language) ? .accentColor : .secondary)
                            .font(.subheadline)
                        Text(language)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selectedLanguages.contains(language) ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @State private var websiteToExclude: String = ""
    @State private var excludedWebsitesDuringOnboarding: [String] = []

    private var websiteExclusionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "globe.badge.chevron.backward")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Website Exclusions")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Disable grammar checking on specific sites")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("TextWarden works in web browsers too. If there are websites where you don't want grammar checking (e.g., code editors, dashboards), you can exclude them here.")
                    .font(.body)
                    .foregroundColor(.secondary)

                // Add website input
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("github.com or *.example.com", text: $websiteToExclude)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                            .onSubmit {
                                addWebsiteToExclusionList()
                            }

                        Button {
                            addWebsiteToExclusionList()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .disabled(websiteToExclude.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    Text("Examples: **github.com** (exact domain) or **\\*.example.com** (all subdomains)")
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                // List of added websites
                if !excludedWebsitesDuringOnboarding.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Websites to exclude:")
                            .font(.body)
                            .foregroundColor(.secondary)

                        ForEach(excludedWebsitesDuringOnboarding, id: \.self) { website in
                            HStack {
                                Image(systemName: "globe")
                                    .foregroundColor(.secondary)
                                    .font(.body)
                                Text(website)
                                    .font(.body)
                                Spacer()
                                Button {
                                    excludedWebsitesDuringOnboarding.removeAll { $0 == website }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                }

                Text("You can manage website exclusions anytime in Settings → Websites.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func addWebsiteToExclusionList() {
        let trimmed = websiteToExclude.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return }

        // Remove protocol prefixes if present
        var domain = trimmed
        if domain.hasPrefix("https://") {
            domain = String(domain.dropFirst(8))
        } else if domain.hasPrefix("http://") {
            domain = String(domain.dropFirst(7))
        }

        // Remove trailing slashes and paths (but preserve the domain)
        if let slashIndex = domain.firstIndex(of: "/") {
            domain = String(domain[..<slashIndex])
        }

        // Remove www. prefix (but keep wildcards like *.example.com)
        if domain.hasPrefix("www."), !domain.hasPrefix("*.") {
            domain = String(domain.dropFirst(4))
        }

        guard !domain.isEmpty, !excludedWebsitesDuringOnboarding.contains(domain) else {
            websiteToExclude = ""
            return
        }

        excludedWebsitesDuringOnboarding.append(domain)
        websiteToExclude = ""
    }

    // MARK: - Getting Started Tutorial

    private var gettingStartedStep: some View {
        GettingStartedTutorialView(
            onSkip: {
                currentStep = .sponsoring
            },
            onComplete: {
                currentStep = .sponsoring
            },
            onBackToOnboarding: {
                currentStep = .websiteExclusion
            }
        )
    }

    private var sponsoringStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Ready to go section
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text("You're All Set!")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("TextWarden is ready to check your writing")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            // Support section
            VStack(alignment: .leading, spacing: 12) {
                Text("Support TextWarden")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("TextWarden is a free, open-source project built during evenings and weekends. Your support helps fund new features, bug fixes, and keeps TextWarden ad-free and privacy-focused.")
                    .font(.body)
                    .foregroundColor(.secondary)

                HStack {
                    Spacer()
                    Link(destination: AppURLs.buyMeACoffee) {
                        Image("BuyMeACoffeeButton")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 44)
                    }
                    .accessibilityLabel("Buy me a coffee")
                    .accessibilityHint("Opens a link to support TextWarden development")
                    Spacer()
                }
            }

            // Links section
            HStack(spacing: 16) {
                Spacer()
                Link(destination: AppURLs.github) {
                    Label("GitHub", systemImage: "arrow.up.forward")
                        .font(.subheadline)
                }
                Link(destination: AppURLs.license) {
                    Label("License", systemImage: "arrow.up.forward")
                        .font(.subheadline)
                }
                Link(destination: AppURLs.issues) {
                    Label("Report Issue", systemImage: "arrow.up.forward")
                        .font(.subheadline)
                }
                Link(destination: AppURLs.discussions) {
                    Label("Feature Requests", systemImage: "arrow.up.forward")
                        .font(.subheadline)
                }
                Spacer()
            }
            .foregroundColor(.accentColor)
        }
    }

    /// Close the onboarding window properly
    private func closeOnboardingWindow() {
        Logger.info("Finishing onboarding setup", category: Logger.ui)

        // Find and close this window
        if let window = NSApp.windows.first(where: { $0.title == "Welcome to TextWarden" }) {
            window.close()
        }

        // Return to accessory mode after window closes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.setActivationPolicy(.accessory)
            Logger.info("Returned to menu bar only mode", category: Logger.lifecycle)

            // Show menu bar tooltip to help users find the icon (only shown once)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MenuBarController.shared?.showMenuBarTooltip()
            }
        }
    }

    // MARK: - Navigation

    private var canGoBack: Bool {
        switch currentStep {
        case .overview:
            false // First step
        case .welcome, .permissionRequest, .verification:
            false // During permission flow, don't allow back
        case .launchAtLogin:
            true // Can go back to verification
        case .writingEnhancements:
            true
        case .languageDetection:
            true
        case .websiteExclusion:
            true
        case .gettingStarted:
            false // Tutorial has its own navigation
        case .sponsoring:
            true
        }
    }

    private func goBack() {
        switch currentStep {
        case .overview, .welcome, .permissionRequest, .verification, .gettingStarted:
            break // Can't go back from these
        case .launchAtLogin:
            currentStep = .verification
        case .writingEnhancements:
            currentStep = .launchAtLogin
        case .languageDetection:
            currentStep = .writingEnhancements
        case .websiteExclusion:
            currentStep = .languageDetection
        case .sponsoring:
            currentStep = .gettingStarted
        }
    }

    private var navigationButton: some View {
        actionButton
    }

    private var actionButton: some View {
        Button(action: handleActionButton) {
            Text(actionButtonTitle)
                .frame(minWidth: 150)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel(actionButtonTitle)
        .accessibilityHint(actionButtonHint)
    }

    private var actionButtonHint: String {
        switch currentStep {
        case .overview:
            "Double tap to begin the setup process"
        case .welcome:
            "Double tap to continue with permission setup"
        case .permissionRequest:
            "Double tap to open System Settings and grant accessibility permission"
        case .verification:
            "Double tap to continue to the next step"
        case .launchAtLogin:
            "Double tap to continue to writing enhancements setup"
        case .writingEnhancements:
            "Double tap to continue to language detection setup"
        case .languageDetection:
            "Double tap to continue to website exclusions"
        case .websiteExclusion:
            "Double tap to view the quick start guide"
        case .gettingStarted:
            "" // Tutorial has its own navigation
        case .sponsoring:
            "Double tap to complete setup"
        }
    }

    private var actionButtonTitle: String {
        switch currentStep {
        case .overview:
            "Get Started"
        case .welcome:
            "Continue"
        case .permissionRequest:
            showTimeoutWarning ? "Retry" : "Open System Settings"
        case .verification:
            "Continue"
        case .launchAtLogin:
            "Continue"
        case .writingEnhancements:
            "Continue"
        case .languageDetection:
            "Continue"
        case .websiteExclusion:
            "Continue"
        case .gettingStarted:
            "" // Tutorial has its own navigation
        case .sponsoring:
            "Finish Setup"
        }
    }

    // MARK: - Actions

    private func handleActionButton() {
        Logger.debug("Onboarding: Button clicked at step: \(currentStep)", category: Logger.ui)

        switch currentStep {
        case .overview:
            // If permissions are already granted, skip to verification
            if permissionManager.isPermissionGranted {
                Logger.info("Onboarding: Permissions already granted, skipping to verification...", category: Logger.ui)
                currentStep = .verification
            } else {
                Logger.info("Onboarding: Moving from overview to permission setup...", category: Logger.ui)
                currentStep = .welcome
            }

        case .welcome:
            Logger.info("Onboarding: Requesting Accessibility permission...", category: Logger.permissions)
            // Request permission (triggers system dialog)
            permissionManager.requestPermission()
            currentStep = .permissionRequest
            startPolling()

        case .permissionRequest:
            Logger.info("Onboarding: Opening System Settings...", category: Logger.permissions)
            // Open System Settings for manual permission grant
            permissionManager.openSystemPreferences()
            startPolling()
            showTimeoutWarning = false
            elapsedTime = 0

        case .verification:
            Logger.info("Onboarding: Verification complete, moving to launch at login...", category: Logger.ui)
            currentStep = .launchAtLogin

        case .launchAtLogin:
            // Save launch at login setting
            LaunchAtLogin.isEnabled = enableLaunchAtLogin
            Logger.info("Onboarding: Launch at login: \(enableLaunchAtLogin)", category: Logger.general)

            // Save auto-update setting
            updaterViewModel.automaticallyChecksForUpdates = enableAutoUpdates
            Logger.info("Onboarding: Auto update checks: \(enableAutoUpdates)", category: Logger.general)

            currentStep = .writingEnhancements

        case .writingEnhancements:
            // Save writing enhancement settings
            UserPreferences.shared.enableStyleChecking = enableStyleChecking
            UserPreferences.shared.readabilityEnabled = enableReadability
            Logger.info("Onboarding: Style checking: \(enableStyleChecking), Readability: \(enableReadability)", category: Logger.general)
            currentStep = .languageDetection

        case .languageDetection:
            // Save dialect selection
            UserPreferences.shared.selectedDialect = selectedDialect
            Logger.info("Onboarding: Selected dialect: \(selectedDialect)", category: Logger.general)

            // Save language detection settings if any languages selected
            // Store display names (e.g., "German") directly - conversion to lowercase codes
            // happens in AnalysisCoordinator when passing to Rust
            if !selectedLanguages.isEmpty {
                UserPreferences.shared.enableLanguageDetection = true
                UserPreferences.shared.excludedLanguages = selectedLanguages
                Logger.info("Onboarding: Enabled language detection for: \(selectedLanguages)", category: Logger.general)
            }
            currentStep = .websiteExclusion

        case .websiteExclusion:
            // Save website exclusions
            for website in excludedWebsitesDuringOnboarding {
                UserPreferences.shared.disableWebsite(website)
            }
            if !excludedWebsitesDuringOnboarding.isEmpty {
                Logger.info("Onboarding: Excluded websites: \(excludedWebsitesDuringOnboarding)", category: Logger.general)
            }
            // Show getting started guide
            currentStep = .gettingStarted

        case .gettingStarted:
            // Tutorial has its own navigation, this shouldn't be called
            currentStep = .sponsoring

        case .sponsoring:
            // Mark onboarding as completed
            UserPreferences.shared.hasCompletedOnboarding = true
            // Close the onboarding window and return to menu bar mode
            closeOnboardingWindow()
            Logger.info("Onboarding: Complete!", category: Logger.general)
        }
    }

    private func checkAppleIntelligenceStatus() {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                let model = SystemLanguageModel.default
                switch model.availability {
                case .available:
                    appleIntelligenceStatus = .available
                    Logger.debug("Onboarding: Apple Intelligence available", category: Logger.ui)
                case let .unavailable(reason):
                    switch reason {
                    case .appleIntelligenceNotEnabled:
                        appleIntelligenceStatus = .notEnabled
                        Logger.debug("Onboarding: Apple Intelligence not enabled", category: Logger.ui)
                    case .deviceNotEligible:
                        appleIntelligenceStatus = .notEligible
                        Logger.debug("Onboarding: Device not eligible for Apple Intelligence", category: Logger.ui)
                    case .modelNotReady:
                        appleIntelligenceStatus = .notEnabled
                        Logger.debug("Onboarding: Apple Intelligence model not ready", category: Logger.ui)
                    @unknown default:
                        appleIntelligenceStatus = .notEnabled
                        Logger.debug("Onboarding: Apple Intelligence unknown status", category: Logger.ui)
                    }
                }
            } else {
                appleIntelligenceStatus = .notSupported
                Logger.debug("Onboarding: macOS version does not support Apple Intelligence", category: Logger.ui)
            }
        #else
            appleIntelligenceStatus = .notSupported
            Logger.debug("Onboarding: FoundationModels not available", category: Logger.ui)
        #endif
    }

    private func checkPermissionAndUpdateStep() {
        // Always show overview first, even if permissions are already granted
        // The user can proceed through the steps normally
        // Only skip to verification if we're already past the overview
        if permissionManager.isPermissionGranted, currentStep != .overview {
            currentStep = .verification
            stopPolling()
        }
    }

    private func startPolling() {
        guard !isPolling else {
            Logger.debug("Onboarding: Already polling, skipping", category: Logger.permissions)
            return
        }

        Logger.debug("Onboarding: Starting permission polling (every 1 second)", category: Logger.permissions)
        isPolling = true
        elapsedTime = 0

        // Poll for permission changes
        pollingTimer = Timer.scheduledTimer(withTimeInterval: TimingConstants.permissionPolling, repeats: true) { _ in
            Task { @MainActor in
                elapsedTime += TimingConstants.permissionPolling

                // Check if permission was granted
                permissionManager.checkPermissionStatus()

                if permissionManager.isPermissionGranted {
                    Logger.info("Onboarding: Permission granted! Advancing to verification", category: Logger.permissions)
                    currentStep = .verification
                    stopPolling()
                } else if elapsedTime >= maxWaitTime {
                    Logger.warning("Onboarding: Timeout reached after \(elapsedTime) seconds", category: Logger.permissions)
                    showTimeoutWarning = true
                    stopPolling()
                } else if Int(elapsedTime) % 10 == 0 {
                    Logger.debug("Onboarding: Still waiting... (\(Int(elapsedTime))s elapsed)", category: Logger.permissions)
                }
            }
        }
    }

    private func stopPolling() {
        isPolling = false
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
}

// MARK: - Supporting Views

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true) // Icon is decorative

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }
}

private struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .accessibilityHidden(true)

            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(Color.accentColor)
                .clipShape(Circle())
                .accessibilityHidden(true) // Number badge is visual only

            Text(text)
                .font(.body)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(text)")
    }
}

// MARK: - Onboarding Steps

private enum OnboardingStep {
    case overview
    case welcome
    case permissionRequest
    case verification
    case launchAtLogin
    case writingEnhancements // Renamed from appleIntelligence - covers readability + style
    case languageDetection
    case websiteExclusion
    case gettingStarted
    case sponsoring
}

// MARK: - Preview

#Preview {
    OnboardingView()
}
