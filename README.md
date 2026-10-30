# DockWindow

A native Swift macOS window manager with a per-desktop Dock, Option+Tab window switcher, hover previews and live settings. The selected app icon is the cartoon dog holding stacked windows. DockWindow remains visible in the native Dock, and is pinned in its replacement Dock.

## Build and run

Requires macOS 14 or newer and Swift 6 tooling. The package uses Swift 5 language mode and Apple frameworks only.

```
swift build
swift test
Scripts/run.sh
```

The bundle installs at `~/Applications/DockWindow.app`. The build script uses `DockWindow Dev` when available, otherwise ad-hoc signing. Ad-hoc builds change identity when the binary changes, so a Settings toggle can refer to an older build's grant. Actual process access is checked asynchronously, with an explicit initial checking state. No permission prompts occur during polling. Settings and onboarding provide request buttons and a fresh-process relaunch helper.

The install script asks the running app to quit and finish native Dock restoration before replacing the bundle. If it remains running, installation stops. The app persists exact original native Dock preference values before hiding it and restores them on disable, Pause and Quit. After a crash it recovers from that backup at the next launch. Do not delete application defaults while recovery is pending.

## Use

- Option+Tab opens one tile per window. Hold Option to inspect; release to focus. Shift reverses, arrows navigate, Escape cancels. The shortcut is configurable.
- The Dock uses the current desktop by default. Pinned apps remain visible. Counts, magnification, autohide, positioning and app rules are live settings.
- Hover previews work with either DockWindow's Dock or the native Dock. Traffic lights act on the exact window.
- Open Settings from the menu bar, app menu, or by clicking the DockWindow icon. Pause or Restore Native Dock returns the native Dock preferences.

## Verification and limits

Build and unit tests cover deterministic policies and failure handling. User-facing behavior involving Accessibility, ScreenCaptureKit, private APIs and macOS Spaces requires the manual checks in `Docs/Milestones.md` and the integration reports. No browser verification is used.

Private APIs load at runtime and degrade when symbols are missing. Their presence is not a behavior guarantee. Cross-desktop AX discovery is bounded and can miss sparse IDs. App assignments and fullscreen behavior can defeat a request to create a new window on a specific desktop. The app verifies outcomes and reports uncertainty rather than claiming an absolute no-switch guarantee.

The Dock cannot reserve screen space. Minimize animations target the hidden native Dock. Third-party app-specific Dock menus are unavailable. SDK 15.5 uses material approximation; the guarded native glass provider needs a newer SDK. Cached protected/minimized thumbnails may be unavailable. Performance budgets and exact native visual parity remain manual verification items.

Research is recorded in `Docs/PrivateAPIReference.md`. Implementation was independently authored from behavior and API facts, without copying GPL implementation bodies. PNG icon concepts and prompt descriptions are retained in `Resources/IconConcepts` and `Docs/IconConcepts.md`.
