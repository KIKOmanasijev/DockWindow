import XCTest
@testable import DogBarCore

final class DockLaunchHandoffTests: XCTestCase {
    func testWindowDiscoveryDoesNotRetireLaunchBeforeDesktopDiscovery() {
        var snapshot = WindowSnapshot(apps: [TrackedApp(pid: 42)], windows: [TrackedWindow(id: 10, pid: 42)])
        XCTAssertFalse(DockLaunchHandoffPolicy.isReady(pid: 42, snapshot: snapshot, requiresMembership: true))
        snapshot.windows[0].spaceIDs = [1]
        XCTAssertTrue(DockLaunchHandoffPolicy.isReady(pid: 42, snapshot: snapshot, requiresMembership: true))
    }
    func testAllDesktopScopeDoesNotRequireMembershipButStillRequiresAppAndWindow() {
        var snapshot = WindowSnapshot(windows: [TrackedWindow(id: 10, pid: 42)])
        XCTAssertFalse(DockLaunchHandoffPolicy.isReady(pid: 42, snapshot: snapshot, requiresMembership: false))
        snapshot.apps = [TrackedApp(pid: 42)]
        XCTAssertTrue(DockLaunchHandoffPolicy.isReady(pid: 42, snapshot: snapshot, requiresMembership: false))
        snapshot.windows = []
        XCTAssertFalse(DockLaunchHandoffPolicy.isReady(pid: 42, snapshot: snapshot, requiresMembership: false))
    }
    func testSpawnedLaunchPlaceholderStaysOnItsLaunchDesktop() {
        let launch = TrackedApp(pid: 42, bundleIdentifier: "com.example.app", lastActiveSpaceIDs: [1])
        XCTAssertTrue(DockLaunchHandoffPolicy.isVisible(launch, scope: .currentDesktop, currentSpaceIDs: [1, 5]))
        XCTAssertFalse(DockLaunchHandoffPolicy.isVisible(launch, scope: .currentDesktop, currentSpaceIDs: [2]))
        XCTAssertTrue(DockLaunchHandoffPolicy.isVisible(launch, scope: .allDesktops, currentSpaceIDs: [2]))
        // Unknown topology must not hide a real launch.
        XCTAssertTrue(DockLaunchHandoffPolicy.isVisible(launch, scope: .currentDesktop, currentSpaceIDs: []))
        XCTAssertTrue(DockLaunchHandoffPolicy.isVisible(TrackedApp(pid: 42), scope: .currentDesktop, currentSpaceIDs: [2]))
    }
    private let appInfo: [String: Any] = ["CFBundleIdentifier": "com.example.app", "CFBundleExecutable": "Example",
                                          "CFBundlePackageType": "APPL", "CFBundleName": "Example"]
    func testSpawnedTopLevelAppExecutableIsALaunchCandidate() {
        let candidate = LaunchCandidatePolicy.candidate(pid: 7, parentPID: 1, executablePath: "/Applications/Example.app/Contents/MacOS/Example",
                                                        serviceName: "application.com.example.app.1.2", info: appInfo, excludingBundleIdentifier: "dev.hristijan.dogbar")
        XCTAssertEqual(candidate, LaunchCandidate(pid: 7, bundleIdentifier: "com.example.app", name: "Example",
                                                  bundleURL: URL(fileURLWithPath: "/Applications/Example.app", isDirectory: true)))
        // Platform apps hide their environment; an unknown job label is still a launch.
        XCTAssertNotNil(LaunchCandidatePolicy.candidate(pid: 7, parentPID: 1, executablePath: "/Applications/Example.app/Contents/MacOS/Example",
                                                        info: appInfo, excludingBundleIdentifier: nil))
    }
    func testHelpersAgentsAndNonLaunchServicesProcessesAreNotLaunchCandidates() {
        let path = "/Applications/Example.app/Contents/MacOS/Example"
        func candidate(_ path: String, parent: pid_t = 1, service: String? = nil, info: [String: Any]? = nil, own: String? = nil) -> LaunchCandidate? {
            LaunchCandidatePolicy.candidate(pid: 7, parentPID: parent, executablePath: path, serviceName: service, info: info ?? appInfo, excludingBundleIdentifier: own)
        }
        XCTAssertNil(candidate(path, parent: 500), "Terminal-run binaries check in normally")
        XCTAssertNil(candidate(path, service: "com.example.agent"), "LaunchAgent using the app executable")
        XCTAssertNil(candidate("/Applications/Example.app/Contents/Frameworks/Example Helper.app/Contents/MacOS/Example Helper"))
        XCTAssertNil(candidate("/Applications/Example.app/Contents/MacOS/example-daemon"), "secondary executable")
        XCTAssertNil(candidate("/Applications/Example.app/Contents/XPCServices/Fetch.xpc/Contents/MacOS/Fetch"))
        XCTAssertNil(candidate(LaunchCandidatePolicy.launchTrampoline))
        XCTAssertNil(candidate(path, info: appInfo.merging(["LSUIElement": true]) { $1 }))
        XCTAssertNil(candidate(path, info: appInfo.merging(["LSUIElement": "1"]) { $1 }))
        XCTAssertNil(candidate(path, info: appInfo.merging(["LSBackgroundOnly": NSNumber(value: 1)]) { $1 }))
        XCTAssertNil(candidate(path, own: "com.example.app"), "DogBar itself")
        XCTAssertNil(LaunchCandidatePolicy.candidate(pid: 7, parentPID: 1, executablePath: path, info: nil, excludingBundleIdentifier: nil))
    }
}
