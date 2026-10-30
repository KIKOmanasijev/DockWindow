# Dock preview integration

## Coordinator contract

Construct and retain `PreviewController(tracker:actions:thumbnails:settings:newWindowOpener:)` on the main actor. `enabled` starts false. Set it only after permission, pause and feature lifecycle gating. The controller additionally checks `previewsEnabled` and `isPaused`. Set false before stopping the tracker, restoring native preferences, changing Dock modes or terminating. Mode changes should dismiss before routing to the new hover source. No feature starts shared services or requests permissions.

Wire replacement Dock callbacks:

```swift
dock.onHover = { [weak previews] item, anchor, screen in
    previews?.hover(item: item, anchor: anchor, screen: screen)
}
dock.onHoverEnded = { [weak previews] in previews?.hoverEnded() }
dock.onShowWindows = { [weak previews] item, anchor, screen in
    previews?.showWindows(item: item, anchor: anchor, screen: screen)
}
dock.onIconClicked = { [weak previews] in previews?.dismiss() }
previews.onVisibilityChanged = { [weak dock] visible in
    dock?.previewVisible = visible
}
```

The coordinator owns `NativeDockReader` start/stop and subscriptions. Route `$hoveredItem` on the next main-loop turn when replacement Dock mode is off. For a non-nil item choose the NSScreen containing its AppKit global frame midpoint, then call `previews.hover(item: nativeItem, screen: screen)`. For nil call `hoverEnded()`. Do not replay stale `hoveredItem` on every mouse move. The adapter checks the actual pointer against the native icon frame, resolves the app by bundle ID or URL, infers bottom/left/right from the selected display and uses the same controller and panel. Folders and Trash are excluded by the reader. The panel's own pointer monitors close even if the native reader never changes its selected item after pointer exit. Native AX selection delivery can still miss a hover entirely; this service limitation cannot be repaired by UI geometry.

`desktopNumber: ((UInt64) -> Int?)?` accepts the coordinator's cached ordinal lookup. The parent has added `SpacesService.State.desktopNumbers` from managed topology and reads it off-main. Supply that cache here; never perform topology/private calls from the closure. Missing ordinals show `Other desktop (Space ID)` rather than labeling a raw ID as a desktop number. `onError` optionally receives actionable new-window failures; the panel also retains the message. `isVisible` and `onVisibilityChanged` reflect actual panel visibility, not the pending delay.

## Behavior and ownership

Hover delay follows settings, default 0.25 seconds and clamped to 0 through 1. Repeated same-identity anchor updates reposition without resetting the pending delay. While visible, switching identities is immediate. Pointer travel uses a tapered bridge between the icon and facing panel edge. Leaving icon, bridge and panel schedules one 0.2-second close; reentry cancels it. Pending appearance cancels immediately on exit. The controller monitors local and global pointer events independently of reader selection. Outside mouse-down closes and passes the click through. Escape closes, swallowing only a local Escape while owned. Global keyboard observation depends on the existing Accessibility gate.

Show All Windows pins the current app panel. Hover endings and other icon hovers do not replace or close it. Outside click, Escape, explicit dismiss, disabled settings, pause or screen topology changes dismiss it. Window activation closes after delegating to WindowActions. Current-desktop known membership uses `focus(_:requiringSpace:)`; all-desktop or unknown minimized membership follows the existing service fallback. Traffic lights call close, minimize and fullscreen services in place. Tracker updates determine resulting content, including close-veto sheets, renamed titles and empty states.

The preview uses its own `previewScope` and `previewIncludeMinimized`, independently of the Dock and switcher. It includes hidden apps, preserving dimming and badges from the shared card. Cards use `WindowCardView` in `.overlay` layout with live title/traffic-light preferences. All-desktop cards on a different Space carry an ordinal badge. The app header, horizontal scrolling, optional edge pointer and material/theme preferences update live. Capture dimensions retain a consistent card ratio; the actual captured image aspect fits inside it.

A running app with zero windows in scope shows a large icon, scope explanation and New Window. This calls `NewWindowOpener.open(app:onSpace:rule:)` with the anchor display's current Space and configured per-app rule. The panel pins during verification, disables repeat requests and shows progress. Opened closes; failed or unknown Space stays visible with guidance to the app's File menu. Dismiss, disable and a new app cancel queued work. Already delivered application commands cannot be undone. A nonrunning pinned app has no valid service PID: its New Window button is disabled until launched through the Dock, and the preview updates when tracking discovers the process. The preview does not synthesize an invalid PID or issue direct AX commands.

`VisibleThumbnailSession` is owned per preview. Cached images render first, service revision redraws successful captures, and lazy card appearance supplies eligible visible IDs. A missing image uses the shared large-icon placeholder. Size, backing scale, interval and visible IDs update the lease. Interval zero captures once per changed visible set. Dismiss stops capture scheduling, cancels appearance/close/open/update tasks and removes both event monitors. Deinitialization also removes monitors and cancels tasks. No pointer timer runs. An in-flight shared capture may finish into cache after close; stopping previews never cancels the switcher's lease. Keep coordinator inventory-to-shareable-content invalidation wiring.

All anchors, screen bounds, placement and bridge tests use AppKit global points. Only thumbnail capture uses `backingScaleFactor`. Panel dimensions clamp to the target visible frame, including negative origins and offset displays. Native edge inference uses the full screen frame; replacement mode uses configured Dock position. Display topology changes dismiss rather than leave an orphan panel on a disconnected screen.

## Verification

`swift build` passed without warnings and `swift test` passed 54 tests, including six PreviewGeometry tests. Tests cover centered placement, both side edges, clamping and oversized panels, offset-screen edge inference, tapered bridge inclusion/exclusion and translation invariance. Test sources were checked for database integration before running; this Swift suite uses no database. Only Features/Previews, this document and PreviewGeometryTests are owned by this implementation. Parent permissions, services and coordinator changes remain untouched. No browser, AX/private call, app launch, bundle build, installation, commit or push was performed. Runtime capture, interaction, visual parity and performance budgets remain manual verification items.

Manual checks after coordinator integration:

1. Hover with default, zero and maximum delays. Move over a magnifying icon without resetting the wait; sweep between icons after opening and confirm immediate changes.
2. Traverse icon, bridge and panel for bottom, left and right Docks. Leave all three for 0.2 seconds, then test reentry before the timeout.
3. Open Show All Windows. Move outside and over other icons; confirm it stays pinned until outside click or Escape. Confirm ordinary icon clicks close and continue their normal Dock action.
4. Disable replacement mode and test native Dock on each edge. Exit an icon with no subsequent AX selection update; confirm the panel still closes. Test native click and Escape dismissal.
5. Use mixed-scale displays to either side and above/below the primary. Confirm anchors stay in points and panels clamp. Disconnect the preview display while pending and visible.
6. Toggle scope, minimized inclusion, titles, controls, pointer, material, theme and size live. Verify remote desktop ordinal badges through the supplied topology cache and minimized/hidden placeholders.
7. Close, minimize and toggle fullscreen with traffic lights. Confirm cards update from snapshots, save sheets can veto close, and thumbnail/title clicks restore and focus exactly one window.
8. With zero scoped windows, use New Window. Check success, unknown Space and failed verification feedback. Launch a nonrunning pin from the Dock and confirm its empty preview updates when the process appears.
9. Test cached first paint, refresh intervals including zero, horizontal scrolling and a concurrent switcher. Dismiss, disable or pause mid-delay and mid-capture; confirm no late preview, repeating capture work or retained event monitors.
