# Models and pure policy integration

`Models/` and `Logic/` are public API in `DogBarCore`. They contain no AX references and do not call private APIs, launch apps, execute defaults commands, or mutate the native Dock.

## Tracker contract

- `TrackedWindow(id:pid:bundleIdentifier:title:frame:spaceIDs:isMinimized:isAppHidden:isFullscreen:lastFocusedAt:rememberedSpaceIDs:)` requires only `id`. Other fields have defaults. Frame uses global coordinates. The tracker must keep AX references in its own storage.
- `TrackedApp(pid:bundleIdentifier:name:bundleURL:icon:isHidden:isFrontmost:badgeLabel:lastActiveSpaceIDs:lastActivatedAt:)` requires only `pid`. `id` equals `pid`. Icons are presentation objects: resolve and modify them on the main actor. Worker closures should capture scalar values such as `pid`, rather than the entire app.
- `WindowSnapshot(apps:windows:activeSpaceIDs:)` defaults to empty values. `activeSpaceIDs` maps display UUIDs to their current Space. `activeSpaceID` prefers `Main`, then the lexically first display, then returns zero for unknown. Supply `Main` when shared Spaces need the main display fallback.
- Keep the window input order stable across publications. `MRUPolicy.ordered` preserves input order on tied timestamps. `MRUPolicy.focusing` applies the timestamp and orders once.
- `SpacePolicy.updatingMembership` records the last nonempty membership across minimize polls. Unknown minimized membership is visible on every desktop. Unknown non-minimized membership is excluded when the current Space is known.
- Do not zip an aggregate `CGSCopySpacesForWindows` result with window IDs: the result is a union. Resolve membership independently per window or from a verified membership source before constructing `TrackedWindow.spaceIDs`.
- The tracker should update `TrackedApp.lastActiveSpaceIDs` and `lastActivatedAt` on app activation. Windowless apps appear only on their last active desktop in the default Dock scope.

## Settings

Create `AppSettings(defaults: .standard)` on the main actor and retain it. It conforms to `ObservableObject`; SwiftUI can bind the named read/write properties directly. Each setter sends `objectWillChange` before persisting. UserDefaults notifications also refresh other instances. `refresh()` is available for deterministic synchronization after external defaults writes.

Keys are `DogBar.` plus the public property name. Scalars use native defaults types; structured values and enums use JSON `Data`. `registeredDefaults` exposes the complete key/default table. `reset()` removes only this table's keys, preserving native Dock backups and unrelated defaults. Confirmation belongs in the UI before calling reset.

Public property groups:

- General: `launchAtLogin`, `showMenuBarIcon`, `isPaused`.
- Dock: `useDogBarDock`, `dockPosition`, `dockDisplay`, `iconSize`, `magnificationEnabled`, `magnificationSize`, `autohide`, `autohideDelay`, `dockScope`, `otherDesktopApps`, `indicatorStyle`, `maxDots`, `includeMinimizedInCount`, `useCustomDotColor`, `dotColor`, `showRunningState`, `bounceOnLaunch`, `showAppNameLabels`, `activeAppClickBehavior`, `showTrash`, `includeMinimizedInDock`, `showWindowlessAppsOnLastActiveDesktop`, `scrollToCycleWindows`, `newWindowRules`, `pinnedApps`, `hasImportedPinnedApps`.
- Switcher: `switcherEnabled`, `switcherShortcut`, `sameAppShortcutEnabled`, `sameAppShortcut`, `switcherScope`, `switcherScreens`, `switcherIncludeMinimized`, `switcherIncludeHiddenApps`, `switcherShowWindowlessApps`, `switcherAppearanceDelay`, `switcherThumbnailWidth`, `switcherThumbnailHeight`, `switcherMaxTilesPerRow`, `switcherCloseWithW`, `switcherMinimizeWithM`, `switcherHideWithH`, `switcherQuitWithQ`.
- Previews: `previewsEnabled`, `previewHoverDelay`, `previewThumbnailHeight`, `previewScope`, `previewShowWindowTitles`, `previewShowTrafficLights`, `previewIncludeMinimized`, `thumbnailRefreshInterval`, `previewShowPointer`.
- Appearance: `theme`, `useCustomSelectionColor`, `selectionColor`, `panelCornerRadius`, `panelMaterial`, `reduceAnimations`.
- Advanced: `debugLogging`, `allowedWindowSubroles`.

