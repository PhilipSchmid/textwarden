//
//  OnboardingView.swift
//  TextWarden
//
//  First-time setup and Accessibility permission onboarding
//

import SwiftUI
import ApplicationServices

/// Onboarding view guiding users through Accessibility permission setup
struct OnboardingView: View {
    @ObservedObject private var permissionManager = PermissionManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep: OnboardingStep = .welcome
    @State private var isPolling = false
    @State private var pollingTimer: Timer?
    @State private var elapsedTime: TimeInterval = 0
    @State private var showTimeoutWarning = false

    private let maxWaitTime: TimeInterval = 300 // 5 minutes

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)

                    Text("Welcome to TextWarden")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Your Privacy-First Grammar Checker")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 24)

                Divider()

                // Content based on current step
                Group {
                    switch currentStep {
                    case .welcome:
                        welcomeStep
                    case .permissionRequest:
                        permissionRequestStep
                    case .verification:
                        verificationStep
                    case .launchAtLogin:
                        launchAtLoginStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

                Divider()

                // Footer with action buttons
                HStack {
                    if showTimeoutWarning {
                        Button("Cancel") {
                            dismiss()
                        }
                        .keyboardShortcut(.escape)
                    }

                    Spacer()

                    // Show both buttons on launch at login step
                    if currentStep == .launchAtLogin {
                        Button("Not Now") {
                            handleSkipLaunchAtLogin()
                        }

                        Button("Enable Launch at Login") {
                            handleEnableLaunchAtLogin()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    } else {
                        actionButton
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(width: 500)
        }
        .frame(width: 550, height: 550)
        .onAppear {
            checkPermissionAndUpdateStep()
        }
        .onDisappear {
            stopPolling()
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Setup Required")
                .font(.headline)

            Text("TextWarden needs Accessibility permissions to check grammar across all your applications.")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "lock.shield", title: "Privacy First", description: "All text processing happens locally on your Mac")
                FeatureRow(icon: "bolt.fill", title: "Real-time Checking", description: "Grammar suggestions appear as you type")
                FeatureRow(icon: "app.badge.checkmark", title: "System-wide", description: "Works in TextEdit, Pages, Mail, and more")
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
                Text("2. Type: 'This are a test'")
                Text("3. Watch for TextWarden's grammar suggestions")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
    }

    private var launchAtLoginStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "power.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Launch at Login")
                        .font(.headline)

                    Text("Start TextWarden automatically")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            Text("Would you like TextWarden to start automatically when you log in?")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "checkmark.circle", title: "Always Protected", description: "Grammar checking available immediately")
                FeatureRow(icon: "bolt.fill", title: "No Manual Launch", description: "TextWarden runs in the background automatically")
                FeatureRow(icon: "minus.circle", title: "Easy to Disable", description: "Change this setting anytime in Preferences")
            }
            .padding(.vertical, 8)

            Text("You can change this preference later in Settings → General.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
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
    }

    private var actionButtonTitle: String {
        switch currentStep {
        case .welcome:
            return "Get Started"
        case .permissionRequest:
            return showTimeoutWarning ? "Retry" : "Open System Settings"
        case .verification:
            return "Continue"
        case .launchAtLogin:
            return "Finish Setup"
        }
    }

    // MARK: - Actions

    private func handleActionButton() {
        print("🎬 Onboarding: Button clicked at step: \(currentStep)")

        switch currentStep {
        case .welcome:
            print("🔐 Onboarding: Requesting Accessibility permission...")
            // Request permission (triggers system dialog)
            permissionManager.requestPermission()
            currentStep = .permissionRequest
            startPolling()

        case .permissionRequest:
            print("⚙️ Onboarding: Opening System Settings...")
            // Open System Settings for manual permission grant
            permissionManager.openSystemPreferences()
            startPolling()
            showTimeoutWarning = false
            elapsedTime = 0

        case .verification:
            print("✅ Onboarding: Verification complete, moving to launch at login...")
            currentStep = .launchAtLogin

        case .launchAtLogin:
            // Handled by separate buttons
            break
        }
    }

    private func handleEnableLaunchAtLogin() {
        print("✅ Onboarding: Enabling launch at login...")
        // TODO: Replace with LaunchAtLogin.isEnabled = true once LaunchAtLogin-Modern is added
        LoginItemManager.shared.setLaunchAtLogin(true)
        dismiss()
    }

    private func handleSkipLaunchAtLogin() {
        print("⏭️ Onboarding: Skipping launch at login...")
        dismiss()
    }

    private func checkPermissionAndUpdateStep() {
        if permissionManager.isPermissionGranted {
            currentStep = .verification
            stopPolling()
        }
    }

    private func startPolling() {
        guard !isPolling else {
            print("⏸️ Onboarding: Already polling, skipping")
            return
        }

        print("⏱️ Onboarding: Starting permission polling (every 1 second)")
        isPolling = true
        elapsedTime = 0

        // Poll every 1 second for permission changes
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedTime += 1.0

            // Check if permission was granted
            permissionManager.checkPermissionStatus()

            if permissionManager.isPermissionGranted {
                print("✅ Onboarding: Permission granted! Advancing to verification")
                currentStep = .verification
                stopPolling()
            } else if elapsedTime >= maxWaitTime {
                print("⏰ Onboarding: Timeout reached after \(elapsedTime) seconds")
                // Show timeout warning after 5 minutes
                showTimeoutWarning = true
                stopPolling()
            } else if Int(elapsedTime) % 10 == 0 {
                print("⏳ Onboarding: Still waiting... (\(Int(elapsedTime))s elapsed)")
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

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
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

            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Onboarding Steps

private enum OnboardingStep {
    case welcome
    case permissionRequest
    case verification
    case launchAtLogin
}

// MARK: - Preview

#Preview {
    OnboardingView()
}
