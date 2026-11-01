import Foundation

/// One screen of the onboarding wizard. Raw values are persisted, so never rename a case.
public enum OnboardingStep: String, CaseIterable, Codable, Sendable {
    case welcome, desktops, previews, switcher
    /// Install location (when needed), both permissions and the usage-data choice, on one screen.
    case setup

    /// Accepts steps saved by earlier builds, which had separate setup screens.
    public init?(persisted raw: String) {
        if let step = Self(rawValue: raw) { self = step; return }
        if ["install", "accessibility", "screenRecording", "privacy", "ready"].contains(raw) { self = .setup; return }
        return nil
    }
}

/// Why the wizard is on screen. Only `.firstRun` persists its position and holds features back.
public enum OnboardingMode: Equatable, Sendable {
    /// The first full tour. Resumes at the saved step after a relaunch.
    case firstRun
    /// The full tour replayed from the menu or Settings. Changes no saved state on its own.
    case tour
    /// Setup was finished before, but something is missing now (a permission, or the install location).
    case recovery
    /// Only the usage-data question, for people who finished setup before it existed.
    case privacyOnly
}

/// Pure decisions about which screens to show. No AppKit, no persistence.
public enum OnboardingPlan {
    /// Tours show the three features, then setup. Recovery and the usage-data question go straight to setup.
    public static func steps(for mode: OnboardingMode) -> [OnboardingStep] {
        switch mode {
        case .firstRun, .tour: return [.welcome, .desktops, .previews, .switcher, .setup]
        case .recovery, .privacyOnly: return [.setup]
        }
    }

    /// What to show once the first permission check has answered. `nil` shows nothing.
    public static func launchMode(tourCompleted: Bool, permissionsGranted: Bool, installed: Bool, privacyAsked: Bool) -> OnboardingMode? {
        if !tourCompleted { return .firstRun }
        if !permissionsGranted || !installed { return .recovery }
        if !privacyAsked { return .privacyOnly }
        return nil
    }

    /// The index to resume at, or the start when the saved step is not in this list.
    public static func resumeIndex(for saved: OnboardingStep?, in steps: [OnboardingStep]) -> Int {
        guard let saved else { return 0 }
        return steps.firstIndex(of: saved) ?? 0
    }
}

/// Remembers whether the first-run tour was finished and where it was left.
/// Stored outside `AppSettings`, so Reset All Settings never brings the tour back.
@MainActor public final class OnboardingStore {
    public static let tourVersion = 1
    enum Keys {
        static let completed = "DogBarOnboarding.completedVersion"
        static let resumeStep = "DogBarOnboarding.resumeStep"
    }
    /// Keys an earlier DogBar version leaves behind. Their presence means this is not a first launch.
    static let legacyPrefixes = ["DogBar.", "DogBarTelemetry.", "nativeDock.", "desktopPins", "pinnedApps"]
    private let defaults: UserDefaults
    /// True when this launch found an existing install without onboarding state and marked the tour done.
    public private(set) var adoptedExistingInstall = false

    /// - Parameter domainName: the persistent domain to inspect for an existing install
    ///   (the bundle identifier for `.standard`, the suite name for tests). Create this before any
    ///   other DogBar service writes its own defaults.
    public init(defaults: UserDefaults = .standard, domainName: String? = Bundle.main.bundleIdentifier) {
        self.defaults = defaults
        let hasOwnState = defaults.object(forKey: Keys.completed) != nil || defaults.object(forKey: Keys.resumeStep) != nil
        if !hasOwnState, let domainName, Self.hasLegacyState(defaults.persistentDomain(forName: domainName) ?? [:]) {
            // Existing users are never pushed through the tour after an update. Missing permissions
            // still get the short recovery flow.
            defaults.set(Self.tourVersion, forKey: Keys.completed)
            adoptedExistingInstall = true
        }
    }
    static func hasLegacyState(_ domain: [String: Any]) -> Bool {
        domain.keys.contains { key in legacyPrefixes.contains { key.hasPrefix($0) } }
    }
    public var isCompleted: Bool { defaults.integer(forKey: Keys.completed) >= 1 }
    public var resumeStep: OnboardingStep? {
        get { defaults.string(forKey: Keys.resumeStep).flatMap(OnboardingStep.init(persisted:)) }
        set { defaults.set(newValue?.rawValue, forKey: Keys.resumeStep) }
    }
    public func markCompleted() {
        defaults.set(Self.tourVersion, forKey: Keys.completed)
        defaults.removeObject(forKey: Keys.resumeStep)
    }
}
