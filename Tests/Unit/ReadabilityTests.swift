//
//  ReadabilityTests.swift
//  TextWarden
//
//  Comprehensive tests for the ReadabilityCalculator algorithms.
//

@testable import TextWarden
import XCTest

final class ReadabilityTests: XCTestCase {
    var calculator: ReadabilityCalculator!

    override func setUp() {
        super.setUp()
        calculator = ReadabilityCalculator.shared
    }

    // MARK: - Syllable Counting Tests

    func testSyllableCount_SingleSyllable() {
        XCTAssertEqual(calculator.syllableCount("cat"), 1)
        XCTAssertEqual(calculator.syllableCount("dog"), 1)
        XCTAssertEqual(calculator.syllableCount("run"), 1)
        XCTAssertEqual(calculator.syllableCount("the"), 1)
        XCTAssertEqual(calculator.syllableCount("a"), 1)
    }

    func testSyllableCount_TwoSyllables() {
        XCTAssertEqual(calculator.syllableCount("happy"), 2)
        XCTAssertEqual(calculator.syllableCount("water"), 2)
        XCTAssertEqual(calculator.syllableCount("table"), 2)
        XCTAssertEqual(calculator.syllableCount("begin"), 2)
        XCTAssertEqual(calculator.syllableCount("easy"), 2)
    }

    func testSyllableCount_ThreeSyllables() {
        XCTAssertEqual(calculator.syllableCount("beautiful"), 3)
        XCTAssertEqual(calculator.syllableCount("computer"), 3)
        XCTAssertEqual(calculator.syllableCount("yesterday"), 3)
        XCTAssertEqual(calculator.syllableCount("important"), 3)
    }

    func testSyllableCount_FourOrMoreSyllables() {
        XCTAssertEqual(calculator.syllableCount("communication"), 5)
        XCTAssertEqual(calculator.syllableCount("university"), 5)
        XCTAssertEqual(calculator.syllableCount("opportunity"), 5)
        XCTAssertEqual(calculator.syllableCount("international"), 5)
    }

    func testSyllableCount_SilentE() {
        // Silent 'e' at end should not add a syllable
        XCTAssertEqual(calculator.syllableCount("make"), 1)
        XCTAssertEqual(calculator.syllableCount("cake"), 1)
        XCTAssertEqual(calculator.syllableCount("time"), 1)
        XCTAssertEqual(calculator.syllableCount("house"), 1)
    }

    func testSyllableCount_LeEnding() {
        // "le" endings are usually pronounced
        XCTAssertEqual(calculator.syllableCount("table"), 2)
        XCTAssertEqual(calculator.syllableCount("apple"), 2)
        XCTAssertEqual(calculator.syllableCount("simple"), 2)
        XCTAssertEqual(calculator.syllableCount("bottle"), 2)
    }

    func testSyllableCount_EdEnding() {
        // "ed" is usually silent after consonants (except t, d)
        XCTAssertEqual(calculator.syllableCount("walked"), 1)
        XCTAssertEqual(calculator.syllableCount("jumped"), 1)
        XCTAssertEqual(calculator.syllableCount("liked"), 1)
        // "ed" is pronounced after t, d
        XCTAssertEqual(calculator.syllableCount("wanted"), 2)
        XCTAssertEqual(calculator.syllableCount("needed"), 2)
    }

    func testSyllableCount_EmptyAndSpecial() {
        XCTAssertEqual(calculator.syllableCount(""), 0)
        XCTAssertEqual(calculator.syllableCount("123"), 0)
        XCTAssertEqual(calculator.syllableCount("..."), 0)
    }

    func testSyllableCount_WithPunctuation() {
        XCTAssertEqual(calculator.syllableCount("hello!"), 2)
        XCTAssertEqual(calculator.syllableCount("world?"), 1)
        XCTAssertEqual(calculator.syllableCount("don't"), 1)
    }

    // MARK: - Word Counting Tests

    func testWordCount_Basic() {
        XCTAssertEqual(calculator.wordCount("hello world"), 2)
        XCTAssertEqual(calculator.wordCount("one two three four"), 4)
        XCTAssertEqual(calculator.wordCount("a"), 1)
    }

    func testWordCount_WithPunctuation() {
        XCTAssertEqual(calculator.wordCount("Hello, world!"), 2)
        XCTAssertEqual(calculator.wordCount("This is a test."), 4)
    }

    func testWordCount_MultipleSpaces() {
        XCTAssertEqual(calculator.wordCount("hello   world"), 2)
        XCTAssertEqual(calculator.wordCount("  spaced  out  "), 2)
    }

