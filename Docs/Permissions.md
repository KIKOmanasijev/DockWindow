# Permissions

DogBar needs Accessibility and Screen Recording. `PermissionsService` reads access on a worker queue. It requests access only when the user presses a button.

## What the status means

`AXIsProcessTrusted()` and `CGPreflightScreenCaptureAccess()` only answer whether the **current process** has access. The SDK header says preflight "checks whether the current process already has screen capture access". A `false` answer does not say why. Most often DogBar has not asked yet, or the switch in System Settings is still off.

| `PermissionAccess` | Meaning | Suggested copy |
| --- | --- | --- |
| `.checking` | The first check has not finished yet. | "Checking…" |
| `.granted` | This process has access. | "Granted" |
| `.notRequested` | DogBar has never asked. This is normal on first launch. | "Not allowed yet" + **Allow…** |
| `.requesting` | A request is in progress. | "Asking macOS…" (disable the button) |
| `.waitingForUser` | DogBar asked and macOS still reports no access. | "Turn on DogBar in System Settings" |

Do not show "Unavailable to this build" for any of these states. A broken grant (the switch is on but the process still has no access after a fresh launch) needs evidence such as `adHoc=true`, a different signing identity or a different bundle ID in the log. It cannot be inferred from `false` alone.

When `screenRecordingNeedsRelaunchAfterGrant` is true, DogBar asked in this process. macOS applies a new Screen Recording grant only to processes started after it was switched on. Offer **Quit & Reopen** (macOS also offers this after the toggle).

## Request flow

1. The user presses the button for Accessibility or Screen Recording (`openAccessibility()` / `openScreenRecording()`).
2. If access is missing and DogBar has not asked yet in this process, it calls the system request once on a dedicated serial queue. Clicks while that request is in progress are ignored.
3. DogBar opens the Privacy pane only after the request returns. By then DogBar is already listed there. If the request is still waiting on a system alert after 2 s, the pane opens anyway, once.
4. Further clicks in the same process open the pane directly. macOS does not show the prompt again.
5. Polling (`refresh()`) never requests access. Request history is stored in `UserDefaults` (`PermissionsService.requested.*`) only to tell `.notRequested` apart from `.waitingForUser` after a relaunch.

DogBar never grants access itself, resets TCC or reports success it has not seen. `ThumbnailService` checks preflight before calling ScreenCaptureKit, so taking thumbnails never shows the prompt.

## Installation location

`installLocation` is `.diskImage` (read-only volume, e.g. the mounted DMG) or `.translocated` (Gatekeeper's randomized path for a quarantined app that has not been moved). In those cases, ask the user to drag DogBar to Applications, eject the DMG and open the copy in Applications *before* granting permissions. The grant then belongs to the copy that stays. Quit & Reopen from a DMG copy also fails once the DMG is ejected.

## Recovering on a user's Mac

1. Quit DogBar. Drag `DogBar.app` from the DMG to Applications. Eject the DMG. Open DogBar from Applications.
2. In onboarding, press the Screen Recording button. Allow access in the prompt or in **System Settings → Privacy & Security → Screen & System Audio Recording**, and turn DogBar on.
3. Choose **Quit & Reopen** when macOS asks, or use **Relaunch DogBar**.
4. If the row still is not granted after a fresh launch from Applications, collect the macOS version, the app path and the `Effective permissions:` line from the DogBar log (it includes `install=`, `adHoc=` and `bundle=`). Do not reset TCC.
