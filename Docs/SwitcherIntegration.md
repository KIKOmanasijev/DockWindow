# Switcher and shared presentation integration

## Coordinator wiring

Construct and retain on the main actor:

```swift
let switcher = SwitcherController(
    tracker: tracker,
    actions: actions,
    thumbnails: thumbnails,
    settings: settings,
    newWindowOpener: newWindowOpener
)
let hotkeys = HotkeyEventTap { [weak switcher] command in
    switcher?.handle(command)
}
```

`enabled` defaults to false. The coordinator must set it only when Accessibility, Screen Recording, pause and overall lifecycle gating permit operation. Match the event tap's configuration.enabled to this gate, `settings.switcherEnabled` and `!settings.isPaused`. Publish a complete HotkeyConfiguration when shortcut or action settings change. The switcher also guards the preference and pause state itself. It never requests permissions, starts the tracker, creates an event tap, changes native Dock preferences or activates DockWindow.

On shutdown or pause set `switcher.enabled = false` and disable/stop the tap. `dismiss()` cancels the delayed appearance, stops this panel's refresh lease and closes without focusing. On ordinary UI dismissal it fades for 120 ms unless Reduce Motion applies. `isActive` is published and includes the appearance-delay period. `isVisible` reflects the panel, including its short outgoing fade. Do not use isVisible as the tap gate: quick switching must begin before the panel is visible.

`onSessionEnded` fires after commit, cancel, empty inventory, selected-list exhaustion, and disabling an active session. It also fires when an attempted begin has no eligible items or no known frontmost app for a same-app session. The callback is synchronous on the main actor and never itself calls the tap.

### Tap synchronization required

The current HotkeyEventTap has no public endSession API. The integrator should add one and wire:

```swift
switcher.onSessionEnded = { [weak hotkeys] in
    hotkeys?.endSession() // Add this to HotkeyEventTap, not to the switcher.
}
```

This method must end the worker's active session, clear heldShortcut and its main-actor hasDeliveredSession, and invalidate already queued commands for that session. Preserve `suppressedKeys`: the owned trigger/action key-up must still be swallowed after a mouse commit or Escape. Do not implement this as stop/start, disabling configuration, or a full reset that loses owned key-ups. Modifier-release commit and Escape already clear worker session ownership before delivery; calling endSession for them should be idempotent.

Without this bridge mouse commit still focuses and closes correctly, but the tap continues treating the held-modifier interval as active until modifier release. An empty list has the same mismatch. The controller ignores those extra commands, but tap ownership should be synchronized for correct subsequent input. No AppDelegate or tap code is modified by the switcher implementation.

Continue the existing tracker inventory-to-thumbnail invalidation wiring described in ServiceIntegration.md. The switcher observes `$snapshot` on the next main-loop turn so it reads the newly assigned snapshot rather than Combine's willSet value.

## Session behavior

`handle(_:)` accepts the existing SwitcherCommand. A forward begin selects index one, wrapping for a single item; reverse selects the last item. Repeated begin behaves like next/previous. The first begin captures the display under the mouse and optional frontmost PID. It does not follow later mouse movement onto other displays during the same session. A screen configuration change retargets and recomputes placement/filtering.

Appearance delay comes from settings, default 120 ms. A commit before the delay focuses without ordering the panel in. No capture timer starts during the delay. Commands for next/previous/left/right wrap through the list. Vertical arrows preserve the column and wrap rows, clamping the final short row. Hover selects only after the pointer moves from its position at begin, so showing a panel beneath a stationary pointer cannot replace index one. Thumbnail/title clicks commit. Traffic lights operate in place without committing. Their availability is independent of keyboard W/M/H/Q preferences.

The live list uses SwitcherPolicy, WindowFilter and SpacePolicy. Current-desktop/all-desktop and minimized/hidden settings are independent of the Dock. Screens=all uses the union of each display's current Space; withMouse uses that display's current Space plus a physical display intersection filter. Shared Spaces use the existing main fallback. Screen frames are converted from AppKit coordinates to the tracker/Quartz convention before filtering. Windowless tiles are added only for apps with no windows anywhere, according to the existing policy.

`SwitcherSession` is pure value state. `SwitcherTileID.window(id)` and `.app(pid)` are stable despite title, focus timestamp, minimized or hidden changes. Updates preserve a surviving selected ID; removing it selects the next tile at the old index or the last remaining tile. Empty updates cancel the session. MRU is recalculated from snapshots without losing selection. Public begin/update/select/move/moveVertically APIs can be exercised by the integrator's test target without AppKit UI activation.

Focus delegates to WindowActions. For a known matching current Space it uses `focus(_:requiringSpace:)`; all-desktop and documented unknown-membership fallback use `focus(_:)`. Close, minimize, fullscreen, hide and quit call only the corresponding service APIs. Closing does not optimistically remove a tile because an app may veto close or show a save sheet. The next tracker snapshot updates the list.

Windowless commit uses `NewWindowOpener.open(app:onSpace:rule:)`, targeting the mouse display's current Space even when all current displays are included. It uses the configured per-app rule. `.failed` and `.unknownSpace` invoke `onNewWindowFailure` if supplied. Otherwise the reused panel shows a short message directing the user to the application's File menu plus a Dismiss button. The sequence is cancelled when disabling or starting a new session. The underlying opener activates the app as part of its strategy. Its documented activation/Space limitations and native Dock mitigation still apply.

## Reusable UI APIs

All views and providers are main-actor types in DockWindowCore.

