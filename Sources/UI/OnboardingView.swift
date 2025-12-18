//
//  OnboardingView.swift
//  TextWarden
//
//  First-time setup and Accessibility permission onboarding
//

import SwiftUI
import ApplicationServices
import LaunchAtLogin

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - App URLs

private enum AppURLs {
    static let buyMeACoffee = URL(string: "https://buymeacoffee.com/textwarden")!
    static let appleIntelligenceSettings = URL(string: "x-apple.systempreferences:com.apple.preference.AppleIntelligence-Siri")!
}

/// Onboarding view guiding users through Accessibility permission setup
struct OnboardingView: View {
    @ObservedObject private var permissionManager = PermissionManager.shared
    /// Access the updater from AppDelegate for auto-update settings
    @ObservedObject private var updaterViewModel: UpdaterViewModel

    @State private var currentStep: OnboardingStep = .overview
    @State private var isPolling = false
    @State private var pollingTimer: Timer?
    @State private var elapsedTime: TimeInterval = 0
    @State private var showTimeoutWarning = false
    @State private var appleIntelligenceStatus: AppleIntelligenceStatus = .checking

    private let maxWaitTime: TimeInterval = TimingConstants.maxPermissionWait

    init() {
        // Get updater from AppDelegate, with fallback
        if let appDelegate = NSApp.delegate as? AppDelegate {
            _updaterViewModel = ObservedObject(wrappedValue: appDelegate.updaterViewModel)
        } else {
            // Fallback - create temporary instance (shouldn't happen in practice)
            _updaterViewModel = ObservedObject(wrappedValue: UpdaterViewModel())
        }
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
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)
                        .accessibilityHidden(true) // Decorative

                    Text("Welcome to TextWarden")
                        .font(.title)
                        .fontWeight(.bold)
                        .accessibilityAddTraits(.isHeader)

