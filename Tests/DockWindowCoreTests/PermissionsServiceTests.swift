import XCTest
@testable import DockWindowCore

final class PermissionsServiceTests: XCTestCase {
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
