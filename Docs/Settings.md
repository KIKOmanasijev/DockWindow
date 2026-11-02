# Settings

DogBar Settings is a calm utility window in the onboarding's palette: lavender paper, white (or deep ink) surfaces, ink text and one purple accent. Native controls keep the system text colors so they read in light and dark. The mascot appears twice, small: presenting DogBar's status on General, and in the empty search state.

Sources live in `Sources/DogBarCore/Features/Settings`. `Docs/SettingsIntegration.md` covers the coordinator API, which is unchanged.

## Layout

A translucent sidebar (search, then pages) and a scrolling detail page. Each page has a title, a one-line summary and titled groups of rows: title and description on the left, one control on the right. Rarely changed options sit behind a quiet **More options** row inside their group.

| Page | Contents |
| --- | --- |
| General | Status card (dog, state, **Pause**), Startup, Permissions, Updates, Privacy, Recovery |
| Features | Dock & Desktops, Previews, Switcher. Each opens with a small demo, a one-line explanation and its main switch, then its options |
| Appearance | A still panel preview that follows theme, selection color and corner radius; Panels; Motion |
| Advanced | New window rules, Diagnostics (with Private API availability collapsed), Window detection |

The sidebar lists the three Features subsections under Features. Clicking one scrolls the page to it; the subsection under the top of the page is marked while scrolling. Command-1 to Command-4 select pages, Command-F focuses search, Command-W closes and Command-Q quits.

The window keeps one hosting view per page after first use and switches by hiding the others. Pages build one per main-queue turn after Settings opens.

## Control mapping

Every previous control remains, bound to the same `AppSettings` key. Moves:

| Setting | Was | Now |
| --- | --- | --- |
| Pause DogBar (`isPaused`) | General › Session | General › status card |
| Launch at login, menu bar icon | General › Startup | same |
| Show DogBar in the Dock (`showDogBarInDock`) | Dock › Dock mode | General › Startup |
| Permissions, Show Setup, Relaunch | General › Permissions | same. Show Setup and Relaunch fold into **Setup and relaunch** once both permissions are allowed |
| Updates, usage data | General | same. The full usage-data explanation is under **What's shared** |
| Restore Native Dock, Reset | General › Session | General › Recovery |
| Use DogBar Dock | Dock › Dock mode | Features › Dock & Desktops (hero switch) |
| Desktop scope, display scope, other-desktop apps, hide windowless | Dock › Display and desktop filtering | Features › Dock & Desktops › Which apps each Dock shows |
| Include minimized, windowless apps on last desktop | same group | that group's More options |
| Re-import pins (per desktop) | Advanced › Diagnostics | Features › Dock & Desktops › Pinned apps |
| Position, display, icon size, autohide, autohide delay, keep maximized clear | Dock › Layout | Features › Dock & Desktops › Layout. Autohide delay shows while autohide is on |
| Indicator style, max dots, labels, active-app click, scroll cycling, Trash | Dock › Window indicators / Interaction | Features › Dock & Desktops › Icons and window dots. Max dots shows with one dot per window |
| Count minimized, running state, custom dot color and color | Dock › Window indicators | that group's More options |
| Bounce on launch (`bounceOnLaunch`) | not shown | Features › Dock & Desktops › Icons and window dots |
| Previews on/off | Dock Previews | Features › Previews (hero switch) |
| Hover delay, scope, height, titles, controls, New Window tile, minimized | Dock Previews | Features › Previews › Previews |
| Empty-app previews, CPU, RAM, pointer arrow, refresh interval | Dock Previews | Features › Previews › More options |
| Switcher mode | Switcher › Activation | Features › Switcher (hero segmented control) |
| Shortcut, same-app toggle and shortcut | Switcher › Shortcuts | Features › Switcher › Shortcuts |
| Windows scope, displays, minimized, hidden, windowless | Switcher › Windows / Applications | Features › Switcher › Windows or Apps |
| Appearance delay | Switcher › Layout | Features › Switcher › Panel |
| Thumbnail width and height, tiles per row | Switcher › Layout | Panel › More options |
| W, M, H, Q | Switcher › Keyboard actions | Features › Switcher › Keys while switching (checkboxes) |
| Theme, selection color, corner radius, reduce animations | Appearance | same |
| Background material | Appearance | Appearance › More options, labelled as the fallback where Liquid Glass is unavailable |
| New window rules | Dock › New window rules | Advanced › New window rules |
| Debug logging, log file, subroles, private API list | Advanced | same; private API list collapsed |

Labels separate the two scopes: **Desktops** are macOS Spaces and **Displays** are monitors. Pins are per desktop and re-import touches only the current desktop.

## Feature demos

`SettingsFeatureScenes.swift` builds three 264 × 166 pt scenes from the onboarding scene parts (`Stage`, `MiniDock`, `WindowThumb`, glass, app icons and wallpapers). They never capture live windows.

- **Dock & Desktops**: Desktop 1's Dock fills, the view swipes to Desktop 2, its Dock fills with other apps. Follows desktop scope, dimmed other-desktop apps, single dots and Trash.
- **Previews**: the pointer moves to Safari, hovers, the preview opens after the hover delay setting, the pointer moves to Hotel booking and clicks, the preview closes, then that window comes forward. Follows titles, New Window tile, CPU and RAM.
- **Switcher**: the modifier goes down, Tab is tapped, the panel appears after the appearance delay, the selection walks to Packing list, release, that window comes forward. Follows mode, shortcut keycaps and selection color. macOS mode shows Apple's switcher as a still.

Each take plays once, then holds its last frame; the corner button replays it. A scene plays only while the Features page is selected, the window is visible (open, not minimized, not hidden and not fully covered, from `windowDidChangeOcclusionState`) and it is the topmost scene at least 70 percent in view. Hidden cached pages never get `onDisappear`, so the gate is explicit: leaving cancels the take and shows the still. Reduce Motion, **Reduce animations** or a feature that is off shows a still with no replay. Takes autoplay again on the next opening of Settings.

## Search

`SettingsSearchIndex` lists every row with its anchor, keywords, the group that hides it and a note when it exists only in some modes. Every word must match the title, page path or keywords; title matches rank first. Results replace the page list; arrows move, Return opens, Escape clears. Opening a result selects its page, opens its More options group, scrolls to the row and briefly highlights it. A row hidden by the current mode falls back to its subsection.

## Resources

`Resources/Settings/Mascot/guide.png` and `search.png` (640 px RGBA, see that folder's README). `Scripts/onboarding_resources.py` copies and verifies them into `Contents/Resources/Settings` before signing, alongside the onboarding art, for `build-app.sh`, `build-preview.py` and `release.py`. `SettingsAssets.requiredFiles` lists the same files. Missing art collapses to nothing.

## Verification

Compile with `swift build --build-tests`. Rendered offscreen at 820 × 580 and 940 × 700 in light and dark: every page, each Features subsection, expanded groups with a search highlight, search results, empty search, Dock, previews and switcher off, paused and missing-permission states, and frame sequences of each demo. Manual checks: open, close, minimize, hide and reopen Settings and confirm demos stop and replay; record shortcuts including Command-Tab; search with the keyboard and VoiceOver.
