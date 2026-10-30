# DockWindow milestones

## M0: Scaffold

Built the Swift 5 package, native menu bar application, permission onboarding, structured logging, metadata and release install/run scripts. Build and bundle metadata test pass. Release app installed and launch requested from `~/Applications/DockWindow.app`. SDK is 15.5. A newer Xcode enables true Liquid Glass. Certificate instructions were already provided by the parent. The certificate is still missing, so this build uses ad-hoc signing.

Manual checks, pending user verification:
- Launch the app from Applications and find its menu bar icon.
- Open Permissions from the menu.
- Check both permission rows reflect System Settings.
- Test both Open System Settings buttons.
- Close and reopen the onboarding window.
- Quit from the menu and verify the process exits.

No native Dock preferences were changed. No GUI or performance criterion is claimed as verified.

## M1: Core services

Added runtime-loaded private API wrappers, background AX inventory and observers, per-display Spaces, bounded remote token discovery, MRU snapshots, exact-window actions, ScreenCaptureKit thumbnail cache, new-window strategies, native Dock reading and transactional preference recovery. Added all settings models and pure policies with 21 policy tests. Debug dump is available in the status menu. Inventory invalidates the shareable-content cache. All 22 tests, debug build and installed release build pass without warnings. GUI and performance remain unverified.

The membership poll deliberately uses inverse per-Space queries with singleton recovery because the specified batched API returns a union. The verified 64-bit ABI, 20-byte remote token, and 256-byte focus storage follow the research report. Remote discovery is bounded and incomplete. New-window and focus operations verify outcomes where possible, without claiming a universal desktop guarantee. Recovery happens at next launch after a crash, not while the process is dead.

Manual checks, pending user verification:
- Grant both permissions, then use Debug: dump windows and compare app/window inventory.
- Rename, create, close and focus windows and compare MRU dates.
- Put two windows of one app on different desktops and compare their membership.
- Minimize a window and verify its last desktop remains attached.
- Test exact-window focus and watch for unwanted clicks or resizing.
- Test a fullscreen Space and a second display with separate Spaces on and off.
- Check responsive UI while another app is unresponsive.
- Check capture placeholders for minimized and protected windows when later panels are enabled.

Public integration contracts are in ModelIntegration.md and ServiceIntegration.md. No replacement Dock has been enabled yet.

## M2: Window switcher

Added the dedicated-thread event tap, Cmd+Tab session decoder, reusable nonactivating SwiftUI window grid, cached thumbnail cards, functional traffic lights, MRU selection, quick switching, arrows, mouse commit, W/M/H/Q, independent scope settings and shared theme/material providers. Permission loss and Pause stop the tap and dismiss the panel. Mouse/empty-list dismissal explicitly ends tap session ownership while preserving consumed key-ups. Added selection and tap lifecycle tests. All 36 tests, debug build and installed release build pass without warnings. Launch requested from the stable installation path. On-screen latency, capture and hotkey interception remain unverified.

Manual checks, pending user verification:
- Tap Cmd+Tab and release before 120 ms, then hold it to show the grid.
- Verify one tile per window and index one initially selected.
- Cycle with Tab, Shift+Tab and arrow keys across partial rows.
- Press Escape, then test mouse hover and click commit.
- Exercise W/M/H/Q and each traffic-light action.
- Close or rename a selected window while the panel is open.
- Change current/all desktop and mouse/all display preferences through saved settings until M6 UI arrives.
- Revoke a permission or Pause during appearance delay and verify interception stops.
- Test protected/minimized thumbnails and appearance under light/dark mode.

## M3: Replacement Dock and window dots

Added AppKit/CALayer Dock rendering, display-linked magnification, autohide, labels, capped dots, badges, launch bounce, pinned import, Finder and Trash, context menus, reorder/removal, app and Trash file drops, and optional scroll cycling. Coordinator now gates replacement on permissions and pause, saves native preferences before showing the panel, restores on disable/Pause/Restore, and delays application termination until exact restoration completes. Startup recovers stale backups before enablement. Errors retain recovery state rather than silently overwriting it. All 42 tests, debug build and installed release build pass without warnings. Runtime preference mutation, GUI parity and performance are not claimed as tested.

Manual checks, pending user verification:
- Record native Dock settings, enable replacement, Pause, resume, Restore and Quit, then compare exact settings.
- Force-exit and relaunch with replacement disabled to check crash recovery.
- Compare size, spacing, background and labels with the native Dock.
- Sweep magnification, test edge autohide and click through transparent overflow.
- Check bottom/left/right and main/mouse display placement.
- Reorder pins, pin a running app and drag out to remove, leaving Finder fixed.
- Test all context-menu actions, badge updates and launch bounce.
- Drop disposable files onto an app and Trash, then test Empty Trash confirmation.
- Create/minimize/close windows and compare count dots, cap, custom color and single-dot style.

Known limits: the SDK uses material approximation, external Trash updates are not watched, running-only ordering is session-local, no screen-space reservation, and minimize animations target the hidden native Dock. DockIntegration.md has detailed runtime checks.

## M4: Per-desktop behavior

Wired current-desktop composition and verified click/open strategies through the replacement Dock. Hardened new-window attempts with a display-specific DesktopTarget: abort when that display changes desktop or disappears, even if another display has the old Space. Space/app activation events now schedule immediate membership queries alongside inventory recovery. Shortened item transition animation to 120 ms. Added three desktop-isolation regressions. All 45 tests and debug/release compilation pass without warnings after the final correction.

The initial milestone bundle installation completed before a parent-coordinated permission repair requested an install pause. It has not been relaunched. Further installation/launch is deferred until the parent clears the signing/request/relaunch fix. No manual isolation or sub-150-ms guarantee is claimed. A busy serial AX inventory may still delay publication, despite off-main membership queries. New-window operations remain best effort for assigned Spaces and app-specific behavior.

Manual checks, pending user verification:
- Put different apps on two desktops and verify only local running apps plus pins and Finder appear.
- Move a window with Mission Control and verify membership catches up.
- Click a remote-only pinned app and verify it creates a local window or reports failure.
- Test Finder, browser and Terminal rules, then a custom keyboard rule.
- Change desktop while opening and verify no fallback commands continue there.
- Check minimized remembered membership and fullscreen desktop behavior.
- Test separate/shared display Spaces and unplug a display during opening.
- Toggle all-desktop Dock scope and confirm clicks still choose local windows.
