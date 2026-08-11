//
//  TextIndexConverterTests.swift
//  TextWardenTests
//

import Foundation
@testable import TextWarden
import XCTest

final class TextIndexConverterTests: XCTestCase {
    func testASCIIIndicesUseTheSameOffsets() {
        let text = "Hello"
        guard let index = TextIndexConverter.scalarIndexToStringIndex(2, in: text) else {
            XCTFail("Expected a valid scalar boundary")
            return
        }

        XCTAssertEqual(index, text.index(text.startIndex, offsetBy: 2))
        XCTAssertEqual(TextIndexConverter.stringIndexToScalarIndex(index, in: text), 2)
        assertRange(
            TextIndexConverter.scalarRangeToUTF16CFRange(start: 1, end: 4, in: text),
            location: 1,
            length: 3
        )
    }

    func testEmojiBeforeErrorShiftsUTF16Location() {
        let text = "Hi 😊 bad"
        let badStart = "Hi 😊 ".unicodeScalars.count
        let badEnd = badStart + "bad".unicodeScalars.count

        assertRange(
            TextIndexConverter.scalarRangeToUTF16CFRange(start: badStart, end: badEnd, in: text),
            location: 6,
            length: 3
        )
        XCTAssertEqual(TextIndexConverter.extractErrorText(start: badStart, end: badEnd, from: text), "bad")
    }

    func testZWJSequenceBeforeErrorUsesItsFullUTF16Width() {
        let family = "👨‍👩‍👧"
        let text = "\(family) test"
        let testStart = "\(family) ".unicodeScalars.count
        let testEnd = testStart + "test".unicodeScalars.count
        let expectedLocation = ("\(family) " as NSString).length

        assertRange(
            TextIndexConverter.scalarRangeToUTF16CFRange(start: testStart, end: testEnd, in: text),
            location: expectedLocation,
            length: 4
        )
        XCTAssertEqual(TextIndexConverter.extractErrorText(start: testStart, end: testEnd, from: text), "test")
    }

    func testScalarIndexInsideGraphemeClusterIsRejected() {
        let family = "👨‍👩‍👧"

        XCTAssertNil(TextIndexConverter.scalarIndexToStringIndex(1, in: family))
        XCTAssertNil(TextIndexConverter.extractErrorText(start: 1, end: 2, from: family))
    }

    func testScalarIndicesRejectInvalidBounds() {
        let text = "Hello"

        XCTAssertNil(TextIndexConverter.scalarIndexToStringIndex(-1, in: text))
        XCTAssertNil(TextIndexConverter.scalarIndexToStringIndex(6, in: text))
        XCTAssertNil(TextIndexConverter.scalarRangeToUTF16CFRange(start: 0, end: 6, in: text))
        XCTAssertNil(TextIndexConverter.extractErrorText(start: 3, end: 3, from: text))
        XCTAssertNil(TextIndexConverter.extractErrorText(start: 4, end: 2, from: text))
    }

    func testUTF16OffsetInsideSurrogatePairIsRejected() {
        let text = "A😊B"

        XCTAssertNil(TextIndexConverter.stringIndex(forUTF16Offset: 2, in: text))
        XCTAssertNil(TextIndexConverter.utf16ToGraphemeIndex(2, in: text))
    }

    func testValidGraphemeBoundariesRoundTripAcrossIndexSystems() {
        let text = "A😊é👨‍👩‍👧Z"
        let boundaries = Array(text.indices) + [text.endIndex]

        for index in boundaries {
            let scalarOffset = TextIndexConverter.stringIndexToScalarIndex(index, in: text)
            let utf16Offset = TextIndexConverter.utf16Offset(of: index, in: text)

            XCTAssertEqual(TextIndexConverter.scalarIndexToStringIndex(scalarOffset, in: text), index)
            XCTAssertEqual(TextIndexConverter.stringIndex(forUTF16Offset: utf16Offset, in: text), index)
        }
    }

    private func assertRange(
        _ range: CFRange?,
        location: Int,
        length: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let range else {
            XCTFail("Expected a valid CFRange", file: file, line: line)
            return
        }

        XCTAssertEqual(range.location, location, file: file, line: line)
        XCTAssertEqual(range.length, length, file: file, line: line)
    }
}
