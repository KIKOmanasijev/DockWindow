import XCTest
import Combine
@testable import DockWindowCore

final class PolicyTests: XCTestCase {
    private func window(_ id: UInt32, pid: pid_t = 10, spaces: [UInt64] = [1], minimized: Bool = false, hidden: Bool = false, remembered: [UInt64] = [], time: TimeInterval = 0) -> TrackedWindow {
        TrackedWindow(id: id, pid: pid, frame: CGRect(x: 0, y: 0, width: 400, height: 300), spaceIDs: spaces, isMinimized: minimized, isAppHidden: hidden, lastFocusedAt: Date(timeIntervalSince1970: time), rememberedSpaceIDs: remembered)
    }
    private func app(_ pid: pid_t, _ bundle: String, frontmost: Bool = false, spaces: [UInt64] = []) -> TrackedApp {
        TrackedApp(pid: pid, bundleIdentifier: bundle, name: bundle, isFrontmost: frontmost, lastActiveSpaceIDs: spaces)
    }
    private func pin(_ id: String) -> PinnedApp { PinnedApp(bundleIdentifier: id, url: URL(fileURLWithPath: "/Applications/\(id).app")) }

    func testModelDefaultsAndHashing() {
        let w = TrackedWindow(id: 5)
        XCTAssertEqual(w.pid, 0); XCTAssertTrue(w.spaceIDs.isEmpty)
        XCTAssertEqual(Set([w, w]).count, 1)
        var changed = w; changed.frame.size.width = 200
        XCTAssertNotEqual(w, changed)
        XCTAssertEqual(Set([w, changed]).count, 2)
        XCTAssertEqual(TrackedApp(pid: 4).id, 4)
        XCTAssertEqual(WindowSnapshot().activeSpaceID, 0)
    }
    func testMRUFocusAndStableTies() {
        let windows = [window(3, time: 1), window(1, time: 2), window(2, time: 2)]
        XCTAssertEqual(MRUPolicy.ordered(windows).map(\.id), [1, 2, 3])
        XCTAssertEqual(MRUPolicy.focusing(3, in: windows, at: Date(timeIntervalSince1970: 3)).map(\.id), [3, 1, 2])
        XCTAssertEqual(MRUPolicy.focusing(99, in: windows, at: Date()).map(\.id), [1, 2, 3])
        XCTAssertEqual(MRUPolicy.ordered([]), [])
    }
    func testSeparateAndSharedDisplaySpaces() {
        let snapshot = WindowSnapshot(activeSpaceIDs: ["Main": 1, "secondary": 9])
        XCTAssertEqual(SpacePolicy.currentSpaceIDs(snapshot: snapshot, displayID: "secondary", separateSpaces: true), [9])
        XCTAssertEqual(SpacePolicy.currentSpaceIDs(snapshot: snapshot, displayID: "secondary", separateSpaces: false), [1])
        XCTAssertEqual(SpacePolicy.currentSpaceIDs(snapshot: snapshot, displayID: nil, separateSpaces: true, allDisplays: true), [1, 9])
        XCTAssertEqual(SpacePolicy.currentSpaceIDs(snapshot: snapshot, displayID: "missing", separateSpaces: true), [1])
        XCTAssertEqual(WindowSnapshot(activeSpaceIDs: ["Z": 9, "A": 7]).activeSpaceID, 7)
        XCTAssertTrue(SpacePolicy.currentSpaceIDs(snapshot: .init(), displayID: nil, separateSpaces: false).isEmpty)
    }
    func testSpaceAndMinimizedFiltering() {
        var fullscreen = window(7, spaces: [40]); fullscreen.isFullscreen = true
        let windows = [window(1), window(2, spaces: [2]), window(3, spaces: [1, 2]), window(4, spaces: [], minimized: true, remembered: [1]), window(5, spaces: [], minimized: true, remembered: [2]), window(6, spaces: [], minimized: true), fullscreen]
        XCTAssertEqual(WindowFilter(currentSpaceIDs: [1]).apply(to: windows).map(\.id), [1, 3, 4, 6])
        XCTAssertEqual(WindowFilter(currentSpaceIDs: [40]).apply(to: windows).map(\.id), [6, 7])
        XCTAssertEqual(WindowFilter(currentSpaceIDs: [1], includeMinimized: false).apply(to: windows).map(\.id), [1, 3])
        XCTAssertEqual(WindowFilter(scope: .allDesktops, currentSpaceIDs: [1]).apply(to: windows).count, 7)
        XCTAssertTrue(SpacePolicy.isOnCurrentSpace(window(99, spaces: []), currentSpaceIDs: []))
        XCTAssertFalse(SpacePolicy.isOnCurrentSpace(window(99, spaces: []), currentSpaceIDs: [1]))
    }
    func testRememberedMembershipSurvivesMinimizedPolls() {
        let original = window(1, spaces: [4, 5])
        let minimized = SpacePolicy.updatingMembership(of: original, spaceIDs: [], isMinimized: true)
        XCTAssertEqual(minimized.rememberedSpaceIDs, [4, 5])
        let poll = SpacePolicy.updatingMembership(of: minimized, spaceIDs: [], isMinimized: true)
        XCTAssertEqual(poll.rememberedSpaceIDs, [4, 5])
        let restored = SpacePolicy.updatingMembership(of: poll, spaceIDs: [8], isMinimized: false)
        XCTAssertEqual(restored.spaceIDs, [8]); XCTAssertEqual(restored.rememberedSpaceIDs, [8])
    }
    func testFilteringPIDHiddenAndScreen() {
        var otherScreen = window(3); otherScreen.frame.origin.x = 2000
        let all = [window(1, hidden: true), window(2, pid: 20), otherScreen]
        XCTAssertEqual(WindowFilter(includeHiddenApps: false).apply(to: all).map(\.id), [2, 3])
        XCTAssertEqual(WindowFilter(pid: 10).apply(to: all).map(\.id), [1, 3])
        XCTAssertEqual(WindowFilter(displayFrame: CGRect(x: 0, y: 0, width: 1000, height: 1000)).apply(to: all).map(\.id), [1, 2])
    }
    func testWindowEligibilityBoundaries() {
        let size = CGRect(x: 0, y: 0, width: 100, height: 50)
        XCTAssertTrue(WindowCandidate(id: 1, frame: size).isEligible())
        XCTAssertTrue(WindowCandidate(id: 1, subrole: "AXDialog", frame: size).isEligible())
        XCTAssertFalse(WindowCandidate(id: 0, frame: size).isEligible())
        XCTAssertFalse(WindowCandidate(id: 1, role: "AXSheet", frame: size).isEligible())
        XCTAssertFalse(WindowCandidate(id: 1, subrole: "AXUnknown", frame: size).isEligible())
        XCTAssertFalse(WindowCandidate(id: 1, frame: CGRect(x: 0, y: 0, width: 99, height: 50)).isEligible())
        XCTAssertFalse(WindowCandidate(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 49)).isEligible())
        XCTAssertFalse(WindowCandidate(id: 1, frame: size, layer: 1).isEligible())
        XCTAssertFalse(WindowCandidate(id: 1, frame: size, alpha: 0).isEligible())
        XCTAssertTrue(WindowCandidate(id: 1, subrole: "Custom", frame: size).isEligible(allowedSubroles: ["Custom"]))
    }
    func testDockCompositionOrderingDeduplicationAndSeparator() {
        let apps = [app(10, "running"), app(11, "pinned"), app(12, "remote"), app(13, "com.apple.finder")]
        let snapshot = WindowSnapshot(apps: apps, windows: [window(1), window(2, pid: 12, spaces: [2])])
        let pinned = [pin("pinned"), pin("second"), pin("pinned"), pin("com.apple.finder")]
        let items = DockCompositionPolicy.items(snapshot: snapshot, pinned: pinned, options: .init(currentSpaceIDs: [1]))
        XCTAssertEqual(items.map(\.id), ["com.apple.finder", "pinned", "second", "running", "separator:trash", "trash"])
        XCTAssertTrue(items[0].isPinned); XCTAssertEqual(items[1].app?.pid, 11)
        XCTAssertEqual(items.suffix(2).map(\.kind), [.separator, .trash])
        let dimmed = DockCompositionPolicy.items(snapshot: snapshot, pinned: pinned, options: .init(currentSpaceIDs: [1], otherDesktopApps: .dimmed, showTrash: false))
        XCTAssertEqual(dimmed.last?.id, "remote"); XCTAssertEqual(dimmed.last?.isDimmed, true)
        XCTAssertFalse(dimmed.contains { $0.kind == .separator })
        let all = DockCompositionPolicy.items(snapshot: snapshot, pinned: [], options: .init(scope: .allDesktops, currentSpaceIDs: [1]))
        XCTAssertEqual(all.filter { $0.kind == .application }.count, 4)
        XCTAssertFalse(all.contains { $0.isDimmed })
    }
    func testDockMinimizedAndWindowlessApps() {
        let snapshot = WindowSnapshot(apps: [app(10, "min"), app(11, "local", spaces: [1]), app(12, "remote", spaces: [2]), app(13, "unknown")], windows: [window(1, spaces: [], minimized: true, remembered: [1])])
        let included = DockCompositionPolicy.items(snapshot: snapshot, pinned: [], options: .init(currentSpaceIDs: [1], showTrash: false))
        XCTAssertEqual(included.map(\.id), ["com.apple.finder", "min", "local"])
        let excluded = DockCompositionPolicy.items(snapshot: snapshot, pinned: [], options: .init(currentSpaceIDs: [1], includeMinimized: false, showWindowlessAppsOnLastActiveDesktop: false, showTrash: false))
        XCTAssertEqual(excluded.map(\.id), ["com.apple.finder"])
    }
    func testDotsAllCombinations() {
        let windows = [window(1), window(2), window(3, minimized: true), window(4, spaces: [2])]
        let filter = WindowFilter(currentSpaceIDs: [1])
        XCTAssertEqual(DotPolicy.indicators(windows: windows, filter: filter).count, 3)
        XCTAssertEqual(DotPolicy.indicators(windows: windows, filter: filter, style: .single).count, 1)
        XCTAssertEqual(DotPolicy.indicators(windows: windows, filter: filter, maxDots: 2).count, 2)
        XCTAssertEqual(DotPolicy.indicators(windows: windows, filter: filter, maxDots: -1).count, 0)
        XCTAssertEqual(DotPolicy.indicators(windows: windows, filter: .init(currentSpaceIDs: [1], includeMinimized: false)).count, 2)
        XCTAssertEqual(DotPolicy.indicators(windows: [], filter: filter), .init(count: 0))
        XCTAssertEqual(DotPolicy.indicators(windows: [], filter: filter, showRunningState: true), .init(count: 1, isHollow: true))
        XCTAssertEqual(DotPolicy.indicators(windows: windows, filter: filter, isRunning: false, showRunningState: true), .init(count: 0))
    }
    func testClickPolicyEveryState() {
        let windows = [window(1, time: 1), window(2, time: 2), window(3, spaces: [2], time: 3)]
        XCTAssertEqual(DockClickPolicy.action(app: nil, windows: windows, currentSpaceIDs: [1]), .launch)
        XCTAssertEqual(DockClickPolicy.action(app: app(10, "app"), windows: windows, currentSpaceIDs: [1]), .focus(2))
        XCTAssertEqual(DockClickPolicy.action(app: app(10, "app"), windows: windows, currentSpaceIDs: [9]), .openNewWindowHere)
        XCTAssertEqual(DockClickPolicy.action(app: app(11, "other"), windows: windows, currentSpaceIDs: [1]), .openNewWindowHere)
        let actions: [(ActiveAppClickBehavior, DockClickAction)] = [(.none, .none), (.cycle, .cycle), (.minimize, .minimize), (.hide, .hide)]
        for (behavior, expected) in actions {
            XCTAssertEqual(DockClickPolicy.action(app: app(10, "app", frontmost: true), windows: windows, currentSpaceIDs: [1], activeBehavior: behavior), expected)
            XCTAssertEqual(DockClickPolicy.action(app: app(10, "app", frontmost: true), windows: windows, currentSpaceIDs: [9], activeBehavior: behavior), .openNewWindowHere)
        }
        XCTAssertEqual(DockClickPolicy.cycleTarget(windows: windows, pid: 10, currentSpaceIDs: [1], focusedWindowID: 2), 1)
        XCTAssertEqual(DockClickPolicy.cycleTarget(windows: windows, pid: 10, currentSpaceIDs: [1], focusedWindowID: 1), 2)
        XCTAssertNil(DockClickPolicy.cycleTarget(windows: windows, pid: 10, currentSpaceIDs: [9], focusedWindowID: nil))
    }
    func testMagnificationSymmetryMonotonicityAndBounds() {
        func scale(_ d: Double) -> Double { MagnificationPolicy.scale(distance: d, baseSize: 48, maximumSize: 96) }
        XCTAssertEqual(scale(0), 2); XCTAssertEqual(scale(3), 1); XCTAssertEqual(scale(100), 1)
        var previous = scale(0)
        for step in 0...300 {
            let d = Double(step) / 100
            XCTAssertEqual(scale(d), scale(-d), accuracy: 0.00001)
            XCTAssertLessThanOrEqual(scale(d), previous); XCTAssertGreaterThanOrEqual(scale(d), 1)
            previous = scale(d)
        }
        XCTAssertEqual(MagnificationPolicy.scale(distance: 0, baseSize: 0, maximumSize: 96), 1)
        XCTAssertEqual(MagnificationPolicy.scale(distance: .nan, baseSize: 48, maximumSize: 96), 1)
        XCTAssertEqual(MagnificationPolicy.scale(distance: 0, baseSize: 96, maximumSize: 48), 1)
    }
    func testPinnedPlistImportFixture() throws {
        func tile(_ url: String, bundle: String? = nil) -> [String: Any] {
            var data: [String: Any] = ["file-data": ["_CFURLString": url]]
            if let bundle = bundle { data["bundle-identifier"] = bundle }
            return ["tile-data": data]
        }
        let fixture: [String: Any] = ["persistent-apps": [tile("file:///Applications/First.app/", bundle: "first"), tile("file:///Applications/Missing.app/", bundle: "missing"), tile("file:///Applications/First.app/", bundle: "first"), tile("file:///Applications/Second%20App.app/"), tile("https://example.com/Bad.app", bundle: "bad"), tile("/Applications/Folder", bundle: "folder"), ["tile-data": [:]], tile("/Applications/Third.app", bundle: "third")]]
        let data = try PropertyListSerialization.data(fromPropertyList: fixture, format: .xml, options: 0)
        let decoded = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let pins = PinnedAppsPolicy.parse(plist: decoded, appExists: { !$0.path.contains("Missing") }, bundleIdentifierAtURL: { $0.path.contains("Second App") ? "second" : nil })
        XCTAssertEqual(pins.map(\.bundleIdentifier), ["first", "second", "third"])
        XCTAssertEqual(pins[1].url.lastPathComponent, "Second App.app")
        XCTAssertTrue(PinnedAppsPolicy.parse(plist: [:], appExists: { _ in true }).isEmpty)
    }
    func testMenuTitlePriorityLocalizationAndShortcutFallback() {
        let shortcut = MenuItemDescriptor(id: "shortcut", title: "New Tab", commandCharacter: "n")
        let shift = MenuItemDescriptor(id: "shift", title: "Private", commandCharacter: "N", modifiers: [.command, .shift])
        let title = MenuItemDescriptor(id: "title", title: "New Finder Window…")
        let roots = [MenuItemDescriptor(id: "file", title: "File", children: [shift, shortcut, title])]
        XCTAssertEqual(NewWindowMenuPolicy.match(in: roots)?.id, "title")
        XCTAssertEqual(NewWindowMenuPolicy.match(in: [shortcut, shift])?.id, "shortcut")
        XCTAssertNil(NewWindowMenuPolicy.match(in: [shift]))
        let localized = MenuItemDescriptor(id: "localized", title: " Neues Fenster... ")
        XCTAssertEqual(NewWindowMenuPolicy.match(in: [localized], titles: ["Neues Fenster"])?.id, "localized")
        XCTAssertNil(NewWindowMenuPolicy.match(in: [.init(id: "disabled", title: "New Window", isEnabled: false)]))
        XCTAssertNil(NewWindowMenuPolicy.match(in: [.init(id: "parent", title: "File", isEnabled: false, children: [title])]))
        XCTAssertEqual(NewWindowMenuPolicy.strategies(for: .init(bundleIdentifier: "a")), [.menu, .shortcut, .reopen])
        XCTAssertEqual(NewWindowMenuPolicy.strategies(for: .init(bundleIdentifier: "a", strategy: .reopen)), [.reopen, .menu, .shortcut])
    }
    func testNewWindowVerificationRequiresNewIDCorrectPIDAndKnownMembership() {
        let windows = [window(1), window(2, pid: 20), window(3, spaces: [2]), window(4, spaces: [], minimized: true), window(5)]
        XCTAssertEqual(NewWindowVerificationPolicy.confirmedWindow(pid: 10, previousWindowIDs: [1], requestedSpaceIDs: [1], windows: windows)?.id, 5)
        XCTAssertNil(NewWindowVerificationPolicy.confirmedWindow(pid: 10, previousWindowIDs: [1, 5], requestedSpaceIDs: [1], windows: windows))
        XCTAssertNil(NewWindowVerificationPolicy.confirmedWindow(pid: 10, previousWindowIDs: [], requestedSpaceIDs: [], windows: windows))
    }
    func testExactNativeDockRestoreAndMissingKeys() throws {
        let before: [String: PreferenceValue] = ["autohide": .bool(false), "autohide-delay": .real(0.75), "launchanim": .integer(1)]
        let backup = NativeDockPolicy.backup(values: before)
        let encoded = try JSONEncoder().encode(backup)
        let roundTrip = try JSONDecoder().decode([String: BackedUpPreference].self, from: encoded)
        let plan = NativeDockPolicy.restorePlan(backup: roundTrip)
        XCTAssertEqual(plan.map(\.key), NativeDockPolicy.keys)
        var restored = Dictionary(uniqueKeysWithValues: NativeDockPolicy.replacementPlan.compactMap { change in change.value.map { (change.key, $0) } })
        for change in plan { restored[change.key] = change.value }
        XCTAssertEqual(restored, before)
        XCTAssertEqual(plan.filter { $0.value == nil }.map(\.key), ["autohide-time-modifier", "workspaces-auto-swoosh"])
        XCTAssertTrue(NativeDockPolicy.restorePlan(backup: [:]).isEmpty)
        XCTAssertTrue(NativeDockPolicy.shouldRestoreAfterLaunch(hasBackup: true, previousSessionClean: false, dockEnabled: false))
        for tuple in [(false, false, false), (true, true, false), (true, false, true)] {
            XCTAssertFalse(NativeDockPolicy.shouldRestoreAfterLaunch(hasBackup: tuple.0, previousSessionClean: tuple.1, dockEnabled: tuple.2))
        }
    }
    func testPreferenceValuesPreservePropertyListTypes() throws {
        let values: [PreferenceValue] = [.bool(true), .integer(3), .real(0.5), .string("value"), .data(Data([1, 2])), .date(Date(timeIntervalSince1970: 5)), .array([.integer(2), .bool(false)]), .dictionary(["k": .string("v")])]
        for value in values {
            XCTAssertEqual(PreferenceValue(propertyList: value.propertyListValue), value)
            XCTAssertEqual(try JSONDecoder().decode(PreferenceValue.self, from: JSONEncoder().encode(value)), value)
        }
        XCTAssertNil(PreferenceValue(propertyList: URL(fileURLWithPath: "/tmp")))
    }
    func testHotkeyBeginCycleReleaseAndCancel() {
        func decode(_ kind: HotkeyEventKind = .keyDown, _ key: UInt16 = 48, _ flags: HotkeyModifiers = .option, active: Bool = false) -> HotkeyDecision {
            HotkeyPolicy.decode(kind: kind, keyCode: key, flags: flags, isSessionActive: active)
        }
        XCTAssertEqual(decode(), .init(command: .begin(reverse: false, sameAppOnly: false), swallow: true))
        XCTAssertEqual(decode(.keyDown, 48, [.option, .shift]), .init(command: .begin(reverse: true, sameAppOnly: false), swallow: true))
        XCTAssertEqual(decode(active: true), .init(command: .next, swallow: true))
        XCTAssertEqual(decode(.keyDown, 48, [.option, .shift], active: true), .init(command: .previous, swallow: true))
        XCTAssertEqual(decode(.keyUp), .init(swallow: true))
        XCTAssertEqual(decode(.flagsChanged, 0, [], active: true), .init(command: .commit))
        XCTAssertEqual(decode(.flagsChanged, 0, [.option, .shift], active: true), .init())
        XCTAssertEqual(decode(.keyDown, 53, .option, active: true), .init(command: .cancel, swallow: true))
        XCTAssertEqual(decode(.tapDisabled), .init(command: .reenableTap))
        XCTAssertEqual(decode(.keyDown, 48, [.option, .control]), .init())
        XCTAssertEqual(decode(.keyDown, 1), .init())
        XCTAssertEqual(decode(.keyDown, 48, [], active: false), .init())
        XCTAssertEqual(decode(.keyDown, 48, HotkeyModifiers(rawValue: HotkeyModifiers.option.rawValue | (1 << 16))), decode())
    }
    func testHotkeyActionsAndConfiguration() {
        let actions: [(UInt16, SwitcherCommand)] = [(123, .moveLeft), (124, .moveRight), (125, .moveDown), (126, .moveUp), (13, .closeWindow), (46, .minimizeWindow), (4, .hideApp), (12, .quitApp)]
        for (key, command) in actions {
            XCTAssertEqual(HotkeyPolicy.decode(kind: .keyDown, keyCode: key, flags: .command, isSessionActive: true), .init(command: command, swallow: true))
            XCTAssertEqual(HotkeyPolicy.decode(kind: .keyUp, keyCode: key, flags: .command, isSessionActive: true), .init(swallow: true))
            XCTAssertEqual(HotkeyPolicy.decode(kind: .keyDown, keyCode: key, flags: .command, isSessionActive: false), .init())
        }
        var config = HotkeyConfiguration()
        config.sameAppEnabled = true
        XCTAssertEqual(HotkeyPolicy.decode(kind: .keyDown, keyCode: 50, flags: .command, isSessionActive: false, configuration: config).command, .begin(reverse: false, sameAppOnly: true))
        config.shortcut = .init(keyCode: 48, modifiers: .option)
        XCTAssertEqual(HotkeyPolicy.decode(kind: .keyDown, keyCode: 48, flags: .option, isSessionActive: false, configuration: config).command, .begin(reverse: false, sameAppOnly: false))
        XCTAssertEqual(HotkeyPolicy.decode(kind: .flagsChanged, flags: [], isSessionActive: true, heldModifiers: .command, configuration: config).command, .commit)
        config.closeWithW = false; config.minimizeWithM = false; config.hideWithH = false; config.quitWithQ = false
        for key: UInt16 in [13, 46, 4, 12] {
            XCTAssertEqual(HotkeyPolicy.decode(kind: .keyDown, keyCode: key, flags: .option, isSessionActive: true, configuration: config), .init())
        }
        config.enabled = false
        XCTAssertEqual(HotkeyPolicy.decode(kind: .keyDown, keyCode: 48, flags: .option, isSessionActive: false, configuration: config), .init())
    }
    func testSwitcherWindowlessAndSameAppPolicies() {
        let snapshot = WindowSnapshot(apps: [app(10, "local"), app(11, "remote"), app(12, "empty")], windows: [window(1), window(2, pid: 11, spaces: [2])])
        let items = SwitcherPolicy.items(snapshot: snapshot, filter: .init(currentSpaceIDs: [1]), showWindowlessApps: true)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.contains { if case .windowlessApp(let a) = $0 { return a.pid == 12 }; return false })
        XCTAssertEqual(SwitcherPolicy.items(snapshot: snapshot, filter: .init(currentSpaceIDs: [1]), showWindowlessApps: true, frontmostPID: 10).count, 1)
        XCTAssertEqual(SwitcherPolicy.items(snapshot: snapshot, filter: .init(currentSpaceIDs: [1]), showWindowlessApps: false).count, 1)
        XCTAssertEqual(SwitcherPolicy.nextIndex(current: 0, count: 3, delta: -1), 2)
        XCTAssertEqual(SwitcherPolicy.nextIndex(current: 2, count: 3), 0)
        XCTAssertEqual(SwitcherPolicy.nextIndex(current: 0, count: 1), 0)
        XCTAssertNil(SwitcherPolicy.nextIndex(current: 0, count: 0))
    }
    func testSettingsDefaultsRoundTripResetAndPublishing() async throws {
        try await MainActor.run {
            let suite = "DockWindow.PolicyTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = AppSettings(defaults: defaults)
            XCTAssertTrue(settings.switcherEnabled); XCTAssertEqual(settings.iconSize, 48)
            XCTAssertEqual(settings.switcherAppearanceDelay, 0.12)
            XCTAssertEqual(settings.newWindowRules.count, 7)
            XCTAssertEqual(settings.newWindowRule(for: "com.apple.finder").menuTitles, ["New Finder Window"])
            XCTAssertEqual(settings.newWindowRule(for: "unknown").strategy, .automatic)
            for (key, value) in AppSettings.registeredDefaults {
                XCTAssertEqual(defaults.object(forKey: key) as? NSObject, value as? NSObject, key)
            }
            var changes = 0
            let token = settings.objectWillChange.sink { changes += 1 }
            let rules = [NewWindowRule(bundleIdentifier: "custom", strategy: .shortcut, menuTitles: ["Localized"], shortcut: .init(keyCode: 45, modifiers: [.command, .shift]))]
            settings.newWindowRules = rules; settings.dockScope = .allDesktops
            settings.pinnedApps = [pin("first")]
            settings.dotColor = .init(red: 1, green: 0, blue: 0)
            settings.iconSize = 64
            let second = AppSettings(defaults: defaults)
            XCTAssertEqual(second.newWindowRules, rules)
            XCTAssertEqual(second.pinnedApps, [pin("first")]); XCTAssertEqual(second.iconSize, 64)
            XCTAssertEqual(second.dockScope, .allDesktops)
            let beforeExternal = changes
            defaults.set(72.0, forKey: AppSettings.keyPrefix + "iconSize")
            settings.refresh()
            XCTAssertEqual(settings.iconSize, 72); XCTAssertGreaterThan(changes, beforeExternal)
            defaults.set("preserve", forKey: "nativeDockBackup")
            settings.reset()
            XCTAssertEqual(settings.iconSize, 48); XCTAssertEqual(settings.newWindowRules, NewWindowRule.defaults)
            XCTAssertEqual(defaults.string(forKey: "nativeDockBackup"), "preserve")
            for (key, value) in AppSettings.registeredDefaults {
                XCTAssertEqual(defaults.object(forKey: key) as? NSObject, value as? NSObject, key)
            }
            XCTAssertGreaterThan(changes, 5)
            withExtendedLifetime(token) {}
        }
    }
}
