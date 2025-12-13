//
//  AboutView.swift
//  TextWarden
//
//  About view showing app information and credits.
//

import SwiftUI

// MARK: - About View

struct AboutView: View {
    /// Access the updater from AppDelegate - use ObservedObject for proper updates
    @ObservedObject private var updaterViewModel: UpdaterViewModel

    /// Current year for copyright
    private var currentYear: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: Date())
    }

    /// State for copy feedback
    @State private var showCopiedFeedback = false

    init() {
        // Get updater from AppDelegate, with fallback
        if let appDelegate = NSApp.delegate as? AppDelegate {
            _updaterViewModel = ObservedObject(wrappedValue: appDelegate.updaterViewModel)
        } else {
            // Fallback - create temporary instance (shouldn't happen in practice)
            _updaterViewModel = ObservedObject(wrappedValue: UpdaterViewModel())
        }
    }

    /// Copy version to clipboard
    private func copyVersionToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(BuildInfo.appVersion, forType: .string)
        showCopiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopiedFeedback = false
        }
    }

    var body: some View {
        Form {
            // MARK: - About TextWarden (main group header with app info)
            Section {
                // App identity row with larger logo
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 20) {
                        Image("TextWardenLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 128, height: 128)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("TextWarden")
                                .font(.system(size: 28, weight: .bold))
                            Text("Grammar and Style Checking for macOS")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                }
                .padding(.vertical, 8)
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("About TextWarden")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("Application information and version details")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Application")
                        .font(.headline)
                        .padding(.top, 8)
                }
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
                    .disabled(!updaterViewModel.canCheckForUpdates || updaterViewModel.isChecking)

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
                                    return .secondary
                                case .success:
                                    return .primary
                                case .error:
                                    return .red
                                }
                            }())
                    }
                }
            } header: {
                Text("Version")
                    .font(.headline)
            }

            // MARK: - Resources (new main group)
            Section {
                Link(destination: URL(string: "https://github.com/philipschmid/textwarden")!) {
                    HStack {
                        Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Link(destination: URL(string: "https://github.com/philipschmid/textwarden/blob/main/LICENSE")!) {
                    HStack {
                        Label("View License", systemImage: "doc.text")
                        Spacer()
                        Text("Apache 2.0")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Link(destination: URL(string: "https://github.com/philipschmid/textwarden/issues")!) {
                    HStack {
                        Label("Report an Issue", systemImage: "exclamationmark.bubble")
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Resources")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("Source code, documentation, and support")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Links")
                        .font(.headline)
                        .padding(.top, 8)
                }
            }

            // Legal subsection
            Section {
                HStack {
                    Text("License")
                    Spacer()
                    Text("Apache 2.0")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Copyright")
                    Spacer()
                    Text("© \(currentYear) Philip Schmid")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Legal")
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
