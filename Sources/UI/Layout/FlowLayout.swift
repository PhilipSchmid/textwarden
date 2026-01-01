//
//  FlowLayout.swift
//  TextWarden
//
//  A SwiftUI layout that arranges views horizontally and wraps to new lines when needed
//

import SwiftUI

/// A layout that arranges views horizontally and wraps to new lines when needed
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    /// Minimum width before wrapping - use a generous default to prevent premature wrapping
    var minWidthBeforeWrap: CGFloat = 350

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, position) in arrangement.positions.enumerated() {
            let subview = subviews[index]
            let size = subview.sizeThatFits(.unspecified)
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(size)
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        // Use the proposed width if available, otherwise use a generous minimum
        // This prevents premature wrapping when parent doesn't pass width proposal
        let maxWidth = proposal.width ?? minWidthBeforeWrap
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            // Check if we need to wrap to next line
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        let totalHeight = currentY + lineHeight
        return (CGSize(width: totalWidth, height: totalHeight), positions)
    }
}
