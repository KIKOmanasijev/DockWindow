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
}
