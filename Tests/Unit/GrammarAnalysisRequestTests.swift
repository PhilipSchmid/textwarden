//
//  GrammarAnalysisRequestTests.swift
//  TextWardenTests
//

import ApplicationServices
@testable import TextWarden
import XCTest

final class GrammarAnalysisRequestTests: XCTestCase {
    private let context = ApplicationContext.application(
        bundleIdentifier: "com.example.editor",
        processID: 42,
        name: "Editor"
    )

    func testRequestMatchesUnchangedAnalysisInputs() {
        let element = AXUIElementCreateSystemWide()
        let request = GrammarAnalysisRequest(
            generation: 7,
            sourceText: "Current text",
            context: context,
            element: element
        )

        XCTAssertTrue(
            request.matches(
                currentGeneration: 7,
                currentText: "Current text",
                currentContext: context,
                currentElement: element
            )
        )
    }

    func testRequestRejectsSupersededGeneration() {
        let request = GrammarAnalysisRequest(
            generation: 7,
            sourceText: "Current text",
            context: context,
            element: nil
        )

        XCTAssertFalse(
            request.matches(
                currentGeneration: 8,
                currentText: "Current text",
                currentContext: context,
                currentElement: nil
            )
        )
    }

    func testRequestRejectsChangedText() {
        let request = GrammarAnalysisRequest(
            generation: 7,
            sourceText: "Old text",
            context: context,
            element: nil
        )

        XCTAssertFalse(
            request.matches(
                currentGeneration: 7,
                currentText: "New text",
                currentContext: context,
                currentElement: nil
            )
        )
    }

    func testRequestRejectsChangedApplicationContext() {
        let request = GrammarAnalysisRequest(
            generation: 7,
            sourceText: "Current text",
            context: context,
            element: nil
        )
        let otherContext = ApplicationContext.application(
            bundleIdentifier: "com.example.other",
            processID: 43,
            name: "Other"
        )

        XCTAssertFalse(
            request.matches(
                currentGeneration: 7,
                currentText: "Current text",
                currentContext: otherContext,
                currentElement: nil
            )
        )
    }

    func testRequestRejectsChangedAccessibilityElement() {
        let element = AXUIElementCreateSystemWide()
        let request = GrammarAnalysisRequest(
            generation: 7,
            sourceText: "Current text",
            context: context,
            element: element
        )

        XCTAssertFalse(
            request.matches(
                currentGeneration: 7,
                currentText: "Current text",
                currentContext: context,
                currentElement: nil
            )
        )
    }
}
