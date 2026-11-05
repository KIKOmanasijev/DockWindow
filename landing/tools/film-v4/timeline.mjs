// DogBar product film v4: one clock for picture and sound, locked to the licensed music edit.
//
// Music: "New Bass 01" (Mixkit #720, Mixkit Stock Music Free License; downloaded at build time, never committed).
// Measured: 126.05 BPM, first beat at 0.056 s. The film starts on track beat 36, and one 4-bar phrase (track
// beats 128–143) is cut at a phrase boundary, so film beat k is exactly k·P. Landmarks in film time:
//   film beat 12  (bar 4)   the drop          → Option-Tab opens the switcher
//   film beat 76  (bar 20)  groove change     → preview cards lift
//   film beat 116 (bar 30)  the ending hit    → DogBar lockup; the track rings out under the end card
//
// Order (one benefit per act): switcher → Agent Activity (reply from the notch) → window counts and previews →
// a separate Dock per desktop → the Dock folds into the app icon.
export const FPS = 60;
export const RATE = 48000;
export const BPM = 126.05;
export const P = 60 / BPM;                 // 0.47600 s
export const BEAT = P;
export const BAR = 4 * P;
export const B = (bar, beat = 1, sixteenths = 0) => +(((bar - 1) * 4 + (beat - 1) + sixteenths / 4) * P).toFixed(6);
export const MUSIC = { id: 720, title: 'New Bass 01', url: 'https://assets.mixkit.co/music/720/720.mp3', license: 'Mixkit Stock Music Free License (https://mixkit.co/license/#musicFree)',
  first: 0.056, startBeat: 36, cutFrom: 128, cutTo: 144 };
export const DURATION = 59.6;

export const T = {
  // ---- Act 1 · context: a real Mac ----
  fadeIn: [0, 0.6],
  settle: [0, B(2, 3)],                    // tilted Mac drifts flat while pushing in
  // ---- Act 2 · Option-Tab (the drop) ----
  optDown: B(3, 4),                        // anticipation: ⌥ goes down a beat before the drop
  open: B(4),                              // 5.71 first Tab: the switcher opens
  tabs: [B(4), B(4, 3), B(5), B(5, 3)],    // 4 Tabs over the MRU list → Cursor
  typeSw: B(4, 2),
  release: B(7),                           // 11.42
  ringGrow: [B(7), B(7, 3)],
  // ---- light (from and into the notch) ----
  paper2: [B(8), B(8, 3)],
  type2a: B(8, 3),
  type2b: B(9),
  toNotch: [B(9, 4), B(10, 2)],
  // ---- Act 3 · Agent Activity beta ----
  finished: B(10, 3),                      // collapsed island turns to "finished"; DogBar's cue
  type5: B(10, 4),
  cursorToIsland: [B(11, 1), B(11, 3)],
  expand: B(11, 3) + 0.1,                  // + the app's 100 ms hover intent
  clickClaude: B(12, 2),
  cursorToField: [B(12, 3), B(13, 1) - 0.05],
  focusField: B(13),                       // click into the reply field
  typing: [B(13, 2), B(14, 3) - 0.2],      // 13 captured prefixes
  type6: B(13, 3),                         // "Reply without switching apps."
  send: B(14, 3),                          // Return: "Reply sent"
  replied: B(15, 1),                       // Claude Code picks it up (Working)
  leave: B(15, 4),
  collapse: B(15, 4) + 0.24,               // + the app's 240 ms exit grace
  // ---- Act 4 · counts and previews ----
  toDots: [B(16, 2), B(17, 1)],            // the camera travels from the notch down to the Dock
  dotsCount: [B(17, 2), B(17, 2, 2), B(17, 3)],
  typeDots: B(17, 1),
  cursorIn: [B(18, 2), B(19, 1)],
  hover: B(19, 1),
  preview: B(19, 1) + 0.25,                // DogBar's 0.25 s hover delay
  toPreviewFrame: [B(18, 4), B(19, 3)],
  lift: [B(20), B(20, 2, 2)],              // the groove change: cards lift (pointer still)
  typePv: B(20),
  land: [B(21), B(21, 2, 2)],
  cardMoves: [B(21, 3), B(22), B(22, 2, 2)],
  click: B(22, 3),
  grow: [B(22, 3) + 0.06, B(23, 2)],
  // ---- Act 5 · a separate Dock on every desktop ----
  detach: [B(23, 3), B(24, 2)],
  plane2In: [B(23, 4), B(24, 3)],
  labelsIn: B(24, 2),
  typeStage: B(24, 1),
  slide1: B(24, 3),                        // stage → Desktop 2
  slide2: B(25, 3),                        // stage → Desktop 1
  toFlat: [B(26, 2), B(27)],               // the planes flatten into the real screen
  swipeReal: B(27, 2),                     // real swipe → Desktop 2, Dock fixed, icons swap in place
  // ---- end ----
  lift2: [B(28), B(28, 3)],
  fold: [B(28, 3), B(29, 2)],              // the Dock folds into the app icon
  lockup: B(29, 3),
  endHit: B(30),                           // 55.22 the track's ending hit: tagline + URL
  fadeOut: [58.4, 59.55],
};

