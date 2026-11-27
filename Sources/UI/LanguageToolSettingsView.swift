//
//  LanguageToolSettingsView.swift
//  TextWarden
//
//  Settings for the optional external grammar source.
//

import SwiftUI

/// Controls for an optional LanguageTool-compatible server.
///
/// TextWarden bundles no server and starts no process. This points at one the
/// user already runs, so the section leads with that and offers a reachability
/// check, because an unreachable server is otherwise silently ignored.
struct LanguageToolSettingsView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @State private var connectionState: ConnectionState = .untested

    private enum ConnectionState: Equatable {
        case untested
        case checking
        case reachable(Int)
        case unreachable(String)
    }

    var body: some View {
        Section {
            Toggle("Use an external LanguageTool server", isOn: $preferences.enableLanguageToolSource)
                .help("Send text to a LanguageTool-compatible server you run yourself")

            Text("Sends the text being checked to a LanguageTool server running on this Mac. Only addresses on this Mac are accepted, so your writing still never leaves the device. TextWarden does not bundle or start a server, and where both engines flag the same text the built-in result is kept.")
                .font(.caption)
                .foregroundColor(.secondary)

            if preferences.enableLanguageToolSource {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Server address:")
                            .foregroundColor(.secondary)
                        LeftAlignedTextField(
                            text: $preferences.languageToolEndpoint,
                            placeholder: LanguageToolConfiguration.defaultEndpointString
                        )
                        .frame(height: 22)
                    }

                    HStack {
                        Text("Language:")
                            .foregroundColor(.secondary)
                        LeftAlignedTextField(
                            text: $preferences.languageToolLanguage,
                            placeholder: LanguageToolConfiguration.defaultLanguage
                        )
                        .frame(height: 22)
                    }

                    Text("Use \"auto\" to let the server detect the language, or a code such as \"en-US\".")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        Text("Maximum text size:")
                            .foregroundColor(.secondary)
                        TextField(
                            "",
                            value: $preferences.languageToolCharacterLimit,
                            format: .number
                        )
                        .frame(width: 90)
                        Text("characters")
                            .foregroundColor(.secondary)
                    }

                    Text("Longer text is checked by the built-in engine alone. Values outside \(LanguageToolConfiguration.characterLimitRange.lowerBound)–\(LanguageToolConfiguration.characterLimitRange.upperBound) are brought back into range.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Button("Test Connection") {
                            testConnection()
                        }
                        .disabled(connectionState == .checking)

                        statusLabel
                    }
                    .padding(.top, 4)
                }
                .padding(.leading, 20)
            }
        } header: {
            Text("External Grammar Source")
                .font(.headline)
        }
        .onChange(of: preferences.languageToolEndpoint) {
            connectionState = .untested
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch connectionState {
        case .untested:
            EmptyView()
        case .checking:
            Text("Checking…")
                .font(.caption)
                .foregroundColor(.secondary)
        case let .reachable(count):
            Text("Connected. \(count) result(s) for the test sentence.")
                .font(.caption)
                .foregroundColor(.green)
        case let .unreachable(reason):
            Text(reason)
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    /// Send one short sentence with a known error, so a reachable server that
    /// returns nothing is still distinguishable from one that is not running.
    private func testConnection() {
        guard let configuration = LanguageToolConfiguration(
            endpointString: preferences.languageToolEndpoint,
            language: preferences.languageToolLanguage,
            timeout: LanguageToolConfiguration.defaultTimeout,
            characterLimit: preferences.languageToolCharacterLimit
        ) else {
            connectionState = .unreachable("Must be a server on this Mac, such as http://localhost:8081.")
            return
        }

        connectionState = .checking
        Task {
            do {
                let results = try await LanguageToolClient.shared.check(
                    text: "She dont like it.",
                    configuration: configuration,
                    // A deliberate act by the user, so it must reach a server
                    // they have just started rather than report the cooldown
                    // left over from before they started it.
                    respectCooldown: false
                )
                connectionState = .reachable(results.count)
            } catch let LanguageToolError.badStatus(code) {
                connectionState = .unreachable("Server answered with HTTP \(code).")
            } catch {
                connectionState = .unreachable("Could not reach the server.")
            }
        }
    }
}
