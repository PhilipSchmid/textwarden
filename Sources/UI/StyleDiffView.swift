//
//  StyleDiffView.swift
//  TextWarden
//
//  Displays text differences with color highlighting for style suggestions
//

import SwiftUI

/// View that displays a text diff with green (added) and red (removed) highlighting
struct StyleDiffView: View {
    let diff: [DiffSegmentModel]
    var showInline: Bool = true

    var body: some View {
        if showInline {
            inlineView
        } else {
            sideBySideView
        }
    }

    // MARK: - Inline View

    private var inlineView: some View {
        Text(attributedDiffText)
            .textSelection(.enabled)
    }

    private var attributedDiffText: AttributedString {
        var result = AttributedString()

        for segment in diff {
            var text = AttributedString(segment.text)

            switch segment.kind {
            case .unchanged:
                text.foregroundColor = .primary

            case .added:
                text.foregroundColor = .green
                text.backgroundColor = Color.green.opacity(0.15)

            case .removed:
                text.foregroundColor = .red
                text.backgroundColor = Color.red.opacity(0.15)
                text.strikethroughStyle = .single
            }

            result.append(text)
        }

        return result
    }

    // MARK: - Side by Side View

    private var sideBySideView: some View {
        HStack(spacing: 16) {
            // Original (with removed parts highlighted)
            VStack(alignment: .leading, spacing: 4) {
                Text("Original")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(originalAttributedText)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)
            }

            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)

            // Suggested (with added parts highlighted)
            VStack(alignment: .leading, spacing: 4) {
                Text("Suggested")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(suggestedAttributedText)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)
            }
        }
    }

    private var originalAttributedText: AttributedString {
        var result = AttributedString()

        for segment in diff {
            guard segment.kind != .added else { continue }

            var text = AttributedString(segment.text)

            if segment.kind == .removed {
                text.foregroundColor = .red
                text.backgroundColor = Color.red.opacity(0.15)
            }

            result.append(text)
        }

        return result
    }

    private var suggestedAttributedText: AttributedString {
        var result = AttributedString()

        for segment in diff {
            guard segment.kind != .removed else { continue }

            var text = AttributedString(segment.text)

            if segment.kind == .added {
                text.foregroundColor = .green
                text.backgroundColor = Color.green.opacity(0.15)
            }

            result.append(text)
        }

        return result
    }
}

/// Compact diff view for popovers
struct CompactDiffView: View {
    let original: String
    let suggested: String
    let diff: [DiffSegmentModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Original text with strikethrough on removed parts
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)

                Text(originalWithHighlight)
                    .font(.callout)
            }

            // Suggested text with highlight on added parts
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)

                Text(suggestedWithHighlight)
                    .font(.callout)
            }
        }
    }

    private var originalWithHighlight: AttributedString {
        var result = AttributedString()

        for segment in diff {
            guard segment.kind != .added else { continue }

            var text = AttributedString(segment.text)

            if segment.kind == .removed {
                text.foregroundColor = .red
                text.strikethroughStyle = .single
            }

            result.append(text)
        }

        return result
    }

    private var suggestedWithHighlight: AttributedString {
        var result = AttributedString()

        for segment in diff {
            guard segment.kind != .removed else { continue }

            var text = AttributedString(segment.text)

            if segment.kind == .added {
                text.foregroundColor = .green
                text.underlineStyle = .single
            }

            result.append(text)
        }

        return result
    }
}

/// Simple before/after view without diff highlighting
struct BeforeAfterView: View {
    let original: String
    let suggested: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                Text("Before:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)

                Text(original)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .top, spacing: 4) {
                Text("After:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)

                Text(suggested)
                    .font(.callout)
            }
        }
    }
}

#Preview("Inline Diff") {
    StyleDiffView(diff: [
        DiffSegmentModel(text: "This is ", kind: .unchanged),
        DiffSegmentModel(text: "really ", kind: .removed),
        DiffSegmentModel(text: "a ", kind: .unchanged),
        DiffSegmentModel(text: "great ", kind: .added),
        DiffSegmentModel(text: "example.", kind: .unchanged)
    ])
    .padding()
}

#Preview("Side by Side") {
    StyleDiffView(
        diff: [
            DiffSegmentModel(text: "This is ", kind: .unchanged),
            DiffSegmentModel(text: "really ", kind: .removed),
            DiffSegmentModel(text: "a ", kind: .unchanged),
            DiffSegmentModel(text: "great ", kind: .added),
            DiffSegmentModel(text: "example.", kind: .unchanged)
        ],
        showInline: false
    )
    .padding()
    .frame(width: 400)
}

#Preview("Compact Diff") {
    CompactDiffView(
        original: "This is really a example.",
        suggested: "This is a great example.",
        diff: [
            DiffSegmentModel(text: "This is ", kind: .unchanged),
            DiffSegmentModel(text: "really ", kind: .removed),
            DiffSegmentModel(text: "a ", kind: .unchanged),
            DiffSegmentModel(text: "great ", kind: .added),
            DiffSegmentModel(text: "example.", kind: .unchanged)
        ]
    )
    .padding()
}
