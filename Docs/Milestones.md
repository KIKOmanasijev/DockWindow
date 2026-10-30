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

## M5: Dock hover previews

Added a shared preview panel for replacement and native Dock modes, delayed hover, instant app switching, tapered pointer bridge, pinned Show All Windows, empty states, live thumbnail leases, title and traffic-light settings, and remote desktop labels from cached topology. Coordinator routes both hover sources and disables previews on permission loss/Pause. Six geometry tests cover edges, negative origins, clamping and bridging. User changed the default switcher binding to Option+Tab; tests now ensure native Cmd+Tab passes through by default. All 55 tests, debug build and installed release build pass without warnings. The parent permission fix 400eff6 is preserved. Ad-hoc installs can still invalidate TCC grants.

Manual checks, pending user verification:
- Use Option+Tab for the switcher and confirm Cmd+Tab remains native by default.
- Hover, move between icons and cross the bridge into the preview panel.
- Leave all regions and reenter before/after the close delay.
- Pin Show All Windows, then dismiss with Escape or outside click.
- Disable replacement Dock and test native Dock hover on all three edges.
- Toggle scope, titles, controls and refresh interval, including zero.
- Click traffic lights and thumbnails, including minimized and protected windows.
- Compare desktop-number badges and mixed-scale display placement.
- Open a preview and switcher concurrently, then close each independently.

Nonrunning pinned apps must first launch from the Dock before New Window is enabled. Native AX selection may miss hover signals. UI parity and timing remain unverified. PreviewIntegration.md contains detailed checks.

## M6: Live settings and selected app icon

Added six complete settings panes with live bindings, physical shortcut recording, editable app rules, permission requests/relaunch, login registration and status errors, reset confirmation, private-symbol diagnostics and opt-in bounded file logging. The coordinator opens Settings from menu or app reopen, hides the menu icon live, applies the subrole allow-list only when changed, and suspends the event tap while recording. Preserved the parent permission repair. The user's selected cartoon dog with stacked windows is packaged as AppIcon.icns. Both original PNG concepts and their prompt set remain in Resources/IconConcepts and Docs/IconConcepts.md. All 55 tests, debug build and release bundle installation pass without warnings. Login registration and all GUI interaction still need manual verification.

Manual checks, pending user verification:
- Open Settings from the menu, resize, close and reopen through the app.
- Change each Dock control live and compare layout, indicators and behavior.
- Record Option+Tab or another combination without opening the switcher; cancel with Escape.
- Add an app rule, edit menu titles/strategy/shortcut, restart and verify persistence.
- Change switcher and preview scope, dimensions, controls and refresh interval.
- Test theme, custom colors, material, corner radius and Reduce Motion.
- Enable/disable login launch and check status, approval and error reporting.
- Request permissions, relaunch through the helper and check the dog icon in Finder.
- Reveal debug logs, inspect symbol flags, and test reset/reimport confirmations without losing recovery backups.

## M7: Hardening and user-reported UI issues

Completed service cancellation, display-specific focus verification, stale membership reply rejection, minimized membership retention, observer teardown, guarded CF conversion, tested byte layouts and bounded capture geometry. Nonrunning pinned preview actions now launch and verify through openPinned. UI hardening covers stale tasks, lifecycle dismissal, hit testing, side autohide, display-link cleanup and exclusive recorder ownership. Removed the debug-only dump menu. Added the Apple Events entitlement used by hardened-runtime Trash automation. Installer requests orderly quit and refuses replacement while a process remains, rather than killing it.

Latest user instructions supersede the original invisible-app requirement: DockWindow is now a regular foreground application, LSUIElement is false, and its own bundle is pinned into the replacement Dock. Normal self windows are tracked. Settings preserves regular activation. The menu bar keeps the dog identity and uses a small adjacent state indicator and tooltip instead of replacing the brand with a triangle. Onboarding has a retained hosting controller, explicit 640 by 530 viewport, scrolling content and layout before display. The parent moved actual permission/signature checks off-main and added an initial checking state. Both permission surfaces distinguish initial Checking from Unavailable to this build. Repeated login-status RPCs were removed from the main thread.

Final verification: swift build, all 67 tests, release compilation and Scripts/build-app.sh passed without warnings. One final combined installation and fresh launch followed the parent's release of the install hold. codesign verification passed. The installed Info.plist reports LSUIElement=false and CFBundleIconFile=AppIcon. Installed icon content matches the selected dog resource. No local database was accessed. No browser or GUI automation was used. git diff --check passed.

Runtime evidence, 2026-10-30: process 86846 launched from /Users/kiko/Applications/DockWindow.app. Its public system log states: accessibility=false, screenRecording=false, adHoc=true. This is the actual process result, despite the user's Settings screenshot showing Screen & System Audio Recording enabled. Permission access is not claimed as fixed. No fake grants or TCC resets were used. Security reports zero valid signing identities. Feature activation remains gated by effective permissions.

A short top sample of this permission/setup state showed about 27 MB resident memory and CPU samples 0.0%, 1.7%, 2.6%. An earlier setup-state sample ranged from 0.0% to 5.4% at about 32 to 33 MB. These are not a verified full-Dock idle workload or 30-window memory test, and do not establish the under-1% CPU budget. Presentation latency, ProMotion pacing, Space-update timing, native visual parity and all live multi-display/private-API behavior remain unverified. The new onboarding rendering and visible Dock behavior still need user confirmation after this final launch.

