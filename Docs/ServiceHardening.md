# M7 service hardening

Service and private-wrapper changes only. PermissionsService, AppRelauncher, DiagnosticsService, Features, executable coordination, models and policies belong to the coordinator or other implementation work. No installation, launch, live focus, Dock preference changes or performance measurements were performed here.

## Fixes

- Space-only replies carry both the worker session and inventory revision. A reply from before stop/restart or an intervening inventory cannot overwrite the new state. Deferred inventory/retry callbacks check their session before changing scheduling state. Old observer callbacks are similarly rejected.
- Tracker stop invalidates queued action ownership immediately on main. Awaited focus bridges task cancellation to the AX queue, checks cancellation before individual effects and after waits, and does not activate an app when its tracked AX element has disappeared. An in-progress AX IPC cannot be interrupted.
- Verified focus captures the requested display before awaiting live membership. It rechecks that same display before effects and at final verification, plus focused AX identity and current window membership. Finding the same Space on a different display is insufficient.
- Minimized windows retain the last nonempty membership. Polls do not overwrite their remembered desktop. Previously validated minimized AX roots may survive WindowServer inventory omission or zero alpha while AX still confirms the root. Invalid roots are removed by the usual validation. Unknown membership is never promoted into confirmed local membership for opening.
- Notification observer tokens are removed during tracker/reader teardown. Observer stop disables callback delivery, clears pending work, and invalidates its keep-alive timer when the run loop exits. Owners must still call stop, since the running observer thread retains its state until then.
- AX/CF force casts were replaced by CF type-ID checks and guarded typed conversion, including validation of each array element. Runtime symbol conversion checks pointer size before conversion. Framework handles remain alive for resolved functions.
- Packed remote-token and focus-record builders are independent pure functions, using the existing private API fact report. No signatures were newly researched. Tokens remain 20 packed bytes; focus records allocate 256 zeroed bytes and declare 248 bytes.
- Thumbnail refresh rejects invalid geometry before integer conversion, bounds refresh intervals, checks cancellation after shareable-content waits and before cache writes, and preserves invalidations arriving during content discovery. Removing a thumbnail cancels its request. Restarting visible refresh cancels preceding requests. An already running ScreenCaptureKit operation may still finish internally.
- DogBar is included among regular applications. Its normal Settings/onboarding windows can be tracked and counted. Existing AX role/subrole and window eligibility checks still apply to panels.

## Pinned application API

```swift
let result = await opener.openPinned(bundleURL: url, onSpace: spaceID, rule: optionalRule)
```

The signature is public and returns `NewWindowOpener.Result`: `.opened(windowID)`, `.failed`, `.cancelled`, or `.unknownSpace`. The tracker must already be running and the requested Space must be known and active. Requests for the same standardized bundle URL are serialized by rejection, rather than issuing duplicate launch requests. An already tracked application uses the existing running-app opening path.

For a nonrunning pin, NSWorkspace launches the application with activation. The service bounds its launch-callback wait to five seconds, then polls the tracker for up to three seconds for the app PID and a newly tracked window whose membership confirms the requested desktop. It uses `focusVerified` before returning `.opened`. If launch produced a tracked window on another desktop or with unknown membership, it returns `.failed` without requesting another window. If the app is tracked but produced no tracked new window during that interval, the existing rule-driven opening strategies run. Each strategy waits up to 1.5 seconds for a new confirmed local window.

Cancellation or loss/change of the captured display desktop stops further strategies. Stop/restart invalidates action ownership. NSWorkspace launch callbacks can arrive after cancellation or timeout and are consumed only once. A cancellation arriving between a check and a delivered IPC can still race with that IPC. Delivered launch, reopen, menu, focus and keyboard commands cannot be undone. Key-down/key-up are delivered as a pair once shortcut delivery begins, to avoid a stuck synthetic key.

The API cannot enforce another application's assigned-Space rules or forbid app-driven desktop switches. A slow launch-created window may arrive after the bounded tracker wait and overlap a fallback command. Missing AX permission, sparse remote AX IDs, blocked apps, unknown membership, protected content and application-specific new-window behavior remain limitations. `.failed` means opening/focus could not be verified, not that nothing happened. Callers should report failure without automatic repeated retries.

## Verification

Final `swift build` passed without warnings. Final `swift test` passed all 67 tests, including six service-hardening tests. `git diff --check` passed for this implementation scope. No bundle build/install or app launch was run.

Pure tests cover exact token bytes and padding, focus record fields/coordinates and zeroed storage, identifier extremes, finite/bounded capture dimensions, sticky cross-queue cancellation, pre-cancelled API calls, and display ownership. These tests do not launch apps, invoke AX, focus windows or mutate system settings. The project has no database-backed tests.

Manual checks still required:

- Cancel pinned launch and verified focus while AX is delayed. Confirm no later strategy runs; an already delivered command may complete.
- Launch a nonrunning browser pin that automatically creates a window. Confirm only that window opens and becomes key on the chosen desktop.
- Exercise an app that creates no launch window, one assigned to another Space, and one whose startup exceeds the timeout. Check failure feedback and avoid repeated clicks.
- Pause/restart during a membership poll, AX discovery and visible capture. Confirm old publications do not return.
- Minimize, switch desktops, restore and close windows, including apps that omit minimized windows from their server inventory.
- Unplug the requested display and move between fullscreen/shared/separate Spaces while opening. Confirm failure or cancellation rather than verified success on another display.
- Open DogBar Settings/onboarding and check normal-window tracking; verify nonactivating overlay panels do not appear as ordinary app windows.
- Verify native-Dock reconnect after restart and permission revocation/regrant. Measure CPU, memory and responsiveness separately before asserting budgets.
