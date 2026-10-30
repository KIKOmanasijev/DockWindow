# Final verification status

## Established

- Native Swift package, Swift 5 language mode, deployment target macOS 14, no dependencies.
- Debug build and release bundle build pass without warnings.
- All 99 native tests pass. Tests have no database integration.
- Dock magnification is removed. Icon rasterization chooses Retina representations and updates for size or display-scale changes. Whole switcher cards render at 90 percent of their previous dimensions.
- Switcher content is bounded before scaling, preventing intrinsic title widths from overlapping adjacent cards. A persistent Dock resize grip supports all three positions. Focus and desktop events use independent fast publication paths instead of waiting for full AX scans. Live latency is still unmeasured.
- App installed at ~/Applications/DockWindow.app and fresh process launched.
- Signature integrity verifies. The installed DogBar display name uses the existing DockWindow Dev self-signed certificate. Its designated requirement retains com.dockwindow.app and the certificate leaf, rather than an ad-hoc binary hash.
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

Dock resize feedback now highlights the inward border and divider in purple, shows an immediate direction/drag cue and live point size, and uses four-point detents with reversal hysteresis. The border target excludes icons and transparent corners on all three edges. Coarser alignment haptics use the system's default performer on supported input devices. Dragging immediately dismisses previews; Escape restores the original size. Tests cover cue visibility independently of app-name labels, border geometry, jitter, bounds, cancellation and mouse-sequence ownership. Perceived feel and hardware haptics still need manual acceptance.

All live interactions, the reported blank Welcome fix, visible Dock/icon behavior, exact native preference restore on real enablement, crash recovery, desktop isolation, hot-plug/sleep/wake, fullscreen, unresponsive applications and the full performance budgets require user verification. A short permission/setup-state sample used about 27 MB but reached 2.6% sampled CPU. This is not a passing idle-Dock performance result.

See Docs/Milestones.md for the consolidated ten-step manual checklist and historical milestone reports. ServiceHardening.md and UIHardening.md document remaining technical limitations.
