//
//  AboutView.swift
//  TextWarden
//
//  About view showing app information and credits.
//

import SwiftUI

// MARK: - App URLs

/// Static URLs for external links - centralized for easy review
/// Force unwraps are safe here as these are hardcoded, syntactically valid URLs
private enum AppURLs {
    static let github = URL(string: "https://github.com/philipschmid/textwarden")!
    static let license = URL(string: "https://github.com/philipschmid/textwarden/blob/main/LICENSE")!
    static let issues = URL(string: "https://github.com/philipschmid/textwarden/issues")!
    static let buyMeACoffee = URL(string: "https://buymeacoffee.com/textwarden")!
}

// MARK: - About View

struct AboutView: View {
    /// Access the singleton updater - use ObservedObject for proper updates
    @ObservedObject private var updaterViewModel = UpdaterViewModel.shared

    /// State for copy feedback
    @State private var showCopiedFeedback = false

    /// Copy version to clipboard
    private func copyVersionToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(BuildInfo.appVersion, forType: .string)
        showCopiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.feedbackDisplayDuration) {
            showCopiedFeedback = false
        }
    }

    var body: some View {
        Form {
            // MARK: - About TextWarden

            Section {
                HStack(spacing: 16) {
                    Image("TextWardenLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("TextWarden")
                            .font(.system(size: 26, weight: .bold))
                        Text("Grammar and Style Checking for macOS")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 2)
            }

            // Version & Updates subsection
            Section {
                // Version with copy button
                HStack {
                    Text("Version")
                    Spacer()
                    Button(action: copyVersionToClipboard) {
                        HStack(spacing: 6) {
                            Text(BuildInfo.appVersion)
                                .foregroundColor(.secondary)
                            Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(showCopiedFeedback ? .green : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Copy version to clipboard")
                }

                Toggle("Automatically check for updates on launch", isOn: $updaterViewModel.automaticallyChecksForUpdates)

                Toggle("Include experimental releases", isOn: $updaterViewModel.includeExperimentalUpdates)
                    .help("Opt-in to receive experimental pre-release versions with new features")

                HStack(spacing: 12) {
                    Button {
                        updaterViewModel.checkForUpdates()
                    } label: {
                        HStack(spacing: 6) {
                            if updaterViewModel.isChecking {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text("Check for Updates")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    // Only disable based on our own isChecking state, not Sparkle's canCheckForUpdates
                    // canCheckForUpdates flickers during Sparkle's automatic background checks
                    .disabled(updaterViewModel.isChecking)

                    Spacer()

                    HStack(spacing: 6) {
                        // Status icon
                        switch updaterViewModel.checkStatus {
                        case .idle:
                            EmptyView()
                        case .checking:
                            EmptyView()
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        case .error:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                        }

                        Text(updaterViewModel.statusText)
                            .font(.caption)
                            .foregroundColor({
                                switch updaterViewModel.checkStatus {
                                case .idle, .checking:
                                    .secondary
                                case .success:
                                    .primary
                                case .error:
                                    .red
                                }
                            }())
                    }
                }
            } header: {
                Text("Updates")
                    .font(.headline)
            }

            // MARK: - Help and Resources

            Section {
                Button {
                    NSApp.sendAction(#selector(AppDelegate.openTutorialWindow), to: nil, from: nil)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Replay Tutorial")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Review the writing control, suggestions, and quick actions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                Link(destination: AppURLs.github) {
                    HStack {
                        Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Link(destination: AppURLs.license) {
                    HStack {
                        Label("View License", systemImage: "doc.text")
                        Spacer()
                        Text("Apache 2.0")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Link(destination: AppURLs.issues) {
                    HStack {
                        Label("Report an Issue", systemImage: "exclamationmark.bubble")
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundColor(.accentColor)
                    Text("Help & Resources")
                        .font(.headline)
                }
            }

            // Support subsection
            Section {
                HStack(spacing: 16) {
                    Text("TextWarden is free and open source. Your support helps its development.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Link(destination: AppURLs.buyMeACoffee) {
                        Image("BuyMeACoffeeButton")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 32)
                    }
                }
            } header: {
                Text("Support")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    PreferencesView()
}
