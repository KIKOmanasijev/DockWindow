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
