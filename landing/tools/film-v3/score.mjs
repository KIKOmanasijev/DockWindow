// Original score + interaction sound design for the DogBar film v3, synthesized from scratch (no samples, loops,
// libraries or third-party music; no reference audio). Instruments, reverb, loudness and limiter are v2's
// (landing/tools/film/score.mjs); the arrangement below is new and follows the v3 cue grid (timeline.mjs).
//
// Musical idea (v2): the motif's head is DogBar's own "Turn finished" agent cue contour (A–E–G, from
// AgentSounds.swift). Sparse, unresolved A-minor plucks under the before/after split; the drop lands as the
// camera pushes through the frame into the Dock; a chromatic-mediant shift to E♭ for the Personal desktop;
// a tense repeated-note pulse under the Command-Tab montage, then a full break so DogBar's real cue is heard
// alone; a quiet bar under the typing; a second drop on Return; IV–V–I and the sonic logo at the end.
// The broad energy curve was informed by the reference analysis (Docs/Marketing/product-film-v2-notes.md);
// no melody, harmony, sample or recording from the reference is used.
//
// Writes 48 kHz 24-bit stereo WAVs: music.wav, sfx.wav (stems), master.wav (stems summed, gained to
// the target loudness, true-peak limited). Prints a JSON summary. Usage:
//   node score.mjs <outDir> [--lufs -16] [--tp -1.0]
import { writeFile, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { RATE, B, T, DURATION, sfxCues } from './timeline.mjs';

const out = process.argv[2] || '.';
const argv = process.argv.slice(3);
const TARGET = Number(argv[argv.indexOf('--lufs') + 1] || -16);
const CEIL = Number(argv[argv.indexOf('--tp') + 1] || -1.0);
const FFMPEG = '/opt/homebrew/bin/ffmpeg';
const N = Math.ceil(DURATION * RATE);
const TAU = Math.PI * 2;

// ---------- utilities ----------
function rng(seed) { return () => { seed |= 0; seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
const R = rng(20261105);
const db = (x) => Math.pow(10, x / 20);
const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);
const NOTE = { C: 0, 'C#': 1, Db: 1, D: 2, 'D#': 3, Eb: 3, E: 4, F: 5, 'F#': 6, Gb: 6, G: 7, 'G#': 8, Ab: 8, A: 9, 'A#': 10, Bb: 10, B: 11 };
const m = (s) => { const [, n, o] = s.match(/^([A-G][b#]?)(-?\d)$/); return NOTE[n] + 12 * (+o + 1); };
const stereo = () => [new Float32Array(N), new Float32Array(N)];
const bus = { keys: stereo(), pluck: stereo(), bell: stereo(), bass: stereo(), drums: stereo(), pad: stereo(), air: stereo(), sfx: stereo(), sfxVerb: stereo(), musicVerb: stereo() };
function add(b, i, l, r) { if (i >= 0 && i < N) { b[0][i] += l; b[1][i] += r; } }
const panLR = (p) => [Math.cos((p + 1) * Math.PI / 4), Math.sin((p + 1) * Math.PI / 4)];

// One-pole filters for noise shaping.
function onePoleLP(fc) { const a = Math.exp(-TAU * fc / RATE); let y = 0; return (x) => (y = (1 - a) * x + a * y); }
function biquadBP(fc, q) { const w = TAU * fc / RATE, al = Math.sin(w) / (2 * q), b0 = al, b2 = -al, a0 = 1 + al, a1 = -2 * Math.cos(w), a2 = 1 - al; let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  return (x) => { const y = (b0 * x + b2 * x2 - a1 * y1 - a2 * y2) / a0; x2 = x1; x1 = x; y2 = y1; y1 = y; return y; }; }
function biquadHP(fc, q = .707) { const w = TAU * fc / RATE, al = Math.sin(w) / (2 * q), c = Math.cos(w), b0 = (1 + c) / 2, b1 = -(1 + c), b2 = b0, a0 = 1 + al, a1 = -2 * c, a2 = 1 - al; let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  return (x) => { const y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0; x2 = x1; x1 = x; y2 = y1; y1 = y; return y; }; }

// ---------- instruments ----------
// Felt keys: additive, slightly inharmonic, two detuned strings, felt-darkened partials, hammer noise.
function keys(t, midi, dur, vel = .6, pan = null, target = bus.keys) {
  const f = mtof(midi), s0 = Math.round(t * RATE), len = Math.round((dur + 2.6) * RATE);
  const p = pan ?? Math.max(-.6, Math.min(.6, (midi - 62) / 24)); const [gl, gr] = panLR(p);
  const Bc = .00035, parts = []; const bright = 1800 + 3200 * vel;
  for (let n = 1; n <= 14; n++) { const fn = f * n * Math.sqrt(1 + Bc * n * n); if (fn > 15000) break;
    const a = Math.pow(n, -1.25) * Math.exp(-fn / bright) * (n === 1 ? 1 : .9); const dec = (1.2 + .05 * midi) / (1 + .35 * n) ; parts.push([fn, a, dec, R() * TAU]); }
  const rel = Math.round(dur * RATE), nz = onePoleLP(2400); const amp = .16 * vel * vel + .05 * vel;
  for (let i = 0; i < len; i++) { const tt = i / RATE; const att = Math.min(1, tt / .004);
    const damp = i > rel ? Math.exp(-(i - rel) / RATE / .18) : 1; let v = 0;
    for (const [fn, a, dec, ph] of parts) { const e = Math.exp(-tt / dec);
      v += a * e * (Math.sin(TAU * fn * tt + ph) + .7 * Math.sin(TAU * fn * 1.0007 * tt + ph * 1.3)); }
    if (tt < .02) v += nz((R() * 2 - 1)) * (1 - tt / .02) * .25 * vel;
    v *= att * damp * amp; add(target, s0 + i, v * gl, v * gr);
    if (damp < 1e-3) break; }
}
// Karplus–Strong pluck with a soft body.
function pluck(t, midi, vel = .6, pan = 0, decay = .996) {
  const f = mtof(midi), period = RATE / f, L = Math.floor(period), frac = period - L; const buf = new Float32Array(L + 2);
  for (let i = 0; i < buf.length; i++) buf[i] = (R() * 2 - 1) * .8; let idx = 0, prev = 0; const s0 = Math.round(t * RATE), len = Math.round(2.4 * RATE);
  const [gl, gr] = panLR(pan); const lp = onePoleLP(3000 + 2000 * vel);
  for (let i = 0; i < len; i++) { const a = buf[idx], b = buf[(idx + 1) % buf.length]; const y = (1 - frac) * a + frac * b; const nv = decay * .5 * (y + prev); prev = y; buf[idx] = nv; idx = (idx + 1) % (L + 1);
    const v = lp(y) * .22 * vel * Math.min(1, i / 30); add(bus.pluck, s0 + i, v * gl, v * gr); }
}
// Bell: DogBar-cue-like sine with a soft octave, plus a short glassy inharmonic shimmer.
function bell(t, midi, vel = .5, pan = 0, target = bus.bell, decay = 5.5) {
  const f = typeof midi === 'number' && midi > 200 ? midi : mtof(midi); const s0 = Math.round(t * RATE), len = Math.round(2.2 * RATE); const [gl, gr] = panLR(pan);
  for (let i = 0; i < len; i++) { const tt = i / RATE, att = Math.min(1, tt / .012), e = att * Math.exp(-tt * decay);
    const v = (Math.sin(TAU * f * tt) + .18 * Math.sin(2 * TAU * f * tt) * Math.exp(-tt * 9) + .06 * Math.sin(TAU * f * 2.76 * tt) * Math.exp(-tt * 18)) * e * vel * .32;
    add(target, s0 + i, v * gl, v * gr); }
}
// Bass: sine + a few harmonics with a plucked brightness envelope; articulated note ends.
function bass(t, midi, dur, vel = .7) {
  // Phone-first: roots below E2 move up an octave so the line is heard, not just felt.
  if (midi < 40) midi += 12;
  const f = mtof(midi), s0 = Math.round(t * RATE), len = Math.round((dur + .12) * RATE);
  for (let i = 0; i < len; i++) { const tt = i / RATE; const att = Math.min(1, tt / .006); const end = tt > dur ? Math.max(0, 1 - (tt - dur) / .12) : 1;
    const br = Math.exp(-tt / .12); let v = Math.sin(TAU * f * tt) + .35 * Math.sin(TAU * 2 * f * tt) * (.3 + .7 * br) + .18 * br * Math.sin(TAU * 3 * f * tt) + .08 * br * Math.sin(TAU * 4 * f * tt);
    v *= att * end * Math.exp(-tt / 1.6) * .2 * vel; add(bus.bass, s0 + i, v, v); }
}
// Pad: additive detuned saws with a slowly breathing spectral tilt.
function pad(t, notes, dur, vel = .5, att = .6, rel = 1.0, bright = 1400) {
  const s0 = Math.round(t * RATE), len = Math.round((dur + rel) * RATE); const voices = [];
  for (const nm of notes) for (const d of [-7, 0, 6]) { const f = mtof(nm) * Math.pow(2, d / 1200); const pan = d / 10;
    const hs = []; for (let h = 1; h <= 18 && f * h < 9000; h++) hs.push([h, R() * TAU]); voices.push([f, pan, hs]); }
  const k = .045 * vel / Math.sqrt(voices.length);
  for (let i = 0; i < len; i += 1) { const tt = i / RATE; const env = Math.min(1, tt / att) * (tt > dur ? Math.max(0, 1 - (tt - dur) / rel) : 1); if (env <= 0) continue;
    const tilt = bright * (1 + .25 * Math.sin(TAU * tt / 3.7));
    let l = 0, r = 0; for (const [f, pan, hs] of voices) { let v = 0; for (const [h, ph] of hs) v += Math.sin(TAU * f * h * tt + ph) / h * Math.exp(-f * h / tilt); l += v * (1 - pan); r += v * (1 + pan); }
    add(bus.pad, s0 + i, l * k * env, r * k * env); }
}
// ---------- percussion ----------
function kick(t, vel = .7) { const s0 = Math.round(t * RATE); let ph = 0;
  for (let i = 0; i < .5 * RATE; i++) { const tt = i / RATE; const f = 46 + 70 * Math.exp(-tt / .035); ph += TAU * f / RATE;
    const v = (Math.sin(ph) * Math.exp(-tt / .22) + (tt < .003 ? (R() * 2 - 1) * .3 : 0)) * .55 * vel * Math.min(1, tt / .002); add(bus.drums, s0 + i, v, v); } }
function rim(t, vel = .5, pan = .1) { const s0 = Math.round(t * RATE); const bp = biquadBP(1900, 3.5); const [gl, gr] = panLR(pan);
  for (let i = 0; i < .09 * RATE; i++) { const tt = i / RATE; const v = (bp(R() * 2 - 1) * 2.4 * Math.exp(-tt / .012) + Math.sin(TAU * 820 * tt) * Math.exp(-tt / .02) * .5) * .35 * vel; add(bus.drums, s0 + i, v * gl, v * gr); } }
function shaker(t, vel = .4, pan = -.25) { const s0 = Math.round(t * RATE); const bp = biquadBP(7200, 1.4), hp = biquadHP(4000); const [gl, gr] = panLR(pan);
  for (let i = 0; i < .11 * RATE; i++) { const tt = i / RATE; const e = Math.min(1, tt / .008) * Math.exp(-tt / .035); const v = hp(bp(R() * 2 - 1)) * e * .5 * vel; add(bus.drums, s0 + i, v * gl, v * gr); } }
function brush(t, vel = .5, pan = .15) { const s0 = Math.round(t * RATE); const lp = onePoleLP(5200), hp = biquadHP(900); const [gl, gr] = panLR(pan);
  for (let i = 0; i < .32 * RATE; i++) { const tt = i / RATE; const e = Math.min(1, tt / .006) * Math.exp(-tt / .09); const v = (hp(lp(R() * 2 - 1)) * 1.1 + Math.sin(TAU * 185 * tt) * Math.exp(-tt / .05) * .25) * e * .38 * vel; add(bus.drums, s0 + i, v * gl, v * gr); } }
function wood(t, midi, vel = .5, pan = 0, target = bus.drums) { const f = mtof(midi); const s0 = Math.round(t * RATE); const [gl, gr] = panLR(pan);
  for (let i = 0; i < .25 * RATE; i++) { const tt = i / RATE; const v = (Math.sin(TAU * f * tt) * Math.exp(-tt / .06) + .4 * Math.sin(TAU * f * 3.9 * tt) * Math.exp(-tt / .015)) * .3 * vel * Math.min(1, tt / .0015); add(target, s0 + i, v * gl, v * gr); } }
function swell(t, dur, vel = .4) { const s0 = Math.round(t * RATE); const hp = biquadHP(3000); const lp = onePoleLP(9000);
  for (let i = 0; i < (dur + 1.5) * RATE; i++) { const tt = i / RATE; const e = tt < dur ? Math.pow(tt / dur, 2.2) : Math.exp(-(tt - dur) / .5); const v = lp(hp(R() * 2 - 1)) * e * .12 * vel; add(bus.drums, s0 + i, v * (.8 + .2 * Math.sin(tt * 7)), v * (.8 + .2 * Math.cos(tt * 5))); } }

// ---------- composition (v3: 112.5 BPM, bar 1 at 0 s) ----------
// Motif head is DogBar's own "Turn finished" contour (A–E–G, AgentSounds.swift).
const S = (bar, step) => B(bar, 1, step);
const H = (v) => v * (1 + (R() - .5) * .12);
const ht = (t) => t + (R() - .5) * .006;
const CH = {
  Am9: ['A3', 'C4', 'E4', 'G4', 'B4'], Fmaj9: ['F3', 'C4', 'E4', 'G4', 'A4'], Dm11: ['D3', 'A3', 'C4', 'F4', 'G4'], E7sus: ['E3', 'A3', 'B3', 'D4'], E7: ['E3', 'G#3', 'B3', 'D4'],
  G6: ['G3', 'B3', 'E4', 'A4'], Cadd9: ['E3', 'G3', 'C4', 'D4', 'G4'], Am7: ['A3', 'E4', 'G4', 'C5'], Dm9: ['D3', 'F3', 'C4', 'E4', 'A4'],
  Ebmaj9: ['Eb3', 'Bb3', 'D4', 'F4', 'G4'], Cmaj9: ['C3', 'G3', 'D4', 'E4', 'B4'], Gsus: ['G3', 'C4', 'D4', 'F4'], Bbmaj7: ['Bb2', 'F3', 'A3', 'D4'],
};
const chord = (t, name, dur, vel = .5, spread = .012) => CH[name].forEach((n, i) => keys(t + i * spread, m(n), dur, H(vel)));
const up = (name) => CH[name].slice(1).map((n) => n.replace(/\d/, (d) => String(+d + 1)));
const bassBar = (bar, root, alt) => { bass(S(bar, 0), m(root), .4, .75); bass(S(bar, 6), m(alt || root), .18, .5); bass(S(bar, 8), m(root), .3, .62); bass(S(bar, 14), m(alt || root), .12, .45); };
const grooveBar = (bar, { kickPat = [0, 8, 10], rimAt = [4, 12], sh = .3, br = [] } = {}) => {
  kickPat.forEach((s) => kick(ht(S(bar, s)), s === 0 ? .62 : .45));
  rimAt.forEach((s) => rim(ht(S(bar, s)), .42));
  br.forEach((s) => brush(ht(S(bar, s)), .3));
  for (let s = 0; s < 16; s++) shaker(ht(S(bar, s)), H(sh * (s % 4 === 2 ? 1 : s % 2 ? .55 : .75)), -.3);
};
const pulse = (bar, notes, vel = .42, every = 2, from = 0, to = 16) => { for (let s = from; s < to; s += every) pluck(S(bar, s), m(notes[(s / every) % notes.length]), H(vel * (s % 4 === 0 ? 1 : .78)), ((s / every) % 2 ? .3 : -.3), .994); };
const motif = (bar, base = 0, vel = .5, instr = 'keys') => {
  const ph = [['A4', 0, .25], ['E4', 2, .25], ['G4', 4, .55], ['C5', 8, .2], ['B4', 10, .2], ['G4', 12, .45]];
  ph.forEach(([n, s, d]) => { const t = S(bar, s); const k = m(n) + base + 12;
    if (instr === 'keys') keys(t, k, d, H(vel)); else if (instr === 'pluck') pluck(t, k, H(vel), .2); else bell(t, k, H(vel), .1); });
};

// Bars 1–2 · a real Mac in near-silence; the Dock lifts on bar 2 with a soft riser.
bell(0.12, m('E6'), .1, .3, bus.bell, 2.2);
pad(S(1, 0), ['A3', 'E4', 'G4', 'C5'], 2.3, .3, .9, 1.0, 800); bass(S(1, 0), m('A1'), 2.0, .24);
pluck(S(1, 8), m('E5'), H(.28), -.3, .993); pluck(S(1, 12), m('G5'), H(.24), .3, .993);
pad(S(2, 0), ['F3', 'C4', 'E4', 'A4'], 2.2, .34, .4, .8, 1000); bass(S(2, 0), m('F1'), 1.9, .3); chord(S(2, 0), 'Fmaj9', 1.4, .26, .03);
swell(S(2, 2), 1.4, .45);
[['A5', 6], ['E5', 8], ['G5', 10]].forEach(([n, s]) => keys(S(2, s), m(n), .5, H(.3)));
// Bars 3–5 · the stage: one Dock, two desktops. Light pulse; every swap is a chord change.
const stage = [['Am9', 'A1', 'E2', ['A4', 'E5', 'C5', 'G5']], ['Ebmaj9', 'Eb2', 'Bb1', ['G4', 'D5', 'Bb4', 'F5']], ['Cadd9', 'C2', 'G1', ['C5', 'G4', 'E5', 'D5']]];
stage.forEach(([c, r, a, pl], i) => { const bar = 3 + i;
  chord(S(bar, 0), c, .9, .3); pad(S(bar, 0), up(c), 2.3, .28, .3, .6, 1100); bassBar(bar, r, a);
  pulse(bar, pl, .3); grooveBar(bar, { kickPat: [0, 8], rimAt: i ? [4, 12] : [12], sh: .2 }); });
// the swaps colour toward the other desktop's chord
chord(T.slide1 + .42, 'Ebmaj9', .5, .22, .02); chord(T.slide2 + .42, 'Am9', .5, .22, .02);
// Bar 6 · into the real screen: hold, then the swipe.
chord(S(6, 0), 'Dm11', 1.6, .3, .02); pad(S(6, 0), up('Dm11'), 2.0, .3, .3, .6, 1000); bass(S(6, 0), m('D2'), 1.4, .5);
pulse(6, ['D5', 'A4', 'F5', 'C5'], .26, 2, 0, 12); swell(S(6, 8), 1.05, .4);
// Bar 7 · proof, then the paper opens: the groove falls away into air.
chord(S(7, 0), 'Cadd9', 1.0, .32); bassBar(7, 'C2', 'G1'); grooveBar(7, { kickPat: [0, 8], rimAt: [4], sh: .22 });
pad(T.paper1[0], ['C4', 'G4', 'D5', 'E5'], 2.6, .32, .5, 1.4, 1700);
// Bar 8 · light: the motif on bare keys.
motif(8, 0, .4); bass(S(8, 0), m('F1'), 2.0, .3); pad(S(8, 0), ['F3', 'C4', 'E4', 'A4'], 2.0, .26, .5, 1.0, 900);
[12, 13, 14, 15].forEach((s, i) => shaker(ht(S(8, s)), .12 + i * .07));
// Bars 9–13 · DROP as the dark opens from the Dock: full groove, staccato pulse.
const prog = [['Am7', 'A1', 'E2', ['E5', 'C5', 'G5', 'A4']], ['Fmaj9', 'F1', 'C2', ['A4', 'E5', 'C5', 'G5']], ['Cadd9', 'C2', 'G1', ['C5', 'G4', 'E5', 'D5']], ['G6', 'G1', 'D2', ['D5', 'B4', 'E5', 'G4']], ['Am7', 'A1', 'E2', ['E5', 'C5', 'G5', 'A4']]];
prog.forEach(([c, r, a, pl], i) => { const bar = 9 + i;
  chord(S(bar, 0), c, .5, .32); chord(S(bar, 6), c, .3, .24); chord(S(bar, 12), c, .3, .22); pad(S(bar, 0), up(c), 2.3, .3, .3, .6, 1100);
  bassBar(bar, r, a); grooveBar(bar, i === 3 ? { kickPat: [0, 8, 10, 14] } : {}); pulse(bar, pl, .34); });
kick(S(9, 0), .62);
motif(10, 0, .42); motif(12, 2, .38);
swell(S(10, 10), 1.0, .35);                                     // into the lift
keys(T.preview, m('E5'), .4, .32); keys(T.preview + .1, m('A5'), .7, .34);
// Bars 14–15 · Option-Tab: tension, repeated-note 16ths over Dm → E7, release on a settle.
chord(S(14, 0), 'Dm9', .9, .3); chord(S(14, 8), 'E7sus', .9, .3); pad(S(14, 0), ['D4', 'F4', 'A4', 'C5'], 1.1, .3, .2, .3, 1300); pad(S(14, 8), ['E4', 'A4', 'B4', 'D5'], 1.0, .3, .2, .3, 1300);
bass(S(14, 0), m('D2'), .9, .6); bass(S(14, 8), m('E2'), .9, .62); grooveBar(14, { kickPat: [0, 6, 8, 14], rimAt: [4, 12], sh: .34 });
for (let s = 0; s < 16; s++) pluck(S(14, s), m(s % 4 === 3 ? 'F5' : 'E5'), H(.2 + s * .006), s % 2 ? .25 : -.25, .99);
chord(S(15, 0), 'E7', .9, .32); bass(S(15, 0), m('E2'), .9, .6); grooveBar(15, { kickPat: [0, 6], rimAt: [4], sh: .3 });
for (let s = 0; s < 8; s++) pluck(S(15, s), m(s % 4 === 3 ? 'G#5' : 'E5'), H(.24), s % 2 ? .25 : -.25, .99);
chord(T.release, 'Am9', 1.6, .36, .02); bass(T.release, m('A1'), 1.6, .55); pad(T.release, up('Am9'), 2.6, .32, .2, .8, 1300);
// Bar 16 · the Cursor window holds; the paper opens from the notch on beat 3.
pulse(16, ['A4', 'E5', 'C5', 'G5'], .24, 2, 0, 8);
pad(T.paper2[0], ['F4', 'C5', 'E5', 'A5'], 3.2, .3, .4, 1.2, 1800);
// Bar 17 · light: break. Keys only, the motif answered a step higher.
motif(17, 2, .36); bass(S(17, 0), m('D2'), 2.0, .28);
// Bar 18 · the notch: near silence so DogBar's real "Turn finished" cue is heard alone.
pad(S(18, 0), ['A4', 'E5', 'B5'], 2.0, .22, .5, .8, 1800);
// Bars 19–20 · Agent Activity: soft re-entry, quarter-note pulse, keys low.
pad(S(19, 0), ['F3', 'A3', 'E4', 'B4'], 2.3, .34, .3, .8, 1100); bass(S(19, 0), m('F1'), 2.0, .4);
[0, 4, 8, 12].forEach((s) => pluck(S(19, s), m('C5'), H(.22), 0, .993));
[['A3', 0, 1.0], ['E3', 4, 1.0], ['G3', 8, 1.6]].forEach(([n, s, d]) => keys(S(19, s), m(n), d, .3));
pad(S(20, 0), ['G3', 'C4', 'D4', 'F4'], 2.2, .32, .3, .5, 1000); bass(S(20, 0), m('G1'), 2.0, .4);
[0, 4, 8, 12].forEach((s) => pluck(S(20, s), m('D5'), H(.22), 0, .993)); swell(S(20, 8), 1.07, .4);
// Bars 21–22 · bookend: second drop as the Mac returns, riser into the fold.
[['Cadd9', 'C2', 'G1', ['C5', 'G4', 'E5', 'D5']], ['Fmaj9', 'F1', 'C2', ['A4', 'E5', 'C5', 'G5']]].forEach(([c, r, a, pl], i) => { const bar = 21 + i;
  chord(S(bar, 0), c, .5, .32); chord(S(bar, 6), c, .3, .24); pad(S(bar, 0), up(c), 2.3, .3, .3, .6, 1200);
  bassBar(bar, r, a); grooveBar(bar, i ? { kickPat: [0, 8, 10, 14] } : {}); pulse(bar, pl, .32); });
kick(S(21, 0), .6); motif(21, 0, .44); swell(S(22, 6), 1.3, .45);
// Bar 23 · end line: IV–V colour, harmonised motif.
chord(S(23, 0), 'G6', 1.4, .42, .02); pad(S(23, 0), ['G3', 'B3', 'E4', 'A4', 'D5'], 2.0, .42, .2, .5, 1700); bass(S(23, 0), m('G1'), 1.9, .56);
[['A5', 0, .3], ['E5', 2, .3], ['G5', 4, .6], ['C6', 8, .25], ['B5', 10, .25], ['G5', 12, .55]].forEach(([n, s, d]) => { keys(S(23, s), m(n), d, H(.38)); keys(S(23, s), m(n) - 12, d, H(.24)); });
// Bar 24 · logo: I (C maj9) with the sonic logo (SFX), long ring to the end.
chord(S(24, 0), 'Cmaj9', 3.0, .46, .03); pad(S(24, 0), ['C3', 'G3', 'E4', 'B4', 'D5'], 4.4, .44, .3, 2.0, 1500); bass(S(24, 0), m('C2'), 3.4, .52); kick(S(24, 0), .42);
bell(S(25, 8), m('E6'), .12, .2, bus.bell, 2.0);

// Air bed: always there, more present in the opening and the break.
{ const lp = onePoleLP(5200), hp = biquadHP(1800), lp2 = onePoleLP(4800), hp2 = biquadHP(1700);
  for (let i = 0; i < N; i++) { const t = i / RATE; const w = .55 + .45 * Math.sin(TAU * t / 6.3);
    const lvl = .018 * (t < .8 ? 1.4 : 1) * (t > B(18) && t < B(19) ? 1.6 : 1) * w * Math.min(1, t / .25) * Math.max(0, Math.min(1, (DURATION - t) / 1.5));
    bus.air[0][i] = hp(lp(R() * 2 - 1)) * lvl; bus.air[1][i] = hp2(lp2(R() * 2 - 1)) * lvl; } }

// ---------- SFX (separate stem) ----------
const TICKS = [m('A5'), m('E5'), m('G5'), m('C6'), m('D5'), m('E5'), m('G5')];
const sfx = bus.sfx;
function keyClick(t, vel = 1, pitch = 1, pan = 0) { const s0 = Math.round(t * RATE); const bp = biquadBP(3600 * pitch, 2), bp2 = biquadBP(240 * pitch, 3); const [gl, gr] = panLR(pan);
  for (let i = 0; i < .06 * RATE; i++) { const tt = i / RATE; const n = R() * 2 - 1; const v = (bp(n) * 1.6 * Math.exp(-tt / .006) + bp2(n) * 3 * Math.exp(-tt / .02)) * vel; add(sfx, s0 + i, v * gl * 1.3, v * gr * 1.3); } }
function tick(t, midi, vel, pan = 0) { const det = (R() - .5) * 16; wood(t, midi + det / 100, vel * (1 + (R() - .5) * .22), pan + (R() - .5) * .2, sfx); }
function settle(t, vel = 1, pan = 0) { const s0 = Math.round(t * RATE); const lp = onePoleLP(700); let ph = 0; const [gl, gr] = panLR(pan * .6);
  for (let i = 0; i < .45 * RATE; i++) { const tt = i / RATE; const f = 70 + 45 * Math.exp(-tt / .05); ph += TAU * f / RATE; const v = (Math.sin(ph) * Math.exp(-tt / .1) + lp(R() * 2 - 1) * .6 * Math.exp(-tt / .06)) * Math.min(1, tt / .003) * vel; add(sfx, s0 + i, v * gl * 1.4, v * gr * 1.4);
    if (i % 1 === 0) add(bus.sfxVerb, s0 + i, v * .2, v * .2); } }
function pop(t, vel = 1, pitch = 1) { const s0 = Math.round(t * RATE); let ph = 0;
  for (let i = 0; i < .12 * RATE; i++) { const tt = i / RATE; const f = (900 + 600 * (1 - Math.exp(-tt / .02))) * pitch; ph += TAU * f / RATE; const v = Math.sin(ph) * Math.exp(-tt / .03) * Math.min(1, tt / .002) * vel; add(sfx, s0 + i, v, v); add(bus.sfxVerb, s0 + i, v * .4, v * .4); } }
function click(t, vel = 1, pitch = 1) { const s0 = Math.round(t * RATE); const bp = biquadBP(2900 * pitch, 6);
  for (let i = 0; i < .04 * RATE; i++) { const tt = i / RATE; const v = ((i < 3 ? 1 : 0) * .8 + bp(R() * 2 - 1) * 2.5 * Math.exp(-tt / .006)) * vel; add(sfx, s0 + i, v, v * .95); } }
function whoosh(t, dir, vel = 1) {
  // Follows the swipe's own spring velocity (0.62 s, bounce 0) and pans with the motion.
  const s0 = Math.round(t * RATE), len = Math.round(1.0 * RATE); const w = TAU / .62;
  let bp = null, f0 = 0; for (let i = 0; i < len; i++) { const tt = i / RATE; const vel01 = w * w * tt * Math.exp(-w * tt) / (w / Math.E); // normalised velocity profile
    const fc = 500 + 2600 * vel01; if (!bp || Math.abs(fc - f0) > 25) { bp = biquadBP(fc, .9); f0 = fc; }
    const v = bp(R() * 2 - 1) * vel01 * vel * .9 * Math.min(1, tt / .01); const p = dir * (-.7 + 1.4 * Math.min(1, tt / .45)); const [gl, gr] = panLR(p);
    add(sfx, s0 + i, v * gl, v * gr); add(bus.sfxVerb, s0 + i, v * gl * .3, v * gr * .3); } }
// DogBar's own agent cues, reproduced with AgentSounds.swift's synthesis (sine + 0.18 octave, 12 ms attack, exp(−5.5t)).
function dogbarCue(t, notes, vel = 1) { const s0 = Math.round(t * RATE); const len = Math.round((Math.max(...notes.map((n) => n[1])) + .9) * RATE);
  const buf = new Float32Array(len); for (const [f, st] of notes) { const off = Math.round(st * RATE); for (let i = 0; i < len - off; i++) { const tt = i / RATE; const a = Math.min(1, tt / .012) * Math.exp(-tt * 5.5);
    buf[off + i] += (Math.sin(TAU * f * tt) + .18 * Math.sin(2 * TAU * f * tt) * Math.exp(-tt * 9)) * a * .32; } }
  let pk = 0; for (const x of buf) pk = Math.max(pk, Math.abs(x)); for (let i = 0; i < len; i++) { const v = buf[i] / Math.max(1, pk) * .7 * vel; add(sfx, s0 + i, v, v); add(bus.sfxVerb, s0 + i, v * .25, v * .25); } }
function bloom(t, vel = 1) { const s0 = Math.round(t * RATE); const lp = onePoleLP(500);
  for (let i = 0; i < .7 * RATE; i++) { const tt = i / RATE; const e = tt < .12 ? tt / .12 : Math.exp(-(tt - .12) / .2); const v = (Math.sin(TAU * 110 * tt) * .5 + Math.sin(TAU * 165 * tt) * .3 + lp(R() * 2 - 1) * 1.2) * e * vel; add(sfx, s0 + i, v, v); add(bus.sfxVerb, s0 + i, v * .3, v * .3); } }
function logo(t, vel = 1) { wood(t, m('A4'), .8 * vel, 0, sfx); [[m('A5'), 0], [m('E5'), .15], [m('G5'), .3], [m('C6'), .6]].forEach(([n, d], i) => { bell(t + d, n, (.55 + .1 * i) * vel, (i - 1.5) * .2, sfx, 3.2); bell(t + d, n, .25 * vel, 0, bus.sfxVerb, 3.2); }); }

// v2 voices: a soft two-note "found", an airy camera swoosh, typing keys, and the reply-sent pop.
function found(t, vel = 1, pan = 0) { [[m('E6'), 0], [m('A6'), .07]].forEach(([n, d]) => bell(t + d, n, .5 * vel, pan, sfx, 6.5)); }
function swoosh(t, vel = 1) { const s0 = Math.round(t * RATE), len = Math.round(.9 * RATE);
  let bp = null, f0 = 0; for (let i = 0; i < len; i++) { const tt = i / RATE, p = tt / .9; const env = Math.sin(Math.PI * Math.min(1, p)) ** 2;
    const fc = 900 + 2600 * p; if (!bp || Math.abs(fc - f0) > 30) { bp = biquadBP(fc, .8); f0 = fc; } const v = bp(R() * 2 - 1) * env * vel * .5;
    add(sfx, s0 + i, v * (1 - p * .4), v * (.6 + p * .4)); add(bus.sfxVerb, s0 + i, v * .35, v * .35); } }
function typeKey(t, vel = 1) { keyClick(t, vel * .55, .9 + R() * .3, (R() - .5) * .2); }
function sent(t, vel = 1) { pop(t, .14 * vel, 1.25); bell(t + .03, m('G6'), .22 * vel, .1, sfx, 7); }

function lift(t, vel = 1) { swoosh(t, .55 * vel); bell(t + .32, m('A6'), .16 * vel, .15, sfx, 6); }
function glint(t, vel = 1) { [[m('E7'), 0], [m('B7'), .06]].forEach(([n, d]) => bell(t + d, n, .2 * vel, (R() - .5) * .4, sfx, 9)); }
function swap(t, vel = 1) { wood(t, m('E6'), .5 * vel, -.2, sfx); wood(t + .055, m('B6'), .42 * vel, .2, sfx); }
const cueLog = [];
for (const c of sfxCues()) {
  const g = db(c.gain + 24);  // gains are relative to a −24 dB reference; overall level is set at the master
  switch (c.kind) {
    case 'key': keyClick(c.t, .5 * g, c.pitch || 1, c.pan || 0); break;
    case 'tick': tick(c.t, TICKS[c.step % TICKS.length], 1.4 * g, c.pan || 0); break;
    case 'settle': settle(c.t, .5 * g, c.pan || 0); break;
    case 'pop': pop(c.t, .18 * g, c.pitch || 1); break;
    case 'click': click(c.t, .35 * g, c.pitch || 1); break;
    case 'whoosh': whoosh(c.t, c.dir, .6 * g); break;
    case 'swoosh': swoosh(c.t, .6 * g); break;
    case 'found': found(c.t, g, c.pan || 0); break;
    case 'type': typeKey(c.t, g); break;
    case 'sent': sent(c.t, g); break;
    case 'dogbarFinished': dogbarCue(c.t, [[880.0, 0], [659.25, .12], [783.99, .24]], .55 * g); break;
    case 'dogbarNeeds': dogbarCue(c.t, [[659.25, 0], [987.77, .13]], .55 * g); break;
    case 'bloom': bloom(c.t, .25 * g); break;
    case 'logo': logo(c.t, .6 * g); break;
    case 'lift': lift(c.t, g); break;
    case 'glint': glint(c.t, g); break;
    case 'swap': swap(c.t, g); break;
    default: throw Error('unknown SFX kind ' + c.kind);
  }
  cueLog.push(c);
}

// ---------- reverb (8-line FDN, Householder feedback, damped) ----------
function fdn(inL, inR, { decay = 2.2, damp = 6500, pre = .02, mix = 1 } = {}) {
  const lens = [1031, 1327, 1523, 1801, 2063, 2357, 2671, 2999].map((x) => Math.round(x * RATE / 44100));
  const bufs = lens.map((l) => new Float32Array(l)), idx = lens.map(() => 0), lp = lens.map(() => 0);
  const g = lens.map((l) => Math.pow(10, -3 * l / RATE / decay)); const a = Math.exp(-TAU * damp / RATE); const P = Math.round(pre * RATE);
  const oL = new Float32Array(N), oR = new Float32Array(N);
  for (let i = 0; i < N; i++) { const x = (i >= P ? inL[i - P] + inR[i - P] : 0) * .5; const outs = bufs.map((b, k) => b[idx[k]]); const sum = outs.reduce((s, v) => s + v, 0) * 2 / 8;
    let l = 0, r = 0; for (let k = 0; k < 8; k++) { let y = (outs[k] - sum) * g[k] + x * (k % 2 ? .5 : -.5); lp[k] = (1 - a) * y + a * lp[k]; bufs[k][idx[k]] = lp[k]; idx[k] = (idx[k] + 1) % lens[k]; if (k % 2) r += outs[k]; else l += outs[k]; }
    oL[i] = l * .35 * mix; oR[i] = r * .35 * mix; }
  return [oL, oR];
}
// Music bus and sends.
const musicDry = stereo();
const sum = (dst, src, g = 1) => { for (let c = 0; c < 2; c++) for (let i = 0; i < N; i++) dst[c][i] += src[c][i] * g; };
const levels = { keys: 1.0, pluck: .9, bell: .8, bass: .95, drums: .72, pad: .8, air: 1.0 };
for (const [k, g] of Object.entries(levels)) sum(musicDry, bus[k], g);
const send = stereo(); sum(send, bus.keys, .45); sum(send, bus.pluck, .4); sum(send, bus.bell, .6); sum(send, bus.pad, .35); sum(send, bus.drums, .12);
const mv = fdn(send[0], send[1], { decay: 2.6, damp: 6000, pre: .025 });
const music = stereo(); sum(music, musicDry); for (let i = 0; i < N; i++) { music[0][i] += mv[0][i]; music[1][i] += mv[1][i]; }
const sv = fdn(bus.sfxVerb[0], bus.sfxVerb[1], { decay: 1.4, damp: 7500, pre: .012 });
const sfxOut = stereo(); sum(sfxOut, bus.sfx); for (let i = 0; i < N; i++) { sfxOut[0][i] += sv[0][i]; sfxOut[1][i] += sv[1][i]; }
// Gentle high-pass on the music (keeps sub energy below 30 Hz out of phone speakers) and fade-out.
for (const ch of [0, 1]) { const hp = biquadHP(28); for (let i = 0; i < N; i++) music[ch][i] = hp(music[ch][i]); }
for (const b of [music, sfxOut]) for (let c = 0; c < 2; c++) for (let i = 0; i < N; i++) { const t = i / RATE; const f = Math.max(0, Math.min(1, (DURATION - t) / 1.2)); b[c][i] *= f * f * Math.min(1, t / .01); }

// ---------- WAV I/O ----------
function wav24(L, Rr) { const n = L.length, data = Buffer.alloc(44 + n * 6); data.write('RIFF', 0); data.writeUInt32LE(36 + n * 6, 4); data.write('WAVEfmt ', 8);
  data.writeUInt32LE(16, 16); data.writeUInt16LE(1, 20); data.writeUInt16LE(2, 22); data.writeUInt32LE(RATE, 24); data.writeUInt32LE(RATE * 6, 28); data.writeUInt16LE(6, 32); data.writeUInt16LE(24, 34);
  data.write('data', 36); data.writeUInt32LE(n * 6, 40); let o = 44;
  for (let i = 0; i < n; i++) for (const x of [L[i], Rr[i]]) { let v = Math.round(Math.max(-1, Math.min(1, x)) * 8388607); if (v < 0) v += 16777216; data[o++] = v & 255; data[o++] = (v >> 8) & 255; data[o++] = (v >> 16) & 255; }
  return data; }
function measure(file) { const r = spawnSync(FFMPEG, ['-hide_banner', '-nostats', '-i', file, '-filter_complex', 'ebur128=peak=true:framelog=quiet', '-f', 'null', '-'], { encoding: 'utf8' });
  const txt = r.stderr; const I = +txt.match(/I:\s+(-?[\d.]+) LUFS/g).pop().match(/-?[\d.]+/)[0]; const tp = txt.match(/Peak:\s+(-?[\d.]+|-inf) dBFS/g); const TP = tp ? +tp.pop().match(/(-?[\d.]+|-inf)/)[0] : null;
  const LRA = +(txt.match(/LRA:\s+(-?[\d.]+) LU/g) || ['LRA: 0']).pop().match(/-?[\d.]+/)[0]; return { I, TP, LRA }; }

// True-peak limiter: 4× oversampled peak detection (windowed sinc), 3 ms lookahead, smooth release.
function tpLimit(L, Rr, ceilDb) {
  const ceil = db(ceilDb), OS = 4, taps = 32; const h = []; for (let p = 1; p < OS; p++) { const row = []; for (let k = -taps / 2; k < taps / 2; k++) { const x = k + p / OS; const w = .5 + .5 * Math.cos(Math.PI * x / (taps / 2)); row.push(Math.sin(Math.PI * x) / (Math.PI * x) * w); } h.push(row); }
  const n = L.length, peak = new Float32Array(n);
  for (const ch of [L, Rr]) for (let i = 0; i < n; i++) { let pk = Math.abs(ch[i]); for (const row of h) { let s = 0; for (let k = 0; k < taps; k++) { const j = i + k - taps / 2 + 1; if (j >= 0 && j < n) s += ch[j] * row[k]; } pk = Math.max(pk, Math.abs(s)); } peak[i] = Math.max(peak[i], pk); }
  const look = Math.round(.003 * RATE), rel = Math.exp(-1 / (.08 * RATE)); const gain = new Float32Array(n); let g = 1;
  const need = new Float32Array(n); for (let i = 0; i < n; i++) need[i] = peak[i] > ceil ? ceil / peak[i] : 1;
  // minimum over the lookahead window, then attack ramp/release
  const minWin = new Float32Array(n); for (let i = 0; i < n; i++) { let mn = 1; for (let j = i; j < Math.min(n, i + look); j++) mn = Math.min(mn, need[j]); minWin[i] = mn; }
  for (let i = 0; i < n; i++) { const target = minWin[i]; g = target < g ? target : target + (g - target) * rel; gain[i] = g; }
  let reduced = 0; for (let i = 0; i < n; i++) { L[i] *= gain[i]; Rr[i] *= gain[i]; if (gain[i] < .999) reduced++; }
  let mg = 1; for (const x of gain) mg = Math.min(mg, x);
  return { reducedSamples: reduced, minGainDb: +(20 * Math.log10(mg)).toFixed(2), gain };
}

await mkdir(out, { recursive: true });
const pre = stereo(); sum(pre, music); sum(pre, sfxOut);
await writeFile(join(out, '_premix.wav'), wav24(pre[0], pre[1]));
const m0 = measure(join(out, '_premix.wav'));
const gainDb = TARGET - m0.I;
for (const b of [music, sfxOut, pre]) for (let c = 0; c < 2; c++) for (let i = 0; i < N; i++) b[c][i] *= db(gainDb);
const lim = tpLimit(pre[0], pre[1], CEIL - .3);
// The same gain envelope on the stems, so music + sfx sum to the master and neither clips.
for (const b of [music, sfxOut]) for (let c = 0; c < 2; c++) for (let i = 0; i < N; i++) b[c][i] *= lim.gain[i];
delete lim.gain;
await writeFile(join(out, 'music.wav'), wav24(music[0], music[1]));
await writeFile(join(out, 'sfx.wav'), wav24(sfxOut[0], sfxOut[1]));
await writeFile(join(out, 'master.wav'), wav24(pre[0], pre[1]));
const m1 = measure(join(out, 'master.wav'));
console.log(JSON.stringify({ premix: m0, gainDb: +gainDb.toFixed(2), limiter: lim, master: m1, stems: { music: measure(join(out, 'music.wav')), sfx: measure(join(out, 'sfx.wav')) }, cues: cueLog.length }));
