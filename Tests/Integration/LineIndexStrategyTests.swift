import AppKit
@testable import TextWarden
import XCTest

final class LineIndexStrategyTests: XCTestCase {
    func testResolverUsesHarpersTypoRangeAfterDecomposedAccent() throws {
        let text = "cafe\u{301} teh cat."
        let analysis: GrammarAnalysisResult = GrammarEngine.shared.analyzeText(text)
        let typo = try XCTUnwrap(analysis.errors.first { $0.suggestions.contains("the") })
        try assertResolvedRange(NSRange(location: typo.start, length: typo.end - typo.start), in: text, covers: "teh")
    }

    func testResolverExpandsSeparatorWithoutIncludingTheNextSpace() throws {
        try assertResolvedRange(NSRange(location: 1, length: 1), in: "7 cafe\u{301} today", covers: "7 cafe\u{301}")
    }

    func testCodexElementTreeLooksUpWholeExpandedWord() {
        final class RecordingTree: ElementTreeStrategy {
            var searches: [String] = []

            override func findBestElementContainingText(_ targetText: String, in _: AXUIElement) -> AXUIElement? {
                searches.append(targetText)
                return nil
            }
        }

        let tree = RecordingTree()
        let resolver = PositionResolver(rangeBounds: RangeBoundsStrategy { _, _ in nil }, elementTree: tree)
        let id = "com.openai.codex"
        let text = "7 cafe\u{301} today. cafe\u{301} teh cat."
        _ = resolver.resolvePosition(
            for: .grammar(NSRange(location: 1, length: 1), in: text), in: AXUIElementCreateSystemWide(),
            text: text, parser: ContentParserFactory.shared.parser(for: id), bundleID: id
        )
        XCTAssertEqual(tree.searches, ["7 cafe\u{301}"])
    }

    private func assertResolvedRange(_ source: NSRange, in text: String, covers expected: String) throws {
        var requests: [NSRange] = []
        let rangeBounds = RangeBoundsStrategy { range, _ in
            requests.append(NSRange(location: range.location, length: range.length))
            return CGRect(x: 100, y: 100, width: 40, height: 15)
        }
        let configs = AppRegistry.shared.allConfigurations.filter { $0.preferredStrategies.first == .rangeBounds }
        XCTAssertFalse(configs.isEmpty)
        for config in configs {
            let bundleID = try XCTUnwrap(config.bundleIDs.sorted().first)
            let resolver = PositionResolver(rangeBounds: rangeBounds)
            requests.removeAll()
            let result = resolver.resolvePosition(
                for: .grammar(source, in: text), in: AXUIElementCreateSystemWide(), text: text,
                parser: ContentParserFactory.shared.parser(for: bundleID), bundleID: bundleID
            )
            XCTAssertEqual(result.strategy, rangeBounds.strategyName, bundleID)
            XCTAssertEqual(requests, [(text as NSString).range(of: expected)], bundleID)
        }
    }

    func testHarperTypoMeasuresTheCorrectRunsOnTheSecondLine() throws {
        for prefix in ["cafe\u{301} ", "👩‍💻 ", "🎉🎉 ", ""] {
            let firstLine = "Heading\n"
            let text = firstLine + prefix + "teh cat."
            let analysis: GrammarAnalysisResult = GrammarEngine.shared.analyzeText(text)
            let typo = try XCTUnwrap(analysis.errors.first { $0.suggestions.contains { $0.lowercased() == "the" } })
            let source = NSRange(location: typo.start, length: typo.end - typo.start)
            let range = PositionRange(scalars: source, in: text)
            let reported = text as NSString
            var requests = [NSRange]()
            let expected = reported.range(of: "teh")
            let strategy = LineIndexStrategy { _, attribute, parameter, result in
                switch attribute as String {
                case "AXLineForIndex":
                    XCTAssertEqual(parameter as? Int, expected.location)
                    result.pointee = 0 as NSNumber
                case "AXRangeForLine":
                    // Some hosts include the previous line in the reported range.
                    var line = CFRange(location: 0, length: reported.length)
                    result.pointee = AXValueCreate(.cfRange, &line)
                case "AXBoundsForRange":
                    var bounds = CGRect(x: 100, y: 100, width: 200, height: 20)
                    result.pointee = AXValueCreate(.cgRect, &bounds)
                case "AXAttributedStringForRange":
                    guard let raw = safeAXValueGetRange(parameter) else { return .illegalArgument }
                    let request = NSRange(location: raw.location, length: raw.length)
                    requests.append(request)
                    guard NSMaxRange(request) <= reported.length else { return .illegalArgument }
                    result.pointee = NSAttributedString(string: reported.substring(with: request))
                default:
                    return .attributeUnsupported
                }
                return .success
            }
            let geometry = try strategy.calculateGeometry(
                errorRange: XCTUnwrap(range.range(for: strategy.strategyType)), element: AXUIElementCreateSystemWide(), text: text,
                parser: GenericContentParser(bundleIdentifier: "com.apple.TextEdit")
            )
            XCTAssertNotNil(geometry)
            let before = NSRange(location: firstLine.utf16.count, length: prefix.utf16.count)
            XCTAssertEqual(requests, prefix.isEmpty ? [expected] : [before, expected])
        }
    }

