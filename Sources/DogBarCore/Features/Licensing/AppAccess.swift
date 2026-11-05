import Combine
import Foundation

/// How this build is distributed, fixed when it is signed. Scripts/license_packaging.py writes
/// `DogBarCommercialMode` from Config/commercial.json. Nothing downloaded at runtime can change it,
/// so a build keeps the access it shipped with.
public enum CommercialPolicy: Sendable, Equatable {
    case free
    case paid(LicenseConfiguration)

    public static let current = resolve(Bundle.main)

    static func resolve(_ bundle: Bundle) -> CommercialPolicy {
        resolve(mode: bundle.object(forInfoDictionaryKey: "DogBarCommercialMode") as? String, configuration: .bundled(bundle))
    }
    /// Only a complete paid configuration enforces activation. Anything else (no key, an unknown
    /// value, or paid without valid licensing) is free, so a packaging mistake never locks anyone out.
    static func resolve(mode: String?, configuration: LicenseConfiguration?) -> CommercialPolicy {
        guard mode == "paid", let configuration, configuration.required else { return .free }
        return .paid(configuration)
    }
    public var isPaid: Bool { if case .paid = self { true } else { false } }
}

/// The one place DogBar decides whether its features may run. A free build creates no license
/// manager: no Keychain item, no network check, and nothing that can turn features off later.
@MainActor public final class AppAccess: ObservableObject {
    public static let shared = AppAccess(policy: .current)
    public let policy: CommercialPolicy
    /// Present only in paid builds.
    public let license: LicenseManager?
    private var forward: AnyCancellable?

    init(policy: CommercialPolicy, makeLicense: @MainActor (LicenseConfiguration) -> LicenseManager = { LicenseManager(configuration: $0) }) {
        self.policy = policy
        if case .paid(let configuration) = policy {
            let license = makeLicense(configuration)
            self.license = license
            forward = license.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        } else {
            license = nil
        }
    }
    public var allowsFeatures: Bool { license?.allowsFeatures ?? true }
    public func start() { license?.start() }
    public func stop() { license?.stop() }
}
