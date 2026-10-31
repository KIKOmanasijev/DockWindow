# Ten-minute recording session

Please record these on your Mac. The project does not control your screen, launch apps, change settings, install a build or quit DogBar.

## Prepare (about four minutes)

1. Keep DogBar running normally. Use one display for the capture. Turn on Focus yourself and hide personal documents, conversations, browser bookmarks and desktop filenames. Review the recording before sharing it.
2. Use your existing wallpaper if it is clean. Optional: manually pick a macOS built-in still wallpaper with a quiet lavender/blue area behind the Dock. Avoid downloaded art with unclear rights. Do not change DogBar's appearance for this shoot.
3. Use four ordinary Spaces, not full-screen app Spaces. Keep the same wallpaper and window sizes. Leave roughly the bottom quarter of the screen clear for the Dock and preview panel.
4. Arrange these real, non-sensitive windows manually. Use windows around 900×600 points and overlap them slightly, not full-screen:
   - Desktop 1, writing: Safari window A at example.com; Safari window B at a Wikipedia page of your choice; TextEdit with a short “Launch checklist”.
   - Desktop 2, planning: Preview with a PDF you own; Calculator. Avoid private files in Preview’s sidebar.
   - Desktop 3, downtime: Music (paused, no copyrighted audio captured); a fresh Notes note with three harmless lines. Close/hide private Notes lists.
   - Desktop 4, files: Finder showing a new empty “DogBar demo” folder; Terminal only if you can keep its title and contents free of personal paths. A clean second TextEdit window is an alternative.
5. Before recording, inspect the actual Dock on each Space. Unpinned running apps should follow the configured desktop scope. Finder, Trash, pinned apps and configured windowless apps may persist: that is expected. Do not claim every icon disappears. If your current configuration does not demonstrate filtering, report that rather than changing DogBar settings for this task.
6. Check Safari hover previews appear and Option+Tab opens DogBar's window switcher with your current shortcut configuration. If either is disabled or rebound, report it; do not simulate it.

## Recording settings (one minute)

**Cmd+Shift+5:** choose Record Entire Screen, select the intended display, microphone None, timer 5 seconds, save somewhere easy to find. Enable Show Mouse Clicks if available. Use a 16:9 display when possible; otherwise record the entire display at its native resolution. Do not change your normal resolution just to hit 1080p. Keep the Dock edge and any preview panel in view.

**Screen Studio alternative:** native/full resolution, 60 fps if available (30 fps is fine), system audio and microphone off. Disable automatic zoom, cursor replacement and baked-in backgrounds for the raw export; preserve the real pointer and entire display. Export the raw recording at original size. We can add deliberate crops later.

Record one continuous take or six clips. The edit needs 38 seconds but long handles make selection easy. Leave 3 seconds motionless before and after each action. Slow down; move the mouse smoothly and pause over a target before clicking. Do not narrate unless you want a separate voice track.

## Exact take order (about five minutes)

| Clip / file | Record this action in order | Keep at least |
|---|---|---|
| `01-spaces.mov` | On Desktop 1, open Mission Control manually (Control+Up). Move pointer away from the Space thumbnails; hold all four visible. Close Mission Control afterward. | 10 s |
| `02-clutter.mov` | Desktop 1, both Safari windows and TextEdit visible. Move pointer from the front window toward the covered Safari window, hesitate briefly, stop. No fake error click. | 10 s |
| `03-desktops.mov` | Start Desktop 1. Hold 2 s. Swipe left once using your trackpad's configured Space gesture (or Control+Right). Wait 2 s on Desktop 2; repeat to 3, then 4. End with Dock visible. Repeat once slowly. | 20 s |
| `04-hover.mov` | Return to Desktop 1. Move pointer to Safari's DogBar icon. Wait for the real preview panel. Pause 1 s so both windows read. Move to Wikipedia’s preview, pause 0.5 s, click once. Keep the newly focused window visible 3 s. Repeat once. | 15 s |
| `05-switcher.mov` | Desktop 1. Hold Option; press Tab once. Keep Option down for 2 s. Press Tab slowly until the other Safari window is selected (not just a different app). Wait 1 s, release Option. Keep result visible 3 s. Repeat once. | 15 s |
| `06-native.mov` | Desktop 1, pointer away from Dock. Hold a clear view of the actual glass Dock and Safari’s two window-count dots. Do not hover if that obscures dots. | 8 s |

If you make a mistake, leave a two-second gap and repeat. Do not trim the only copy. Keep original recordings outside Git; place copies under `raw/`. A single long recording is fine: use the same source filename for multiple beats and set each beat's `start` in seconds.

## What to send back

The six originals (or one long take), which take you prefer, and any behaviour that differed from the guide. Optionally include a music file **plus its source URL and licence**. No music is required; this is designed for muted feeds.

For stills instead, manually hold each actual state and capture it. Never build a fake Space transition from one screenshot. Stills are labeled “Still” by the renderer and cannot prove hover/click/shortcut outcomes.
