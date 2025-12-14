//
//  WebsiteSettingsView.swift
//  TextWarden
//
//  Per-website settings for disabling grammar checking.
//

import SwiftUI
import AppKit

// MARK: - Website Settings

struct WebsiteSettingsView: View {
    @ObservedObject var preferences: UserPreferences
    @State private var searchText = ""
    @State private var newWebsite = ""
    @State private var showingAddSheet = false

    /// Filtered websites based on search text
    private var filteredWebsites: [String] {
        let sorted = Array(preferences.disabledWebsites).sorted()
        if searchText.isEmpty {
            return sorted
        }
        return sorted.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field and add button row
            HStack {
                // Search field (matching Applications style)
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search websites...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

                // Current website button (if in browser)
                if let currentDomain = AnalysisCoordinator.shared.browserDomain() {
                    if !preferences.isWebsiteDisabled(currentDomain) {
                        Button {
                            preferences.disableWebsite(currentDomain)
                        } label: {
                            Label("Disable \(currentDomain)", systemImage: "minus.circle")
                        }
                        .buttonStyle(.bordered)
                        .help("Disable grammar checking on the current website")
                    }
                }

                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help("Add a website to disable")
            }
            .padding()

            // Website list
            List {
                Section {
                    if filteredWebsites.isEmpty && !preferences.disabledWebsites.isEmpty {
                        // Search returned no results
                        HStack {
                            Spacer()
                            Text("No matching websites")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else if preferences.disabledWebsites.isEmpty {
                        // No websites added yet
                        VStack(spacing: 12) {
                            Image(systemName: "globe")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("No disabled websites")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Add websites to disable grammar checking on specific sites")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(filteredWebsites, id: \.self) { website in
                            HStack {
                                // Website icon
                                Image(systemName: website.hasPrefix("*.") ? "globe.badge.chevron.backward" : "globe")
                                    .foregroundColor(.accentColor)
                                    .frame(width: 24, height: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(website)
                                        .font(.body)
                                    if website.hasPrefix("*.") {
                                        Text("Includes all subdomains")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                // Status indicator
                                Text("Disabled")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.15))
                                    .cornerRadius(4)

                                // Remove button
                                Button {
                                    preferences.enableWebsite(website)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Enable grammar checking on this website")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    HStack {
                        Text("Disabled Websites")
                            .font(.headline)
                        Spacer()
                        Text("\(preferences.disabledWebsites.count) \(preferences.disabledWebsites.count == 1 ? "website" : "websites")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .headerProminence(.increased)
            }
            .listStyle(.inset)

            // Info text (matching Applications style)
            Text("Disable grammar checking on specific websites. Enter exact domains like \"github.com\" or use wildcards like \"*.google.com\" to include all subdomains. When browsing, use the button above to quickly disable the current site.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddWebsiteSheet(
                newWebsite: $newWebsite,
                isPresented: $showingAddSheet,
                onAdd: { website in
                    preferences.disableWebsite(website)
                    newWebsite = ""
                }
            )
        }
    }
}

/// Sheet for adding a new website to the disabled list
private struct AddWebsiteSheet: View {
    @Binding var newWebsite: String
    @Binding var isPresented: Bool
    let onAdd: (String) -> Void
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 4) {
                Image(systemName: "globe.badge.chevron.backward")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                Text("Add Website")
                    .font(.headline)
                Text("Disable grammar checking on a specific website")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Input field
            VStack(alignment: .leading, spacing: 6) {
                Text("Domain")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g., github.com or *.google.com", text: $newWebsite)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
                Text("Use * as wildcard for subdomains (e.g., *.example.com)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Buttons
            HStack {
                Button("Cancel") {
                    newWebsite = ""
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Website") {
                    let trimmed = newWebsite.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onAdd(trimmed)
                    }
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(newWebsite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}
