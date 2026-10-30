# Replacement Dock integration

## Lifecycle and ownership

All presentation types are main-actor AppKit/CALayer types in DockWindowCore. Construct and retain:

```swift
let dock = DockController(
    tracker: tracker,
    actions: actions,
    settings: settings,
    pinnedApps: pinnedApps,
    newWindowOpener: newWindowOpener
)
```

Call `start()` only after the coordinator has applied `NativeDockController.beginSession(dockEnabled:)`, started tracking and passed permission/pause gates. Call `stop()` before restoring native preferences, pausing, disabling or terminating. Start/stop are idempotent. The controller owns its panel, event monitors, subscriptions, display link, delayed hide and opening tasks. It does not start shared services, request permissions, alter native Dock preferences or activate DockWindow. The coordinator must await native restore/endSession through the existing delayed-termination path. Keep the reader-to-tracker badge wiring from ServiceIntegration.md.

Snapshot, pin and settings changes are consumed on the next main run-loop turn so Combine's willSet publication does not produce stale reads. Main display means the primary/menu-bar display, not the focused-window display returned by NSScreen.main. Mouse display follows pointer movement except during dragging or an open preview. Screen topology changes reselect and reframe. Current Space selection uses the display UUID and shared-Spaces policy fallback.

The panel uses Dock window level, nonactivating style, clear backing and the specified all-Spaces/stationary behavior. Its transparent overflow passes input through by toggling ignoresMouseEvents from local/global pointer monitors. A view display link is created only while tracking inside the Dock or dragging, and invalidated on exit/stop. There is no idle animation timer or feature AX polling. Autohide uses one cancellable delay and an 180 ms slide; touching the selected screen edge reveals it. An open context menu or preview keeps it visible.

## Preview hooks

- `onHover: ((DockItem, CGRect, NSScreen) -> Void)?` supplies the icon's actual AppKit global frame and display. Anchors update each tracking frame, even for the same item. M5 must compare item identity before starting/restarting its hover delay. This callback does not implement the preview delay itself.
- `onHoverEnded: (() -> Void)?` fires when application hover ends, including moving to Trash, transparent overflow, hiding or stopping. M5 owns bridge geometry and the delayed close.
- `onShowWindows` has the same signature as onHover and requests a pinned-open preview from Show All Windows. This menu action is disabled until a callback is wired.
- `onIconClicked: (() -> Void)?` closes a preview before normal click or context-menu handling.
- Set `previewVisible = true` while a preview is visible to suppress name labels and defer autohide. Set false on close.

No callback itself focuses or mutates settings. Window menus always list current-desktop windows, independent of the Dock's visible-app scope. Show All Windows delegates preview content/scope to M5.

## Rendering and interactions

Finder remains first and cannot be dragged, unpinned or removed. Stored pins follow, then scoped running apps with session reorder, optional separator and Trash. Dimmed remote apps, minimized visibility and count scope come from existing policies. Indicators support capped per-window dots, single dot, hollow running-state ring, custom color and 150 ms count crossfades. Icons include reader-supplied badges, launching bounce, material/glass provider background and truncated name capsules. Reduce Motion suppresses bounce, count/slide animations and autohide slide duration. The background provider is retained and updated when material/theme/base size changes.

Magnification uses cosine falloff in base icon widths and actual expanded frames for hover/click hit testing. Crowded Docks proportionally shrink icons so the strip fits the display. Side Docks run from Finder at the top to Trash at the bottom. Dragging uses stable base geometry, with explicit neighbor slide animation and an image drag session. Drop a running app into the pinned region to persist a pin. Pin reorder persists through PinnedAppsStore; running reorder lasts for the controller session. Finder is never persisted as an ordinary reorder target. Drag out beyond 60 points and release removes a pin with a fade/shrink; a running app is also suppressed until it exits or the controller stops. Cancelling a drag restores the prior visual order.

