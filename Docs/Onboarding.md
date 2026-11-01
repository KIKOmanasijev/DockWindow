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
- While a `firstRun` or `recovery` wizard is open, the replacement Dock, previews and switcher stay off (`OnboardingWindowController.holdsFeatures`). They start after **Start DogBar** or closing the window. A replayed tour leaves running features alone.
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

Four static poses with alpha (`welcome`, `guide`, `permissions`, `celebrate`). See `Resources/Onboarding/Mascot/README.md`. Native choreography only:

- Pose follows state: welcome on Welcome, guide presenting the scene on feature steps, patient on Setup until DogBar is installed and both permissions are on, then celebrate.
- Pose changes cross-fade with a small settle from the paws.
- Two one-shot reactions: a greeting tilt when the wizard opens and a short hop when a permission turns on. Nothing loops.

This is pose swapping with small transforms, not character animation. A future option is a layered Rive rig (separate head, ears, tail and paws with a state machine), using Rive's AppKit/SwiftUI runtime. That adds a runtime dependency and an authoring and export pipeline, so it is not used now.

## Checking it

- Replay without changing saved state: paw menu → **Welcome Tour…**, or `open -n ~/Applications/DogBar.app --args --onboarding-tour` (quit DogBar first).
- Packaging: `Scripts/onboarding_resources.py` copies exactly the files the app loads (not the art README) before signing in `build-app.sh`, `build-preview.py` and `release.py`, and both verifiers check them.
