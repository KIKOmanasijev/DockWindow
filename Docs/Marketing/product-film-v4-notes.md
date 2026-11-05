# DogBar product film v4: review changes

Status: internal cut for review only. Nothing published.
Source: `landing/tools/film-v4/` (v3's object model and engine). Output: `dist/social/product-film-v4/` (git-ignored).
v3 (`landing/tools/film-v3/`, `dist/social/product-film-v3/`) is kept for comparison.

## Review notes and what changed

| Note | v4 |
|---|---|
| The music is ugly; use a library like other demos | Licensed bed: **"New Bass 01" (Mixkit #720)** under the Mixkit Stock Music Free License (free, commercial use, no attribution; not for CDs/DVDs/games/broadcast; do not claim or redistribute the file). It is downloaded at build time into the git-ignored output folder and never committed. Chosen from 16 Mixkit candidates by measured structure: a quiet intro, a bass drop, a groove change, and a real ending that rings out. The picture is locked to its grid (126.05 BPM). One 4-bar phrase is cut at a phrase boundary so its ending lands on the lockup. Original UI sounds stay on top, quieter, and the bed dips under DogBar's own "Turn finished" cue and the typing. |
| Separate Docks should not lead | New order: Option-Tab switcher (on the drop) → Agent Activity → window counts and previews → a separate Dock per desktop → the Dock folds into the app icon. |
| Talk about benefits, not mechanics | Every act now leads with the benefit: "Every open window, one shortcut away." / "Find the right window. Not just the app." / "Know when your agent is done." / "Reply without switching apps." / "How many windows are open? See it at a glance." / "Preview windows before you switch." / "Keep work and personal apart. Every desktop gets its own Dock." |
| Send a reply through the notch | Pick the session, click the reply field, type "Also cover an expired coupon, please." (native island captures, one per 3 characters, caret placed like the field), Return → "Reply sent. Claude Code is picking it up." → Working. The pointer hides while typing, as on macOS. |

## Revision 2: no dead time (36.4 s)

Review: idle holds lost viewers (the Mac sat still from 2.5 s to 6 s; after picking Cursor nothing happened for ~2 s).
Every hold without something to read is gone; actions follow a beat apart, and each headline keeps ~1.5 s of
reading time. The music edit follows the picture on the track's own bar lines (`MUSIC.segments`: track beats
44–88, 112–136, 168–end), so the landmarks still land on actions:

- 1.90 s: the drop; the first Tab opens the switcher (the Mac has settled by 1.4 s).
- 20.94 s: the groove change; the preview cards lift.
- 32.37 s: the ending hit; the tagline and address land; the track rings out to 36.4 s.

## Accuracy rules (unchanged from v3)

The Dock never slides sideways on a desktop change. Cinematic moves (tile assembly, ring growth, card lift,
card → window) end in the real state. Island, session list, reply typing and "Reply sent" are native
`AgentIslandView` renders. Agent Activity is labelled beta. Window content is fictional.
