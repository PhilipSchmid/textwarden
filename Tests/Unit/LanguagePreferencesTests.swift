// LanguagePreferencesTests.swift

@testable import TextWarden
import XCTest

@MainActor
final class LanguagePreferencesTests: XCTestCase {
    func testDetectorCatalogContainsAllLanguagesAndExcludesEnglishFromPreferences() {
        let detectorLanguages = GrammarEngine.supportedLanguages
        let preferenceLanguages = UserPreferences.availableLanguages

        XCTAssertEqual(detectorLanguages.count, 70)
        XCTAssertEqual(Set(detectorLanguages.map(\.code)).count, 70)
        XCTAssertEqual(preferenceLanguages.count, 69)
        XCTAssertFalse(preferenceLanguages.contains { $0.code == "eng" })

        let latvian = preferenceLanguages.first { $0.code == "lav" }
        XCTAssertEqual(latvian?.englishName, "Latvian")
        XCTAssertEqual(latvian?.nativeName, "Latviešu")
    }

    func testLegacyLanguageNamesMigrateToISO639Codes() {
        let migrated = UserPreferences.migratedLanguageCodes(
            from: ["German", "Latviešu", "spa", "English", "Unknown"]
        )

        XCTAssertEqual(migrated, ["deu", "lav", "spa"])
    }

    func testLanguageCodeMigrationIsIdempotent() {
        let codes: Set = ["deu", "lav", "spa"]

        XCTAssertEqual(UserPreferences.migratedLanguageCodes(from: codes), codes)
    }

    func testLatvianMatchesEnglishNativeAndCodeSearches() throws {
        let latvian = try XCTUnwrap(UserPreferences.availableLanguages.first { $0.code == "lav" })

        XCTAssertTrue(latvian.matches("Latvian"))
        XCTAssertTrue(latvian.matches("latviesu"))
        XCTAssertTrue(latvian.matches("lav"))
        XCTAssertFalse(latvian.matches("Lithuanian"))
    }
}