Consolidated manual checklist, all pending user verification:
- Check Welcome content renders immediately, initial status says Checking, and resolved rows match actual process logs. Confirm the selected dog icon stays visible in the native and replacement Docks and the menu bar retains its identity.
- Exercise Settings open/close/reopen and every pane live, including shortcut recording, login status, custom app rules, theme/material, reset/reimport and debug logs.
- Use Option+Tab for quick and held switching, reverse/arrows/mouse/Escape, windowless apps, W/M/H/Q and traffic lights. Confirm Cmd+Tab stays native by default.
- Create, rename, minimize, hide and close windows while surfaces are open. Check stable selection, title updates, count dots, caches and protected-content placeholders.
- Compare native visual styling, magnification, labels, bounce, badges, autohide, transparent click-through and bottom/left/right layout.
- Test pin reorder/removal, drag cancellation, file drops, scrolling, context menus and Trash confirmation with disposable files.
- Place windows of the same app on different desktops, including fullscreen. Test local focus, remote-only new-window actions, rules and cancellation while switching desktops. Failure feedback must not claim verified success.
- Test hover delay, instant app switching, bridge travel, pinned previews, native-Dock fallback, outside/Escape dismissal and concurrent switcher/preview captures.
- Exercise mixed-scale offset displays, shared/separate Spaces, hot unplug, sleep/wake, app crashes and unresponsive apps. Verify no orphan panel, stale publication or late command.
- Compare exact native Dock preferences after disable/Pause/Restore/Quit and next-launch crash recovery, then measure all performance budgets with effective permissions and a realistic 30-window workload.

Known limits remain: exact native Liquid Glass requires a newer SDK; no third-party screen-space reservation; minimize animations target the hidden native Dock; third-party app-specific Dock menus are unavailable; remote AX discovery is bounded; capture can fail for protected/minimized surfaces; app Space assignments can defeat opening/focus intent. Crash recovery occurs on the next launch. The complete Definition of Done is not signed off until permission and manual/performance checks pass.

## Follow-up: fixed Dock icons and smaller switcher cards

Removed pointer magnification and its settings controls. Fixed icon sizing applies even when an older stored preference enabled magnification. Pointer movement now redraws on events without a display link. Icon images are rendered from the best NSImage representation at the display's pixel scale and cached by source and pixel dimensions. Moving to a different scale or changing icon size invalidates that raster. Entire Option+Tab cards, including header and padding, render at 90 percent of the previous dimensions; panel and grid calculations use the same scaled sizes. Existing user thumbnail settings are preserved.

Debug build and all 71 tests pass without warnings. Four new tests verify fixed pointer geometry, physical pixel dimensions, selection of a distinct Retina representation, cache invalidation, clearing absent icons and full-card scaling for default/custom sizes.

Manual checks:
- Sweep the pointer across the Dock and verify every icon keeps its size and position.
- Confirm hover labels, previews, clicks and drag reorder still work without magnification.
- Compare icon sharpness at small and large settings on Retina and non-Retina displays.
- Move the Dock between mixed-scale displays and check icons rerender sharply.
- Open Option+Tab with window and windowless cards, check smaller headers/thumbnails, selection and scrolling.

## Follow-up: layout, resize grip and focus updates

Constrained switcher cards before scaling and clipped their bounds to prevent long titles from expanding into adjacent grid cells. Corrected column fitting to include panel padding. Added a cursor and tooltip resize grip at the divider, with an inward-edge fallback when no divider exists. Inward dragging enlarges the Dock and outward dragging shrinks it, with persistent 16 to 128 point icon sizing. Resize owns its mouse sequence and suppresses icon clicks and hover previews. Escape cancellation restores the starting size.

Workspace activation publishes frontmost state before inventory enumeration. Focus-only AX queries and desktop topology use separate coalesced queues, and merging prevents slow inventory replies from undoing newer focus/Space events. The Dock consumes the supplied published snapshot synchronously. The 1.5-second fallback membership poll is unchanged. Unchanged permission polls no longer emit UI reconciliation. The menu bar uses a monochrome template paw, with permission status inside its menu and tooltip.

All 87 tests pass. Live latency, long-title rendering and pointer interactions remain manual checks. The GitHub repository was created private under KIKOmanasijev/DockWindow at the user's request, superseding the original no-push instruction.

Manual checks:
- Open the switcher with long titles and windowless apps, and verify cards and click targets stay separated.
- Resize from the divider or fallback grip at bottom, left and right, then reopen the app to check persistence.
- Cancel resizing and ensure no app was focused, pinned app moved or hover panel left open.
- Switch rapidly between apps, windows and desktops and check the Dock updates promptly without reverting.
- Check the monochrome paw on light and dark menu bars, then open its menu for permission status.

## DogBar rebrand and custom domain

Renamed the public site and native display name, menus, onboarding and Settings to DogBar. Kept com.dockwindow.app, DockWindow executable and install path, settings keys, window autosave keys and DockWindow Dev certificate name unchanged. Bundle metadata tests cover the new display name and preserved executable/identifier.

The user-created self-signed identity was present but excluded from valid-only identity lookup. Signing a temporary app copy proved it works without changing system trust settings. The installer now selects present signing identities, aborts on signing failure rather than silently changing identity, and waits for asynchronous quit/restoration before replacing the app. The installed app verifies with Authority DockWindow Dev and a designated requirement anchored to its certificate leaf. All 87 tests, debug and release builds pass. Current process permissions remain false, with adHoc=false, so permission reapproval is still pending.

Attached dogbar.hristijan.dev to the existing Vercel project. Cloudflare is authoritative for hristijan.dev. The project-specific CNAME is configured, public DNS returns the expected target, and Vercel reports misconfigured=false. HTTPS certificate validation and page-content hash verification pass against the Vercel endpoint; the local resolver initially retained a negative DNS cache. DNS instructions are in landing/README.md. Canonical/social URLs use the custom domain; dockwindow.vercel.app remains a working fallback.
