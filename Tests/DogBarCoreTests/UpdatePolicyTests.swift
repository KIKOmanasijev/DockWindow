import Foundation
import XCTest
@testable import DogBarCore

final class UpdatePolicyTests: XCTestCase {
    let macOS26 = OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)
    let key = "PNudz/8nyHP1fR6ADTVhfXAciGkEoyOpTEgHkJ8Hb/0="

    func rejects(_ expected: UpdateRejection, _ body: () throws -> Void, line: UInt = #line) {
        XCTAssertThrowsError(try body(), line: line) { XCTAssertEqual($0 as? UpdateRejection, expected, line: line) }
    }

    func info(_ changes: [String: Any] = [:]) -> [String: Any] {
        var value: [String: Any] = ["DogBarUpdateChannel": "preview", "CFBundleVersion": "7", "SUPublicEDKey": key,
                                    "SUFeedURL": "https://dogbar.hristijan.dev/appcast.xml", "SUVerifyUpdateBeforeExtraction": true,
                                    "SURequireSignedFeed": true, "SUAutomaticallyUpdate": false, "SUAllowsAutomaticUpdates": false]
        value.merge(changes) { $1 }
        return value
    }

    func candidate(_ path: String = "/downloads/DogBar-0.1.0-preview.7-arm64.dmg", build: String = "8", channel: String? = "preview",
                   minimum: String? = "26.0", hardware: Set<String> = ["arm64"], host: String = "dogbar.hristijan.dev") -> UpdateCandidate {
        UpdateCandidate(fileURL: URL(string: "https://\(host)\(path)"), build: build, channel: channel,
                        minimumSystemVersion: minimum, hardwareRequirements: hardware)
    }

    func testConfigurationRequiresSignedFeedAndManualInstallSettings() {
        XCTAssert(UpdateConfiguration(info: info())?.channel == .preview)
        XCTAssert(UpdateConfiguration(info: info(["DogBarUpdateChannel": "stable"]))?.channel == .stable)
        for change: [String: Any] in [["DogBarUpdateChannel": "beta"], ["SURequireSignedFeed": false], ["SUVerifyUpdateBeforeExtraction": false],
                                      ["SUAutomaticallyUpdate": true], ["SUAllowsAutomaticUpdates": true], ["SUPublicEDKey": "short"],
                                      ["SUFeedURL": "http://dogbar.hristijan.dev/appcast.xml"], ["CFBundleVersion": "0"]] {
            XCTAssert(UpdateConfiguration(info: info(change)) == nil)
        }
        var missing = info(); missing["DogBarUpdateChannel"] = nil
        XCTAssert(UpdateConfiguration(info: missing) == nil)
    }

    func testPreviewAcceptsNewerSameOriginAppleSiliconBuilds() throws {
        try UpdatePolicy.check(candidate(), channel: .preview, currentBuild: 7, runningOS: macOS26)
        try UpdatePolicy.check(candidate("/downloads/DogBar-1.0.0-arm64.dmg", channel: nil), channel: .preview, currentBuild: 7, runningOS: macOS26)
    }

    func testStableNeverAcceptsPreviewItems() {
        rejects(UpdateRejection.wrongChannel) {
            try UpdatePolicy.check(candidate("/downloads/DogBar-1.0.0-arm64.dmg"), channel: .stable, currentBuild: 7, runningOS: macOS26)
        }
        rejects(UpdateRejection.untrustedLocation) {
            try UpdatePolicy.check(candidate(channel: nil), channel: .stable, currentBuild: 7, runningOS: macOS26)
        }
    }

    func testRejectsDowngradesAndSameBuild() {
        for build in ["7", "6", "0", "07", "8a", ""] {
            rejects(UpdateRejection.notNewer) {
                try UpdatePolicy.check(candidate(build: build), channel: .preview, currentBuild: 7, runningOS: macOS26)
            }
        }
    }

    func testRejectsForeignOrUnversionedLocations() {
        for (path, host) in [("/downloads/DogBar-0.1.0-preview.7-arm64.dmg", "example.com"), ("/DogBar-0.1.0-preview.7-arm64.dmg", "dogbar.hristijan.dev"),
                             ("/downloads/DogBar-latest-arm64.dmg", "dogbar.hristijan.dev"), ("/downloads/DogBar-0.1.0-preview.7-x86_64.dmg", "dogbar.hristijan.dev"),
                             ("/downloads/../DogBar-0.1.0-preview.7-arm64.dmg", "dogbar.hristijan.dev")] {
            rejects(UpdateRejection.untrustedLocation) {
                try UpdatePolicy.check(candidate(path, host: host), channel: .preview, currentBuild: 7, runningOS: macOS26)
            }
        }
        let insecure = UpdateCandidate(fileURL: URL(string: "http://dogbar.hristijan.dev/downloads/DogBar-0.1.0-preview.7-arm64.dmg"),
                                       build: "8", channel: "preview", minimumSystemVersion: "26.0", hardwareRequirements: ["arm64"])
        rejects(UpdateRejection.untrustedLocation) { try UpdatePolicy.check(insecure, channel: .preview, currentBuild: 7, runningOS: macOS26) }
    }

    func testRejectsIncompatibleSystemsAndArchitectures() {
        for minimum in ["27.0", "26.2", nil, "12.0", "26.x"] as [String?] {
            rejects(UpdateRejection.operatingSystem) {
                try UpdatePolicy.check(candidate(minimum: minimum), channel: .preview, currentBuild: 7, runningOS: macOS26)
            }
        }
        rejects(UpdateRejection.architecture) {
            try UpdatePolicy.check(candidate(hardware: []), channel: .preview, currentBuild: 7, runningOS: macOS26)
        }
    }

    func testPublicKeyShape() {
        XCTAssert(UpdatePolicy.isPublicKey(key))
        XCTAssert(!UpdatePolicy.isPublicKey(String(key.dropLast(2)) + "=="))
        XCTAssert(!UpdatePolicy.isPublicKey("not a key"))
    }
}
