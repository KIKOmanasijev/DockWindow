// DogBar product film v4 exporter: picture (deterministic 60 fps headless-Chrome render of page.mjs,
// temporal 180° shutter where things move) + score (score.mjs, same clock) → muxed MP4, stems, posters, sheets.
// Same engine as v2 (landing/tools/film/export.mjs); outputs go to dist/social/product-film-v4/; v2 and v3 are untouched.
//
//   node landing/tools/film-v4/export.mjs --check 0.5,1.9,8.6   render named times to PNG only
//   node landing/tools/film-v4/export.mjs --range 4,11          render a sequence to <out>/proof-<a>-<b>.mp4
//   node landing/tools/film-v4/export.mjs                       full render
//   options: --skip-picture (reuse the rendered video), --skip-audio (reuse audio/)
// The film is composed for 16:9 only: its subject is horizontal Mac UI shown in full context.
//
// Outputs are git-ignored. Temporary frames live in a unique
// mkdtemp directory removed at the end; nothing else is cleaned up.
import { readFile, writeFile, mkdir, mkdtemp, rm, access } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createServer } from 'node:http';
import { extname } from 'node:path';
import { chromium } from '../../../licensing/node_modules/@playwright/test/index.mjs';
import { encodePNG } from '../png.mjs';
import { inflateSync } from 'node:zlib';
// Chrome screenshots are 8-bit RGB PNGs; decode to RGBA for frame blending (png.mjs reads RGBA only).
function decodeScreenshot(buf) {
  let pos = 8, width = 0, height = 0, ct = 0; const idat = [];
  while (pos < buf.length) { const len = buf.readUInt32BE(pos), type = buf.toString('latin1', pos + 4, pos + 8), d = buf.subarray(pos + 8, pos + 8 + len);
    if (type === 'IHDR') { width = d.readUInt32BE(0); height = d.readUInt32BE(4); ct = d[9]; if (d[8] !== 8 || (ct !== 2 && ct !== 6) || d[12]) throw Error('unsupported PNG'); }
    else if (type === 'IDAT') idat.push(d); else if (type === 'IEND') break; pos += 12 + len; }
  const bpp = ct === 6 ? 4 : 3, stride = width * bpp, raw = inflateSync(Buffer.concat(idat)), px = Buffer.alloc(height * stride);
  for (let y = 0; y < height; y++) { const f = raw[y * (stride + 1)], src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)), o = y * stride;
    for (let x = 0; x < stride; x++) { const a = x >= bpp ? px[o + x - bpp] : 0, b = y ? px[o - stride + x] : 0, c = x >= bpp && y ? px[o - stride + x - bpp] : 0; let v = src[x];
      if (f === 1) v += a; else if (f === 2) v += b; else if (f === 3) v += (a + b) >> 1; else if (f === 4) { const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }
      px[o + x] = v & 255; } }
  if (bpp === 4) return { width, height, data: px };
  const data = Buffer.alloc(width * height * 4); for (let i = 0, j = 0; i < px.length; i += 3, j += 4) { data[j] = px[i]; data[j + 1] = px[i + 1]; data[j + 2] = px[i + 2]; data[j + 3] = 255; }
  return { width, height, data };
}
import { buildPage } from './page.mjs';
import { FPS, RATE, DURATION, T, B, sfxCues, frameOf, sampleOf, MUSIC } from './timeline.mjs';

const here = fileURLToPath(new URL('.', import.meta.url));
const root = resolve(here, '../../..');
const out = join(root, 'dist/social/product-film-v4');
const v2 = join(root, 'dist/social/product-film-v2');
const FFMPEG = '/opt/homebrew/bin/ffmpeg';
const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i < 0 ? d : args[i + 1]; };
const has = (k) => args.includes(k);
const format = '16x9';
const [W, H] = [1920, 1080];
await mkdir(out, { recursive: true });

const exists = (p) => access(p).then(() => true, () => false);
// Native renders (DogBarCore views compiled unchanged) and the original wallpapers are reused from v2's output;
// if v2's output is missing, they are rebuilt with v2's tools.
const film = join(here, '../film');
if (!(await exists(join(out, 'native/manifest.json')))) {
  if (!(await exists(join(v2, 'native/manifest.json')))) { const r = spawnSync('sh', [join(film, 'native/render-native.sh'), join(v2, 'native')], { stdio: 'inherit' }); if (r.status) throw Error('native render failed'); }
  spawnSync('cp', ['-R', join(v2, 'native'), join(out, 'native')]);
}
if (!(await exists(join(out, 'assets/wallpaper-dusk.jpg')))) {
  if (!(await exists(join(v2, 'assets/wallpaper-dusk.jpg')))) { const r = spawnSync(process.execPath, [join(film, 'wallpaper.mjs'), join(v2, 'assets')], { stdio: 'inherit' }); if (r.status) throw Error('wallpaper render failed'); }
  spawnSync('cp', ['-R', join(v2, 'assets'), join(out, 'assets')]);
}

