import AppKit
@testable import TextWarden
import XCTest

final class TeamsStrategyValidationTests: XCTestCase {
    func testSingleLineEstimateUsesChildFrameAndScalarRange() throws {
        let frame = CGRect(x: 100, y: 200, width: 80, height: 16)
        let bounds = try XCTUnwrap(TeamsStrategy.estimateSingleLineBounds(
            text: "aaaa\n",
            targetRange: NSRange(location: 1, length: 2),
            frame: frame,
            font: .monospacedSystemFont(ofSize: 14, weight: .regular)
        ))

        XCTAssertEqual(bounds.minX, 120, accuracy: 0.01)
        XCTAssertEqual(bounds.width, 40, accuracy: 0.01)
        XCTAssertEqual(bounds.minY, 200)
        XCTAssertEqual(bounds.height, 16)
        XCTAssertNil(TeamsStrategy.estimateSingleLineBounds(
            text: "aa\naa",
            targetRange: NSRange(location: 1, length: 2),
            frame: frame,
            font: .systemFont(ofSize: 14)
        ))
    }
}
