# DogBar product film v3: storyboard and notes

Status: internal cut for review only. Not published, uploaded, scheduled or attached anywhere.
Source: `landing/tools/film-v3/` (timeline, page, export, score). Output: `dist/social/product-film-v3/` (git-ignored).
v2 (`landing/tools/film/`, `dist/social/product-film-v2/`) is untouched; v3 reads v2's window content (`content.mjs`),
window stylesheet, native renders (DogBarCore views compiled unchanged) and the original wallpapers.

## Why v3

v2 was a desktop-and-checkout story told by a camera moving over one screen, with a long Command-Tab
comparison up front. More zoom, blur and cross-fades would not fix that. v3 is built from a few continuous
objects that keep their identity between shots, and leads with DogBar's main strength: a separate Dock on
every desktop. Motion language taken from the reference (not its brand, UI or audio): one oversized central
object, the same object returning to real UI, a dark-to-light masked type beat, a short real proof, and a
brand end.

Visual thesis: deep DogBar purple stage, glass objects with a moving specular edge, Mac UI as the only
imagery, light paper only for the two type beats. Yellow appears once, as the beta dot.

## Objects

| Object | Where it goes |
|---|---|
| The Dock | Drawn by the Mac, lifts out, floats large while two desktops slide behind it, lands back on the Mac, opens into paper, returns, folds into the app icon. It never slides sideways on a desktop change: DogBar's Dock panel is `.canJoinAllSpaces` + `.stationary`, so the desktops move and its icons recompose in place. |
| Desktop planes | Desktop 1 / Desktop 2 as 3D planes on the stage; flat and clipped to the Mac for the real swipe. |
| Safari icon → preview cards → window | Dots light one by one (one dot per window), hover opens the real preview (0.25 s delay), cards lift off the panel, settle, the pointer picks "Fix flaky checkout test", and that card grows into the window. |
| Window → tile → ring → window | Option-Tab: a copy of the window shrinks into tile 1 while the other tiles assemble (MRU order); the selection ring steps on each Tab; on release the ring grows into the Cursor window. |
| Notch → paper → island | The light beat opens from the notch and folds back into the island's collapsed capsule. |

## Storyboard (112.5 BPM, bar 1 at 0 s)

| Bars | Time | Shot | Type |
|---|---|---|---|
| 1–2 | 0.0–4.3 | A tilted Mac settles flat (menu bar, Safari, DogBar Dock); the Dock lifts out and the desktop recedes | none |
| 3–5 | 4.3–10.7 | Stage: one Dock, Desktop 1 and Desktop 2 slide behind it three times; icons recompose in place, dots follow | labels "Desktop 1/2" |
| 6–7 | 10.7–14.9 | The planes flatten into the real screen; a real swipe back to Desktop 1, Dock fixed, icons swap in place | none |
| 7–8 | 13.9–17.1 | The Dock's shape opens into paper | "Each desktop. / Its own Dock." |
| 9 | 17.1–19.2 | Dark opens from the Dock; push onto Safari's three dots, lit in turn | "3 windows · One dot per window" |
| 10–13 | 19.2–27.7 | Pointer hovers Safari, label, preview; cards lift (isolate) and land; hover, click, the card grows into the window | "See every window / before you switch." |
| 14–16 | 27.7–33.1 | Option-Tab keycaps; window → tile, tiles assemble, ring steps ×4, release grows the ring into Cursor | keycaps only |
| 16–17 | 33.1–36.5 | Paper opens from the notch | "Every window. / Not just the app." |
| 18–20 | 36.5–42.7 | Paper folds into the island; "Turn finished" (DogBar's real cue); hover expands, pick the session | "Agent Activity · beta" / "Know when your agent is done." |
| 21–25 | 42.7–55.0 | The Mac again; the Dock lifts and folds into the app icon; lockup | "Window management your Mac should have shipped with." → DogBar, URL, platform |

## Accuracy rules kept

- The Dock never slides in from a side on a desktop change. On the stage it stays fixed while desktops move; in the real swipe it stays fixed and recomposes with a quick cross-fade.
- Cinematic devices are clearly separate from interaction: card lift, tile assembly, ring growth and the
  window growing from a card happen with the pointer still or hidden, and each ends in the real state
  (the clicked window in front, the released window in front).
- Pointer causality: hover → label → preview after 0.25 s → move along cards (hover highlight) → click ripple
  → panel dismisses → window in front. On the island: hover → expand after 100 ms intent → click the session.
- Dots: one per window (DotPolicy), DockIconLayer geometry. Personal pins without windows have no dots.
- Island, dog icons and session list are native renders of `AgentIslandView`. Agent Activity is labelled beta.
- No invented features or UI. Window content is fictional; the corner note says so.

## Sound

Original synthesis only (v2 instruments, new arrangement). Sparse intro → light pulse on the stage with a
chord change per swap → drop when the dark opens from the Dock → tense 16ths under Option-Tab, resolving on
release → break under the paper and the notch so DogBar's own "Turn finished" cue plays alone → second drop
on the bookend → IV–V–I and the sonic logo. No reference audio or third-party music.

## Limitations

- Glass is an approximation of DogBar's material (backdrop blur + rim + tint), not Apple's Liquid Glass renderer.
- The stage, card lift, tile assembly and ring growth are cinematic and not app animations.
- Desktop names "Desktop 1/2" are generic; macOS does not draw labels during a swipe.
