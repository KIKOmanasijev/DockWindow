# Service integration

All code here is independently implemented from the specification and API facts in `PrivateAPIReference.md`. This layer does not enable features, alter Dock preferences, or request permissions merely by being constructed. AppDelegate, Features, Package.swift, PermissionsService, models, and policy tests remain outside this implementation scope.

## Ownership and lifecycle

Create `WindowTracker`, `WindowActions(tracker:)`, `ThumbnailService`, `NativeDockReader`, `PinnedAppsStore`, and `NewWindowOpener(tracker:)` on the main actor. Retain them in the application coordinator. Call tracker `start()` once permissions allow operation and `stop()` on pause or shutdown. Start and stop the native reader with the features that consume badges or native Dock previews.

`WindowTracker.snapshot` publishes `WindowSnapshot` through Combine. It contains apps, MRU windows, and `activeSpaceIDs` keyed by display identifier. Snapshots contain no AX references. Observe `$snapshot` from UI; do not poll AX from Features. `refresh()` requests inventory recovery. `allowedSubroles` defaults to standard windows and dialogs. `setBadges(_:)` accepts bundle identifier to label mappings. `dumpWindows()` logs apps, window IDs, titles, MRU dates, memberships, and active Spaces for the coordinator's debug menu item.

`AXObserverHub` owns observer sources on its own background thread and run loop. All subscription work and callbacks stay off main. Tracker AX inventory and actions run on one serial worker queue. Each app receives a 0.25 second AX timeout. The native reader and new-window menu walker have separate serial queues. The hub must be stopped by its owner; tracker and reader do this on stop and deinitialization. Explicit stop also unregisters workspace observers.

A burst of inventory notifications coalesces before scanning, then finished snapshots coalesce for 16 ms on main. A 1.5 second timer performs Space-only work on a separate queue. A stalled AX call can delay serial inventory and actions but cannot block main or stop the Space query thread. Updating the published state still waits for the serial inventory queue. App-specific queue isolation could reduce that latency further if measurement warrants it.

## Private API status

Merge `SkyLight.shared.availability`, `AXPrivate.shared.availability`, and `ProcessFocus.shared.availability` for Advanced settings. Each dictionary exposes individual symbol presence. These wrappers keep runtime-loaded handles alive and use C function pointers with explicit Copy/Create ownership. `isAvailable` is a capability summary, not proof that an individual call succeeds on this OS.

SkyLight exposes topology, current Space, union memberships and per-Space window IDs. AXPrivate exposes window IDs and packed remote tokens. ProcessFocus sends a 256-byte allocated record with declared length 248, far-positive coordinates, and mouse-down only. Missing symbols return empty/nil/false rather than trapping. All service calls into AX run off main. Features should use services rather than these wrappers.

## Membership and discovery limitations

`CGSCopySpacesForWindows` returns a flat union. It cannot return window-indexed memberships in one call. The implementation deliberately departs from the impossible single-call requirement: one topology query, one union query to discover occupied Spaces, and one inverse inventory per Space, with singleton recovery for IDs missing from those inventories. Poll cost scales with desktop count plus exceptional IDs, rather than assigning the union to every window. No AX runs in this timer. CPU budgets still need measurement on the user's window and desktop counts.

Empty memberships preserve the last known membership. `rememberedSpaceIDs` follows successful membership reads and survives minimize. Unknown membership remains unknown, so the pure window policy may apply its documented all-desktop fallback. Display identifiers come directly from topology, including `Main` when Spaces are shared; use the existing display policy to select the Dock's or switcher's current Space. Fullscreen IDs are exposed in `SpacesService.State.fullscreenSpaceIDs`.

Discovery merges published, focused, main and cached AX elements. For missing layer-zero WindowServer IDs, remote-token discovery uses packed 20-byte tokens, UInt64 IDs at byte offset 12, root-role validation, a 40 ms monotonic per-app slice, a 256-candidate slice cap, a 250 ms inventory-wide scan budget, and a short per-candidate timeout. Cursors and cached valid elements survive subsequent slices. Gap recovery retries at most sixteen times per app with a three-second backoff, then only subsequent inventory events continue the cursor. A long-lived app's sparse or high IDs can remain unresolved. Finite scans never prove absence. An individual IPC can exceed a slice deadline by its timeout. Process state clears when the app leaves the running inventory.

## Actions and verified opening

`WindowActions` exposes `focus(_:)`, `focus(windowID:)`, `close(_:)`, `minimize(_:)`, `zoom(_:)`, `hide(pid:)`, and `quit(pid:force:)`. Window overloads also exist for hide and quit. Zoom toggles AX fullscreen, matching the requested green control. Focus restores minimized state, unhides, uses the private front/key sequence, and raises/sets main. Public activation is a logged fallback when the private operation fails; that fallback may switch Spaces.

`focus(_:requiringSpace:)` rejects targets without matching known membership before enqueueing focus. For operations that need an awaited outcome, use `await focusVerified(_:requiringSpace:)`: it rechecks singleton membership before the attempt, then checks focused AX window identity and the resulting active Space plus target membership. A false return reports uncertainty or failure. It cannot undo an app-driven Space switch.