export const TYPE = {
  sw: 'Every open window, one shortcut away.',
  light: ['Find the right window.', 'Not just the app.'],
  agentA: ['Know when your', 'agent is done.'],
  agentB: ['Reply without', 'switching apps.'],
  dots: ['How many windows are open?', 'See it at a glance.'],
  pv: 'Preview windows before you switch.',
  stage: ['Keep work and personal apart.', 'Every desktop gets its own Dock.'],
  end: 'Window management your Mac should have shipped with.',
};

// UI sound design over the music (original synthesis; quiet, never on top of a vocal-like lead).
export function sfxCues() {
  const c = [];
  const P_ = (t, kind, gain, note, extra = {}) => c.push({ t, kind, gain, note, ...extra });
  P_(T.optDown, 'key', -36, '⌥ down');
  T.tabs.forEach((t, i) => P_(t, 'tick', -36, 'Tab', { step: 3 + i }));
  P_(T.release, 'settle', -34, 'release');
  P_(T.paper2[0], 'swoosh', -38, 'paper from the notch');
  P_(T.toNotch[0], 'swoosh', -38, 'into the notch');
  P_(T.finished, 'dogbarFinished', -25, 'DogBar cue: Turn finished (A5 E5 G5)');
  P_(T.expand, 'bloom', -36, 'island opens');
  P_(T.clickClaude, 'click', -31, 'select Claude Code');
  P_(T.focusField, 'click', -32, 'click reply field', { pitch: 1.1 });
  const steps = typeSteps(13);
  steps.slice(1).forEach((t, i) => { const dt = steps[1] - steps[0]; for (let k = 0; k < (i === 11 ? 1 : 3); k++) P_(+(t - dt + (k + .5) * dt / 3).toFixed(4), 'type', -41 + ((i * 3 + k) % 3) * .8, 'typing'); });
  P_(T.send, 'key', -35, 'Return', { pitch: .85 });
  P_(T.send + 0.03, 'sent', -32, 'reply sent');
  P_(T.toDots[0], 'swoosh', -38, 'down to the Dock');
  T.dotsCount.forEach((t, i) => P_(t, 'tick', -35, 'dot ' + (i + 1), { step: i }));
  P_(T.preview, 'pop', -32, 'preview');
  P_(T.click, 'click', -29, 'click card');
  P_(T.grow[0], 'swoosh', -38, 'card grows into window');
  P_(T.detach[0], 'lift', -34, 'Dock lifts out');
  P_(T.slide1, 'whoosh', -35, '→ Desktop 2', { dir: 1 });
  P_(T.slide2, 'whoosh', -35, '→ Desktop 1', { dir: -1 });
  P_(T.swipeReal, 'whoosh', -36, 'real swipe', { dir: 1 });
  P_(T.fold[0] + 0.3, 'glint', -36, 'folds into the icon');
  return c.sort((a, b) => a.t - b.t);
}
export function typeSteps(n) { return Array.from({ length: n }, (_, i) => +(T.typing[0] + (T.typing[1] - T.typing[0]) * i / Math.max(1, n - 1)).toFixed(4)); }
export const frameOf = (t) => Math.round(t * FPS);
export const sampleOf = (t) => Math.round(t * RATE);