    func testWordCount_Newlines() {
        XCTAssertEqual(calculator.wordCount("hello\nworld"), 2)
        XCTAssertEqual(calculator.wordCount("line one\nline two\nline three"), 6)
    }

    func testWordCount_Empty() {
        XCTAssertEqual(calculator.wordCount(""), 0)
        XCTAssertEqual(calculator.wordCount("   "), 0)
        XCTAssertEqual(calculator.wordCount("..."), 0)
        XCTAssertEqual(calculator.wordCount("123 456"), 0) // Numbers only, no letters
    }

    // MARK: - Sentence Counting Tests

    func testSentenceCount_SinglePeriod() {
        XCTAssertEqual(calculator.sentenceCount("Hello world."), 1)
        XCTAssertEqual(calculator.sentenceCount("This is a test."), 1)
    }

    func testSentenceCount_MultiplesSentences() {
        XCTAssertEqual(calculator.sentenceCount("Hello. World."), 2)
        XCTAssertEqual(calculator.sentenceCount("One. Two. Three."), 3)
    }

    func testSentenceCount_QuestionAndExclamation() {
        XCTAssertEqual(calculator.sentenceCount("How are you?"), 1)
        XCTAssertEqual(calculator.sentenceCount("Hello! How are you?"), 2)
        XCTAssertEqual(calculator.sentenceCount("Wow! That's great! Really?"), 3)
    }

    func testSentenceCount_Abbreviations() {
        // Common abbreviations should not count as sentence endings
        XCTAssertEqual(calculator.sentenceCount("Mr. Smith is here."), 1)
        XCTAssertEqual(calculator.sentenceCount("Dr. Jones and Mrs. Smith."), 1)
        XCTAssertEqual(calculator.sentenceCount("I live on Main St. in the city."), 1)
    }

    func testSentenceCount_NoEnding() {
        // Text without sentence-ending punctuation counts as 1
        XCTAssertEqual(calculator.sentenceCount("Hello world"), 1)
        XCTAssertEqual(calculator.sentenceCount("No ending punctuation here"), 1)
    }

    func testSentenceCount_Empty() {
        XCTAssertEqual(calculator.sentenceCount(""), 0)
        XCTAssertEqual(calculator.sentenceCount("   "), 0)
    }

    // MARK: - Flesch Reading Ease Tests

    func testFleschRE_VeryEasy() throws {
        // Very simple text should score high (90+)
        let simpleText = "The cat sat on the mat. The dog ran fast. It was fun."
        let result = calculator.fleschReadingEase(for: simpleText)

        XCTAssertNotNil(result)
        XCTAssertGreaterThan(try XCTUnwrap(result?.score), 80, "Simple text should score above 80")
        XCTAssertEqual(result?.algorithm, .fleschReadingEase)
    }

    func testFleschRE_Standard() throws {
        // Typical news article level text
        let standardText = """
        The government announced new policies yesterday. \
        These changes will affect many citizens across the country. \
        Officials expect the implementation to begin next month.
        """
        let result = calculator.fleschReadingEase(for: standardText)

        XCTAssertNotNil(result)
        // Standard text typically scores 50-70
        XCTAssertGreaterThan(try XCTUnwrap(result?.score), 40)
        XCTAssertLessThan(try XCTUnwrap(result?.score), 80)
    }

    func testFleschRE_Difficult() throws {
        // Academic/technical text should score lower
        let difficultText = """
        The epistemological implications of quantum mechanical phenomena necessitate \
        a fundamental reconceptualization of classical deterministic frameworks. \
        Contemporary theoretical physicists increasingly acknowledge the \
        insufficiency of traditional reductionist methodologies.
        """
        let result = calculator.fleschReadingEase(for: difficultText)

        XCTAssertNotNil(result)
        XCTAssertLessThan(try XCTUnwrap(result?.score), 50, "Academic text should score below 50")
    }

