import Foundation
import CryptoKit

public struct LicenseConfiguration: Sendable, Equatable {
    public let apiURL: URL
    public let publicKey: Data
    public let keyID: String
    public let environment: String
    public let required: Bool
    public var manageURL: URL { apiURL.appendingPathComponent("manage") }
    public var purchaseURL: URL { apiURL.appendingPathComponent("buy") }
    public init(apiURL: URL, publicKey: Data, keyID: String, environment: String, required: Bool) {
        self.apiURL = apiURL; self.publicKey = publicKey; self.keyID = keyID
        self.environment = environment; self.required = required
    }
    /// Trust is pinned into the signed application. Never download an untrusted replacement key.
    public static func bundled(_ bundle: Bundle = .main) -> LicenseConfiguration? {
        guard let raw = bundle.object(forInfoDictionaryKey: "DogBarLicenseAPIURL") as? String,
              let url = URL(string: raw), url.scheme == "https", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/",
              let key = bundle.object(forInfoDictionaryKey: "DogBarLicensePublicKey") as? String,
              let data = Data(base64URL: key), data.count == 32,
              let keyID = bundle.object(forInfoDictionaryKey: "DogBarLicenseKeyID") as? String,
              let environment = bundle.object(forInfoDictionaryKey: "DogBarLicenseEnvironment") as? String,
              ["sandbox", "live"].contains(environment) else { return nil }
        return .init(apiURL: url, publicKey: data, keyID: keyID, environment: environment,
                     required: bundle.object(forInfoDictionaryKey: "DogBarLicenseRequired") as? Bool ?? false)
    }
}

public struct LicenseClaims: Codable, Equatable, Sendable {
    public let iss: String
    public let aud: String
    public let sub: String
    public let activationId: String
    public let installationId: String
    public let environment: String
    public let iat: TimeInterval
    public let renewAfter: TimeInterval
    public let exp: TimeInterval
}

public enum LicenseValidationError: LocalizedError {
    case invalid
    public var errorDescription: String? { "The license service returned an invalid activation. Try again or contact support." }
}
public enum LicenseVerifier {
    public static func verify(_ token: String, configuration: LicenseConfiguration, installationID: UUID,
                              now: Date = Date()) throws -> LicenseClaims {
        guard token.utf8.count < 8192 else { throw LicenseValidationError.invalid }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let headerData = Data(base64URL: String(parts[0])),
              let payload = Data(base64URL: String(parts[1])), let signature = Data(base64URL: String(parts[2])),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: String],
              header["alg"] == "EdDSA", header["typ"] == "JWT", header["kid"] == configuration.keyID,
              signature.count == 64 else { throw LicenseValidationError.invalid }
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: configuration.publicKey)
        guard key.isValidSignature(signature, for: Data("\(parts[0]).\(parts[1])".utf8)) else { throw LicenseValidationError.invalid }
        let claims = try JSONDecoder().decode(LicenseClaims.self, from: payload)
        let time = now.timeIntervalSince1970
        guard claims.iss == "dogbar-licensing", claims.aud == "dev.hristijan.dogbar",
              claims.environment == configuration.environment,
              UUID(uuidString: claims.installationId) == installationID,
              claims.sub.hasPrefix("lic_"), claims.activationId.hasPrefix("act_"),
              claims.iat.isFinite, claims.exp.isFinite, claims.renewAfter.isFinite,
              claims.iat <= time + 300, claims.exp > time,
              claims.renewAfter > claims.iat, claims.renewAfter < claims.exp,
              claims.exp - claims.iat <= 90 * 86400 else { throw LicenseValidationError.invalid }
        return claims
    }
}

extension Data {
    init?(base64URL value: String) {
        guard value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        var text = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        self.init(base64Encoded: text)
    }
}
