# Final verification status

## Established

- Native Swift package, Swift 5 language mode, deployment target macOS 14, no dependencies.
- Debug build and release bundle build pass without warnings.
- All 67 tests pass. Tests have no database integration.
- App installed at ~/Applications/DockWindow.app and fresh process launched.
- Signature integrity verifies. Signing is ad-hoc, with no valid DockWindow Dev identity installed.
- Selected dog AppIcon.icns and CFBundleIconFile are packaged.
- LSUIElement is false. The app uses regular activation and pins itself in the replacement Dock.
- Source audit found no AX/private force casts, force tries, em dashes or debug-only dump menu in current code.
- Private symbols are runtime-loaded; verified byte layouts have pure tests.
- All work is on main, without branches, PRs or pushes.

## Runtime blocker

The final installed process 86846 logged accessibility=false and screenRecording=false. The user's Screen & System Audio Recording toggle is enabled in Settings, but that does not change the observed API result for this ad-hoc build. Actual access is not claimed as repaired. Initial checks are asynchronous and explicit. Invasive features stay disabled until both effective permissions are true.

## Pending acceptance

All live interactions, the reported blank Welcome fix, visible Dock/icon behavior, exact native preference restore on real enablement, crash recovery, desktop isolation, hot-plug/sleep/wake, fullscreen, unresponsive applications and the full performance budgets require user verification. A short permission/setup-state sample used about 27 MB but reached 2.6% sampled CPU. This is not a passing idle-Dock performance result.

See Docs/Milestones.md for the consolidated ten-step manual checklist and historical milestone reports. ServiceHardening.md and UIHardening.md document remaining technical limitations.
