# Settings

DogBar Settings is a native macOS 26 settings window, built against the macOS 26+ SDK so it gets Liquid Glass. It has:
- the system's glass sidebar;
- a unified toolbar showing the page name as the window title;
- system colors throughout.

Purple appears only as the app's accent, and onboarding's art appears only as the pictures inside page heroes and demos.

Sources live in `Sources/DogBarCore/Features/Settings`. `Docs/SettingsIntegration.md` covers the coordinator API, which is unchanged.

## Window

The window uses an `NSSplitViewController` with a sidebar item (210–260 pt) and a unified `NSToolbar` with a sidebar-tracking separator. The window title follows the selected page. When built with Swift 6.2 or newer, the page scroll view uses `scrollEdgeEffectStyle(.soft, for: .top)` under the glass toolbar.

`SettingsPalette` maps to system colors:
- window background;
- `labelColor` and `secondaryLabelColor`;
- `separatorColor`;
- `systemGreen` and `systemOrange` for status;
- a grouped-section fill.

## Sidebar

The sidebar has an AppKit `NSSearchField` at large size, then a SwiftUI `List` in `.sidebar` style at `sidebarRowSize(.large)`. Selection, hover and keyboard behavior are native. Each page shows a System Settings–style tile (a white SF Symbol on a colored rounded square). The pages sit in three groups under the system's sidebar section headers:

| Group | Pages |
| --- | --- |
| (none) | General, Permissions |
| Features | Dock & Desktops, Previews, Switcher, Appearance |
| Advanced | New Windows, Diagnostics |

Search results use the same list. With no matches it shows `ContentUnavailableView.search`.

## Layout

Pages are grouped sections like System Settings: a `.headline` heading, a rounded section, and `Divider` between rows.
- **Rows:** the title (13 pt) and an optional short description (11.5 pt, wrapping at 380 pt) sit on the left. One control sits on the right. Pop-up menus are right-aligned at their natural width, sliders share a 196 pt column, and switches are small.
- **More options:** rarely changed options sit behind a quiet **More options** row.
- **Page heroes:** General, the three feature pages and Appearance open with a hero. It's a plain section holding a picture (the mascot, a demo, or the panel preview), a `.title3` line and one sentence, then the main control as a row. The window title already names the page, so the hero states what the feature does ("A Dock for every desktop").
- **Native controls:** Finish Setup uses `.glassProminent`, demo Replay buttons use circular `.glass`, switcher keys are checkboxes, and statuses are a colored SF Symbol with a secondary label.

| Page | Contents |
| --- | --- |
| General | Status hero (mascot, state, **Finish Setup…** when needed, **Pause DogBar**), Startup, Updates, Privacy, Recovery |
| Permissions | Required (Accessibility and Screen Recording, with **Allow…** when missing), Troubleshooting (Show Setup, Relaunch) |
| Dock & Desktops | Demo hero with **Use DogBar’s Dock**; Apps in each Dock (including Pinned apps); Layout; Icons and window dots |
| Previews | Demo hero with **Dock previews**; Previews |
| Switcher | Demo hero with the mode; Shortcuts; Windows or Apps; Panel |
| Appearance | Hero with the live panel preview and the Theme segmented control; Style; Motion |
| New Windows | Per-app rules for opening another window, with an empty state |
| Diagnostics | Logging (Private API availability collapsed), Window detection |

While Settings is open, DogBar is a regular app, and its icon shows in DogBar’s Dock and Apple’s, whatever **Show DogBar in the Dock** says. Closing Settings returns to that preference. `SettingsWindowController.isOpen` and `presenceDidChange` carry this to the Dock and the app delegate.

Command-1 to Command-8 select pages in sidebar order, Command-F focuses search, Command-W closes and Command-Q quits.

The window keeps one hosting view per page after first use and switches by hiding the others. Pages build one per main-queue turn after Settings opens.

## Control mapping

Every previous control remains, bound to the same `AppSettings` key. Moves:

| Setting | Was | Now |
| --- | --- | --- |
| Pause DogBar (`isPaused`) | General › Session | General › status hero hero |
| Launch at login, menu bar icon | General › Startup | same |
| Show DogBar in the Dock (`showDogBarInDock`) | Dock › Dock mode | General › Startup |
| Permissions, Show Setup, Relaunch | Permissions | same. Show Setup and Relaunch fold into **Setup and relaunch** once both permissions are allowed |
| Updates, usage data | General | same. The full usage-data explanation is under **What's shared** |
| Restore Native Dock, Reset | General › Session | General › Recovery |
| Use DogBar Dock | Dock › Dock mode | Dock & Desktops (hero) |
| Desktop scope, display scope, other-desktop apps, hide windowless | Dock › Display and desktop filtering | Dock & Desktops › Apps in each Dock |
| Include minimized, windowless apps on last desktop | same group | that group's More options |
| Re-import pins (per desktop) | Diagnostics | Dock & Desktops › Apps in each Dock › Pinned apps (**Copy from Apple’s Dock…**) |
| Position, display, icon size, autohide, autohide delay, keep maximized clear | Dock › Layout | Dock & Desktops › Layout. Autohide delay shows while autohide is on |
| Indicator style, max dots, labels, active-app click, scroll cycling, Trash | Dock › Window indicators / Interaction | Dock & Desktops › Icons and window dots. Max dots shows with one dot per window |
| Count minimized, running state, custom dot color and color | Dock › Window indicators | that group's More options |
| Bounce on launch (`bounceOnLaunch`) | not shown | Dock & Desktops › Icons and window dots |
| Previews on/off | Dock Previews | Previews (hero) |
| Hover delay, scope, height, titles, controls, New Window tile, minimized | Dock Previews | Previews › Previews |
| Empty-app previews, CPU, RAM, pointer arrow, refresh interval | Dock Previews | Previews › More options |
| Switcher mode | Switcher › Activation | Switcher (hero, segmented) |
| Shortcut, same-app toggle and shortcut | Switcher › Shortcuts | Switcher › Shortcuts |
| Windows scope, displays, minimized, hidden, windowless | Switcher › Windows / Applications | Switcher › Windows or Apps |
| Appearance delay | Switcher › Layout | Switcher › Panel |
| Thumbnail width and height, tiles per row | Switcher › Layout | Panel › More options |
| W, M, H, Q | Switcher › Keyboard actions | Switcher › Panel › Keys while switching (checkboxes) |
| Theme | Appearance | Appearance hero strip (segmented) |
| Selection color, corner radius, reduce animations | Appearance | Appearance › Style and Motion. The color well shows while a custom color is on |
| Background material | Appearance | Appearance › More options, labelled as the fallback where Liquid Glass is unavailable |
| New window rules | Dock › New window rules | New Windows |
| Debug logging, log file, subroles, private API list | Advanced | Diagnostics; private API list collapsed |

