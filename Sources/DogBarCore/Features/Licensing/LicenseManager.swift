import AppKit
import Combine
import Security

struct LicenseCredential: Codable {
    var installationID: UUID
    var activationToken: String?
    var entitlement: String?
    var lastObservedTime: Date
}

protocol LicenseCredentialStore {
    func load(account: String) throws -> LicenseCredential?
    func save(_ credential: LicenseCredential, account: String) throws
}

struct LicenseKeychain: LicenseCredentialStore {
    static let service = "dev.hristijan.dogbar.licensing"
    func load(account: String) throws -> LicenseCredential? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CocoaError(.fileReadNoPermission) }
        return try JSONDecoder().decode(LicenseCredential.self, from: data)
    }
    func save(_ credential: LicenseCredential, account: String) throws {
        let data = try JSONEncoder().encode(credential)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service, kSecAttrAccount as String: account]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw CocoaError(.fileWriteNoPermission) }
        } else if update != errSecSuccess { throw CocoaError(.fileWriteNoPermission) }
    }
}

private final class LicenseNetworkPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Activation keys/tokens must never follow an HTTP redirect to another host.
        completionHandler(nil)
    }
}

/// Activation for paid builds only. Use `AppAccess` for the access decision; it creates this
/// only when the signed build is paid.
@MainActor public final class LicenseManager: ObservableObject {
    public let configuration: LicenseConfiguration?
    @Published public private(set) var isActivated = false
    @Published public private(set) var busy = false
    @Published public private(set) var message = ""
    @Published public private(set) var expiresAt: Date?
    public var required: Bool { configuration?.required ?? false }
    public var allowsFeatures: Bool { !required || isActivated && (expiresAt ?? .distantPast) > now() }
    public var canRefresh: Bool { credential?.activationToken != nil }
    private var credential: LicenseCredential?
    private var checkTask: Task<Void, Never>?
    private var account: String { "\(configuration?.environment ?? "unconfigured"):\(configuration?.apiURL.host ?? "none")" }
    private let session: URLSession
    private let credentialStore: any LicenseCredentialStore
    private let now: () -> Date

    public convenience init(configuration: LicenseConfiguration?, session: URLSession? = nil) {
        self.init(configuration: configuration, session: session, credentialStore: LicenseKeychain(), now: Date.init)
    }
    init(configuration: LicenseConfiguration?, session: URLSession?, credentialStore: any LicenseCredentialStore, now: @escaping () -> Date) {
        self.configuration = configuration
        self.credentialStore = credentialStore
        self.now = now
        self.session = session ?? URLSession(configuration: .ephemeral, delegate: LicenseNetworkPolicy(), delegateQueue: nil)
        guard configuration != nil else { message = "Licensing is not configured in this build."; return }
        do {
            credential = try credentialStore.load(account: account) ?? LicenseCredential(installationID: UUID(), lastObservedTime: now())
            try save()
            validateCached()
        } catch { message = "Could not read the license from Keychain. Unlock your login Keychain and try again." }
    }
    public func start() {
        guard configuration != nil, checkTask == nil else { return }
        checkTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                do { try await Task.sleep(for: .seconds(6 * 3600)) } catch { break }
            }
        }
    }
    public func stop() { checkTask?.cancel(); checkTask = nil }
    private func save() throws { if let credential { try credentialStore.save(credential, account: account) } }
    private func validateCached() {
        guard let configuration, let credential, let token = credential.entitlement else {
            isActivated = false; expiresAt = nil; message = "Enter your license key to activate this Mac."; return
        }
        do {
            guard now().timeIntervalSince(credential.lastObservedTime) > -300 else { throw LicenseValidationError.invalid }
            let claims = try LicenseVerifier.verify(token, configuration: configuration, installationID: credential.installationID, now: now())
            isActivated = true; expiresAt = Date(timeIntervalSince1970: claims.exp)
            message = "License active on this Mac."
        } catch { isActivated = false; expiresAt = nil; message = "Connect to the internet to refresh this Mac’s activation." }
    }
    private struct APIResponse: Decodable { var entitlement: String?; var activationToken: String?; var message: String?; var error: String? }
    private struct APIError: LocalizedError {
        let status: Int; let detail: String
        var errorDescription: String? { detail }
    }
    private func request(_ route: String, body: [String: String]) async throws -> APIResponse {
        guard let configuration else { throw APIError(status: 503, detail: "Licensing is not configured.") }
        var request = URLRequest(url: configuration.apiURL.appendingPathComponent("api/licenses/\(route)"))
        request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count < 16384 else { throw APIError(status: 503, detail: "Unexpected license service response.") }
        let value = try JSONDecoder().decode(APIResponse.self, from: data)
        guard http.statusCode == 200 else { throw APIError(status: http.statusCode, detail: value.message ?? "License service unavailable.") }
        return value
    }
    public func activate(key: String) async {
        guard !busy, var current = credential, let configuration else { return }
        busy = true; defer { busy = false }
        do {
            let value = try await request("activate", body: ["key": key.trimmingCharacters(in: .whitespacesAndNewlines),
                "installationId": current.installationID.uuidString.lowercased(), "deviceName": Host.current().localizedName ?? "Mac"])
            guard let token = value.entitlement, let activation = value.activationToken else { throw LicenseValidationError.invalid }
            _ = try LicenseVerifier.verify(token, configuration: configuration, installationID: current.installationID, now: now())
            current.entitlement = token; current.activationToken = activation; current.lastObservedTime = now()
            try credentialStore.save(current, account: account); credential = current; validateCached()
        } catch { message = error.localizedDescription }
    }
    public func check(force: Bool = false) async {
        guard !busy, var current = credential, let configuration else { return }
        validateCached()
        guard let activation = current.activationToken else { return }
        if !force, let token = current.entitlement,
           let claims = try? LicenseVerifier.verify(token, configuration: configuration, installationID: current.installationID, now: now()),
           now().timeIntervalSince1970 < claims.renewAfter {
            current.lastObservedTime = max(current.lastObservedTime, now()); credential = current; try? save(); return
        }
        busy = true; defer { busy = false }
        do {
            let value = try await request("renew", body: ["activationToken": activation,"installationId": current.installationID.uuidString.lowercased()])
            guard let token = value.entitlement else { throw LicenseValidationError.invalid }
            _ = try LicenseVerifier.verify(token, configuration: configuration, installationID: current.installationID, now: now())
            current.entitlement = token; current.lastObservedTime = now()
            try credentialStore.save(current, account: account); credential = current; validateCached()
        } catch let error as APIError where error.status == 403 {
            current.entitlement = nil; current.activationToken = nil; credential = current; try? save(); validateCached(); message = error.detail
        } catch {
            message = isActivated ? "Couldn’t reach the license service. Your saved activation still works offline." : "Connect to the internet and try checking your license again."
        }
    }
    public func deactivate() async {
        guard !busy, var current = credential, let activation = current.activationToken else { return }
        busy = true; defer { busy = false }
        do {
            _ = try await request("deactivate", body: ["activationToken": activation,"installationId": current.installationID.uuidString.lowercased()])
            current.entitlement = nil; current.activationToken = nil; credential = current; try save(); validateCached()
        } catch { message = "Couldn’t deactivate this Mac. Try again online, or remove it on the license management page." }
    }
}
