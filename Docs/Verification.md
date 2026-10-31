# Final verification status

## Established

- Native Swift package, Swift 5 language mode, deployment target macOS 26, no dependencies.
- Debug build and release bundle build pass without warnings.
- All 102 native tests pass. Tests have no database integration.
- Dock magnification is removed. Icon rasterization chooses Retina representations and updates for size or display-scale changes. Whole switcher cards render at 90 percent of their previous dimensions.
- Switcher content is bounded before scaling, preventing intrinsic title widths from overlapping adjacent cards. A persistent Dock resize grip supports all three positions. Focus and desktop events use independent fast publication paths instead of waiting for full AX scans. Live latency is still unmeasured.
- App installed at ~/Applications/DogBar.app and fresh process launched.
- Signature integrity verifies. The installed DogBar display name uses the existing DockWindow Dev self-signed certificate. Its designated requirement retains dev.hristijan.dogbar and the certificate leaf, rather than an ad-hoc binary hash.
- Selected dog AppIcon.icns and CFBundleIconFile are packaged.
- LSUIElement is false. The app uses regular activation and pins itself in the replacement Dock.
- Source audit found no AX/private force casts, force tries, em dashes or debug-only dump menu in current code.
- Private symbols are runtime-loaded; verified byte layouts have pure tests.
- Changes are committed and pushed to main in the private GitHub repository.

## Historical permission report

After the DogBar rebrand, installed process 21095 logged accessibility=false, screenRecording=false and adHoc=false. The signing fallback bug is fixed: the self-signed DockWindow Dev identity was being excluded by valid-only identity lookup even though it can sign successfully. Existing grants still do not authorize this process, so actual permission access is not claimed as repaired. Initial checks are asynchronous and explicit. Invasive features stay disabled until both effective permissions are true.

This records that earlier process, not the permission state of every subsequent build.

The resize-feedback build launched as process 50404 on 2026-10-30 and logged accessibility=true, screenRecording=true and adHoc=false. Both effective permissions are active for that installed process with the preserved signing requirement.

## Dock context menus and Hide

Context-menu tracking now suppresses pending, hover and pinned previews. The gate is set before dismissal to cover synchronous visibility callbacks. Menu actions, including Options submenu actions, execute after AppKit finishes tracking. This also prevents Show All Windows from displaying a preview over its own menu.

Hide waits for the target application's actual hidden state, tries the Accessibility AXHidden attribute if the AppKit request has no effect, and reports failure from the Dock. Cancellation and terminated targets stop the operation. Eight regression tests cover these paths, menu action timing and real preview-panel suppression. A live fixture exposed a verification race even though the application became hidden; verification now waits for state changes regardless of the acknowledgement. The actual WindowActions path subsequently hid a separate temporary AppKit fixture and reported success with isHidden=true.

The release bundle was rebuilt, installed and launched with the existing DockWindow Dev identity. Signature integrity and the stable designated requirement were verified. Manual acceptance still includes right-click and long-press menus, Options submenus, Hide on the reported target app, and Show All Windows after menu dismissal.

## Pending acceptance

Dock resize feedback now uses a thin purple pill on hover and drag, without a text badge or full-border outline. Four-point detents retain reversal hysteresis. The border target excludes icons and transparent corners on all three edges. Coarser alignment haptics use the system's default performer on supported input devices. Dragging immediately dismisses previews; Escape restores the original size. Tests cover pill geometry without a text label, border hit targets, jitter, bounds, cancellation and mouse-sequence ownership. Empty-app hover previews are off by default for both Docks; the opt-in setting persists, and changing it closes an empty hover panel. Explicit Show All Windows remains available. Perceived feel and hardware haptics still need manual acceptance.

All live interactions, the reported blank Welcome fix, visible Dock/icon behavior, exact native preference restore on real enablement, crash recovery, desktop isolation, hot-plug/sleep/wake, fullscreen, unresponsive applications and the full performance budgets require user verification. A short permission/setup-state sample used about 27 MB but reached 2.6% sampled CPU. This is not a passing idle-Dock performance result.

See Docs/Milestones.md for the consolidated ten-step manual checklist and historical milestone reports. ServiceHardening.md and UIHardening.md document remaining technical limitations.

## Unnotarized preview distribution

The owner explicitly authorized a self-signed, unnotarized preview. Version 0.1.0-preview.1 (build 2) was built in an isolated directory, signed with the preserved DockWindow Dev certificate, and checked for signature integrity, arm64 architecture, metadata, exact entitlements, read-only UDZO image integrity, Applications shortcut and the mounted inner app. Its staged 3,146,380-byte DMG has SHA-256 `1d914c181344b0628c508cff843682fc18a0ca6b5e976c2924eabb95c01f922c`. Gatekeeper acceptance and fresh-Mac installation are not claimed. The existing notarized pipeline remains strict; its literal codesign requirement syntax was corrected after a real preview build exposed the filename-vs-inline distinction.

The preview is published at https://dogbar.hristijan.dev/downloads/DogBar-0.1.0-preview.1-arm64.dmg. Before enabling the CTAs, an actual HTTPS download matched the build checksum and passed repeated image and inner-app signature checks. All 20 deployed runtime files match local bytes; download attachment/content-type headers and no-store manifest headers were checked. The site's actual served scripts and manifests enabled both CTAs in a jsdom integration check, disclosed the preview status, and showed installation help and the hash. All 25 website tests and 22 packaging tests pass. Desktop/mobile browser layout and a fresh-Mac quarantined install remain manual acceptance items.
