// DogBar product film v3: one clock for picture and sound. Seconds everywhere.
// 112.5 BPM, 4/4: a beat is 0.5333 s (32 frames at 60 fps), a 16th is 8 frames, so every grid hit is a whole frame.
// Bar 1 starts at 0. Structure (one idea per shot, the Dock is the continuous object):
//   1–2   context: a real Mac (menu bar, window, DogBar Dock), then the Dock lifts out of it
//   3–5   the Dock stays still while two desktop planes slide behind it; its icons recompose in place
//   6–7   proof: the same, flat and full screen, as it really looks
//   8     light: "Each desktop. Its own Dock." (the Dock's shape opens into paper)
//   9–13  window-count dots → hover → preview → cards lift → click → the card grows into the window
//   14–16 Option-Tab: the window becomes a tile, the others assemble, the ring steps, release grows the ring into a window
//   17    light: "Every window. Not just the app." (opens from, and closes into, the notch)
//   18–20 Agent Activity beta: the notch says the agent finished; hover, pick the session
//   21–25 bookend: the Mac again, the Dock lifts and folds into the app icon, lockup
export const FPS = 60;
export const RATE = 48000;
export const BPM = 112.5;
export const BEAT = 60 / BPM;
export const BAR = BEAT * 4;
export const B = (bar, beat = 1, sixteenths = 0) => +((bar - 1) * BAR + (beat - 1) * BEAT + sixteenths * BEAT / 4).toFixed(6);
export const DURATION = 55.0;

export const T = {
  // ---- Act 1 · context ----
  fadeIn: [0, 0.6],
  settle: [0, B(1, 4, 2)],                 // tilted Mac drifts flat while pushing in
  detach: [B(2, 1), B(2, 4)],              // 2.13 → 3.73: the Dock lifts out, the desktop recedes
  // ---- Act 2 · one Dock, two desktops (stage) ----
  plane2In: [B(2, 3), B(3, 2)],            // Desktop 2 arrives beside Desktop 1
  labelsIn: B(3, 1),
  slide1: B(3, 3),                         // 5.33 → Desktop 2
  slide2: B(4, 3),                         // 7.47 → Desktop 1
  slide3: B(5, 2),                         // 9.07 → Desktop 2 (faster, on the push)
  toFlat: [B(5, 4), B(6, 3)],              // 10.13 → 11.73: planes flatten into the real screen, the Dock lands
  // ---- proof (flat, real) ----
  swipeReal: B(6, 4),                      // 12.27: real swipe back to Desktop 1, Dock fixed, icons swap in place
  // ---- light 1 ----
  paper1: [B(7, 3), B(8, 1)],              // 13.87 → 14.93 the Dock's shape opens into paper
  type1a: B(8, 1),                         // "Each desktop."
  type1b: B(8, 2, 2),                      // "Its own Dock."
  iris1: [B(9, 1), B(9, 2, 2)],            // 17.07: dark opens from the Dock (back to stage)
  // ---- Act 3 · dots, preview, card → window ----
  dotsZoom: [B(9, 1), B(9, 4)],
  dotsCount: [B(9, 3), B(9, 3, 2), B(9, 3, 4)],   // the three Safari dots light in turn
  cursorIn: [B(10, 1), B(10, 2, 2)],
  hover: B(10, 2, 2),                      // pointer on Safari
  preview: B(10, 2, 2) + 0.25,             // DogBar's 0.25 s hover delay
  toPreviewFrame: [B(10, 2), B(10, 4)],
  lift: [B(11, 1), B(11, 2, 2)],           // cards lift off the panel (cinematic isolate; pointer hidden)
  type3a: B(11, 1, 2),                     // "See every window"
  land: [B(11, 4), B(12, 1, 2)],           // cards settle back into the real panel
  cardMoves: [B(12, 1, 2), B(12, 2, 2), B(12, 3)],
  click: B(12, 3, 2),                      // 24.80 click "Fix flaky checkout test"
  grow: [B(12, 3, 2) + 0.06, B(13, 1, 2)], // card → window, camera to the full Mac
  type3b: B(13, 1),                        // "before you switch."
  // ---- Act 4 · Option-Tab ----
  optDown: B(14, 1),                       // 27.73
  open: B(14, 1, 2),                       // first Tab: switcher opens (the window becomes tile 0)
  tabs: [B(14, 1, 2), B(14, 3), B(14, 4), B(15, 1)],   // 4 Tabs over the MRU list: checkout, docs, claude, cursor
  release: B(15, 3),                       // 30.40
  ringGrow: [B(15, 3), B(15, 4, 2)],
  type4: B(14, 2),                         // tag + "Every window, by name."
  // ---- light 2 (from and into the notch) ----
  paper2: [B(16, 3), B(17, 1)],
  type2a: B(17, 1),
  type2b: B(17, 2, 2),
  toNotch: [B(17, 4), B(18, 1, 2)],        // paper folds into the island capsule
  // ---- Act 5 · Agent Activity beta ----
  finished: B(18, 3),                      // 37.33: collapsed island turns to "finished", DogBar's cue
  cursorToIsland: [B(18, 4), B(19, 1)],
  expand: B(19, 1) + 0.1,                  // + the app's 100 ms hover intent
  clickClaude: B(19, 4),
  leave: B(20, 4),
  collapse: B(20, 4) + 0.24,               // + the app's 240 ms exit grace
  type5: B(19, 2),
  // ---- Act 6 · bookend ----
  pullBack: [B(21, 1), B(21, 4)],
  lift2: [B(22, 1), B(22, 3)],
  fold: [B(22, 3), B(23, 1)],              // the Dock folds into the app icon
  endline: B(23, 1),
  lockup: B(24, 1),
  fadeOut: [53.6, 54.85],
};

