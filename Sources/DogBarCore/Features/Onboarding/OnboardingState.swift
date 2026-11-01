import Foundation

/// One screen of the onboarding wizard. Raw values are persisted, so never rename a case.
public enum OnboardingStep: String, CaseIterable, Codable, Sendable {
    case welcome, desktops, previews, switcher, install, accessibility, screenRecording, privacy, ready
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
    public struct Inputs: Equatable, Sendable {
        public var installed: Bool
        public var accessibility: Bool
        public var screenRecording: Bool
        public var privacyAsked: Bool
        public init(installed: Bool, accessibility: Bool, screenRecording: Bool, privacyAsked: Bool) {
            self.installed = installed; self.accessibility = accessibility
            self.screenRecording = screenRecording; self.privacyAsked = privacyAsked
        }
    }

    /// The step list is computed once per presentation and stays stable while it is on screen,
    /// so granting a permission never makes a step vanish under the reader.
    public static func steps(for mode: OnboardingMode, _ inputs: Inputs) -> [OnboardingStep] {
        switch mode {
        case .firstRun, .tour:
            var steps: [OnboardingStep] = [.welcome, .desktops, .previews, .switcher]
            if !inputs.installed { steps.append(.install) }
            steps += [.accessibility, .screenRecording, .privacy, .ready]
            return steps
        case .recovery:
            var steps: [OnboardingStep] = []
            if !inputs.installed { steps.append(.install) }
            if !inputs.accessibility { steps.append(.accessibility) }
            if !inputs.screenRecording { steps.append(.screenRecording) }
            if !inputs.privacyAsked { steps.append(.privacy) }
            return steps + [.ready]
        case .privacyOnly:
            return [.privacy]
        }
    }

    /// What to show once the first permission check has answered. `nil` shows nothing.
    public static func launchMode(tourCompleted: Bool, permissionsGranted: Bool, installed: Bool, privacyAsked: Bool) -> OnboardingMode? {
        if !tourCompleted { return .firstRun }
        if !permissionsGranted || !installed { return .recovery }
        if !privacyAsked { return .privacyOnly }
        return nil
    }

    /// The index to resume at. A saved step that is no longer in the list (for example the
    /// install step after DogBar was moved) resumes at the next step that is.
    public static func resumeIndex(for saved: OnboardingStep?, in steps: [OnboardingStep]) -> Int {
        guard let saved, !steps.isEmpty else { return 0 }
        if let index = steps.firstIndex(of: saved) { return index }
        let order = OnboardingStep.allCases
        guard let rank = order.firstIndex(of: saved) else { return 0 }
        return steps.firstIndex { (order.firstIndex(of: $0) ?? 0) > rank } ?? steps.count - 1
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
        get { defaults.string(forKey: Keys.resumeStep).flatMap(OnboardingStep.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: Keys.resumeStep) }
    }
    public func markCompleted() {
        defaults.set(Self.tourVersion, forKey: Keys.completed)
        defaults.removeObject(forKey: Keys.resumeStep)
    }
}
