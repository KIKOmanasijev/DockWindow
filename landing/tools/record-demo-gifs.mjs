// Records the hero demo's three chapters as GIFs for the repository README.
// Uses headless Google Chrome (a throwaway profile, nothing is installed) over the
// DevTools protocol, and ffmpeg for the GIFs. Node 22+ (built-in WebSocket).
//   node landing/tools/record-demo-gifs.mjs
// Output: .github/readme/demo-{previews,alt-tab,desktops}.gif
import { spawn, execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const PAGE = pathToFileURL(join(ROOT, "landing", "index.html")).href;
const OUT = join(ROOT, ".github", "readme");
const CHROME = process.env.CHROME_PATH || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const SCALE = 2;          // capture at 2x for crisp text, then downscale
const WIDTH = 760;        // GIF width in pixels
const FPS = 15;
// Chapter index, file name and length in ms (matches SCENES in landing/script.js).
const CHAPTERS = [[0, "demo-previews", 7800], [1, "demo-alt-tab", 5600], [2, "demo-desktops", 7000]];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const work = mkdtempSync(join(tmpdir(), "dogbar-gifs-"));
const chrome = spawn(CHROME, [
  "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${join(work, "profile")}`,
  "--hide-scrollbars", "--no-first-run", "--no-default-browser-check", "--window-size=1440,900", "about:blank",
], { stdio: "ignore" });

try {
  // Chrome writes its debugging port to DevToolsActivePort once it is listening.
  const portFile = join(work, "profile", "DevToolsActivePort");
  for (let i = 0; i < 100 && !existsSync(portFile); i++) await sleep(100);
  const port = readFileSync(portFile, "utf8").split("\n")[0];
  const target = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find((t) => t.type === "page");

  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener("open", r, { once: true }));
  let seq = 0;
  const pending = new Map();
  const listeners = new Set();
  ws.addEventListener("message", ({ data }) => {
    const msg = JSON.parse(data);
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
    else listeners.forEach((fn) => fn(msg));
  });
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++seq;
    pending.set(id, (m) => (m.error ? reject(new Error(`${method}: ${m.error.message}`)) : resolve(m.result)));
    ws.send(JSON.stringify({ id, method, params }));
  });
  const evaluate = async (expression) => (await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })).result.value;

  await send("Page.enable");
  await send("Runtime.enable");
  await send("Emulation.setDeviceMetricsOverride", { width: 1440, height: 900, deviceScaleFactor: SCALE, mobile: false });
  await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-reduced-motion", value: "no-preference" }] });
  const loaded = new Promise((r) => listeners.add((m) => m.method === "Page.loadEventFired" && r()));
  await send("Page.navigate", { url: PAGE });
  await loaded;
  await sleep(1800); // fonts, entrance animation, autoplay kick-off
  // A GIF can't be paused, so leave the play/pause button out of the picture.
  await evaluate(`document.head.insertAdjacentHTML("beforeend", "<style>.tour-toggle{visibility:hidden}</style>")`);

  for (const [chapter, name, ms] of CHAPTERS) {
    // The demo area: the screen, chapter bar and caption, with some purple around it.
    const box = await evaluate(`(() => {
      document.querySelector('[data-tour-step="${chapter}"]').click();
      const r = document.querySelector("#demo").getBoundingClientRect();
      return { x: r.x, y: r.y, width: r.width, height: r.height };
    })()`);
    const pad = 24;

    // Screencast sends a frame whenever the page repaints; keep each with its timestamp.
    const frames = [];
    const onFrame = (m) => {
      if (m.method !== "Page.screencastFrame") return;
      const file = join(work, `${name}-${String(frames.length).padStart(4, "0")}.jpg`);
      writeFileSync(file, Buffer.from(m.params.data, "base64"));
      frames.push({ file, t: m.params.metadata.timestamp });
      send("Page.screencastFrameAck", { sessionId: m.params.sessionId }).catch(() => {});
    };
    listeners.add(onFrame);
    await send("Page.startScreencast", { format: "jpeg", quality: 95, maxWidth: 1440 * SCALE, maxHeight: 900 * SCALE, everyNthFrame: 1 });
    await sleep(ms);
    await send("Page.stopScreencast");
    listeners.delete(onFrame);
    if (frames.length < 2) throw new Error(`${name}: no frames captured`);

    // Frames may arrive below the device scale; map the CSS box onto actual frame pixels.
    const frameWidth = Number(execFileSync("ffprobe", ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width",
      "-of", "csv=p=0", frames[0].file]).toString().trim());
    const k = frameWidth / 1440;
    const even = (n) => Math.floor(n / 2) * 2;
    const crop = {
      x: Math.max(0, Math.round((box.x - pad) * k)), y: Math.max(0, Math.round((box.y - pad) * k)),
      w: even((box.width + pad * 2) * k), h: even((box.height + pad * 2) * k),
    };

    // Hold each frame until the next one arrived; the last one fills the chapter.
    const start = frames[0].t;
    const list = frames.map((f, i) => {
      const next = i + 1 < frames.length ? frames[i + 1].t : start + ms / 1000;
      return `file '${f.file}'\nduration ${Math.max(0.001, next - f.t).toFixed(3)}`;
    }).join("\n") + `\nfile '${frames.at(-1).file}'\n`;
    const listFile = join(work, `${name}.txt`);
    writeFileSync(listFile, list);

    const out = join(OUT, `${name}.gif`);
    execFileSync("ffmpeg", [
      "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", listFile,
      "-vf", `crop=${crop.w}:${crop.h}:${crop.x}:${crop.y},fps=${FPS},scale=${WIDTH}:-1:flags=lanczos,` +
        "split[a][b];[a]palettegen=stats_mode=diff:max_colors=200[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle",
      "-loop", "0", out,
    ]);
    console.log(`${out}  (${frames.length} frames)`);
  }
  ws.close();
} finally {
  chrome.kill();
  await sleep(300);
  rmSync(work, { recursive: true, force: true });
}
