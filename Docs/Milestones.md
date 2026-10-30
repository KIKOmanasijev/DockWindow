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