// ---------- Native measurements ----------
const manifest = JSON.parse(await readFile(join(out, 'native/manifest.json'), 'utf8'));
const shapes = Object.fromEntries(Object.entries(manifest).filter(([k]) => k.endsWith('.png.shape')).map(([k, v]) => [k.replace('.shape', ''), v]));
const G = manifest.geometry;
const native = { geometry: G, shapes, typingSteps: manifest.typingSteps, followUp: manifest.followUp };
if (!native.typingSteps) throw Error('native manifest lacks typing steps; re-run render-native.sh');

// A loopback-only static server: CSS masks and fonts are CORS-blocked from file:// pages.
const FONT_DIR = '/System/Applications/Utilities/Terminal.app/Contents/Resources/Fonts';
const TYPES = { '.png': 'image/png', '.jpg': 'image/jpeg', '.html': 'text/html; charset=utf-8', '.otf': 'font/otf' };
const server = createServer(async (req, res) => {
  const path = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (path === '/favicon.ico') { res.writeHead(204).end(); return; }
  const file = path.startsWith('/sfmono/') ? join(FONT_DIR, path.slice(8)) : join(out, path);
  if (!file.startsWith(out) && !file.startsWith(FONT_DIR)) { res.writeHead(403).end(); return; }
  try { const body = await readFile(file); res.writeHead(200, { 'content-type': TYPES[extname(file)] || 'application/octet-stream' }).end(body); }
  catch { res.writeHead(404).end(); }
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const origin = `http://127.0.0.1:${server.address().port}/`;
const html = buildPage({ W, H, base: origin, native });
const htmlName = `product-film-v4-${format}.html`;
const htmlPath = join(out, htmlName);
await writeFile(htmlPath, html);

// ---------- Browser ----------
const launch = () => chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
let browser = await launch();
const errors = [];
let page;
async function open() {
  page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('requestfailed', (r) => errors.push('request failed: ' + r.url()));
  page.on('response', (r) => { if (r.status() >= 400) errors.push('HTTP ' + r.status() + ' ' + r.url()); });
  await page.goto(origin + htmlName, { waitUntil: 'load' });
  if (errors.length) throw Error('page errors on load:\n' + errors.join('\n'));
  await page.evaluate(async () => { await document.fonts.ready; await Promise.all([...document.images].map((i) => i.decode().catch(() => null))); });
  const broken = await page.evaluate(() => [...document.images].filter((i) => !i.naturalWidth).map((i) => i.src));
  if (broken.length) throw Error('images failed to load: ' + broken.join(', '));
  // Warm every state once so lazily built panels decode their images before frame 0.
  for (let t = 0; t < DURATION; t += 0.5) await page.evaluate((t) => window.renderAt(t), t);
  await page.evaluate(async () => { await Promise.all([...document.images].map((i) => i.decode().catch(() => null))); });
  await page.waitForLoadState('networkidle');
  const fonts = await page.evaluate(() => ({ mono: document.fonts.check('12px SFMonoLocal'), status: [...document.fonts].map((f) => f.family + ':' + f.status) }));
  if (!fonts.mono) throw Error('SF Mono failed to load: ' + JSON.stringify(fonts));
}

try {
  await open();
  if (has('--check')) {
    const times = opt('--check', '').split(',').map(Number);
    await mkdir(join(out, 'check'), { recursive: true });
    for (const t of times) {
      const m = await page.evaluate((t) => window.metricsAt(t), t);
      await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
      const file = join(out, 'check', `${format}-t${t.toFixed(2).padStart(6, '0')}.png`);
      await page.screenshot({ path: file });
      console.log(t, JSON.stringify(m));
    }
  }

  if (has('--range')) { const [a, b] = opt('--range', '0,6').split(',').map(Number); await renderFilm(a, b); }
  else if (!has('--check')) await renderFilm();
  if (errors.length) throw Error(errors.join('\n'));
} finally {
  await browser.close();
  server.close();
}

// ---------------------------------------------------------------------------------------------
async function renderFilm(ra = 0, rb = DURATION) {
  const proof = ra !== 0 || rb !== DURATION;
  const base = proof ? join(out, `proof-${ra}-${rb}`) : join(out, `dogbar-product-film-v4-${format}`);
  const f0 = Math.round(ra * FPS), total = Math.round(rb * FPS);
  const videoOnly = base + '-video.mp4';
  const COLOR = ['-vf', 'scale=in_range=full:out_range=tv:in_color_matrix=bt601:out_color_matrix=bt709,format=yuv420p,setparams=range=tv:color_primaries=bt709:color_trc=bt709:colorspace=bt709',
    '-color_range', 'tv', '-colorspace', 'bt709', '-color_trc', 'bt709', '-color_primaries', 'bt709'];
  if (!has('--skip-picture')) {
    // PNG frames piped into x264: no lossy intermediate and no temporary frame folder.
    const enc = (await import('node:child_process')).spawn(FFMPEG, ['-hide_banner', '-loglevel', 'error', '-y', '-f', 'image2pipe', '-c:v', 'png', '-framerate', String(FPS), '-i', '-',
      ...COLOR, '-c:v', 'libx264', '-profile:v', 'high', '-preset', 'slow', '-crf', '15', '-tune', 'animation', '-g', '120', '-an', '-movflags', '+faststart', videoOnly], { stdio: ['pipe', 'inherit', 'inherit'] });
    const done = new Promise((res, rej) => enc.on('close', (c) => c ? rej(Error('x264 exit ' + c)) : res()));
    const write = (buf) => new Promise((res) => { if (enc.stdin.write(buf)) res(); else enc.stdin.once('drain', res); });
    // Render, then wait two animation frames so Chrome composites backdrop-filter (the glass panels)
    // before the screenshot. Without this, newly shown glass panels are captured unblurred.
    const draw = (t) => page.evaluate((t) => { window.renderAt(t); return new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))); }, t);
    const metrics = []; const t0 = Date.now(); let blurred = 0;
    // A crashed or closed browser (display sleep, GPU reset) is relaunched and the same frame
    // retried; the encoder keeps its pipe open, so the output stays one continuous file.
    let relaunches = 0;
    const recover = async (f, e) => {
      if (++relaunches > 5) throw e;
      console.log(`frame ${f}: browser lost (${String(e.message).split('\n')[0]}), relaunching`);
      try { await browser.close(); } catch {}
      browser = await launch(); errors.length = 0; await open();
    };
    for (let f = f0; f < total; f++) {
      try { await frame(f); } catch (e) { if (!/closed|crash|Target/i.test(String(e.message))) throw e; await recover(f, e); f--; }
    }
    async function frame(f) {
      const t = f / FPS;
      const motion = await page.evaluate((t) => window.motionAt(t), t);
      const m = await page.evaluate((t) => { const r = window.metricsAt(t); return { dock: r.dock, front: r.front, slide: +r.slide.toFixed(3), stage: +r.stage.toFixed(3), sw: r.sw, morph: r.morph, island: r.island, paper: r.paper, D: r.D }; }, t); m.motion = motion;
      // Motion blur (180° shutter) only where the image moves more than ~8 px per frame.
      const K = m.motion > 8 ? Math.min(8, Math.ceil(m.motion / 5)) : 1;
      let png;
      if (K === 1) { await draw(t); png = await page.screenshot({ type: 'png' }); }
      else {
        blurred++; let acc = null, img;
        for (let k = 0; k < K; k++) { const ts = t + ((k + .5) / K - .5) * (.5 / FPS); await draw(ts);
          img = decodeScreenshot(await page.screenshot({ type: 'png' })); if (!acc) acc = new Float32Array(img.data.length); for (let i = 0; i < acc.length; i++) acc[i] += img.data[i]; }
        const data = Buffer.alloc(acc.length); for (let i = 0; i < acc.length; i++) data[i] = Math.round(acc[i] / K);
        png = encodePNG({ width: img.width, height: img.height, data });
        await page.evaluate((t) => window.renderAt(t), t);
      }
      await write(png);
      metrics.push({ f, t: +t.toFixed(4), K, ...m, motion: +m.motion.toFixed(1) });
      if (f % 300 === 0) console.log(`frame ${f}/${total}  ${((Date.now() - t0) / 1000).toFixed(0)} s  blurred ${blurred}`);
    }
    enc.stdin.end(); await done;
    if (relaunches) console.log(`recovered from ${relaunches} browser relaunch(es)`);
    await writeFile(base + '-frames.json', JSON.stringify({ fps: FPS, frames: total - f0, blurredFrames: metrics.filter((x) => x.K > 1).length, browserRelaunches: relaunches, metrics }));
    if (errors.length) throw Error(errors.join('\n'));
    // Poster: a clean still of the switcher (no caption), rendered fresh.
    if (!proof) for (const [name, pt] of [['poster', T.tabs[3] + 0.6], ['poster-agent', T.replied + 0.6], ['poster-preview', T.lift[1] + 0.3], ['poster-stage', T.slide1 + 1.3], ['poster-end', T.endHit + 1.5]]) {
      await page.evaluate((t) => { window.renderAt(t); return new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))); }, pt);
      await page.screenshot({ path: `${base}-${name}.png` });
    }
  }
  if (proof) { console.log('wrote', videoOnly); return; }
  // ---------- audio ----------
  const audio = join(out, 'audio');
  if (!has('--skip-audio')) {
    // Licensed bed: downloaded once into the git-ignored output folder (never committed or redistributed).
    const track = join(out, 'music', `mixkit-${MUSIC.id}.mp3`);
    if (!(await exists(track))) { await mkdir(join(out, 'music'), { recursive: true }); const res = await fetch(MUSIC.url); if (!res.ok) throw Error('music download ' + res.status); await writeFile(track, Buffer.from(await res.arrayBuffer())); }
    const r = spawnSync(process.execPath, [join(here, 'score.mjs'), audio], { encoding: 'utf8', env: { ...process.env, FILM_MUSIC: track } });
    if (r.status) throw Error(r.stderr); await writeFile(join(audio, 'score-report.json'), r.stdout.trim());
  }
  const final = base + '.mp4', muted = base + '-muted.mp4';
  let r = spawnSync(FFMPEG, ['-hide_banner', '-loglevel', 'error', '-y', '-i', videoOnly, '-i', join(audio, 'master.wav'), '-map', '0:v', '-map', '1:a', '-c:v', 'copy',
    '-c:a', 'aac', '-b:a', '320k', '-ar', '48000', '-t', String(DURATION), '-movflags', '+faststart', final], { encoding: 'utf8' });
  if (r.status) throw Error(r.stderr);
  r = spawnSync(FFMPEG, ['-hide_banner', '-loglevel', 'error', '-y', '-i', videoOnly, '-c', 'copy', '-movflags', '+faststart', muted], { encoding: 'utf8' });
  if (r.status) throw Error(r.stderr);
  // ---------- cue sheet ----------
  const rows = [['time_s', 'frame_60fps', 'sample_48k', 'layer', 'event']];
  const pic = Object.entries(T).flatMap(([k, v]) => Array.isArray(v) ? v.map((x, i) => [x, `${k}[${i}]`]) : [[v, k]]);
  for (const [t, k] of pic) rows.push([t.toFixed(3), frameOf(t), sampleOf(t), 'picture', k]);
  for (const c of sfxCues()) rows.push([c.t.toFixed(3), frameOf(c.t), sampleOf(c.t), 'sfx', `${c.kind}: ${c.note || ''} (${c.gain} dB ref)`]);
  for (let bar = 1; bar <= 31; bar++) { const t = B(bar); rows.push([t.toFixed(3), frameOf(t), sampleOf(t), 'music', `bar ${bar} downbeat`]); }
  rows.sort((a, b) => (+a[0] || -1) - (+b[0] || -1));
  await writeFile(join(out, 'cue-sheet.csv'), rows.map((r) => r.map((x) => /[,"]/.test(String(x)) ? `"${String(x).replace(/"/g, '""')}"` : x).join(',')).join('\n') + '\n');
  // ---------- sheets ----------
  spawnSync(FFMPEG, ['-hide_banner', '-loglevel', 'error', '-y', '-i', final, '-vf', 'fps=1/1.5,scale=384:-1,tile=6x5:padding=6:color=black', '-frames:v', '1', '-q:v', '3', base + '-contact.jpg']);
  const dense = [['open-switcher', 0, T.release], ['release-paper-notch', T.release - .3, T.finished + .5], ['agent-reply', T.finished - .3, T.collapse + .3],
    ['dots-preview', T.toDots[0], T.lift[1]], ['lift-grow', T.lift[0], T.grow[1] + .4], ['stage-proof', T.detach[0] - .2, T.lift2[0] + .3], ['fold-lockup', T.lift2[0], DURATION]];
  for (const [name, a, b] of dense) {
    const n = 24, step = (b - a) / n;
    const rs = spawnSync(FFMPEG, ['-hide_banner', '-loglevel', 'error', '-y', '-ss', String(a), '-t', String(b - a + .01), '-i', final, '-vf', `fps=1/${step.toFixed(4)},scale=480:-1,tile=6x4:padding=4:color=black`, '-frames:v', '1', '-q:v', '3', `${base}-motion-${name}.jpg`], { encoding: 'utf8' });
    if (rs.status) throw Error('motion sheet ' + name + ': ' + rs.stderr);
  }
  console.log('wrote', final);
}
