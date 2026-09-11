@testable import TextWarden
import XCTest

/// Opt-in CPU baselines, independent of Mail, AX permissions, and user preferences.
@MainActor
final class CPURegressionTests: XCTestCase {
    private final class Vocabulary: CustomVocabularyProviding {
        func containsAnyWord(in _: String) -> Bool {
            false
        }

        func addWord(_: String) throws {}
        func allWords() -> [String] {
            []
        }
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TEXTWARDEN_CPU_BENCHMARKS"] == "1", "Run make cpu-benchmark locally")
    }

    private func benchmark(_ operation: () -> Void) {
        XCTAssertEqual(ProcessInfo.processInfo.thermalState, .nominal, "Repeat on a cool machine")
        operation() // Warm dictionaries, regex infrastructure, and allocation paths.
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTCPUMetric(), XCTClockMetric()], options: options, block: operation)
        XCTAssertEqual(ProcessInfo.processInfo.thermalState, .nominal, "Repeat on a cool machine")
    }

    func testQuoteShort() {
        quote(repetitions: 4)
    }

    func testQuoteMedium() {
        quote(repetitions: 50)
    }

    func testQuoteLarge() {
        quote(repetitions: 1300)
    }

    private func quote(repetitions: Int) {
        let text = String(repeating: "We are reviewing the report tomorrow. ", count: repetitions).trimmingCharacters(in: .whitespaces)
        benchmark {
            for _ in 0 ..< 10 {
                XCTAssertEqual(MailContentParser.stripQuotedContent(from: text), text)
            }
        }
    }

    func testFilterFewErrors() {
        filter(repetitions: 1)
    }

    func testFilterManyErrors() {
        filter(repetitions: 1300)
    }

    private func filter(repetitions: Int) {
        let sentence = "This is a sentnce with a spelling mistke. "
        let text = String(repeating: sentence, count: repetitions)
        let errors = (0 ..< repetitions).flatMap { i in
            [10 ..< 17, 34 ..< 40].map { range in
                GrammarErrorModel(start: i * 42 + range.lowerBound, end: i * 42 + range.upperBound,
                                  message: "Spelling", severity: .warning, category: "Spelling", lintId: "Spelling")
            }
        }
        let config = GrammarFilterConfig(enabledCategories: ["Spelling"], ignoredRules: [], ignoredErrorTexts: [], useMacOSDictionary: false)
        let vocabulary = Vocabulary()
        benchmark {
            for _ in 0 ..< 10 {
                let result = GrammarErrorFilter.filter(errors: errors, sourceText: text, config: config, customVocabulary: vocabulary)
                XCTAssertEqual(result.count, errors.count)
                XCTAssertEqual(result.last?.end, errors.last?.end)
            }
        }
    }

    func testGrammarClean() {
        grammar(repetitions: 50, errors: false)
    }

    func testGrammarManyErrors() {
        grammar(repetitions: 1300, errors: true)
    }

    private func grammar(repetitions: Int, errors: Bool) {
        let sentence = errors ? "This is a sentnce with a spelling mistke. " : "We are reviewing the report tomorrow. "
        let text = String(repeating: sentence, count: repetitions)
        benchmark {
            let result = GrammarEngine.shared.analyzeText(text, dialect: "American",
                                                          enableInternetAbbrev: false, enableGenZSlang: false,
                                                          enableITTerminology: false, enableBrandNames: false,
                                                          enablePersonNames: false, enableLastNames: false)
            XCTAssertEqual(result.errors.count, errors ? repetitions * 2 : 0)
        }
    }
}
