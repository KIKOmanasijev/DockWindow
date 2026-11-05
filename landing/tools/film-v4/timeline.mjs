// DogBar product film v4: one clock for picture and sound, locked to the licensed music edit.
//
// Music: "New Bass 01" (Mixkit #720, Mixkit Stock Music Free License; downloaded at build time, never committed).
// Measured: 126.05 BPM, first beat at 0.056 s. The film starts one bar before the drop and the track is edited on
// its own bar lines (MUSIC.segments): the drop opens the switcher, the groove change lifts the preview cards, the
// ending hit lands the tagline, and the track rings out under the end card.
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
  first: 0.056,
  // track beat ranges played back to back (end null = to the end of the track); every join is on a bar line,
  // and each section is entered at its own first beat, so the joins read as phrase changes
  segments: [[44, 88], [112, 136], [168, null]] };
// Film beat k is exactly k·P. Landmarks: film beat 4 = the drop (track 48), film beat 44 = the groove change
// (track 112), film beat 68 = the ending hit (track 168).
const b = (beats) => +(beats * P).toFixed(6);
export const DURATION = +(b(68) + 4.0).toFixed(3);

// Holds are kept only where there is something to read (~1.5 s after a headline lands); actions follow each
// other a beat apart.
export const T = {
  fadeIn: [0, 0.35],
  settle: [0, b(3)],                       // the Mac settles flat (1.4 s of context)
  // ---- Option-Tab on the drop ----
  optDown: b(3),
  open: b(4),
  tabs: [b(4), b(5.5), b(7), b(8.5)],      // → Cursor
  typeSw: b(4.5),
  release: b(10.5),
  ringGrow: [b(10.5), b(12)],
  // ---- light, from and into the notch ----
  paper2: [b(12), b(13.5)],
  type2a: b(13.5),
  type2b: b(14.5),
  toNotch: [b(17.5), b(19)],
  // ---- Agent Activity beta ----
  finished: b(19.5),
  type5: b(20),
  cursorToIsland: [b(20.5), b(21.5)],
  expand: b(21.5) + 0.1,
  clickClaude: b(23),
  cursorToField: [b(23.5), b(24.5) - 0.05],
  focusField: b(24.5),
  type6: b(25.5),
  typing: [b(25.5), b(30)],
  send: b(30.5),
  replied: b(31.5),
  leave: b(33.5),
  collapse: b(33.5) + 0.24,
  // ---- counts and previews ----
  toDots: [b(34), b(36)],
  typeDots: b(35.5),
  dotsCount: [b(36.5), b(36.75), b(37)],
  cursorIn: [b(38.5), b(40)],
  hover: b(40),
  preview: b(40) + 0.25,
  toPreviewFrame: [b(39.5), b(41.5)],
  lift: [b(44), b(45.5)],                  // the groove change
  typePv: b(44),
  land: [b(46.5), b(47.5)],
  cardMoves: [b(48), b(48.75), b(49.5)],
  click: b(50),
  grow: [b(50) + 0.06, b(51.5)],
  // ---- a separate Dock per desktop ----
  detach: [b(52), b(53.5)],
  plane2In: [b(52.5), b(54)],
  labelsIn: b(53.5),
  typeStage: b(52.5),
  slide1: b(54.5),
  slide2: b(57),
  toFlat: [b(58), b(59.5)],
  swipeReal: b(60),
  // ---- end ----
  lift2: [b(62), b(63.5)],
  fold: [b(63.5), b(65.5)],
  lockup: b(66.5),
  endHit: b(68),
  fadeOut: [+(b(68) + 2.9).toFixed(3), +(b(68) + 3.95).toFixed(3)],
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
