import XCTest
import CryptoKit
@testable import DogBarCore

final class LicenseEntitlementTests: XCTestCase {
    func testNodeSignedEntitlementInteroperability() throws {
        guard let path = ProcessInfo.processInfo.environment["DOGBAR_LICENSE_FIXTURE"] else {
            throw XCTSkip("Run licensing/scripts/native-test-fixture.mjs and set DOGBAR_LICENSE_FIXTURE for cross-language verification.")
        }
        struct Fixture: Decodable { let token: String; let publicKey: String; let keyID: String; let installationId: String; let now: Double }
        let f = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let c = LicenseConfiguration(apiURL: URL(string: "https://licenses.example.com")!, publicKey: try XCTUnwrap(Data(base64URL: f.publicKey)), keyID: f.keyID, environment: "sandbox", required: true)
        XCTAssertEqual(try LicenseVerifier.verify(f.token, configuration: c, installationID: try XCTUnwrap(UUID(uuidString: f.installationId)), now: Date(timeIntervalSince1970: f.now)).sub, "lic_interop")
    }
    private let installation = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private func fixture(environment: String = "sandbox", expiry: TimeInterval = 2_000_000_000) throws -> (String, LicenseConfiguration) {
        let key = Curve25519.Signing.PrivateKey()
        let config = LicenseConfiguration(apiURL: URL(string: "https://licenses.example.com")!, publicKey: key.publicKey.rawRepresentation,
                                          keyID: "test-1", environment: "sandbox", required: true)
        let b64: (Data) -> String = { $0.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
        let header = b64(try JSONSerialization.data(withJSONObject: ["alg": "EdDSA", "typ": "JWT", "kid": "test-1"]))
        let payload = b64(try JSONSerialization.data(withJSONObject: ["iss": "dogbar-licensing", "aud": "dev.hristijan.dogbar", "sub": "lic_test",
            "activationId": "act_test", "installationId": installation.uuidString.lowercased(), "environment": environment,
            "iat": 1_999_000_000, "renewAfter": 1_999_600_000, "exp": expiry]))
        let message = "\(header).\(payload)"
        return ("\(message).\(b64(try key.signature(for: Data(message.utf8))))", config)
    }
    func testSignedEntitlementActivatesOnlyBoundInstallation() throws {
        let (token, config) = try fixture()
        let now = Date(timeIntervalSince1970: 1_999_100_000)
        XCTAssertEqual(try LicenseVerifier.verify(token, configuration: config, installationID: installation, now: now).sub, "lic_test")
        XCTAssertThrowsError(try LicenseVerifier.verify(token, configuration: config, installationID: UUID(), now: now))
    }
    func testExpiredAndFutureEntitlementsAreRejected() throws {
        let (token, config) = try fixture()
        XCTAssertThrowsError(try LicenseVerifier.verify(token, configuration: config, installationID: installation, now: Date(timeIntervalSince1970: 2_000_000_001)))
        XCTAssertThrowsError(try LicenseVerifier.verify(token, configuration: config, installationID: installation, now: Date(timeIntervalSince1970: 1_998_000_000)))
    }
    func testSandboxEntitlementCannotUnlockLiveBuild() throws {
        let (token, c) = try fixture()
        let live = LicenseConfiguration(apiURL: c.apiURL, publicKey: c.publicKey, keyID: c.keyID, environment: "live", required: true)
        XCTAssertThrowsError(try LicenseVerifier.verify(token, configuration: live, installationID: installation, now: Date(timeIntervalSince1970: 1_999_100_000)))
    }
    func testTamperedTokenIsRejected() throws {
        let (token, config) = try fixture()
        let pieces = token.split(separator: "."); let changed = "\(pieces[0]).e30.\(pieces[2])"
        XCTAssertThrowsError(try LicenseVerifier.verify(changed, configuration: config, installationID: installation))
        XCTAssertThrowsError(try LicenseVerifier.verify(String(repeating: "x", count: 9000), configuration: config, installationID: installation))
    }
}
