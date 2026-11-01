# Onboarding

DogBar's first-run wizard: `Sources/DogBarCore/Features/Onboarding`. Art: `Resources/Onboarding` (bundled at `Contents/Resources/Onboarding`).

## Flows

| Mode | When | Steps |
| --- | --- | --- |
| `firstRun` | No onboarding state and no earlier DogBar defaults | Welcome → Dock per desktop → Previews → Switcher → Setup |
| `recovery` | Tour done, but a permission is missing, or DogBar runs from a disk image | Setup |
| `privacyOnly` | Tour done and permissions on, usage-data question never answered | Setup (everything already allowed, choice still open) |
| `tour` | Paw menu or app menu → **Welcome Tour…**, Settings → **Show Setup** when nothing is missing, or launch with `--onboarding-tour` | Full tour. Saves nothing on its own |

Welcome and each feature screen can be skipped straight to Setup. Setup is one screen: the install-location banner when needed, one card per permission, and the usage-data choice (two equal buttons, nothing preselected, no auto-advance). The primary action is the next permission's **Allow…** until both are on, then **Start DogBar**. **Finish Later** always closes.

- Granting a permission updates the Setup cards and the mascot but never advances or closes the wizard.
- `firstRun` saves its step in `DogBarOnboarding.resumeStep`. Quit & Reopen after Screen Recording returns to the same step. Steps saved by the earlier five-screen setup map to Setup.
- Completion is `DogBarOnboarding.completedVersion`. These keys are outside `AppSettings`, so Reset All Settings does not bring the tour back.
- Existing installs: on the first launch of this version, any earlier DogBar defaults (`DogBar.*`, `DogBarTelemetry.*`, `nativeDock.*`, pins) mark the tour as done. Those users see recovery or the usage-data question only if needed.
- Closing the first tour early marks it done when both permissions are on. Otherwise the next launch resumes it.
- While any onboarding wizard is open, the replacement Dock, previews and switcher stay off (`OnboardingWindowController.holdsFeatures`). They start after **Start DogBar** or closing the window. This includes a replayed tour: DogBar hides its surfaces before activating the wizard and restores Apple’s Dock, then resumes the configured Dock mode after the window closes.
- Sparkle's "check automatically?" question is deferred until onboarding is complete (`updaterShouldPromptForPermissionToCheckForUpdates:`). It is separate from the usage-data choice.

### Install location

`PermissionsService.installLocation` (see [Permissions.md](Permissions.md)). From a mounted disk image or App Translocation, Setup shows the install banner first and the permission cards say "Install first" instead of requesting. DogBar never copies itself. When a copy exists in `/Applications` or `~/Applications`, **Open DogBar from Applications** quits this copy through the normal quit path and opens that one.

### Permission copy

Status comes from `PermissionAccess`: Checking, Allowed, Not allowed yet, Asking macOS, Turn on DogBar in System Settings. A `false` check is never described as a broken build. Screen Recording shows Quit & Reopen when `screenRecordingNeedsRelaunchAfterGrant` or after a request. The ad-hoc signing note appears only for ad-hoc builds.

## Focus and activation

`OnboardingWindowController` owns one window for the app's lifetime. While visible, the app is `.regular`, so the window can be key and DogBar is in Cmd+Tab when the user returns from System Settings. The `showDogBarInDock` preference applies again once it closes (`AppDelegate.updateFeatureState`).

Presenting orders the window front, makes it key and activates once, then retries at 120 ms and 350 ms because policy changes and activation finish asynchronously. A retry happens only while the frontmost app is still DogBar or the app it was launched from, so it never pulls focus back from System Settings. Permission changes never activate the app.

## Design

