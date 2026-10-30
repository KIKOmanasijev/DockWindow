# M7 UI hardening

This report supersedes the earlier integration reports where they describe a disabled New Window button for nonrunning pins, accessory activation for Settings, or periodic login-status polling. Scope is Features, UIHardeningTests and this report. Coordinator, services, models, private wrappers and bundle configuration are owned by the other integrators.

## Implemented fixes

- Nonrunning pinned previews display the application's name and icon. New Window calls the public `NewWindowOpener.openPinned(bundleURL:onSpace:rule:)`. Running apps retain `open(app:onSpace:rule:)`. The Dock context menu uses the same distinction. Space and configured rule are passed to the service; UI does not synthesize a PID or perform AX work.
- A cancelled or superseded preview appearance task cannot dismiss a newer preview. Source-mode changes dismiss the old source. Existing local/global pointer monitors dismiss on icon/bridge/panel exit even when native Dock selection stays unchanged. Pending appearance, opening, close and capture tasks remain cancellation guarded.
- Preview card identity resets for a new presentation so visible-thumbnail callbacks are renewed when reopening the same app. Each surface retains its independent capture lease. No repeating capture task is started while hidden.
- Preview and switcher sessions dismiss on sleep, wake, Space transitions and screen topology changes, cancelling stale work rather than retaining an anchor or desktop target from before the transition. Fullscreen Space changes use this same path. The switcher hides immediately for lifecycle events.
- Switcher dismissal cancels outstanding new-window work. Fade completion checks both cancellation and presentation generation, so cancelling a fade for an error surface cannot hide that surface later. Disabling or pausing hides immediately. Reduce Motion changes update open surfaces and finish an outstanding switcher fade.
- Empty Dock layouts have no interactive material. Material hit testing follows rounded corners for bottom/left/right layouts, preserving magnified icon hits while passing transparent corners through. Offset display edge reveal and hidden side-panel geometry are covered by regression tests.
- Dock mouse-down ownership survives pointer movement through transparent areas until mouse-up or drag completion. Autohide respects that ownership. Preview visibility clears the cancelled hide-task handle, allowing autohide to resume after the preview closes. This fixes a cancelled-handle case that could otherwise leave the Dock permanently shown.
- Dock tracking stops on hide, sleep, missing display and stop. Drag completion invalidates its display link. Stop clears pending press state and layer animations after restoring resting geometry. Dock teardown removes event monitors and notification observers and cancels delayed work. Launch completions carry a lifecycle generation so a completion from before stop/restart cannot mutate the new session.
- Shortcut recording has an explicit owner. Transferring recording ends the old monitor. Stale cleanup cannot release the new owner's hotkey suspension. Recording rejects another window's events and ends on focus loss, close, view removal and teardown.
- Settings uses `.regular` on show and close, preserving the visible Dock identity required by the latest instruction. It no longer temporarily forces accessory activation.
- Settings has no recurring timer. Login status starts with a Checking state and `.notRegistered` placeholder. It is queried when General opens and after a login operation. All `SMAppService.status` reads and login registration/unregistration work run in a detached worker. Reset verifies real login state through that worker before resetting preferences. Concurrent reset/login actions are gated.
- Permission rows use the service's `hasCheckedPermissions` and `isChecking`. The initial state says Checking, never Missing. Requests are disabled during the initial check. Known granted/missing values remain visible during later checks. This presentation does not infer Screen Recording denial from the initial false value.

## Audit notes

Traffic lights are sibling buttons to the title/thumbnail activation buttons in the shared card, including preview overlays. There is no parent tap gesture or nested activation button to commit a card when a traffic light is clicked. They continue to call the existing service actions in place. This code audit is not a claim of verified AppKit/SwiftUI event behavior.

Features contain no raw AX or private-symbol calls and no force unwraps of window-server results. Desktop selection continues to use SpacePolicy, display UUIDs and the shared/separate-Spaces policy. Native-reader selection and image-capture availability remain service responsibilities. Native Dock preference restoration, blank Welcome rendering and application bundle identity remain coordinator/service integration responsibilities.

## Verification

The Swift test target was inspected for database access before running. It has no database integration. `swift build` passes without warnings. `swift test` passes all 67 tests, including 5 UIHardeningTests, with zero failures in the final shared-checkout run.

UIHardeningTests cover initial permission presentation, an empty Dock passing through every sampled desktop point on all edges, rounded material corners with magnified icon hits, side autohide on a display with negative coordinates, and stale recorder-owner release. Existing DockLayout, PreviewGeometry, SwitcherSession and service tests provide additional policy coverage.

No browser, GUI automation, application launch, bundle build, installation, commit, branch, push or PR was performed by this implementation. No runtime CPU, memory, presentation latency, frame pacing or visual-parity result is claimed.

## Manual verification still required

1. Confirm DockWindow's Dock icon remains visible after opening and closing Settings. Verify Welcome content and permission state through the integrator's separate changes.
2. Open General and switch panes repeatedly. Confirm login status loads without blocking input, login registration and reset report real errors, and no periodic Service Management RPC remains after closing Settings.
3. Hover nonrunning pins, then request New Window on each display. Test unknown Space and failure feedback, dismiss during the operation, and verify no late panel appears.
4. Use traffic lights in both surfaces, including save-sheet close vetoes. Confirm the card does not activate or commit from those controls.
5. In native fallback mode, leave the icon while the native reader retains its old selection. Confirm pending previews cancel and visible previews dismiss after the bridge delay.
6. Test bottom/left/right Docks, transparent corners, inter-icon drag travel, long press, external drops and drag cancellation. Open and close a preview with autohide enabled, then confirm hiding resumes.
7. With mixed-scale offset displays and shared/separate Spaces, change desktop, enter fullscreen, unplug the anchor display and sleep/wake during hover delays, opening work and switcher fades. Confirm no orphan panels or late UI.
8. Switch recorder controls, close Settings during recording and reopen. Confirm only one recorder owns the events and normal hotkeys resume after its release.
9. Toggle app Reduce animations and macOS Reduce Motion while a Dock launch bounce, preview hover or switcher fade is active. Verify stop/pause removes animation work and the Dock can resume tracking afterward.
10. Measure idle CPU, memory and latency with the installed signed build. Exercise capture denial/revocation, slow or unresponsive apps and concurrent switcher/preview capture. These require runtime validation and are not established by unit tests.
