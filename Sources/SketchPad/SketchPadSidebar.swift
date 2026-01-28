//
//  SketchPadSidebar.swift
//  TextWarden
//
//  Left sidebar for Sketch Pad showing draft list
//

import SwiftUI

/// Sidebar view showing drafts and settings
struct SketchPadSidebar: View {
    @ObservedObject var viewModel: SketchPadViewModel
    @State private var showingDeleteConfirmation = false
    @State private var documentToDelete: SketchDocument?

    var body: some View {
        VStack(spacing: 0) {
            // New Sketch button
            Button {
                viewModel.newDocument()
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("New Sketch")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(16)

            // Past sketches header
            HStack {
                Text("PAST SKETCHES")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Draft list
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(viewModel.drafts) { draft in
                        DraftRow(
                            draft: draft,
                            isSelected: viewModel.currentDocument?.id == draft.id,
                            onSelect: {
                                viewModel.loadDocument(draft)
                            },
                            onDelete: {
                                documentToDelete = draft
                                showingDeleteConfirmation = true
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .alert("Delete Sketch?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                documentToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let doc = documentToDelete {
                    Task {
                        await viewModel.deleteDocument(doc)
                    }
                }
                documentToDelete = nil
            }
        } message: {
            if let doc = documentToDelete {
                Text("Are you sure you want to delete \"\(doc.title)\"? This action cannot be undone.")
            }
        }
    }
}

/// Row representing a single draft in the sidebar
private struct DraftRow: View {
    let draft: SketchDocument
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(draft.formattedTimestamp)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isHovering {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete sketch")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
