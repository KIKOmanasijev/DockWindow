import XCTest
import Combine
@testable import DogBarCore

final class PermissionsServiceTests: XCTestCase {
    func testUnchangedPermissionPollsDoNotTriggerFeatureAndUIReconciliation() async {
        await MainActor.run {
            var recording = false
            let service = PermissionsService(checkAccessibility: { true }, checkScreenRecording: { recording },
                requestAccessibility: {}, requestScreenRecording: {}, showSettings: { _ in })
            var changes = 0
            let subscription = service.objectWillChange.sink { changes += 1 }
            service.refresh(); service.refresh()
            XCTAssertEqual(changes, 0)
            recording = true; service.refresh()
            XCTAssertEqual(changes, 1)
            XCTAssertTrue(service.isGranted)
            subscription.cancel()
        }
    }

    func testSlowSystemProbeDoesNotBlockUIOrPublishMissingBeforeCompletion() async {
        let gate = DispatchSemaphore(value: 0)
        let started = expectation(description: "Background preflight starts once")
        started.assertForOverFulfill = true
        let completed = expectation(description: "Effective access published")
        let (service, subscription) = await MainActor.run {
            let service = PermissionsService(checkAccessibility: {
                XCTAssertFalse(Thread.isMainThread)
                started.fulfill()
                XCTAssertEqual(gate.wait(timeout: .now() + 5), .success)
                return true
            }, checkScreenRecording: {
                XCTAssertFalse(Thread.isMainThread)
                return true
            }, requestAccessibility: { XCTFail("Polling must not request access") },
                requestScreenRecording: { XCTFail("Polling must not request access") }, showSettings: { _ in },
                workerQueue: DispatchQueue(label: "test.permissions"), checkSigning: { true })
            XCTAssertTrue(service.isChecking)
            XCTAssertFalse(service.hasCheckedPermissions)
            XCTAssertFalse(service.isGranted)
            let subscription = service.$hasCheckedPermissions.dropFirst().filter { $0 }.sink { _ in completed.fulfill() }
            service.refresh(); service.refresh()
            return (service, subscription)
        }
        await fulfillment(of: [started], timeout: 2)
        await MainActor.run { service.refresh() }
        gate.signal()
        await fulfillment(of: [completed], timeout: 2)
        await MainActor.run {
            XCTAssertTrue(service.isGranted)
            XCTAssertFalse(service.isChecking)
            XCTAssertTrue(service.usesAdHocSigning)
            subscription.cancel()
        }
    }

    func testPollingReadsEffectiveAccessWithoutRequestingPermission() async {
        await MainActor.run {
            var accessibility = false, recording = false, requests = 0
            let service = PermissionsService(checkAccessibility: { accessibility }, checkScreenRecording: { recording },
                requestAccessibility: { requests += 1 }, requestScreenRecording: { requests += 1 }, showSettings: { _ in })
            XCTAssertFalse(service.isGranted)
            accessibility = true; service.refresh()
            XCTAssertTrue(service.accessibility)
            XCTAssertFalse(service.isGranted)
            recording = true; service.refresh()
            XCTAssertTrue(service.isGranted)
            accessibility = false; service.refresh()
            XCTAssertFalse(service.isGranted, "Revocation must disable features even after both permissions were granted.")
            XCTAssertEqual(requests, 0)
        }
    }

    func testExplicitButtonsRegisterMissingPermissionsAndRefreshStatus() async {
        await MainActor.run {
            var accessibility = false, recording = false
            var accessibilityRequests = 0, recordingRequests = 0
            var opened: [String] = []
            let service = PermissionsService(checkAccessibility: { accessibility }, checkScreenRecording: { recording },
                requestAccessibility: { accessibilityRequests += 1; accessibility = true },
                requestScreenRecording: { recordingRequests += 1; recording = true }, showSettings: { opened.append($0) })
            service.openAccessibility()
            XCTAssertTrue(service.accessibility)
            XCTAssertFalse(service.screenRecording)
            service.openScreenRecording()
            XCTAssertTrue(service.isGranted)
            service.openAccessibility(); service.openScreenRecording()
            XCTAssertEqual(accessibilityRequests, 1)
            XCTAssertEqual(recordingRequests, 1)
            XCTAssertEqual(opened, ["Privacy_Accessibility", "Privacy_ScreenCapture", "Privacy_Accessibility", "Privacy_ScreenCapture"])
        }
    }

    func testOpeningSettingsDoesNotPretendAccessWasGranted() async {
        await MainActor.run {
            let service = PermissionsService(checkAccessibility: { false }, checkScreenRecording: { false },
                requestAccessibility: {}, requestScreenRecording: {}, showSettings: { _ in }, usesAdHocSigning: true)
            service.openAccessibility(); service.openScreenRecording()
            XCTAssertFalse(service.isGranted)
            XCTAssertTrue(service.usesAdHocSigning)
        }
    }
    func testFirstLaunchMissingAccessIsNotRequestedNotUnavailable() async {
        await MainActor.run {
            let service = PermissionsService(checkAccessibility: { true }, checkScreenRecording: { false },
                requestAccessibility: {}, requestScreenRecording: { XCTFail("Polling must not request access") }, showSettings: { _ in },
                defaults: Self.freshDefaults())
            service.refresh(); service.refresh()
            XCTAssertEqual(service.accessibilityAccess, .granted)
            XCTAssertEqual(service.screenRecordingAccess, .notRequested, "A first launch has simply not asked yet.")
            XCTAssertFalse(service.screenRecordingNeedsRelaunchAfterGrant)
        }
    }