                    Text("Your Privacy-First Grammar Checker")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 24)
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
                    case .appleIntelligence:
                        appleIntelligenceStep
                    case .languageDetection:
                        languageDetectionStep
                    case .websiteExclusion:
                        websiteExclusionStep
                    case .sponsoring:
                        sponsoringStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

                Divider()

                // Footer with action buttons
                HStack {
                    if showTimeoutWarning {
                        Button("Cancel") {
                            // Close the onboarding window and return to menu bar mode
                            closeOnboardingWindow()
                        }
                        .keyboardShortcut(.escape)
                        .accessibilityLabel("Cancel setup")
                        .accessibilityHint("Double tap to cancel and close the setup window")
                    }

                    Spacer()

                    if currentStep == .launchAtLogin {
                        startupAndUpdatesButtons
                    } else if currentStep == .appleIntelligence {
                        appleIntelligenceButtons
                    } else if currentStep == .languageDetection {
                        languageDetectionButtons
                    } else if currentStep == .websiteExclusion {
                        websiteExclusionButtons
                    } else if currentStep == .sponsoring {
                        sponsoringButtons
                    } else {
                        actionButton
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(width: 530)
        }
        .frame(width: 580, height: 650)
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
                .font(.title3)
                .fontWeight(.semibold)

            Text("TextWarden is a privacy-first grammar checker that works across all your applications. Catch typos, fix grammar, and improve your writing style — all without your text ever leaving your Mac.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(icon: "checkmark.circle.fill", title: "Grammar & Spelling", description: "Instant detection of typos, grammar errors, and punctuation issues")
                FeatureRow(icon: "sparkles", title: "AI Style Suggestions", description: "Apple Intelligence rewrites for clarity, tone, and readability")
                FeatureRow(icon: "lock.shield.fill", title: "100% Private", description: "Everything runs locally — your text never leaves your device")
                FeatureRow(icon: "macwindow.on.rectangle", title: "Works Everywhere", description: "Slack, Mail, Notes, browsers, and thousands more apps")
            }
            .padding(.vertical, 8)

            Text("Let's get you set up in just a few steps.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Setup Required")
                .font(.headline)

            Text("TextWarden needs Accessibility permissions to check grammar across all your applications.")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "lock.shield.fill", title: "100% Local & Private", description: "All processing on your Mac — no cloud, no data leaves your device")
                FeatureRow(icon: "sparkles", title: "AI-Powered Style Suggestions", description: "Apple Intelligence rewrites for clarity and tone")
                FeatureRow(icon: "macwindow.on.rectangle", title: "Works in Every App", description: "Slack, Notion, VS Code, Mail, and thousands more")
            }
            .padding(.vertical, 8)

            Text("This permission allows TextWarden to read text from applications and provide grammar suggestions.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
    }

    private var permissionRequestStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Grant Accessibility Permission")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                StepRow(number: 1, text: "Click 'Open System Settings' below")
                StepRow(number: 2, text: "Navigate to Privacy & Security → Accessibility")
                StepRow(number: 3, text: "Find 'TextWarden' in the list and enable it")
                StepRow(number: 4, text: "Return to TextWarden - we'll detect the change automatically")
            }
            .padding(.vertical, 8)

            if isPolling {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.7)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Waiting for permission...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if showTimeoutWarning {
                            Text("Taking longer than expected. Need help?")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(.top, 8)
            }

            if showTimeoutWarning {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Having trouble?")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("• Make sure you're enabling 'TextWarden' in the Accessibility list\n• You may need to unlock the settings pane first\n• Click 'Open System Settings' again to retry")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 12)
            }
        }
    }

    private var verificationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Permission Granted!")
                        .font(.headline)

                    Text("Grammar checking is now active")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Try it out:")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("1. Open TextEdit or any text application")
                Text("2. Type something with a typo, e.g. 'teh' or 'definately'")
                Text("3. Watch for TextWarden's underline and suggestions")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
    }

    private var launchAtLoginStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Startup & Updates")
                        .font(.headline)

                    Text("Configure automatic behavior")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                // Launch at Login
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $enableLaunchAtLogin) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch at Login")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Start TextWarden automatically when you log in")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }

                Divider()

                // Automatic Updates
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $enableAutoUpdates) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatic Update Checks")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Check for new versions periodically")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }

                Text("You can change these settings anytime in Settings → General.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @State private var enableLaunchAtLogin: Bool = false
    @State private var enableAutoUpdates: Bool = true
    @State private var enableAutoStyleChecking: Bool = false

    private var appleIntelligenceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: appleIntelligenceStatusIcon)
                    .font(.system(size: 40))
                    .foregroundColor(appleIntelligenceStatusColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Style Checking")
                        .font(.headline)

                    Text(appleIntelligenceStatusSubtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            appleIntelligenceContent
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
                        .font(.headline)

                    Text("Configure dialect and multilingual support")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                // Dialect Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("English Dialect")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("Choose your preferred spelling style (e.g., \"color\" vs \"colour\").")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    dialectSelectionPicker
                }

                Divider()

                // Multilingual Support
                VStack(alignment: .leading, spacing: 8) {
                    Text("Multilingual Writing")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("If you mix other languages with English, select them below to avoid false positives on foreign phrases like \"Freundliche Grüsse\" or \"Merci beaucoup\".")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    languageSelectionGrid
                }

                Text("You can change these settings anytime in Settings → Grammar.")
                    .font(.caption)
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
                            .font(.subheadline)
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

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(supportedLanguages, id: \.self) { language in
                Button {
                    if selectedLanguages.contains(language) {
                        selectedLanguages.remove(language)
                    } else {
                        selectedLanguages.insert(language)
                    }
                } label: {
                    HStack {
                        Image(systemName: selectedLanguages.contains(language) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedLanguages.contains(language) ? .accentColor : .secondary)
                        Text(language)
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedLanguages.contains(language) ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1))
                    .cornerRadius(8)
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
                        .font(.headline)

                    Text("Disable grammar checking on specific sites")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("TextWarden works in web browsers too. If there are websites where you don't want grammar checking (e.g., code editors, dashboards), you can exclude them here.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Add website input
                HStack {
                    TextField("Enter domain (e.g., github.com)", text: $websiteToExclude)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addWebsiteToExclusionList()
                        }

                    Button {
                        addWebsiteToExclusionList()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(websiteToExclude.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                // List of added websites
                if !excludedWebsitesDuringOnboarding.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Websites to exclude:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(excludedWebsitesDuringOnboarding, id: \.self) { website in
                            HStack {
                                Image(systemName: "globe")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                Text(website)
                                    .font(.subheadline)
                                Spacer()
                                Button {
                                    excludedWebsitesDuringOnboarding.removeAll { $0 == website }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                }

                Text("You can manage website exclusions anytime in Settings → Websites.")
                    .font(.caption)
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

        // Remove trailing slashes and paths
        if let slashIndex = domain.firstIndex(of: "/") {
            domain = String(domain[..<slashIndex])
        }

        // Remove www. prefix
        if domain.hasPrefix("www.") {
            domain = String(domain.dropFirst(4))
        }

        guard !domain.isEmpty, !excludedWebsitesDuringOnboarding.contains(domain) else {
            websiteToExclude = ""
            return
        }

        excludedWebsitesDuringOnboarding.append(domain)
        websiteToExclude = ""
    }

    private var sponsoringStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.pink)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Support TextWarden")
                        .font(.headline)

                    Text("Help keep development going")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("TextWarden is a side project built during evenings and weekends. If you find it useful, consider supporting its development.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "sparkles", title: "New Features", description: "Support helps prioritize new capabilities")
                    FeatureRow(icon: "ladybug", title: "Bug Fixes", description: "Keep TextWarden running smoothly")
                    FeatureRow(icon: "heart", title: "Independent Development", description: "No ads, no tracking, just a useful tool")
                }
                .padding(.vertical, 8)

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
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var appleIntelligenceContent: some View {
        switch appleIntelligenceStatus {
        case .checking:
            HStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Checking Apple Intelligence availability...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

        case .available:
            VStack(alignment: .leading, spacing: 12) {
                Text("Style checking uses Apple Intelligence to suggest rewrites that improve clarity, tone, and readability of your writing - all processed locally on your Mac.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "sparkles", title: "Style Suggestions", description: "AI rewrites for better clarity and flow")
                    FeatureRow(icon: "text.quote", title: "Multiple Styles", description: "Concise, Formal, Casual, Business")
                    FeatureRow(icon: "lock.shield", title: "100% On-Device", description: "Private - nothing leaves your Mac")
                }
                .padding(.vertical, 8)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $enableAutoStyleChecking) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatic Style Checking")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Analyze your writing automatically as you type")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    Text("When disabled, use ⌘⌃S to check style manually.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("You can change these settings anytime in Settings → Style.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }

        case .notEnabled:
            VStack(alignment: .leading, spacing: 12) {
                Text("Apple Intelligence is not enabled on your Mac. Enable it to unlock AI-powered style suggestions.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    StepRow(number: 1, text: "Click 'Open Settings' below")
                    StepRow(number: 2, text: "Enable Apple Intelligence")
                    StepRow(number: 3, text: "Wait for the model to download")
                }
                .padding(.vertical, 8)

                Text("This is optional - grammar checking works without it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

        case .notEligible:
            VStack(alignment: .leading, spacing: 12) {
                Text("Apple Intelligence requires a Mac with Apple Silicon (M1 or later). Style suggestions are not available on this Mac.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Grammar and spelling checking work normally without this feature.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }

        case .notSupported:
            VStack(alignment: .leading, spacing: 12) {
                Text("AI style suggestions require macOS 26 (Tahoe) or later. Your current macOS version does not support this feature.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Grammar and spelling checking work normally without this feature.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    private var appleIntelligenceStatusIcon: String {
        switch appleIntelligenceStatus {
        case .checking: return "hourglass"
        case .available: return "checkmark.circle.fill"
        case .notEnabled: return "exclamationmark.circle.fill"
        case .notEligible, .notSupported: return "xmark.circle.fill"
        }
    }

    private var appleIntelligenceStatusColor: Color {
        switch appleIntelligenceStatus {
        case .checking: return .secondary
        case .available: return .green
        case .notEnabled: return .orange
        case .notEligible, .notSupported: return .secondary
        }
    }

    private var appleIntelligenceStatusSubtitle: String {
        switch appleIntelligenceStatus {
        case .checking: return "Checking availability..."
        case .available: return "Available on your Mac"
        case .notEnabled: return "Requires setup"
        case .notEligible: return "Not available on this Mac"
        case .notSupported: return "Requires macOS 26+"
        }
    }

    @ViewBuilder
    private var appleIntelligenceButtons: some View {
        switch appleIntelligenceStatus {
        case .checking:
            Button("Please wait...") {}
                .disabled(true)

        case .available:
            Button("Skip") {
                // Explicitly disable style checking when skipped
                UserPreferences.shared.enableStyleChecking = false
                UserPreferences.shared.autoStyleChecking = false
                Logger.info("Onboarding: Style checking disabled", category: Logger.general)
                currentStep = .languageDetection
            }

            Button("Enable Style Checking") {
                // Enable style checking in preferences
                UserPreferences.shared.enableStyleChecking = true
                UserPreferences.shared.autoStyleChecking = enableAutoStyleChecking
                Logger.info("Onboarding: Style checking enabled, auto=\(enableAutoStyleChecking)", category: Logger.general)
                currentStep = .languageDetection
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

        case .notEligible, .notSupported:
            Button("Continue") {
                currentStep = .languageDetection
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

        case .notEnabled:
            Button("Skip") {
                // Explicitly disable style checking when skipped
                UserPreferences.shared.enableStyleChecking = false
                currentStep = .languageDetection
            }

            Button("Open Settings") {
                NSWorkspace.shared.open(AppURLs.appleIntelligenceSettings)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var startupAndUpdatesButtons: some View {
        Button("Continue") {
            // Save launch at login setting
            LaunchAtLogin.isEnabled = enableLaunchAtLogin
            Logger.info("Onboarding: Launch at login: \(enableLaunchAtLogin)", category: Logger.general)

            // Save auto-update setting
            updaterViewModel.automaticallyChecksForUpdates = enableAutoUpdates
            Logger.info("Onboarding: Auto update checks: \(enableAutoUpdates)", category: Logger.general)

            currentStep = .appleIntelligence
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
    }

    private var languageDetectionButtons: some View {
        Button("Continue") {
            // Save dialect selection
            UserPreferences.shared.selectedDialect = selectedDialect
            Logger.info("Onboarding: Selected dialect: \(selectedDialect)", category: Logger.general)

            // Save language detection settings if any languages selected
            if !selectedLanguages.isEmpty {
                UserPreferences.shared.enableLanguageDetection = true
                let languageCodes = selectedLanguages.map { UserPreferences.languageCode(for: $0) }
                UserPreferences.shared.excludedLanguages = Set(languageCodes)
                Logger.info("Onboarding: Enabled language detection for: \(selectedLanguages)", category: Logger.general)
            }
            currentStep = .websiteExclusion
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
    }

    private var websiteExclusionButtons: some View {
        HStack {
            Button("Skip") {
                currentStep = .sponsoring
            }

            Button("Continue") {
                // Save website exclusions
                for website in excludedWebsitesDuringOnboarding {
                    UserPreferences.shared.disableWebsite(website)
                }
                if !excludedWebsitesDuringOnboarding.isEmpty {
                    Logger.info("Onboarding: Excluded websites: \(excludedWebsitesDuringOnboarding)", category: Logger.general)
                }
                currentStep = .sponsoring
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var sponsoringButtons: some View {
        Button("Finish Setup") {
            // Mark onboarding as completed
            UserPreferences.shared.hasCompletedOnboarding = true
            // Close the onboarding window and return to menu bar mode
            closeOnboardingWindow()
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
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
        }
    }

    // MARK: - Action Button

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
            return "Double tap to begin the setup process"
        case .welcome:
            return "Double tap to continue with permission setup"
        case .permissionRequest:
            return "Double tap to open System Settings and grant accessibility permission"
        case .verification:
            return "Double tap to continue to the next step"
        case .launchAtLogin:
            return "Double tap to continue to AI style checking setup"
        case .appleIntelligence:
            return "Double tap to continue to language detection setup"
        case .languageDetection:
            return "Double tap to continue to website exclusions"
        case .websiteExclusion:
            return "Double tap to continue"
        case .sponsoring:
            return "Double tap to complete setup"
        }
    }

    private var actionButtonTitle: String {
        switch currentStep {
        case .overview:
            return "Get Started"
        case .welcome:
            return "Continue"
        case .permissionRequest:
            return showTimeoutWarning ? "Retry" : "Open System Settings"
        case .verification:
            return "Continue"
        case .launchAtLogin:
            return "Continue"
        case .appleIntelligence:
            return "Continue"
        case .languageDetection:
            return "Continue"
        case .websiteExclusion:
            return "Continue"
        case .sponsoring:
            return "Finish Setup"
        }
    }

    // MARK: - Actions

    private func handleActionButton() {
        Logger.debug("Onboarding: Button clicked at step: \(currentStep)", category: Logger.ui)

        switch currentStep {
        case .overview:
            Logger.info("Onboarding: Moving from overview to permission setup...", category: Logger.ui)
            currentStep = .welcome

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
            // Handled by separate buttons
            break

        case .appleIntelligence:
            // Handled by separate buttons
            break

        case .languageDetection:
            // Handled by separate buttons
            break

        case .websiteExclusion:
            // Handled by separate buttons
            break

        case .sponsoring:
            // Handled by separate buttons
            break
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
            case .unavailable(let reason):
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
        if permissionManager.isPermissionGranted {
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
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true) // Icon is decorative

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
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
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor)
                .clipShape(Circle())
                .accessibilityHidden(true) // Number badge is visual only

            Text(text)
                .font(.subheadline)
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
    case appleIntelligence
    case languageDetection
    case websiteExclusion
    case sponsoring
}

// MARK: - Preview

#Preview {
    OnboardingView()
}