Labels separate the two scopes: **Desktops** are macOS Spaces and **Displays** are monitors. Pins are per desktop and re-import touches only the current desktop.

## Feature demos

`SettingsFeatureScenes.swift` builds three 264 × 166 pt scenes from the onboarding scene parts (`Stage`, `MiniDock`, `WindowThumb`, glass, app icons and wallpapers), each in a dark Mac bezel. They never capture live windows. Every take has four beats at one pace (`DemoPace`): the opening frame held for about a second (anticipation), one clear action on slow-in, slow-out curves, a hold of about 2.5 s on the result, and a gentle return to the opening frame (reset). The opening frame is also the resting frame, so starting, cancelling and finishing never jump.

- **Dock & Desktops** (about 6.6 s): Desktop 1 with its own Dock, settled. The view leans back slightly, glides to Desktop 2 (whose Dock already holds other apps), holds, then glides back. Nothing fills in icon by icon. Follows desktop scope, dimmed other-desktop apps, single dots and Trash.
- **Previews** (about 9 s): the pointer rests on the desktop, travels to Safari and hovers. The preview opens after the hover delay setting, clamped to 0.3–0.8 s so long delays don't stall the demo, and stays long enough to read. The pointer moves to Hotel booking and clicks, the preview closes, and that window cross-fades to the front. After the hold, everything returns. Follows titles, New Window tile, CPU and RAM.
- **Switcher** (about 8.5 s): the keys rest, the modifier goes down, and Tab is tapped. The panel appears after the appearance delay (clamped to 0.1–0.6 s), and the selection steps to Packing list. On release, Packing list cross-fades in front of the other window. After the hold, everything returns. Follows mode, shortcut keycaps and selection color. macOS mode shows Apple's switcher as a still.

Each take plays once; the corner button replays it. A scene plays only when all of these hold: its page is selected; the window is visible (open, not minimized, not hidden and not fully covered, from `windowDidChangeOcclusionState`); and it is at least 70 percent in view. Hidden cached pages never get `onDisappear`, so this check is explicit. Leaving cancels the take and shows the resting frame. Reduce Motion, **Reduce animations** or a feature that is off shows an explanatory still with no replay. Takes autoplay again the next time Settings opens.

## Search

`SettingsSearchIndex` lists every row with its anchor, keywords, the group that hides it and a note when it exists only in some modes. Every word must match the title, page path or keywords; title matches rank first. Results replace the page list; arrows move, Return opens, Escape clears. Opening a result selects its page, opens its More options group, scrolls to the row and briefly highlights it. A row hidden by the current mode falls back to the top of its page. Results show their path, such as “Features › Previews”. With no matches the sidebar shows the system search empty state.

## Resources

`Resources/Settings/Mascot/guide.png` and `search.png` (640 px RGBA, see that folder's README). `Scripts/onboarding_resources.py` copies and verifies them into `Contents/Resources/Settings` before signing, alongside the onboarding art, for `build-app.sh`, `build-preview.py` and `release.py`. `SettingsAssets.requiredFiles` lists the same files. Only `guide.png` is shown (General hero); search uses the system empty state. Missing art collapses to nothing.

## Verification

Compile with `swift build --build-tests`. Rendered offscreen at 820 × 580 and 940 × 700 in light and dark. The renders covered every page from top to bottom, each feature page, an expanded group with a search highlight, search results, empty search, Dock, previews and switcher off, Apps mode, paused and missing-permission states. Each demo was also sampled every 0.15 s from a mouse-transparent, zero-alpha window, so animations interpolated. Offscreen renders show switches and prominent buttons in their inactive gray, because that window is never key.

Manual checks still needed in the live app:
- Accent colors in the key window.
- The glass sidebar (offscreen renders cannot capture behind-window materials), traffic-light placement over it, and sidebar resizing.
- Titlebar dragging over both columns.
- Hover states.
- Demo pacing at real frame rates.
- Open, close, minimize, hide and reopen, confirming that demos stop and replay.
- Recording shortcuts, including Command-Tab.
- Keyboard search and VoiceOver.