    func testReadabilityAndHarperAgreeAfterFilteredPrefix() {
        let text = "👩‍💻 cafe\u{301} 🎉!"
        let word = NSRange(location: 5, length: 1)
        let readable = PositionRange(characters: word, in: text, afterScalarPrefix: 4)
        let harper = PositionRange(scalars: NSRange(location: 6, length: 1), in: text, afterScalarPrefix: 4)
        XCTAssertEqual(readable.utf16, (text as NSString).range(of: "🎉"))
        XCTAssertEqual(readable.utf16, harper.utf16)
        XCTAssertEqual(readable.range(for: .textMarker), word)
        XCTAssertNil(PositionRange(scalars: NSRange(location: 1, length: 1), in: text).utf16)
        XCTAssertNil(PositionRange(scalars: NSRange(location: 100, length: 1), in: text).utf16)
    }

    func testMailUsesNativeRangesForGrammarAndReadability() {
        let text = "\n\n👩🏽‍💻 cafe\u{301} sentnce."
        let expected = (text as NSString).range(of: "sentnce")
        let prefix = text.prefix { $0 != "s" }
        XCTAssertEqual(PositionRange.grammar(NSRange(location: prefix.unicodeScalars.count, length: 7), in: text).range(for: .mail), expected)
        XCTAssertEqual(PositionRange(characters: NSRange(location: prefix.count, length: 7), in: text).range(for: .mail), expected)
        XCTAssertNil(PositionRange(scalars: NSRange(location: 10, length: 6), in: "").range(for: .mail))
    }

    func testExpandedRangePreservesDedicatedStrategyInput() {
        let range = PositionRange.grammar(NSRange(location: 1, length: 1), in: "7 cafe\u{301} today")
        XCTAssertEqual(range.range(for: .word), NSRange(location: 0, length: 6))
        XCTAssertEqual(range.range(for: .rangeBounds), NSRange(location: 0, length: 7))
    }

    func testAXFontRunsUseTheHostFonts() throws {
        let small = try XCTUnwrap(NSFont(name: "Menlo", size: 12))
        let large = try XCTUnwrap(NSFont(name: "Menlo-Bold", size: 24))
        let host = NSMutableAttributedString(string: "aβx")
        let expected = NSMutableAttributedString(string: "aβ")
        for (index, font) in [small, large].enumerated() {
            let run = NSRange(location: index, length: 1)
            host.addAttribute(NSAttributedString.Key("AXFont"), value: [
                "AXFontName": font.fontName, "AXFontSize": font.pointSize,
            ], range: run)
            expected.addAttribute(.font, value: font, range: run)
        }
        let measured = try XCTUnwrap(LineIndexStrategy.measureUsingAttributedString(
            textBefore: "aβ", errorRange: NSRange(location: 2, length: 1), errorText: "x",
            attributedString: host.attributedSubstring(from:)
        ))
        XCTAssertEqual(measured.textBeforeWidth, expected.size().width, accuracy: 0.01)
    }
}
