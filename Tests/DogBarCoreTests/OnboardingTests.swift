import XCTest
@testable import DogBarCore

final class OnboardingTests: XCTestCase {
    private let ready = OnboardingPlan.Inputs(installed: true, accessibility: true, screenRecording: true, privacyAsked: true)

    func testFirstRunShowsFeaturesBeforePermissionsAndInstallOnlyWhenNeeded() {
        XCTAssertEqual(OnboardingPlan.steps(for: .firstRun, ready),
                       [.welcome, .desktops, .previews, .switcher, .accessibility, .screenRecording, .privacy, .ready])
        var dmg = ready; dmg.installed = false
        let steps = OnboardingPlan.steps(for: .firstRun, dmg)
        XCTAssertEqual(steps.firstIndex(of: .install), steps.firstIndex(of: .accessibility).map { $0 - 1 })
    }

    func testRecoveryShowsOnlyWhatIsMissing() {
        var inputs = ready; inputs.screenRecording = false
        XCTAssertEqual(OnboardingPlan.steps(for: .recovery, inputs), [.screenRecording, .ready])
        XCTAssertEqual(OnboardingPlan.steps(for: .privacyOnly, inputs), [.privacy])
    }

    func testLaunchModeNeverRepeatsTheTourForFinishedSetups() {
        XCTAssertEqual(OnboardingPlan.launchMode(tourCompleted: false, permissionsGranted: true, installed: true, privacyAsked: true), .firstRun)
        XCTAssertEqual(OnboardingPlan.launchMode(tourCompleted: true, permissionsGranted: false, installed: true, privacyAsked: true), .recovery)
        XCTAssertEqual(OnboardingPlan.launchMode(tourCompleted: true, permissionsGranted: true, installed: false, privacyAsked: true), .recovery)
        XCTAssertEqual(OnboardingPlan.launchMode(tourCompleted: true, permissionsGranted: true, installed: true, privacyAsked: false), .privacyOnly)
        XCTAssertNil(OnboardingPlan.launchMode(tourCompleted: true, permissionsGranted: true, installed: true, privacyAsked: true))
    }

    func testResumeFallsForwardWhenTheSavedStepIsGone() {
        let steps: [OnboardingStep] = [.welcome, .desktops, .previews, .switcher, .accessibility, .screenRecording, .privacy, .ready]
        XCTAssertEqual(OnboardingPlan.resumeIndex(for: .screenRecording, in: steps), 5)
        XCTAssertEqual(OnboardingPlan.resumeIndex(for: .install, in: steps), 4)
        XCTAssertEqual(OnboardingPlan.resumeIndex(for: nil, in: steps), 0)
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
        store.resumeStep = .screenRecording
        // A relaunch with its own state is never treated as an existing install, even with other keys present.
        defaults.set(true, forKey: "DogBar.telemetryAsked")
        let relaunched = OnboardingStore(defaults: defaults, domainName: suite)
        XCTAssertFalse(relaunched.isCompleted)
        XCTAssertEqual(relaunched.resumeStep, .screenRecording)
        relaunched.markCompleted()
        XCTAssertTrue(relaunched.isCompleted)
        XCTAssertNil(relaunched.resumeStep)
    }
}
