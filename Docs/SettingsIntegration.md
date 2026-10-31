# Settings integration

Settings lives entirely in `DogBarCore/Features/Settings`. Construct and retain this controller on the main actor:

```swift
@MainActor
public init(
    settings: AppSettings,
    permissions: PermissionsService,
    pinnedApps: PinnedAppsStore,
    onRestoreNativeDock: @escaping () -> Void,
    onShowPermissions: @escaping () -> Void
)

@MainActor public func show()
```

The public type is `SettingsWindowController: NSWindowController, NSWindowDelegate`. Pass the same model and services used by the coordinator. The controller hosts six SwiftUI panes in a `NavigationSplitView`. The titled, closable, miniaturizable, resizable window has a minimum size of 720 by 520. `show()` saves the current activation policy, sets `.accessory`, activates the app and makes Settings key. Closing restores the saved policy. Repeated `show()` calls do not overwrite the saved policy.

`onRestoreNativeDock` must use the coordinator's existing restore path, disable replacement UI and report restoration errors. `onShowPermissions` opens the existing onboarding window. Settings does not edit or own that executable view. Relaunch calls the existing throwing `AppRelauncher.relaunch()` and displays errors; the helper's delayed restoration-safe termination behavior is preserved.

## Shortcut recording integration

The recorder captures a physical `NSEvent.keyCode` plus Command, Option, Shift and Control flags into `KeyboardShortcut`. At least one modifier is required. Escape cancels without modifying the existing binding. Repeats are ignored. Losing focus, closing the window or removing the view ends recording and removes the local monitor. Default switcher binding comes from `KeyboardShortcut.switcher`, currently Option+Tab. Same-app defaults to Command+grave accent, disabled.

The coordinator must suspend hotkey interception during recording, otherwise an already intercepted Option+Tab cannot reach AppKit. These public main-actor APIs support that integration:

```swift
@MainActor public enum SettingsShortcutRecording {
    public static let recordingDidChange: Notification.Name
    public private(set) static var isRecording: Bool
}
```

Observe `SettingsShortcutRecording.recordingDidChange` on the main queue and rerun hotkey configuration using `!SettingsShortcutRecording.isRecording` as an additional enable condition. Stop the tap while recording, cancel any active switcher session, and restore the usual permission/pause/enable gates afterward. Include this condition in every configuration refresh, so permission polling cannot reenable the tap mid-recording. The notification has no payload; read `isRecording` on the main actor.

## Live settings and actions

Every pane binds existing `AppSettings` properties. Each control has secondary description text. Dock layout, indicators, filtering and interaction sections are disabled in native Dock fallback mode with an explanation; previews, switcher and new-window rules remain available. Display pickers offer the spec's supported choices. Both thumbnail dimensions are independently editable. Additional existing preferences for minimized Dock visibility, windowless apps, scroll cycling, hollow running indicators, preview pointer and allowed AX subroles are exposed.

The rules table selects an application for editing strategy, physical shortcut and semicolon-separated exact localized menu titles below the table. Add app opens an application-bundle picker starting in `/Applications`. Bundle identifiers are validated and duplicates select the existing row. Remove restores the app's automatic rule fallback. The text editor preserves separators during typing while saving parsed title arrays live.

Launch at login applies `SMAppService.mainApp.register()` or awaited `unregister()`, then checks the actual status. The persisted preference changes only after an accepted status. Requires approval is shown explicitly with an Open Login Items button. Thrown errors and unexpected final status are shown in an alert. Settings polls status while open. Launch-at-login changes require an installed application bundle and manual verification.

Permissions are read from `PermissionsService` and refreshed every second while the view is active. The actual request buttons call `openAccessibility()` and `openScreenRecording()`. Screen Recording copy explains relaunch, and ad-hoc signing displays certificate guidance. Merely opening Settings does not request permissions or mutate login registration.

Reset requires confirmation and unregisters the login item before clearing settings. If unregister fails, reset does not proceed. It calls `AppSettings.reset()`, preserving native Dock recovery backups and unrelated defaults. The independently persisted `PinnedAppsStore` list is retained. Re-import has its own destructive confirmation and calls `pinnedApps.reimportNativeDock()`; it never writes native Dock pins.

Advanced uses only the public Services facade:

```swift
DiagnosticsService.privateAPIAvailability // [String: Bool]
DiagnosticsService.logFileURL             // URL
DiagnosticsService.setDebugLogging(_: Bool)
DiagnosticsService.revealLogFile()        // @MainActor
```

Features never reference the raw Private wrappers. The debug toggle persists `settings.debugLogging` and updates the sink immediately. The coordinator should also observe that flag for resets and external changes. No service is started, application launched, bundle installed or native Dock preference changed by constructing this controller.

## Verification

`swift build` passes without warnings with the provided DiagnosticsService facade and executable integration. `swift test` passes all 55 tests. Automated policy and service tests cover models, reset preservation, Option+Tab defaults and permission request behavior. Settings interaction, OS registration and focus restoration require the following manual checks:

- Open, resize, close and reopen Settings from the menu bar and app relaunch path. Check focus and activation-policy restoration.
- Change controls in each pane while features are active. Confirm layout, scopes, colors, thumbnail sizes and keyboard actions update live.
- Record Option+Tab and a different physical combination. Check modifier requirement, Escape cancellation and focus-loss cancellation, with no switcher appearing during recording.
- Add an installed app, edit strategy and shortcut, type multiple localized menu titles, then remove the rule. Check persistence after restarting.
- Disable replacement Dock. Confirm replacement controls are disabled and explained, while switcher and native Dock previews remain configurable.
- Enable and disable login launch from the installed bundle. Check Requires approval, System Settings approval and failure alerts without a false success indication.
- Request both permissions from a missing state. Check live status, signing guidance and restoration-safe Relaunch.
- Enable debug logging and reveal its file. Compare each private symbol's status, then confirm pin re-import and reset confirmations preserve native Dock recovery data.