    func testDeclinedOrPendingRequestReportsWaitingAndRelaunchHintWithoutClaimingSuccess() async {
        await MainActor.run {
            var opened: [String] = []
            let service = PermissionsService(checkAccessibility: { true }, checkScreenRecording: { false },
                requestAccessibility: {}, requestScreenRecording: {}, showSettings: { opened.append($0) },
                defaults: Self.freshDefaults())
            service.openScreenRecording()
            XCTAssertEqual(service.screenRecordingAccess, .waitingForUser)
            XCTAssertTrue(service.screenRecordingNeedsRelaunchAfterGrant)
            XCTAssertFalse(service.screenRecording)
            XCTAssertFalse(service.isGranted)
            XCTAssertEqual(opened, ["Privacy_ScreenCapture"])
        }
    }

    func testRequestHistorySurvivesRelaunchButOnlyHintsRelaunchForTheRequestingProcess() async {
        await MainActor.run {
            let defaults = Self.freshDefaults()
            let first = PermissionsService(checkAccessibility: { true }, checkScreenRecording: { false },
                requestAccessibility: {}, requestScreenRecording: {}, showSettings: { _ in }, defaults: defaults)
            first.openScreenRecording()
            var requests = 0
            let second = PermissionsService(checkAccessibility: { true }, checkScreenRecording: { false },
                requestAccessibility: {}, requestScreenRecording: { requests += 1 }, showSettings: { _ in }, defaults: defaults)
            XCTAssertEqual(second.screenRecordingAccess, .waitingForUser)
            XCTAssertFalse(second.screenRecordingNeedsRelaunchAfterGrant)
            second.openScreenRecording()
            XCTAssertEqual(requests, 1, "A new process may ask once; macOS decides whether to prompt.")
        }
    }

    func testRequestFinishesBeforeSettingsOpensAndRepeatedClicksAreSerialized() async {
        let gate = DispatchSemaphore(value: 0)
        let requestStarted = expectation(description: "Request runs off the main thread")
        let settingsOpened = expectation(description: "Pane opens after registration")
        let (service, log) = await MainActor.run { () -> (PermissionsService, EventLog) in
            let log = EventLog()
            let service = PermissionsService(checkAccessibility: { true }, checkScreenRecording: { false },
                requestAccessibility: {}, requestScreenRecording: {
                    XCTAssertFalse(Thread.isMainThread)
                    log.append("request")
                    requestStarted.fulfill()
                    XCTAssertEqual(gate.wait(timeout: .now() + 5), .success)
                }, showSettings: { log.append("settings:\($0)"); settingsOpened.fulfill() },
                workerQueue: DispatchQueue(label: "test.permissions.probe"), defaults: Self.freshDefaults(),
                settingsFallbackDelay: .seconds(30))
            service.openScreenRecording()
            return (service, log)
        }
        await fulfillment(of: [requestStarted], timeout: 2)
        await MainActor.run {
            XCTAssertEqual(service.screenRecordingAccess == .requesting || !service.hasCheckedPermissions, true)
            service.openScreenRecording(); service.openScreenRecording()
            service.refresh()
        }
        gate.signal()
        await fulfillment(of: [settingsOpened], timeout: 2)
        await MainActor.run {
            XCTAssertEqual(log.events, ["request", "settings:Privacy_ScreenCapture"])
        }
    }

    func testBlockedRequestStillOpensSettingsOnceAfterFallbackDelay() async {
        let gate = DispatchSemaphore(value: 0)
        let settingsOpened = expectation(description: "Fallback opens the pane")
        settingsOpened.assertForOverFulfill = true
        let log = EventLog()
        await MainActor.run {
            let service = PermissionsService(checkAccessibility: { false }, checkScreenRecording: { false },
                requestAccessibility: { _ = gate.wait(timeout: .now() + 5) }, requestScreenRecording: {},
                showSettings: { log.append($0); settingsOpened.fulfill() },
                workerQueue: DispatchQueue(label: "test.permissions.probe"), defaults: Self.freshDefaults(),
                settingsFallbackDelay: .milliseconds(50))
            service.openAccessibility()
            XCTAssertEqual(service.accessibilityAccess == .requesting || !service.hasCheckedPermissions, true)
        }
        await fulfillment(of: [settingsOpened], timeout: 2)
        gate.signal()
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(log.events, ["Privacy_Accessibility"])
    }

    func testInstallLocationDistinguishesDiskImageAndTranslocationFromInstalledCopy() {
        XCTAssertEqual(InstallLocation.classify(bundlePath: "/Applications/DogBar.app", isReadOnlyVolume: false), .installed)
        XCTAssertEqual(InstallLocation.classify(bundlePath: "/Users/a/Applications/DogBar.app", isReadOnlyVolume: false), .installed)
        XCTAssertEqual(InstallLocation.classify(bundlePath: "/Volumes/DogBar/DogBar.app", isReadOnlyVolume: true), .diskImage)
        XCTAssertEqual(InstallLocation.classify(
            bundlePath: "/private/var/folders/xy/T/AppTranslocation/0A1B/d/DogBar.app", isReadOnlyVolume: true), .translocated)
        XCTAssertFalse(InstallLocation.diskImage.isInstalled)
    }

    private static func freshDefaults() -> UserDefaults {
        let name = "PermissionsServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var events: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    func append(_ event: String) { lock.lock(); storage.append(event); lock.unlock() }
}
