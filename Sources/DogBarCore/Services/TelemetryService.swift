import Foundation

/// Anonymous usage counts for product decisions: who opens DogBar, finishes setup, keeps it
/// running and which features they use. Never window titles, app names, files or anything
/// typed. Events share the website's PostHog project and are tagged `source: "app"`.
@MainActor public final class TelemetryService {
    /// Counted at most once per feature per day: the aim is "does anyone use this", not volume.
    public enum Feature: String, CaseIterable, Sendable {
        case dockClick = "dock_click", dockPreview = "dock_preview", switcher, desktopSwitch = "desktop_switch"
    }

    /// Public project token. It only allows sending events, and ships in the website's source too.
    nonisolated static let projectToken = "phc_kRpqsTn5CZ2b8yMYjvwFkGMoZo2jXAPEFWhuEK6D9MkU"
    nonisolated static let endpoint = URL(string: "https://eu.i.posthog.com/batch/")!

    private let settings: AppSettings
    private let defaults: UserDefaults
    private let context: TelemetryContext
    private let send: @Sendable (Data) async -> Bool
    private var pending: [TelemetryEvent] = []
    private var flushTask: Task<Void, Never>?
    private var dayTimer: Timer?
    private var started = false

    public init(settings: AppSettings, defaults: UserDefaults = .standard, context: TelemetryContext = .current,
                send: (@Sendable (Data) async -> Bool)? = nil) {
        self.settings = settings; self.defaults = defaults; self.context = context
        self.send = send ?? { await TelemetryService.post($0) }
    }

    /// Reports the launch and today's activity, then checks once an hour for a new day.
    public func start() {
        guard !started else { return }
        started = true
        let firstLaunch = defaults.string(forKey: Keys.installID) == nil
        record("app_launched", ["first_launch": .bool(firstLaunch)])
        recordDailyActivity()
        dayTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordDailyActivity() }
        }
        dayTimer?.tolerance = 300
    }

    /// Once per install: both permissions granted is the end of setup.
    public func permissionsGranted() {
        guard isEnabled, !defaults.bool(forKey: Keys.permissionsReported) else { return }
        defaults.set(true, forKey: Keys.permissionsReported)
        record("permissions_granted")
    }

    public func featureUsed(_ feature: Feature) {
        guard isEnabled else { return }
        var days = defaults.dictionary(forKey: Keys.featureDays) as? [String: String] ?? [:]
        let today = TelemetryPolicy.day(Date())
        guard TelemetryPolicy.isNewDay(last: days[feature.rawValue], today: today) else { return }
        days[feature.rawValue] = today
        defaults.set(days, forKey: Keys.featureDays)
        record("feature_used", ["feature": .string(feature.rawValue)])
    }

    /// Turning the setting off drops anything not yet sent.
    public func settingsChanged() {
        if !isEnabled { pending.removeAll(); flushTask?.cancel(); flushTask = nil }
    }

    private var isEnabled: Bool { settings.telemetryEnabled && context.isReleaseBundle }

    private func recordDailyActivity() {
        guard isEnabled else { return }
        let today = TelemetryPolicy.day(Date())
        guard TelemetryPolicy.isNewDay(last: defaults.string(forKey: Keys.lastActiveDay), today: today) else { return }
        defaults.set(today, forKey: Keys.lastActiveDay)
        record("app_active")
    }

    private func record(_ name: String, _ properties: [String: TelemetryValue] = [:]) {
        guard isEnabled else { return }
        var all = context.properties
        all["dock_mode"] = .string(settings.useDogBarDock ? "dogbar" : "native")
        all["switcher_mode"] = .string(settings.switcherMode.rawValue)
        for (key, value) in properties { all[key] = value }
        pending.append(TelemetryEvent(name: name, distinctID: installID, timestamp: Date(), properties: all))
        if pending.count > TelemetryPolicy.maximumPending { pending.removeFirst(pending.count - TelemetryPolicy.maximumPending) }
        scheduleFlush(after: 5)
    }

    /// A random ID created on first use. It identifies an install, never a person.
    private var installID: String {
        if let id = defaults.string(forKey: Keys.installID) { return id }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: Keys.installID)
        return id
    }

    private func scheduleFlush(after seconds: Double) {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func flush() async {
        flushTask = nil
        guard isEnabled, !pending.isEmpty, let body = TelemetryPolicy.batchBody(pending, token: Self.projectToken) else { return }
        let sent = pending
        pending.removeAll()
        if await send(body) { return }
        // Offline or rejected: keep the events for a later attempt, newest last.
        pending = Array((sent + pending).suffix(TelemetryPolicy.maximumPending))
        scheduleFlush(after: 300)
    }

    private nonisolated static func post(_ body: Data) async -> Bool {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
    }

    private enum Keys {
        // Outside AppSettings, so "Reset all settings" keeps the install's identity and history.
        static let installID = "DogBarTelemetry.installID"
        static let lastActiveDay = "DogBarTelemetry.lastActiveDay"
        static let featureDays = "DogBarTelemetry.featureDays"
        static let permissionsReported = "DogBarTelemetry.permissionsReported"
    }
}