    func testFleschRE_ScoreClamping() throws {
        // Scores should be clamped to 0-100 range
        let result = calculator.fleschReadingEase(for: "Go. Do. Be. See. Run. Eat. Sit. Win.")

        XCTAssertNotNil(result)
        XCTAssertLessThanOrEqual(try XCTUnwrap(result?.score), 100)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(result?.score), 0)
    }

    // MARK: - Edge Cases

    func testFleschRE_EmptyText() {
        let result = calculator.fleschReadingEase(for: "")
        XCTAssertNil(result, "Empty text should return nil")
    }

    func testFleschRE_SingleWord() {
        let result = calculator.fleschReadingEase(for: "Hello")

        // Single word with no sentence ending should still work (counted as 1 sentence)
        XCTAssertNotNil(result)
    }

    func testFleschRE_OnlyPunctuation() {
        let result = calculator.fleschReadingEase(for: "... !!! ???")
        XCTAssertNil(result, "Text with only punctuation should return nil")
    }

    func testFleschRE_OnlyNumbers() {
        let result = calculator.fleschReadingEase(for: "123 456 789")
        XCTAssertNil(result, "Text with only numbers should return nil")
    }

    // MARK: - Result Properties

    func testReadabilityResult_Labels() throws {
        // Test different score ranges produce correct labels
        let veryEasyText = "I am. He is. We go. You see."
        let result = calculator.fleschReadingEase(for: veryEasyText)

        XCTAssertNotNil(result)
        XCTAssertFalse(try XCTUnwrap(result?.label.isEmpty), "Label should not be empty")
    }

    func testReadabilityResult_DisplayScore() throws {
        let text = "This is a simple test sentence."
        let result = calculator.fleschReadingEase(for: text)

        XCTAssertNotNil(result)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(result?.displayScore), 0)
        XCTAssertLessThanOrEqual(try XCTUnwrap(result?.displayScore), 100)
    }

    func testReadabilityResult_Emoji() throws {
        let text = "This is a simple test."
        let result = calculator.fleschReadingEase(for: text)

        XCTAssertNotNil(result)
        let validEmojis = ["🟢", "🟡", "🟠", "🔴"]
        XCTAssertTrue(try validEmojis.contains(XCTUnwrap(result?.emoji)), "Should have a valid emoji")
    }

    func testReadabilityResult_ImprovementTips() throws {
        // Difficult text should have tips
        let difficultText = """
        The epistemological implications necessitate fundamental reconceptualization.
        """
        let result = calculator.fleschReadingEase(for: difficultText)

        XCTAssertNotNil(result)
        if try XCTUnwrap(result?.score) < 70 {
            XCTAssertFalse(try XCTUnwrap(result?.improvementTips.isEmpty), "Difficult text should have improvement tips")
        }
    }

    func testReadabilityResult_Interpretation() throws {
        let text = "This is a test sentence for checking interpretations."
        let result = calculator.fleschReadingEase(for: text)

        XCTAssertNotNil(result)
        XCTAssertFalse(try XCTUnwrap(result?.interpretation.isEmpty), "Should have an interpretation")
    }

    // MARK: - Performance Tests

    func testPerformance_ShortText() {
        let text = "This is a short test sentence. It has only a few words."

        measure {
            for _ in 0 ..< 100 {
                _ = calculator.fleschReadingEase(for: text)
            }
        }
    }

    func testPerformance_LongText() {
        // Generate ~1000 word text
        let sentence = "The quick brown fox jumps over the lazy dog. "
        let longText = String(repeating: sentence, count: 111) // ~1000 words

        measure {
            _ = calculator.fleschReadingEase(for: longText)
        }
    }

    // MARK: - Algorithm Enum Tests

    func testReadabilityAlgorithm_CaseIterable() {
        XCTAssertFalse(ReadabilityAlgorithm.allCases.isEmpty)
        XCTAssertTrue(ReadabilityAlgorithm.allCases.contains(.fleschReadingEase))
    }

    func testReadabilityAlgorithm_RawValue() {
        XCTAssertEqual(ReadabilityAlgorithm.fleschReadingEase.rawValue, "fleschReadingEase")
    }

    // MARK: - Real-World Examples

    func testFleschRE_GettysburgAddress() throws {
        // The Gettysburg Address is written at approximately 9th grade level
        let text = """
        Four score and seven years ago our fathers brought forth on this continent \
        a new nation, conceived in Liberty, and dedicated to the proposition that \
        all men are created equal.
        """
        let result = calculator.fleschReadingEase(for: text)

        XCTAssertNotNil(result)
        // Historical speeches typically score in the 50-70 range
        XCTAssertGreaterThan(try XCTUnwrap(result?.score), 30)
        XCTAssertLessThan(try XCTUnwrap(result?.score), 80)
    }

    func testFleschRE_ChildrensText() throws {
        let text = """
        See the cat. The cat is big. The cat runs fast. I like the cat.
        """
        let result = calculator.fleschReadingEase(for: text)

        XCTAssertNotNil(result)
        // Very simple children's text should score 90+
        XCTAssertGreaterThan(try XCTUnwrap(result?.score), 85)
    }
}
