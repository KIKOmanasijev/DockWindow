# Onboarding

DogBar's first-run wizard: `Sources/DogBarCore/Features/Onboarding`. Art: `Resources/Onboarding` (bundled at `Contents/Resources/Onboarding`).

## Flows

| Mode | When | Steps |
| --- | --- | --- |
| `firstRun` | No onboarding state and no earlier DogBar defaults | Welcome → Dock per desktop → Previews → Switcher → (Install) → Accessibility → Screen Recording → Usage data → Ready |
| `recovery` | Tour done, but a permission is missing, or DogBar runs from a disk image | Only the missing steps, then Ready |
| `privacyOnly` | Tour done and permissions on, usage-data question never answered | Usage data |
| `tour` | Paw menu or app menu → **Welcome Tour…**, Settings → **Show Setup** when nothing is missing, or launch with `--onboarding-tour` | Full tour. Saves nothing on its own |

- The step list is fixed when the window opens. Granting a permission updates that step (status, toggle, mascot) but never advances it.
- `firstRun` saves its step in `DogBarOnboarding.resumeStep`. Quit & Reopen after Screen Recording returns to the same step. A saved step that no longer applies (Install after moving the app) resumes at the next one.
- Completion is `DogBarOnboarding.completedVersion`. These keys are outside `AppSettings`, so Reset All Settings does not bring the tour back.
- Existing installs: on the first launch of this version, any earlier DogBar defaults (`DogBar.*`, `DogBarTelemetry.*`, `nativeDock.*`, pins) mark the tour as done. Those users see recovery or the usage-data question only if needed.
- Closing the first tour early marks it done when both permissions are on. Otherwise the next launch resumes it.
- While a `firstRun` or `recovery` wizard is open, the replacement Dock, previews and switcher stay off (`OnboardingWindowController.holdsFeatures`). They start after **Start DogBar** or closing the window. A replayed tour leaves running features alone.
- Sparkle's "check automatically?" question is deferred until onboarding is complete (`updaterShouldPromptForPermissionToCheckForUpdates:`). It is separate from the usage-data choice.

### Install location

`PermissionsService.installLocation` (see [Permissions.md](Permissions.md)). From a mounted disk image or App Translocation, the Install step comes before permissions, and the permission steps ask to move DogBar first instead of requesting. DogBar never copies itself. When a copy exists in `/Applications` or `~/Applications`, **Open DogBar from Applications** quits this copy through the normal quit path and opens that one.

### Permission copy

Status comes from `PermissionAccess`: Checking, Allowed, Not allowed yet, Asking macOS, Turn on DogBar in System Settings. A `false` check is never described as a broken build. Screen Recording shows Quit & Reopen when `screenRecordingNeedsRelaunchAfterGrant` or after a request. The ad-hoc signing note appears only for ad-hoc builds.

## Focus and activation

`OnboardingWindowController` owns one window for the app's lifetime. While visible, the app is `.regular`, so the window can be key and DogBar is in Cmd+Tab when the user returns from System Settings. The `showDogBarInDock` preference applies again once it closes (`AppDelegate.updateFeatureState`).

Presenting orders the window front, makes it key and activates once, then retries at 120 ms and 350 ms because policy changes and activation finish asynchronously. A retry happens only while the frontmost app is still DogBar or the app it was launched from, so it never pulls focus back from System Settings. Permission changes never activate the app.

## Design

- Landing page system: deep purple hero for Welcome and Ready, paper and ink for the rest, yellow only for the one primary action, system fonts, thin borders. Dynamic colors for Dark Mode.
- Product scenes are native SwiftUI recreations of the landing page's art: the same app icons and wallpapers (copied into `Resources/Onboarding/Product`), the same window thumbnails and Dock geometry. No web view, remote assets or analytics.
- Each scene plays one short sequence when its step opens: one desktop swipe; pointer to Safari, preview, choose Hotel booking, window comes forward; three Tab presses moving the switcher selection. Then it stops. **Play Again** replays it. Sequences are `.task`s and cancel when the step leaves.
- Keyboard: Return is the primary action, Cmd+[ goes back, Tab moves between controls, Cmd+W closes. Every permission step has **Not Now**.
- VoiceOver: the title of each new step gets accessibility focus, scenes have a text description, the mascot is hidden, grants are announced.
- Reduce Motion (system or DogBar's setting): no scene sequences, final states shown, no mascot movement, cross-fades only.

## Mascot

Four static poses with alpha (`welcome`, `guide`, `permissions`, `celebrate`). See `Resources/Onboarding/Mascot/README.md`. Native choreography only:

- Pose follows state: welcome on Welcome, guide presenting the scene on feature steps, patient on Install and missing permissions, celebrate once a permission is on and on Ready.
- Pose changes cross-fade with a small settle from the paws.
- Two one-shot reactions: a greeting tilt when the wizard opens and a short hop when a permission turns on. Nothing loops.

This is pose swapping with small transforms, not character animation. A future option is a layered Rive rig (separate head, ears, tail and paws with a state machine), using Rive's AppKit/SwiftUI runtime. That adds a runtime dependency and an authoring and export pipeline, so it is not used now.

## Checking it

- Replay without changing saved state: paw menu → **Welcome Tour…**, or `open -n ~/Applications/DogBar.app --args --onboarding-tour` (quit DogBar first).
- Packaging: `Scripts/onboarding_resources.py` copies exactly the files the app loads (not the art README) before signing in `build-app.sh`, `build-preview.py` and `release.py`, and both verifiers check them.
