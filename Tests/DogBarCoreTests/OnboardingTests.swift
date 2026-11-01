import XCTest
@testable import DogBarCore

final class OnboardingTests: XCTestCase {
    func testToursEndInOneSetupStepAndRecoveryGoesStraightThere() {
        XCTAssertEqual(OnboardingPlan.steps(for: .firstRun), [.welcome, .desktops, .previews, .switcher, .setup])
        XCTAssertEqual(OnboardingPlan.steps(for: .tour), OnboardingPlan.steps(for: .firstRun))
        XCTAssertEqual(OnboardingPlan.steps(for: .recovery), [.setup])
        XCTAssertEqual(OnboardingPlan.steps(for: .privacyOnly), [.setup])
    }

    func testLaunchModeNeverRepeatsTheTourForFinishedSetups() {
        XCTAssertEqual(OnboardingPlan.launchMode(tourCompleted: false, permissionsGranted: true, installed: true, privacyAsked: true), .firstRun)
        XCTAssertEqual(OnboardingPlan.launchMode(tourCompleted: true, permissionsGranted: false, installed: true, privacyAsked: true), .recovery)
        XCTAssertEqual(OnboardingPlan.launchMode(tourCompleted: true, permissionsGranted: true, installed: false, privacyAsked: true), .recovery)
        XCTAssertEqual(OnboardingPlan.launchMode(tourCompleted: true, permissionsGranted: true, installed: true, privacyAsked: false), .privacyOnly)
        XCTAssertNil(OnboardingPlan.launchMode(tourCompleted: true, permissionsGranted: true, installed: true, privacyAsked: true))
    }

    func testResumeUsesTheSavedStepAndMapsOlderSetupScreens() {
        let steps = OnboardingPlan.steps(for: .firstRun)
        XCTAssertEqual(OnboardingPlan.resumeIndex(for: .previews, in: steps), 2)
        XCTAssertEqual(OnboardingPlan.resumeIndex(for: nil, in: steps), 0)
        XCTAssertEqual(OnboardingStep(persisted: "screenRecording"), .setup)
        XCTAssertNil(OnboardingStep(persisted: "unknown"))
    }

    @MainActor func testExistingInstallIsAdoptedAndFreshInstallIsNot() throws {
        for (legacy, expected) in [(true, true), (false, false)] {
            let suite = "OnboardingTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            if legacy { defaults.set(true, forKey: "DogBar.telemetryAsked") }
            let store = OnboardingStore(defaults: defaults, domainName: suite)
            XCTAssertEqual(store.isCompleted, expected)
            XCTAssertEqual(store.adoptedExistingInstall, expected)
        }
    }

    @MainActor func testResumeStepSurvivesUntilCompletion() throws {
        let suite = "OnboardingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OnboardingStore(defaults: defaults, domainName: suite)
        store.resumeStep = .setup
        // A relaunch with its own state is never treated as an existing install, even with other keys present.
        defaults.set(true, forKey: "DogBar.telemetryAsked")
        let relaunched = OnboardingStore(defaults: defaults, domainName: suite)
        XCTAssertFalse(relaunched.isCompleted)
        XCTAssertEqual(relaunched.resumeStep, .setup)
        relaunched.markCompleted()
        XCTAssertTrue(relaunched.isCompleted)
        XCTAssertNil(relaunched.resumeStep)
    }
}