`await NewWindowOpener.open(app:onSpace:rule:)` tries a matched AX menu command, a pid-targeted shortcut, then application reopen. Supply a `NewWindowRule` for localized menu titles and shortcut overrides; defaults come from the models. The detached AX menu tree is matched using `NewWindowMenuPolicy`. AX menu traversal has depth, node and time bounds. Each strategy waits up to 1.5 seconds for a new tracker window with the correct PID and confirmed target membership, then awaits verified focus. `.opened(id)`, `.failed`, `.cancelled`, and `.unknownSpace` are explicit outcomes. Only one opening sequence per PID runs at a time. Cancellation stops subsequent strategies but cannot reverse an already delivered menu/key/reopen event.

The coordinator must have hidden the native Dock through NativeDockController before current-desktop activation strategies, so `workspaces-auto-swoosh` is disabled. That preference is a mitigation, not a universal guarantee. Assigned Spaces, fullscreen windows and app-specific behavior can still move desktops or decline to create a window. Show an actionable failure message when opening cannot be verified; do not treat `.failed` as success or repeatedly issue more commands indefinitely.

## Captures

`cachedImage(for:)` is synchronous and returns a CGImage immediately. `await refresh(windowID:size:scale:)` refreshes a thumbnail and retains the old image on failure. `capturedAt(for:)` exposes cache age. The LRU holds 150 images by default and updates usage on reads. The capture gate permits at most four captures across every caller. Requests for the same ID share a task. Target dimensions preserve aspect ratio, apply backing scale, and cap at 2048 pixels on either axis. Empty transparent images are rejected; opaque protected/blank content cannot always be distinguished from legitimate black imagery.

Wire `tracker.onWindowInventoryChanged` to `thumbnailService.invalidateShareableContent()`. Shareable content is cached and invalidations refresh at most once per second. Call `startRefreshingVisible(windowIDs:interval:size:scale:)` when a panel opens or its visible IDs change, and `stopRefreshingVisible()` when it closes. Interval zero captures once and disables periodic refresh. Stop cancels queued requests; an in-flight screenshot cannot necessarily be interrupted. Observe `$revision` to redraw successful capture updates. If no cached image exists, Features renders the app-icon placeholder. No deprecated capture API is used.

## Native Dock persistence and reader

`NativeDockController` is an actor. Call `try await beginSession(dockEnabled:)` before presenting replacement UI. It preserves the original five relevant preferences, including their property-list types and explicit missing keys, before any change. A stale backup is reused rather than overwritten. Invalid backups block mutation. Preference changes use Process arguments to `/usr/bin/defaults`, without a shell. Restart uses `/usr/bin/killall Dock`.

On Pause, disable, or Restore Native Dock, call `try await restore()`. On ordinary termination call `try await endSession()` and wait for completion before terminating the app. Do not launch an unawaited task in applicationWillTerminate and expect it to finish. Use the application's delayed termination path if necessary. Restore deletes keys that originally did not exist. The backup is removed only after every restoration write and Dock restart succeeds. Failed or partial restoration retains the durable backup for retry. `hasBackup` supports status reporting. No crash signal handler performs unsafe Foundation work. Crash recovery occurs at next launch; a crash cannot restore preferences while the process is dead.

`NativeDockReader.items` publishes app Dock items and `hoveredItem` publishes the selected icon only when its frame contains the mouse. Frames are converted from Quartz to AppKit global coordinates using the primary display's top edge. AXURL resolves bundle identifiers; badges are keyed by bundle ID. Observe `$items` and pass `reader.badges` to tracker `setBadges`. Badge reads run every two seconds. Selection notifications trigger reads immediately. After Dock restart, the reader reconnects on workspace launch or timer recovery. Selection is an AX signal, not a guaranteed mouse-hover API; the panel coordinator must still apply delay, pointer bridge and close behavior. Folders and Trash are excluded from application previews.

`PinnedAppsStore` imports the native persistent-apps list once if no own saved list exists. `apps`, `pin(bundleIdentifier:url:at:)`, `unpin(bundleIdentifier:)`, `move(from:to:)` and `reimportNativeDock()` provide ordered persistence. Reimport is an explicit overwrite of DogBar's pins only. File existence and bundle ID parsing use the shared pure policy. Neither the store nor the reader writes native Dock pins.

## Verification and manual checks

`swift build` and the current 22 tests passed during implementation. Policy tests belong to the model/logic delegate. No service was activated, no native Dock preference was changed, and no focus event was injected during verification. This delegate did not build/install the app bundle because executable integration belongs to the coordinator.

- Launch with AX permission absent, then grant it and start tracking. Confirm responsive UI and useful debug output.
- Create, rename, move, minimize, restore and close windows; verify MRU, remembered memberships and window counts.
- Put multiple windows of one app on different desktops. Compare membership logs, including a fullscreen Space and shared/separate display Spaces.
- Switch exact windows repeatedly and check for unwanted clicks, resizing, activation of another Space, or incorrect key-window identity.
- Open a new window using each strategy in Finder, a browser, Terminal and a localized app. Check reported failure for apps that decline the operation.
- Open previews for more than four windows. Verify cached first paint, bounded fresh capture work, minimized-image retention and stop-on-close.
- Read native Dock badges and hover items, restart Dock, and check reconnection and mixed-scale display anchor geometry.
- Record original preference values and missing keys, enable/restore, then repeat with a forced process exit followed by disabled launch. Verify exact restoration and recovery backup retention after errors.
