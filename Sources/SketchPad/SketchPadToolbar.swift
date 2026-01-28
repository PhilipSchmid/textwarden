//
//  SketchPadToolbar.swift
//  TextWarden
//
//  Simplified toolbar with document title, status, and editor options
//

import SwiftUI

/// Simplified toolbar with document title and editor options
struct SketchPadToolbar: View {
    @ObservedObject var viewModel: SketchPadViewModel
    @ObservedObject private var preferences = UserPreferences.shared

    var body: some View {
        HStack(spacing: 12) {
            // Document title
            TextField("Document title", text: $viewModel.documentTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            // Undo/Redo buttons
            ToolbarButton(
                icon: "arrow.uturn.backward",
                action: { viewModel.undo() },
                isEnabled: viewModel.canUndo,
                tooltip: "Undo (⌘Z)"
            )

            ToolbarButton(
                icon: "arrow.uturn.forward",
                action: { viewModel.redo() },
                isEnabled: viewModel.canRedo,
                tooltip: "Redo (⇧⌘Z)"
            )

            ToolbarDivider()

            // Editor options
            ToolbarToggle(
                icon: "list.number",
                isOn: $preferences.sketchPadShowLineNumbers,
                tooltip: "Line Numbers – Show line numbers in the gutter"
            )

            ToolbarToggle(
                icon: "line.horizontal.star.fill.line.horizontal",
                isOn: $preferences.sketchPadHighlightLine,
                tooltip: "Highlight Line – Subtly highlight the line where your cursor is located"
            )

            ToolbarToggle(
                icon: "paragraphsign",
                isOn: $preferences.sketchPadShowInvisibles,
                tooltip: "Invisible Characters – Show spaces, tabs, and line breaks"
            )

            ToolbarToggle(
                icon: "text.word.spacing",
                isOn: $preferences.sketchPadLineWrapping,
                tooltip: "Line Wrapping – Wrap long lines to fit the window"
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Toolbar Components

/// Action button for toolbar (undo, redo, etc.)
private struct ToolbarButton: View {
    let icon: String
    let action: () -> Void
    var isEnabled: Bool = true
    var tooltip: String = ""

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(isEnabled ? .primary : .secondary.opacity(0.5))
                .frame(width: 26, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(tooltip)
    }
}

/// Toggle button for toolbar options
private struct ToolbarToggle: View {
    let icon: String
    @Binding var isOn: Bool
    var tooltip: String = ""

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(isOn ? .accentColor : .secondary)
                .frame(width: 26, height: 24)
        }
        .buttonStyle(.plain)
        .background(isOn ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(4)
        .help(tooltip)
    }
}

/// Subtle vertical divider
private struct ToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 8)
    }
}

// MARK: - Status Bar

/// Status bar at the bottom showing save status, word count, character count
struct SketchPadStatusBar: View {
    @ObservedObject var viewModel: SketchPadViewModel

    var body: some View {
        HStack(spacing: 16) {
            // Save status
            HStack(spacing: 4) {
                if viewModel.saveStatus == .saving {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                }
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(viewModel.saveStatus.displayText)
            }

            Spacer()

            // Word count
            HStack(spacing: 4) {
                Text("\(viewModel.wordCount)")
                    .fontWeight(.medium)
                Text("words")
            }

            StatusDivider()

            // Character count
            HStack(spacing: 4) {
                Text("\(viewModel.characterCount)")
                    .fontWeight(.medium)
                Text("chars")
            }

            StatusDivider()

            // Line count
            HStack(spacing: 4) {
                Text("\(viewModel.lineCount)")
                    .fontWeight(.medium)
                Text("lines")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusColor: Color {
        switch viewModel.saveStatus {
        case .saved:
            .green
        case .saving:
            .orange
        case .unsaved:
            .yellow
        case .error:
            .red
        }
    }
}

/// Subtle vertical divider for status bar
private struct StatusDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 1, height: 12)
    }
}