`launchAtLogin` expresses the user's preference. The UI/service must apply it through SMAppService and surface any failure. Permission status and private-symbol availability are live service state, not persisted preferences. Restore, reveal logs, and reimport are service actions.

`newWindowRule(for:)` returns the matching rule or automatic fallback. Defaults cover Finder, Safari, Chrome, Arc, Firefox, Terminal and iTerm2. Automatic strategy uses menu, shortcut, reopen. Per-app preference runs first, then the remaining fallbacks. Keyboard key codes are physical macOS key codes. Modifiers use CGEvent flag bit positions.

## Policy entry points

- `SpacePolicy.currentSpaceIDs(snapshot:displayID:separateSpaces:allDisplays:)`: select the Dock's display, switcher's mouse display, or union of all displays' current Spaces. Shared-Spaces mode uses the snapshot main fallback.
- `WindowFilter.apply(to:)`: MRU windows filtered by scope, minimized/hidden flags, optional PID and optional display frame. A zero-sized or unknown frame cannot match a display filter; the tracker should preserve the last known frame for minimized windows.
- `WindowCandidate.isEligible`: standard role/subrole, minimum size 100 by 50, nonzero ID, layer zero and positive alpha. Runtime AX query failures must be rejected by the service before creating candidates.
- `SwitcherPolicy.items`: one tile per eligible window and optionally one per app with no windows anywhere. It does not create an empty-app tile merely because all app windows were filtered out. `nextIndex` supports wrapping and empty lists.
- `DockCompositionPolicy.items`: Finder always first; pins in stored order; local running apps; dimmed remote apps; separator and Trash only when Trash is enabled. Duplicate bundle identities collapse. Missing bundle IDs use process identities. Pins remain visible even with no current windows.
- `DotPolicy.indicators`: supply a filter scoped to the app PID and the indicator scope. `DotIndicators` describes filled dots or an optional hollow running-state ring. Include minimized separately from Dock visibility.
- `DockClickPolicy.action`: always pass current desktop IDs, regardless of Dock scope. Returns `focus(id)`, `cycle`, `openNewWindowHere`, `launch`, `minimize`, `hide`, or `none`. `cycleTarget` chooses the next local window using a focused ID, wrapping as needed. The action service executes the result.
- `MagnificationPolicy.scale`: distance and range are measured in base icon widths, not points. Range defaults to three widths.
- `PinnedAppsPolicy.parse`: pass the exported plist, an existence predicate, and optionally a bundle-ID resolver. It preserves native pin order, skips invalid/missing/non-app entries, and deduplicates IDs. It performs no file access itself.
- `NewWindowMenuPolicy.match`: pass a detached tree with service-owned IDs. Title matching across the full enabled tree precedes exact Cmd+N fallback. Convert AX modifier flags to `HotkeyModifiers` first: AX menu flags have different bit semantics, including an inverted no-command bit. Custom localized titles come from the rule/UI, not English translation guesses.
- `NewWindowVerificationPolicy.confirmedWindow`: records prior IDs, requires a new ID for the same PID and confirmed membership in the requested Space set. Unknown membership is not success. Activation and no-Space-switch behavior remain best effort and require runtime verification.
- `NativeDockPolicy.backup`, `replacementPlan`, `restorePlan`: preserve typed original values and explicit missing keys. A nil change value means delete the key. Persist backup before applying changes. Do not overwrite an existing un-restored backup with DogBar's own replacement values. `PreferenceValue` converts property-list values without losing Boolean/integer/real distinctions. Crash recovery decision is available separately.
- `HotkeyPolicy.decode`: pure event-to-command decoding. The tap service must reenable on `reenableTap`, swallow only when requested, and retain the modifier set of the shortcut that began the active session. Pass that set as `heldModifiers` when decoding modifier release. Dispatch commands to the main actor; release commits even during the appearance delay, allowing quick switching without showing the panel. Initial forward selection is index one, wrapped through `nextIndex`; reverse begins at the last item. Keep session ownership until trigger key-up has been swallowed, even if modifier release already committed the selection.

All policy options are values and can be constructed from settings on the main actor, then passed to worker queues. Services own failures, retries, timeouts, permission gating and actual UI/system effects.