// Kinetic type: very short, integrated, one idea per shot.
export const TYPE = {
  t1: ['Each desktop.', 'Its own Dock.'],
  t3: ['See every window', 'before you switch.'],
  t4: 'Every window, by name.',
  t2: ['Every window.', 'Not just the app.'],
  t5: ['Know when your', 'agent is done.'],
  end: 'Window management your Mac should have shipped with.',
};

export function sfxCues() {
  const c = [];
  const P = (t, kind, gain, note, extra = {}) => c.push({ t, kind, gain, note, ...extra });
  P(T.detach[0], 'lift', -30, 'Dock lifts out');
  P(T.detach[1] - 0.12, 'glint', -36, 'specular settle');
  P(T.slide1, 'whoosh', -31, 'planes → Desktop 2', { dir: 1 });
  P(T.slide1 + 0.42, 'swap', -32, 'Dock recomposes');
  P(T.slide2, 'whoosh', -31, 'planes → Desktop 1', { dir: -1 });
  P(T.slide2 + 0.42, 'swap', -32, 'Dock recomposes');
  P(T.slide3, 'whoosh', -33, 'planes → Desktop 2', { dir: 1 });
  P(T.slide3 + 0.36, 'swap', -33, 'Dock recomposes');
  P(T.toFlat[0], 'swoosh', -35, 'into the real screen');
  P(T.swipeReal, 'whoosh', -33, 'real swipe', { dir: -1 });
  P(T.paper1[0], 'bloom', -34, 'Dock opens into paper');
  P(T.iris1[0], 'swoosh', -35, 'dark returns');
  T.dotsCount.forEach((t, i) => P(t, 'tick', -32, 'dot ' + (i + 1), { step: i }));
  P(T.preview, 'pop', -30, 'preview');
  P(T.lift[0], 'lift', -34, 'cards lift');
  P(T.land[0], 'settle', -34, 'cards land');
  P(T.click, 'click', -27, 'click card');
  P(T.grow[0], 'swoosh', -34, 'card grows into window');
  P(T.optDown, 'key', -34, '⌥ down');
  T.tabs.forEach((t, i) => P(t, 'tick', -33, 'Tab', { step: 3 + i }));
  P(T.release, 'settle', -31, 'release');
  P(T.paper2[0], 'bloom', -35, 'paper from the notch');
  P(T.toNotch[0], 'swoosh', -35, 'into the notch');
  P(T.finished, 'dogbarFinished', -24, 'DogBar cue: Turn finished (A5 E5 G5)');
  P(T.expand, 'bloom', -33, 'island opens');
  P(T.clickClaude, 'click', -29, 'select Claude Code');
  P(T.lift2[0], 'lift', -33, 'Dock lifts again');
  P(T.fold[0] + 0.3, 'glint', -33, 'folds into the icon');
  P(T.lockup, 'logo', -21, 'sonic logo');
  return c.sort((a, b) => a.t - b.t);
}
export const frameOf = (t) => Math.round(t * FPS);
export const sampleOf = (t) => Math.round(t * RATE);
