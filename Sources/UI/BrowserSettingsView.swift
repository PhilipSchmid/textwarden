import AppKit
import SafariServices
import SwiftUI

struct BrowserSettingsView: View {
    @ObservedObject private var integration = BrowserIntegration.shared
    @State private var chromeURL: URL?
    @State private var braveURL: URL?
    @State private var safariURL: URL?
    @State private var firefoxURL: URL?
    @State private var zenURL: URL?
    @State private var showingSetup: String?
    @State private var feedback: String?

    var body: some View {
        Form {
            extensionSection("com.google.Chrome", name: "Google Chrome", browserURL: chromeURL)
            extensionSection("com.brave.Browser", name: "Brave", browserURL: braveURL)
            extensionSection("org.mozilla.firefox", name: "Firefox", browserURL: firefoxURL)
            extensionSection("app.zen-browser.zen", name: "Zen", browserURL: zenURL)

            extensionSection("com.apple.Safari", name: "Safari", browserURL: safariURL)

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Website Rules")
                        Text("Manage pages and websites where checking is paused.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Manage Websites…") { PreferencesWindowController.shared.selectTab(.websites) }
                        .buttonStyle(.bordered)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Application Settings")
                        Text("Pause checking for an entire browser.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Manage Applications…") { PreferencesWindowController.shared.selectTab(.applications) }
                        .buttonStyle(.bordered)
                }
            } header: {
                Text("Checking Preferences")
                    .font(.headline)
            } footer: {
                Text("For quick page controls, click the TextWarden extension in your browser’s toolbar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func activationHint(_ bundleID: String, name: String) -> String {
        bundleID == "app.zen-browser.zen"
            ? "On a web page, open the settings icon in Zen’s address bar, then click the TextWarden feather."
            : "On a web page, click TextWarden in \(name)’s toolbar."
    }

    private func extensionSection(_ bundleID: String, name: String, browserURL: URL?) -> some View {
        let connected = integration.connectedBrowsers.contains(bundleID)
        return
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        browserIcon(browserURL)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name)
                                .font(.headline)
                            Text(browserURL == nil ? "Not installed" : "Browser extension · Preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label(connected ? "Connected" : "Not connected",
                              systemImage: connected ? "checkmark.circle.fill" : "minus.circle")
                            .font(.caption)
                            .foregroundStyle(connected ? Color.green : Color.secondary)
                    }

                    Text(connected
                        ? activationHint(bundleID, name: name)
                        : browserURL == nil
                        ? "Install \(name) to use the browser extension preview."
                        : !integration.isListening
                        ? "The browser connection couldn’t start. Try again, or reinstall TextWarden if the problem continues."
                        : "The connection is configured automatically. Install the extension, then start checking from your browser.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                if browserURL != nil {
                    if !integration.isListening {
                        Button("Try Again") { integration.start() }
                    }
                    DisclosureGroup("Install Extension", isExpanded: Binding(get: { showingSetup == bundleID }, set: { showingSetup = $0 ? bundleID : nil })) {
                        setup(name: name, bundleID: bundleID)
                            .padding(.top, 8)
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    if bundleID == "com.google.Chrome" {
                        HStack(spacing: 8) {
                            Image(systemName: "network")
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                            Text("TextWarden Browser Extension (Preview)")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }

                        Text("Add precise underlines and native writing tools to web editors. Text stays on your Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(name)
                        .font(.headline)
                        .padding(.top, 8)
                }
            }
    }

    private func browserIcon(_ url: URL?) -> some View {
        Group {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }

    private func setup(name: String, bundleID: String) -> some View {
        let isSafari = bundleID == "com.apple.Safari"
        let isGecko = ["org.mozilla.firefox", "app.zen-browser.zen"].contains(bundleID)
        return VStack(alignment: .leading, spacing: 12) {
            Text(isSafari ? "The extension is included with TextWarden. Enable it in Safari’s Extensions settings." : isGecko
                ? "This preview loads temporarily until you restart the browser. A signed extension will be needed for permanent installation."
                : "This preview isn’t in the Chrome Web Store yet. Install it once; the connection to TextWarden is automatic.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(isSafari ? "1. Enable the extension" : "1. Load the extension")
                .font(.headline)
            Text(isSafari ? "Open Safari Extensions and enable TextWarden Browser Extension (Preview)." : isGecko
                ? "Open the folder and \(name)’s Extensions page. Choose Load Temporary Add-on, then select manifest.json in the revealed folder."
                : "Open the folder and \(name)’s Extensions page. Turn on Developer mode, choose Load unpacked, then select the BrowserExtension folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                if !isSafari { Button("Reveal Extension Folder") {
                    guard let folder = BrowserSetup.extensionFolder(for: bundleID), FileManager.default.fileExists(atPath: folder.path) else {
                        feedback = "The preview is missing from this build. Reinstall TextWarden."; return
                    }
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                } }
                Button("Open \(name) Extensions") { openExtensions(bundleID) }
            }
            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(feedback)
            }
            Divider()
            Text("2. Start writing")
                .font(.headline)
            Text("Keep TextWarden running. \(activationHint(bundleID, name: name)) Then click a text field.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func refresh() {
        chromeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome")
        braveURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.brave.Browser")
        safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
        firefoxURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.mozilla.firefox")
        zenURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "app.zen-browser.zen")
    }

    private func openExtensions(_ bundleID: String) {
        if bundleID == "com.apple.Safari" {
            SFSafariApplication.showPreferencesForExtension(withIdentifier: BrowserWire.safariExtensionID) { error in
                if let error { Task { @MainActor in feedback = "Could not open Safari Extensions: \(error.localizedDescription)" } }
            }
            return
        }
        let address = ["org.mozilla.firefox", "app.zen-browser.zen"].contains(bundleID)
            ? "about:debugging#/runtime/this-firefox"
            : bundleID == "com.brave.Browser" ? "brave://extensions" : "chrome://extensions"
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let url = URL(string: address) else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: .init()) { _, error in
            if let error {
                Task { @MainActor in feedback = "Could not open the browser: \(error.localizedDescription)" }
            }
        }
    }
}
