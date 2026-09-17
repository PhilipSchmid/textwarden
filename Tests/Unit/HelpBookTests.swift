import XCTest

final class HelpBookTests: XCTestCase {
    func testBundledManualsIncludeBrowserPreview() throws {
        let book = try XCTUnwrap(Bundle.main.url(forResource: "TextWarden", withExtension: "help"))
        for name in ["configuration", "troubleshooting"] {
            let page = book.appendingPathComponent("Contents/Resources/en.lproj/\(name).html")
            let html = try String(contentsOf: page, encoding: .utf8)
            XCTAssertTrue(html.contains("id=\"browser-extension-preview\""), "\(name) is missing the browser preview guide")
        }
    }
}