- `WindowCardView(window:app:image:thumbnailSize:layout:selected:selectionColor:showTitle:showTrafficLights:reduceMotion:select:activate:close:minimize:zoom:)` renders the same thumbnail surface in `.header` switcher layout or `.overlay` preview layout. Supply the cached CGImage, optional TrackedApp, closures and setting values. It contains no AX/private calls, focus logic or capture ownership. The parent must observe ThumbnailService revision to redraw cached images. `select` is a hover callback. `activate` is a thumbnail/title click. Traffic lights call their own closures without activating the card.
- `TrafficLightsView(close:minimize:zoom:)` provides grey resting controls with colored hover controls, help and accessibility labels. Zoom means service fullscreen toggle.
- `WindowTitlePill(app:title:showsAppName:)` provides the icon, semibold app name and middle-truncated secondary window title. Hide the app-name line when the preview header already names the app.
- `VisualEffectBackground(material:cornerRadius:theme:)` uses active behind-window NSVisualEffectView with rounded clipping and a half-point light border. Material and forced/system appearance update in place.
- `Theme.selection(_:)`, `color(_:)`, `appearance(_:)`, `material(_:)` and `reducesMotion(_:)` share settings conversions. Reduce Motion combines the app preference and macOS accessibility preference. Switcher selection uses system accent or custom sRGB color. The panel follows system/light/dark theme and live settings.
- `SwitcherPanel` is a reusable borderless nonactivating panel at popUpMenu level, joining Spaces and fullscreen, with clear backing and a shadow. It never becomes key or main. The controller creates it and its NSHostingView once. The grid caps width at 90% and height at 85% of the display's visible area and scrolls vertically. It scrolls the selected ID into view. Tiles use the configured maximum thumbnail dimensions while retaining captured image aspect ratio.

## Independent visible-thumbnail lifecycle

Use one `VisibleThumbnailSession(service:)` per switcher or preview panel. Call `update(windowIDs:interval:size:scale:)` when visible IDs, refresh interval, target dimensions or display backing scale change. Call `stop()` on close. Interval zero performs one refresh per changed visible set and no recurring work. Lazy grid tile appearance/disappearance supplies the switcher's visible set. IDs are intersected with current snapshot items before scheduling; capture failures keep cached thumbnails and fall back to the large app icon. Minimized and hidden tiles are dimmed and badged.

This helper deliberately does not call ThumbnailService.startRefreshingVisible or stopRefreshingVisible. Those APIs own a single shared task and stop can cancel requests belonging to other consumers. The panel-owned helper calls `refresh` through the same deduplicated service and capture gate. Cancelling a lease stops future refresh rounds without cancelling another consumer's requests. An already started ScreenCaptureKit request can finish and populate the cache after closing. There is no capture timer while hidden. Previews can use this helper concurrently with the switcher.

## Dock background provider

`DockBackgroundProviders.preferred()` returns an existential `DockBackgroundProvider`. Retain one provider, call `makeBackgroundView()`, insert the view behind icon layers, and call `updateBackgroundView(_:material:cornerRadius:theme:)` on setting or geometry changes. The provider view should fill the visible Dock background bounds, excluding magnification and label overflow. The caller controls its layout.

The default MaterialDockBackgroundProvider supplies behind-window blur, rounded inner border, faint top highlight and soft shadow. GlassDockBackgroundProvider references NSGlassEffectView only inside `#if compiler(>=6.2)` and `@available(macOS 26.0, *)`. The factory also checks running OS availability. The installed SDK is 15.5, so only the fallback was compiled here. Installing Xcode 26 or newer permits the native implementation. No dynamically invented selector calls are used.

## Verification and remaining integration

`swift build` passed without warnings after the feature implementation. `swift test` passed all 32 tests, including current model/policy tests and the separate hotkey delegate's tests. The test target contains no database integration. No window focus, capture, Dock preference mutation, app installation or app launch was performed for verification. Build/install/commit remain with the main integrator. New pure SwitcherSession paths are not yet covered by an XCTest file because Tests is outside this delegate's exclusive ownership. Add tests for forward/reverse 0/1/N items, stable identity through MRU/title changes, middle/last removal, empty updates, horizontal wrapping and vertical navigation through a partial final row.

Manual checks after coordinator and tap wiring:

1. Tap Cmd+Tab and immediately release. Confirm previous-window focus and no visible panel. Hold long enough to see index one selected. Test reverse first press and a single-window session.
2. Cycle with Tab, Shift+Tab and all arrow keys across several rows. Confirm selection stays visible while scrolling and Escape leaves the original window focused.
3. Open beneath a stationary pointer. Confirm index one survives until the pointer moves. Hover a different tile and click its title or thumbnail, then release the modifier. Confirm only that window focuses.
4. Exercise close/minimize/fullscreen traffic lights and W/M/H/Q. Disable individual keyboard actions and confirm the corresponding traffic light still works. Test a close-veto save dialog.
5. Rename, close, minimize and create windows externally while the panel is open. Confirm surviving IDs stay selected, removal moves selection sensibly, and removing the last tile closes the session.
6. Test current/all desktop scope, all/mouse screens, separate/shared Spaces and a fullscreen Space. Confirm centered placement on the initial mouse display and correct filtering on secondary displays above/below the primary.
7. Show a windowless app and commit. Confirm the new-window rule is used on the current mouse desktop. Exercise failed/unknown-Space outcomes and dismiss the error surface.
8. With and without Screen Recording, verify cached images or icon placeholders, live refresh, interval zero and no repeating refresh after close. Open previews concurrently after integration and confirm closing either surface does not stop the other's refresh.
9. Change theme, material, corner radius, custom selection color, thumbnail dimensions and Reduce Motion live. Pause/disable during the appearance delay and confirm no late panel appears. Hot-plug a display while open.

UI matching, under-50-ms presentation latency, memory and idle CPU still require the user's on-screen/performance verification. The guarded SDK26 implementation requires a newer Xcode build to validate.
