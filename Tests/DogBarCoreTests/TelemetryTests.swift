import XCTest
@testable import DogBarCore

final class TelemetryTests: XCTestCase {
    func testBatchBodyIsAnonymousAndUsesPostHogBatchShape() throws {
        let event = TelemetryEvent(name: "app_active", distinctID: "install-1", timestamp: Date(timeIntervalSince1970: 0),
                                   properties: ["source": "app", "first_launch": true])
        let body = try XCTUnwrap(TelemetryPolicy.batchBody([event], token: "phc_test"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["api_key"] as? String, "phc_test")
        let item = try XCTUnwrap((json["batch"] as? [[String: Any]])?.first)
        XCTAssertEqual(item["event"] as? String, "app_active")
        XCTAssertEqual(item["distinct_id"] as? String, "install-1")
        let properties = try XCTUnwrap(item["properties"] as? [String: Any])
        XCTAssertEqual(properties["$process_person_profile"] as? Bool, false)
        XCTAssertEqual(properties["source"] as? String, "app")
        XCTAssertEqual(properties["first_launch"] as? Bool, true)
    }

    func testDailyDedupeUsesLocalCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Skopje")!
        let lateEvening = Date(timeIntervalSince1970: 1_793_570_000) // 2026-11-01 22:33 local
        XCTAssertEqual(TelemetryPolicy.day(lateEvening, calendar: calendar), "2026-11-01")
        XCTAssertFalse(TelemetryPolicy.isNewDay(last: "2026-11-01", today: "2026-11-01"))
        XCTAssertTrue(TelemetryPolicy.isNewDay(last: nil, today: "2026-11-01"))
    }

    @MainActor func testDisabledSettingSendsNothing() async throws {
        let suite = "TelemetryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.telemetryEnabled = false
        let context = TelemetryContext(appVersion: "1", build: "1", channel: "development", osVersion: "27.0",
                                       architecture: "arm64", isReleaseBundle: true)
        let telemetry = TelemetryService(settings: settings, defaults: defaults, context: context, send: { _ in
            XCTFail("Nothing may be sent while telemetry is off"); return true
        })
        telemetry.start(); telemetry.permissionsGranted(); telemetry.featureUsed(.switcher)
        XCTAssertNil(defaults.string(forKey: "DogBarTelemetry.installID"), "no install ID is created while off")
    }
}