/// Values allowed in an event: deliberately no free-form objects.
public enum TelemetryValue: Equatable, Sendable {
    case string(String), bool(Bool)
    var json: Any { switch self { case .string(let value): return value; case .bool(let value): return value } }
}
extension TelemetryValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

public struct TelemetryEvent: Equatable, Sendable {
    public var name: String
    public var distinctID: String
    public var timestamp: Date
    public var properties: [String: TelemetryValue]
}

/// Facts about this build and Mac that every event carries.
public struct TelemetryContext: Sendable {
    public var appVersion: String
    public var build: String
    /// From `DogBarBuildChannel`, stamped by each build script: "development" (Scripts/run.sh),
    /// "preview" or "release". Unstamped builds count as development.
    public var channel: String
    public var osVersion: String
    public var architecture: String
    /// Only a real .app sends; `swift run` and tests never do.
    public var isReleaseBundle: Bool

    public static var current: TelemetryContext {
        let info = Bundle.main.infoDictionary ?? [:]
        let preview = info["DogBarPreviewVersion"] as? String
        let channel = info["DogBarBuildChannel"] as? String
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        return TelemetryContext(appVersion: preview ?? info["CFBundleShortVersionString"] as? String ?? "0",
                                build: info["CFBundleVersion"] as? String ?? "0",
                                channel: channel ?? "development",
                                osVersion: "\(os.majorVersion).\(os.minorVersion)",
                                architecture: architecture,
                                isReleaseBundle: Bundle.main.bundleURL.pathExtension == "app")
    }

    var properties: [String: TelemetryValue] {
        ["source": "app", "app_version": .string(appVersion), "app_build": .string(build), "build_channel": .string(channel),
         "os_version": .string(osVersion), "arch": .string(architecture)]
    }
}

/// Pure rules, kept apart from timers and networking so they can be tested.
public enum TelemetryPolicy {
    static let maximumPending = 100

    /// A local calendar day, so "active today" matches the person's own day.
    public static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func isNewDay(last: String?, today: String) -> Bool { last != today }

    /// PostHog's batch format. `$process_person_profile: false` keeps every event anonymous:
    /// no person profile is created or merged for the install ID.
    public static func batchBody(_ events: [TelemetryEvent], token: String) -> Data? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let batch: [[String: Any]] = events.map { event in
            var properties = event.properties.mapValues(\.json)
            properties["$process_person_profile"] = false
            properties["$lib"] = "dogbar-macos"
            return ["event": event.name, "distinct_id": event.distinctID,
                    "timestamp": formatter.string(from: event.timestamp), "properties": properties]
        }
        return try? JSONSerialization.data(withJSONObject: ["api_key": token, "batch": batch], options: [.sortedKeys])
    }
}
