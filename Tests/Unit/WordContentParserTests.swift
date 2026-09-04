@testable import TextWarden
import XCTest

final class WordContentParserTests: XCTestCase {
    func testRequestsFullTextOnlyWhenAXValueIsIncomplete() {
        XCTAssertTrue(
            WordContentParser.needsFullDocumentText(
                visibleText: "\n\n\n",
                characterCount: 160
            )
        )
        XCTAssertFalse(
            WordContentParser.needsFullDocumentText(
                visibleText: "Complete text",
                characterCount: "Complete text".utf16.count
            )
        )
    }
}
