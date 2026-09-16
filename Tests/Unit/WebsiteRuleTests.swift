import Foundation
@testable import TextWarden
import XCTest

final class WebsiteRuleTests: XCTestCase {
    @MainActor
    func testWebsiteRulesPreservePortsPathsAndExistingDomains() throws {
        let local = try XCTUnwrap(URL(string: "http://LOCALHOST:8766/Editor?token=secret#selection"))
        XCTAssertEqual(UserPreferences.pageKey(local), "http://localhost:8766/Editor")
        XCTAssertEqual(UserPreferences.siteKey(local), "http://localhost:8766")
        XCTAssertTrue(UserPreferences.websiteRuleMatches("http://localhost:8766/Editor", url: local))
        for other in ["http://localhost:8767/Editor", "http://localhost:8766/editor", "http://localhost:8766/Other", "https://localhost:8766/Editor"] {
            XCTAssertFalse(try UserPreferences.websiteRuleMatches("http://localhost:8766/Editor", url: XCTUnwrap(URL(string: other))))
        }
        XCTAssertTrue(UserPreferences.websiteRuleMatches("localhost", url: local))
        XCTAssertTrue(UserPreferences.websiteRuleMatches("localhost:8766", url: local))
        XCTAssertFalse(UserPreferences.websiteRuleMatches("localhost:8767", url: local))
        XCTAssertEqual(try UserPreferences.siteKey(XCTUnwrap(URL(string: "https://example.com:443/path"))), "https://example.com")
        XCTAssertEqual(try UserPreferences.siteKey(XCTUnwrap(URL(string: "http://example.com:80/path"))), "http://example.com")
        XCTAssertEqual(try UserPreferences.pageKey(XCTUnwrap(URL(string: "http://[::1]:8766/Editor"))), "http://[::1]:8766/Editor")
        XCTAssertTrue(try UserPreferences.websiteRuleMatches("*.example.com", url: XCTUnwrap(URL(string: "https://sub.example.com:8443/path"))))
        XCTAssertFalse(try UserPreferences.websiteRuleMatches("*.example.com", url: XCTUnwrap(URL(string: "https://notexample.com/path"))))
    }

    @MainActor
    func testTimedWebsitePausesPersistExpireAndKeepPortBoundaries() throws {
        let name = "io.textwarden.tests.website-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = UserPreferences(defaults: defaults)
        let url = try XCTUnwrap(URL(string: "http://localhost:8766/editor"))
        let other = try XCTUnwrap(URL(string: "http://localhost:8767/editor"))
        preferences.disableWebsite("http://localhost:8766", duration: .oneHour)
        XCTAssertFalse(preferences.isEnabled(forURL: url))
        XCTAssertTrue(preferences.isEnabled(forURL: other))
        XCTAssertFalse(UserPreferences(defaults: defaults).isEnabled(forURL: url))
        preferences.disableWebsite("http://localhost:8766", duration: .oneHour, now: Date().addingTimeInterval(-3601))
        XCTAssertTrue(preferences.isEnabled(forURL: url))
        preferences.disableWebsite("http://localhost:8766", duration: .indefinite)
        XCTAssertFalse(preferences.isEnabled(forURL: url))
        XCTAssertNil(preferences.websitePausedUntil["http://localhost:8766"])
        preferences.enableWebsite("http://localhost:8766")
        XCTAssertTrue(preferences.isEnabled(forURL: url))
    }
}
