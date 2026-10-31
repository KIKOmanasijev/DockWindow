import XCTest
@testable import DogBarCore

final class WindowTitleFormatterTests: XCTestCase {
    func testDropsTheAppNameWhereThePreviewAlreadyShowsIt() {
        XCTAssertEqual(WindowTitleFormatter.withoutAppName("Dimitris Kountanis - Slack", appName: "Slack"), "Dimitris Kountanis")
        XCTAssertEqual(WindowTitleFormatter.withoutAppName("Inbox \u{2014} Mail", appName: "Mail"), "Inbox")
        XCTAssertEqual(WindowTitleFormatter.withoutAppName("Slack | #general", appName: "Slack"), "#general")
        XCTAssertEqual(WindowTitleFormatter.withoutAppName("README.md - dogbar - Visual Studio Code", appName: "Visual Studio Code"), "README.md - dogbar")
    }
    func testKeepsTitlesThatAreOnlyTheAppNameOrUnrelated() {
        XCTAssertEqual(WindowTitleFormatter.withoutAppName("Slack", appName: "Slack"), "Slack")
        XCTAssertEqual(WindowTitleFormatter.withoutAppName("Lisbon day plan", appName: "Safari"), "Lisbon day plan")
        XCTAssertEqual(WindowTitleFormatter.withoutAppName("Slackers - Notes", appName: "Slack"), "Slackers - Notes")
        XCTAssertEqual(WindowTitleFormatter.withoutAppName("   ", appName: "Notes"), "Untitled window")
        XCTAssertEqual(WindowTitleFormatter.withoutAppName("Untitled", appName: nil), "Untitled")
    }
}
