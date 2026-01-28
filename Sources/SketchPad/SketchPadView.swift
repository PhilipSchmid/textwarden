//
//  SketchPadView.swift
//  TextWarden
//
//  Main view for the Sketch Pad feature with 3-column layout
//

import SwiftUI

/// Main Sketch Pad view with sidebar, editor, and insights panel
struct SketchPadView: View {
    @StateObject private var viewModel = SketchPadViewModel.shared

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar (collapsible) - controlled by toolbar button
            if viewModel.sidebarVisible {
                SketchPadSidebar(viewModel: viewModel)
                    .frame(width: 250)
                    .transition(.move(edge: .leading))
            }

            // Main content area
            VStack(spacing: 0) {
                // Integrated title + formatting bar at top
                SketchPadToolbar(viewModel: viewModel)

                Divider()

                // Editor
                SketchPadEditor(viewModel: viewModel)

                Divider()

                // Status bar at bottom
                SketchPadStatusBar(viewModel: viewModel)
            }
            .frame(minWidth: 400)

            // Right panel - Insights
            SketchPadInsightsPanel(viewModel: viewModel)
                .frame(width: 320)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.2), value: viewModel.sidebarVisible)
    }
}
