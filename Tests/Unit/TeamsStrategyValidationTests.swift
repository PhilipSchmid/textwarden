import AppKit
@testable import TextWarden
import XCTest

final class TeamsStrategyValidationTests: XCTestCase {
    func testSingleLineEstimateUsesChildFrameAndScalarRange() throws {
        let frame = CGRect(x: 100, y: 200, width: 80, height: 16)
        let bounds = try XCTUnwrap(TextPartBoundsCalculator.estimateSingleLineBounds(
            text: "aaaa\n",
            targetRange: NSRange(location: 1, length: 2),
            frame: frame,
            font: .monospacedSystemFont(ofSize: 14, weight: .regular)
        ))

        XCTAssertEqual(bounds.minX, 120, accuracy: 0.01)
        XCTAssertEqual(bounds.width, 40, accuracy: 0.01)
        XCTAssertEqual(bounds.minY, 200)
        XCTAssertEqual(bounds.height, 16)
        XCTAssertNil(TextPartBoundsCalculator.estimateSingleLineBounds(
            text: "aa\naa",
            targetRange: NSRange(location: 1, length: 2),
            frame: frame,
            font: .systemFont(ofSize: 14)
        ))
    }

    func testSingleLineEstimateHandlesEmojiScalarOffsets() throws {
        let font = NSFont.systemFont(ofSize: 14)
        let text = "Hi 👩‍💻 qick"
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let frame = CGRect(
            x: 100,
            y: 200,
            width: (text as NSString).size(withAttributes: attributes).width,
            height: 16
        )
        let bounds = try XCTUnwrap(TextPartBoundsCalculator.estimateSingleLineBounds(
            text: text,
            targetRange: NSRange(location: 7, length: 4),
            frame: frame,
            font: font
        ))

        XCTAssertEqual(
            bounds.minX,
            frame.minX + ("Hi 👩‍💻 " as NSString).size(withAttributes: attributes).width,
            accuracy: 0.01
        )
        XCTAssertEqual(bounds.width, ("qick" as NSString).size(withAttributes: attributes).width, accuracy: 0.01)
    }

    func testFrameLayoutEstimatesSoftWrappedLine() throws {
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let bounds = try XCTUnwrap(TextPartBoundsCalculator.estimateLineBounds(
            text: "aaaa aaaa aaaa",
            targetRange: NSRange(location: 10, length: 4),
            frame: CGRect(x: 100, y: 200, width: 50, height: 56),
            font: font
        ))

        XCTAssertEqual(bounds.count, 1)
        XCTAssertEqual(bounds[0].minX, 100, accuracy: 0.01)
        XCTAssertEqual(bounds[0].minY, 240, accuracy: 0.01)
        XCTAssertEqual(bounds[0].height, 16, accuracy: 0.01)
    }
}
