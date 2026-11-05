import XCTest
import CryptoKit
@testable import DogBarCore

private final class MemoryLicenseStore: LicenseCredentialStore {
    var value: LicenseCredential?
    var failWrites = false
    func load(account: String) throws -> LicenseCredential? { value }
    func save(_ credential: LicenseCredential, account: String) throws {
        if failWrites { throw CocoaError(.fileWriteNoPermission) }
        value = credential
    }
}

private final class LicenseStubProtocol: URLProtocol {
    static var respond: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.respond!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor final class LicenseManagerTests: XCTestCase {
    private let key = Curve25519.Signing.PrivateKey()
    private let installation = UUID()
    private let initialTime = Date(timeIntervalSince1970: 1_800_000_000)
    private var configuration: LicenseConfiguration {
        .init(apiURL: URL(string: "https://licenses.example.test")!, publicKey: key.publicKey.rawRepresentation, keyID: "test", environment: "sandbox", required: true)
    }
    private func token(issued: Date, for device: UUID? = nil) throws -> String {
        func encode(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
        let header = encode(try JSONSerialization.data(withJSONObject: ["alg": "EdDSA", "typ": "JWT", "kid": "test"]))
        let payload = encode(try JSONSerialization.data(withJSONObject: ["iss": "dogbar-licensing", "aud": "dev.hristijan.dogbar", "sub": "lic_test", "activationId": "act_test", "installationId": (device ?? installation).uuidString.lowercased(), "environment": "sandbox", "iat": issued.timeIntervalSince1970, "renewAfter": issued.addingTimeInterval(7 * 86400).timeIntervalSince1970, "exp": issued.addingTimeInterval(37 * 86400).timeIntervalSince1970]))
        let message = header + "." + payload
        return message + "." + encode(try key.signature(for: Data(message.utf8)))
    }
    private func manager(store: MemoryLicenseStore, now: @escaping () -> Date) -> LicenseManager {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [LicenseStubProtocol.self]
        return LicenseManager(configuration: configuration, session: URLSession(configuration: sessionConfiguration), credentialStore: store, now: now)
    }
    private func store(entitlement: String? = nil, activation: String? = nil) -> MemoryLicenseStore {
        let store = MemoryLicenseStore()
        store.value = .init(installationID: installation, activationToken: activation, entitlement: entitlement, lastObservedTime: initialTime)
        return store
    }
    private func reply(_ value: [String: String]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }

    func testActivationPersistsAndRestoresWithoutSavingLicenseKey() async throws {
        let entitlement = try token(issued: initialTime), data = try reply(["entitlement": entitlement, "activationToken": "device-token"])
        LicenseStubProtocol.respond = { request in
            XCTAssertEqual(request.url?.path, "/api/licenses/activate")
            XCTAssertEqual(request.httpMethod, "POST")
            return (200, data)
        }
        let storage = store(), manager = manager(store: storage, now: { self.initialTime })
        XCTAssertFalse(manager.allowsFeatures)
        await manager.activate(key: "DOG-example")
        XCTAssertTrue(manager.isActivated)
        XCTAssertTrue(manager.allowsFeatures)
        XCTAssertEqual(storage.value?.activationToken, "device-token")
        XCTAssertFalse(String(data: try JSONEncoder().encode(storage.value), encoding: .utf8)!.contains("DOG-example"))
        let restored = self.manager(store: storage, now: { self.initialTime })
        XCTAssertTrue(restored.isActivated)
    }
    func testWrongDeviceSignatureCannotActivate() async throws {
        let data = try reply(["entitlement": token(issued: initialTime, for: UUID()), "activationToken": "device-token"])
        LicenseStubProtocol.respond = { _ in (200, data) }
        let storage = store(), manager = manager(store: storage, now: { self.initialTime })
        await manager.activate(key: "DOG-example")
        XCTAssertFalse(manager.allowsFeatures)
        XCTAssertNil(storage.value?.activationToken)
    }
    func testKeychainWriteFailureDoesNotClaimActivationWasSaved() async throws {
        let data = try reply(["entitlement": token(issued: initialTime), "activationToken": "device-token"])
        LicenseStubProtocol.respond = { _ in (200, data) }
        let storage = store(), manager = manager(store: storage, now: { self.initialTime })
        storage.failWrites = true
        await manager.activate(key: "DOG-example")
        XCTAssertFalse(manager.isActivated)
        XCTAssertFalse(manager.canRefresh)
        XCTAssertNil(storage.value?.activationToken)
    }
    func testDeviceLimitMessageIsShown() async throws {
        let data = try reply(["error": "device_limit", "message": "Both Mac activations are in use."])
        LicenseStubProtocol.respond = { _ in (409, data) }
        let manager = manager(store: store(), now: { self.initialTime })
        await manager.activate(key: "DOG-example")
        XCTAssertFalse(manager.isActivated)
        XCTAssertEqual(manager.message, "Both Mac activations are in use.")
    }
    func testOfflineRenewalKeepsValidCachedActivation() async throws {
        LicenseStubProtocol.respond = { _ in throw URLError(.notConnectedToInternet) }
        let storage = store(entitlement: try token(issued: initialTime), activation: "device-token")
        let manager = manager(store: storage, now: { self.initialTime.addingTimeInterval(8 * 86400) })
        await manager.check()
        XCTAssertTrue(manager.allowsFeatures)
        XCTAssertTrue(manager.message.contains("still works offline"))
    }
    func testExpiredActivationCanRefreshAndRecover() async throws {
        let later = initialTime.addingTimeInterval(38 * 86400)
        let data = try reply(["entitlement": token(issued: later)])
        LicenseStubProtocol.respond = { request in
            XCTAssertEqual(request.url?.path, "/api/licenses/renew")
            return (200, data)
        }
        let storage = store(entitlement: try token(issued: initialTime), activation: "device-token")
        let manager = manager(store: storage, now: { later })
        XCTAssertFalse(manager.isActivated)
        XCTAssertTrue(manager.canRefresh)
        await manager.check(force: true)
        XCTAssertTrue(manager.allowsFeatures)
    }
    func testRevokedActivationStopsFeaturesAndClearsCachedCredentials() async throws {
        let data = try reply(["error": "license_inactive", "message": "This license is no longer active."])
        LicenseStubProtocol.respond = { _ in (403, data) }
        let storage = store(entitlement: try token(issued: initialTime), activation: "device-token")
        let manager = manager(store: storage, now: { self.initialTime })
        await manager.check(force: true)
        XCTAssertFalse(manager.allowsFeatures)
        XCTAssertFalse(manager.canRefresh)
        XCTAssertNil(storage.value?.entitlement)
    }
    func testFailedDeactivationRetainsAccessUntilServerConfirms() async throws {
        LicenseStubProtocol.respond = { _ in throw URLError(.notConnectedToInternet) }
        let manager = manager(store: store(entitlement: try token(issued: initialTime), activation: "device-token"), now: { self.initialTime })
        await manager.deactivate()
        XCTAssertTrue(manager.allowsFeatures)
        LicenseStubProtocol.respond = { request in
            XCTAssertEqual(request.url?.path, "/api/licenses/deactivate")
            return (200, Data("{}".utf8))
        }
        await manager.deactivate()
        XCTAssertFalse(manager.allowsFeatures)
        XCTAssertFalse(manager.canRefresh)
    }
    func testExpiryClosesFeatureGateEvenBetweenScheduledChecks() throws {
        var current = initialTime
        let manager = manager(store: store(entitlement: try token(issued: initialTime), activation: "device-token"), now: { current })
        XCTAssertTrue(manager.allowsFeatures)
        current = current.addingTimeInterval(38 * 86400)
        XCTAssertFalse(manager.allowsFeatures)
    }
}