- Landing page system: the purple "Get DogBar" hero for Welcome, paper with soft lavender light for the rest, yellow only for the one primary action, system fonts, thin borders. Dynamic colors for Dark Mode.
- Product scenes are native SwiftUI versions of the landing page's feature art: the same macOS wallpapers and app icons (copied into `Resources/Onboarding/Product`), window thumbnails and Dock geometry, framed in the landing page's white feature card. No web view, remote assets or analytics.
- Glass: each glass surface (Dock, preview panel, switcher) draws a blurred, saturated crop of the exact wallpaper behind it (`WallpaperGlass`, aligned through a named coordinate space), a tint, a top inner light and a specular rim. This renders the same in a window and offscreen, unlike system materials.
- Each scene plays one short sequence when its step opens, then stops on an explanatory final frame: Desktop 1's Dock fills icon by icon, then focus moves to Desktop 2 and its own Dock fills (click either desktop to switch); the pointer moves to Safari, the preview opens, Hotel booking is chosen and that window comes forward; the modifier and Tab keys press, the switcher opens and the selection walks across window tiles. **Play Again** replays it. Sequences are `.task`s and cancel when the step leaves.
- Keyboard: Return is the primary action, Cmd+[ goes back, Tab moves between controls, Cmd+W closes. Setup always has **Finish Later**.
- VoiceOver: the title of each new step gets accessibility focus, scenes have a text description, the mascot is hidden, grants are announced.
- Reduce Motion (system or DogBar's setting): no scene sequences, final states shown, no mascot movement, cross-fades only.

## Mascot

`Scripts/mascot_rig.py` cuts the four poses in `Resources/Onboarding/Mascot` into layers on their shared 1254 px canvas, written to `Resources/Onboarding/Rig` at 768 px. Rerun it after the art changes. `MascotRig.swift` draws and directs them.

- Layers: each frame's body, its tail (behind the body, wagged around the hip), welcome's raised forearm (rotated around the elbow), and celebrate's two raised paws (drawn in front of an edge). Eyelids are drawn natively in the fur colour above each eye.
- Frames: `wave` (welcome), `think` (welcome body and raised paw with the curious permissions head), `guide` and `celebrate`. Welcome and celebrate share the same head pixels (mean difference 8.5/255), so switching between them reads as the arms moving.
- Moves (`MascotDirector`): blink, wag, wave, scratch, hop with squash, tap (a lean onto a target), and pose changes with a settle. Each move is short and cancellable. Nothing loops. With Reduce Motion only the final pose is shown. Hovering or clicking the dog plays one small reaction when no scene choreography is running.
- Peeking: the body is clipped at a fixed edge under the chin, and the paws are drawn in front of the edge. They fade in only once the dog has nearly reached it.

Per screen:
- Welcome: rises slowly from behind a glass DogBar Dock, grips it with both paws, blinks, then lets go with one paw and waves.
- Dock per desktop: peeks over the top of the card above Desktop 1, then ducks, slides along the edge to Desktop 2 as it becomes active, pops up and waves.
- Previews: watches from the card's corner and cheers after the click. The pointer does the clicking (see below).
- Switcher: facing left, leans onto the Tab key for each press, so the key and the moving selection have a visible cause.
- Setup: scratches behind its ear while asking, then cheers (celebrate, hop, wag) each time a permission turns on, and goes back to thinking if one is still missing.

This is a cut-out puppet with native transforms, not frame-by-frame character animation. A Rive state machine or generated animation frames would allow full-body acting later.

### Previews timeline

One take, cause before effect. Lisbon day plan is in front and the preview is closed. The pointer travels to Safari in the Dock and rests there, and the preview opens. The pointer travels to Hotel booking and only that tile highlights. The pointer presses, with a ripple. The preview closes, and only then does Hotel booking come in front of Lisbon day plan. The final frame holds (preview closed, pointer where it clicked) until Play Again, which resets every value before replaying. Target frames are measured in the stage and kept, so the pointer never jumps. The whole chapter is one `.task` that SwiftUI cancels when the step or window goes away. Reduce Motion shows a still of the preview open with Hotel booking under the pointer and a caption.

## Checking it

- Replay without changing saved state: paw menu → **Welcome Tour…**, or `open -n ~/Applications/DogBar.app --args --onboarding-tour` (quit DogBar first).
- Packaging: `Scripts/onboarding_resources.py` copies exactly the files the app loads (not the art README) before signing in `build-app.sh`, `build-preview.py` and `release.py`, and both verifiers check them.