File URL drops highlight application/Trash targets. App drops use NSWorkspace with the chosen application. Trash drops use FileManager.trashItem off-main and report individual failures. Trash opens in Finder; Empty Trash requires explicit confirmation and runs Finder AppleScript off-main. Its icon is refreshed from NSWorkspace on inventory/settings updates and after our own Trash actions. External Trash contents are not independently watched.

Right click or a stationary 500 ms press opens the current-window list, New Window, Show All Windows, Hide, Quit, alternate Option Force Quit, Options pin toggle and Show in Finder. Optional scrolling cycles current-desktop windows with an 180 ms event gate. Third-party app Dock menus are not read.

## Actions and errors

Click decisions use DockClickPolicy with current display Spaces even when the Dock shows all desktops. Existing apps with no local windows use NewWindowOpener and the per-app rule. Nonrunning pins launch through NSWorkspace. Current-window focus awaits `focusVerified(_:requiringSpace:)`; missing confirmed membership is rejected with an actionable message. A single focus task is retained so a later request cancels earlier verification feedback. New-window sequences are bounded by the service and deduplicated by item. Stop cancels queued task work but cannot undo commands already delivered to another app.

`onError: ((String) -> Void)?` receives actionable opening, focusing, file-drop and Trash errors. Without a callback the controller shows an NSAlert. The coordinator can route this to its own nonmodal error surface. Launch errors report the app location. Unknown current Space does not silently activate another desktop. Current-desktop isolation still depends on the existing service and native Dock mitigation; assigned Spaces, fallback activation and app behavior remain runtime limitations. M4 owns further verification and regression tests.

## Verification and remaining criteria

`swift build` and `swift test` pass without new warnings. There are six pure DockLayout tests, with the complete suite currently at 42 passing tests. No database, browser, native Dock preference mutation, UI launch, focus injection, Trash operation or file-opening operation was performed. Only Features/Dock, this document and DockLayoutTests were changed. Release assembly/install and lifecycle wiring belong to the integrator.

The following are not claimed as verified: native visual parity, pointer passthrough at high pointer speed, ProMotion frame pacing, idle CPU/memory budgets, fullscreen visibility, per-desktop isolation for real applications, cross-display drag behavior and runtime AppleScript permissions. The SDK-compatible background is used with the current SDK; native Liquid Glass requires a newer SDK through the existing provider. The Dock cannot reserve screen space. Minimize animations target the hidden native Dock. Running-only reorder/removal is session-local. External Trash changes do not immediately refresh its icon. A screenshot/performance/manual pass is still required before declaring the M3 definition of done satisfied.

Manual checks after integration:

1. Enable, pause, restore, resume and quit. Confirm native preference restoration and that our panel never becomes key.
2. Exercise bottom/left/right and primary/mouse displays, including an offset mixed-scale display and hot unplug. Click windows beneath transparent overflow.
3. Sweep icons at different tile/magnification sizes, disable magnification, change theme/material, and toggle Reduce Motion. Check labels, clipping and preview label suppression.
4. Create, minimize and close multiple local/remote windows. Verify counts, cap, single dot, hollow ring, custom color, dimmed apps and count fades.
5. Launch a pinned app, check bounce stops, check badge updates, and test missing app/opening/focus errors. Confirm exact local-window focus and no unintended desktop switch.
6. Reorder pins and running apps, pin a running app by drop, cancel a drag with Escape, and remove by dragging out. Confirm Finder cannot move and pin order survives restart.
7. Drop several files on an app and Trash, including a failing file. Open Trash and cancel/confirm Empty Trash in a disposable test setup.
8. Open menus by right click and long press, hold Option for Force Quit, and use window, New Window, Show All Windows, Hide, pin and reveal actions. Confirm menu tracking defers autohide.
9. Toggle scrolling and autohide. Check cycling direction/rate, hide delay, edge reveal and preview bridge behavior once M5 is wired. Verify no display-link activity after pointer exit or stop.
