import XCTest
@testable import DogBarCore

/// Free is the default and the fallback. Paid needs a complete, enforcing license configuration.
@MainActor final class CommercialPolicyTests: XCTestCase {
    private let configuration = LicenseConfiguration(apiURL: URL(string: "https://licenses.example.test")!,
                                                     publicKey: Data(repeating: 1, count: 32), keyID: "test",
                                                     environment: "sandbox", required: true)

    func testEverythingButCompletePaidConfigurationIsFree() {
        XCTAssertEqual(CommercialPolicy.resolve(mode: nil, configuration: nil), .free)
        XCTAssertEqual(CommercialPolicy.resolve(mode: "free", configuration: configuration), .free)
        XCTAssertEqual(CommercialPolicy.resolve(mode: "trial", configuration: configuration), .free)
        XCTAssertEqual(CommercialPolicy.resolve(mode: "paid", configuration: nil), .free)
        let optional = LicenseConfiguration(apiURL: configuration.apiURL, publicKey: configuration.publicKey, keyID: "test",
                                            environment: "sandbox", required: false)
        XCTAssertEqual(CommercialPolicy.resolve(mode: "paid", configuration: optional), .free)
        XCTAssertEqual(CommercialPolicy.resolve(mode: "paid", configuration: configuration), .paid(configuration))
    }

    func testFreeAccessNeverCreatesLicensing() {
        let access = AppAccess(policy: .free) { _ in
            XCTFail("A free build must not create a license manager")
            return LicenseManager(configuration: nil)
        }
        XCTAssertNil(access.license)
        XCTAssertTrue(access.allowsFeatures)
        XCTAssertFalse(SettingsPane.available.contains(.license))
        XCTAssertFalse(SettingsSearchIndex.entries.contains { $0.pane == .license })
    }

    func testPaidAccessFollowsActivation() {
        let access = AppAccess(policy: .paid(configuration)) { LicenseManager(configuration: $0, session: nil,
            credentialStore: EmptyLicenseStore(), now: Date.init) }
        XCTAssertNotNil(access.license)
        XCTAssertFalse(access.allowsFeatures)
    }
}

private struct EmptyLicenseStore: LicenseCredentialStore {
    func load(account: String) throws -> LicenseCredential? { nil }
    func save(_ credential: LicenseCredential, account: String) throws {}
}
