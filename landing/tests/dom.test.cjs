// DOM behaviour of the landing page: download CTA states and the interactive demo.
// Needs jsdom, which this repo does not install. Point JSDOM_PATH at any local copy
// (for example node_modules/jsdom from another project); the suite skips otherwise.
//   JSDOM_PATH=/path/to/node_modules/jsdom node --test landing/tests/
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.join(__dirname, "..");
const JSDOM = (() => {
  for (const id of [process.env.JSDOM_PATH, "jsdom"].filter(Boolean)) {
    try { return require(id).JSDOM; } catch { /* try the next one */ }
  }
  return null;
})();
const skip = JSDOM ? false : "jsdom not found (set JSDOM_PATH)";

const HTML = fs.readFileSync(path.join(ROOT, "index.html"), "utf8").replace(/<script src="[^"]+" defer><\/script>/g, "");
const RELEASE_JS = fs.readFileSync(path.join(ROOT, "release.js"), "utf8");
const SCRIPT_JS = fs.readFileSync(path.join(ROOT, "script.js"), "utf8");
const MANIFEST = {
  available: true, version: "1.0.0", url: "/downloads/DogBar-1.0.0-arm64.dmg", sha256: "b".repeat(64),
  architecture: "arm64", minimumMacOS: "14.0", notarized: true,
};

// Loads the page with a stubbed fetch for /release.json, then runs both scripts.
async function page(fetchImpl, url = "https://dogbar.hristijan.dev/") {
  const dom = new JSDOM(HTML, { url, runScripts: "outside-only", pretendToBeVisual: true });
  const w = dom.window;
  w.matchMedia = () => ({ matches: false, addEventListener() {} });
  const calls = [];
  w.fetch = (input, init) => { calls.push({ input, init }); return fetchImpl(input, init); };
  w.eval(RELEASE_JS);
  w.eval(SCRIPT_JS);
  await new Promise((r) => w.setTimeout(r, 0));
  await new Promise((r) => w.setTimeout(r, 0));
  const d = w.document;
  return { w, d, calls, $: (s) => d.querySelector(s), $$: (s) => [...d.querySelectorAll(s)] };
}
const json = (body, ok = true) => async () => ({ ok, status: ok ? 200 : 404, json: async () => body });

function assertPending({ $$, d }) {
  const ctas = $$("[data-download]");
  assert.equal(ctas.length, 2);
  for (const a of ctas) {
    assert.equal(a.hasAttribute("href"), false, "no href");
    assert.equal(a.hasAttribute("download"), false);
    assert.match(a.textContent, /Download for Mac/);
    assert.match(a.textContent, /Coming soon/);
    a.focus();
    assert.notEqual(d.activeElement, a, "placeholder is not focusable");
  }
  for (const note of $$("[data-download-note]")) assert.match(note.textContent, /being prepared/);
  assert.equal(d.querySelector("[data-download-hash]").hidden, true);
  assert.equal(d.documentElement.dataset.release, undefined);
  assert.doesNotMatch(d.body.textContent, /Apple Silicon/, "architecture only shown once live");
}

test("download CTAs: placeholder release.json keeps the honest state", { skip }, async () => {
  const p = await page(json(JSON.parse(fs.readFileSync(path.join(ROOT, "release.json"), "utf8"))));
  assert.equal(p.calls.length, 1);
  assert.equal(p.calls[0].input, "/release.json");
  assert.equal(p.calls[0].init.mode, "same-origin");
  assert.equal(p.calls[0].init.cache, "no-store");
  if (JSON.parse(fs.readFileSync(path.join(ROOT, "release.json"), "utf8")).available !== true) assertPending(p);
});

test("download CTAs: fetch failures stay unavailable", { skip }, async () => {
  assertPending(await page(async () => { throw new TypeError("offline"); }));
  assertPending(await page(json(MANIFEST, false)));
  assertPending(await page(async () => ({ ok: true, json: async () => { throw new SyntaxError("bad json"); } })));
  assertPending(await page(json({ ...MANIFEST, notarized: "true" })));
  assertPending(await page(json({ ...MANIFEST, url: "https://evil.example/downloads/DogBar-1.0.0-arm64.dmg" })));
  assertPending(await page(json(MANIFEST), "http://dogbar.hristijan.dev/"));
});

test("download CTAs: a verified manifest enables both, same link", { skip }, async () => {
  const { $$, $, d } = await page(json(MANIFEST));
  const ctas = $$("[data-download]");
  assert.equal(ctas.length, 2);
  for (const a of ctas) {
    assert.equal(a.getAttribute("href"), "/downloads/DogBar-1.0.0-arm64.dmg");
    assert.equal(a.getAttribute("download"), "DogBar-1.0.0-arm64.dmg");
    a.focus();
    assert.equal(d.activeElement, a, "live link is focusable");
    assert.match(a.textContent, /Download for Mac/);
    assert.match(a.textContent, /Apple Silicon/);
    assert.doesNotMatch(a.textContent, /Coming soon/);
  }
  for (const note of $$("[data-download-note]")) assert.equal(note.textContent, "Version 1.0.0 · Apple Silicon · macOS 14+");
  assert.equal($("[data-download-hash]").hidden, false);
  assert.equal($("[data-download-hash] code").textContent, "b".repeat(64));
  assert.equal(d.documentElement.dataset.release, "live");
});

test("page structure and accessibility basics", { skip }, async () => {
  const { $, $$, d } = await page(json(null));
  const ids = $$("[id]").map((el) => el.id);
  assert.equal(new Set(ids).size, ids.length, "ids are unique");
  for (const img of $$("img")) assert.ok(img.hasAttribute("alt"), `alt on ${img.getAttribute("src")}`);
  for (const el of $$("[aria-describedby], [aria-labelledby], [aria-controls]")) {
    for (const attr of ["aria-describedby", "aria-labelledby", "aria-controls"]) {
      for (const ref of (el.getAttribute(attr) || "").split(/\s+/).filter(Boolean)) assert.ok(d.getElementById(ref), `${attr} -> #${ref}`);
    }
  }
  for (const a of $$('a[href^="#"]')) {
    const id = a.getAttribute("href").slice(1);
    assert.ok(d.getElementById(id), `anchor target #${id}`);
  }
  assert.equal($$("h1").length, 1);
  assert.equal($$("[data-demo-start]").length, 2, "Try the demo in hero and banner");
  assert.ok($$("[data-demo-start]").every((a) => a.getAttribute("href") === "#demo"));
  assert.equal($(".status-pill").getAttribute("href"), "#get");
  assert.ok($("#get [data-download]") && $(".hero [data-download]"), "CTA in hero and in the banner");
});

test("demo: switcher, previews, desktops and reset", { skip }, async () => {
  const { w, $, $$ } = await page(json(null));
  const cap = () => $("[data-caption]").textContent;
  const dockApps = () => $$(".dock-btn").map((b) => b.dataset.app + ":" + b.querySelectorAll(".dots i").length).join(",");
  const key = (k) => $("#demo").dispatchEvent(new w.KeyboardEvent("keydown", { key: k, bubbles: true }));

  assert.equal($$(".win").length, 3);
  assert.equal(dockApps(), "finder:0,dockwindow:0,safari:2,notes:1");
  assert.equal($(".win.is-front").dataset.win, "s2");
  for (const b of $$(".dock-btn")) {
    assert.equal(b.getAttribute("aria-controls"), "demo-preview");
    assert.equal(b.hasAttribute("aria-haspopup"), false);
  }

  $("[data-tab]").click();
  assert.ok(!$("[data-switcher]").hidden && $$(".tile").length === 3);
  assert.equal($$(".tile")[1].getAttribute("aria-current"), "true", cap());
  $("[data-tab]").click();
  assert.equal($$(".tile")[2].getAttribute("aria-current"), "true");
  key("ArrowRight");
  assert.equal($$(".tile")[0].getAttribute("aria-current"), "true", "arrow wraps");
  $("[data-tab]").click();
  $("[data-release]").click();
  assert.ok($("[data-switcher]").hidden && $(".win.is-front").dataset.win === "n1", cap());
  $("[data-tab]").click();
  key("Escape");
  assert.ok($("[data-switcher]").hidden && $(".win.is-front").dataset.win === "n1", "escape cancels");

  // Keyboard activation moves focus into the previews; Escape returns it to the Dock.
  const safari = $('.dock-btn[data-app="safari"]');
  safari.focus();
  safari.dispatchEvent(new w.MouseEvent("click", { bubbles: true, detail: 0 }));
  assert.ok(!$("[data-preview]").hidden && $$(".pv").length === 2);
  assert.ok($("[data-preview]").contains(w.document.activeElement), "focus moved into previews");
  key("Escape");
  assert.ok($("[data-preview]").hidden);
  assert.equal(w.document.activeElement, $('.dock-btn[data-app="safari"]'));

  $('.dock-btn[data-app="safari"]').click();
  $('[data-focus="s1"]').click();
  assert.ok($("[data-preview]").hidden && $(".win.is-front").dataset.win === "s1", cap());
  $('.dock-btn[data-app="safari"]').click();
  $('[data-close="s1"]').click();
  assert.ok(dockApps().includes("safari:1") && $$(".pv").length === 1 && !$("[data-reset]").hidden, cap());
  $('[data-close="s2"]').click();
  assert.ok(!dockApps().includes("safari") && $("[data-preview]").hidden, dockApps());
  $('.dock-btn[data-app="finder"]').click();
  assert.match($(".pv-empty").textContent, /No open windows/);

  $('[data-desk-btn="2"]').click();
  assert.equal(dockApps(), "finder:0,dockwindow:0,terminal:1,music:1");
  assert.equal($('[data-desk-btn="2"]').getAttribute("aria-pressed"), "true");
  assert.equal($("[data-desk-chip]").textContent, "Desktop 2");
  $('[data-desk-btn="1"]').click();
  assert.equal(dockApps(), "finder:0,dockwindow:0,notes:1", "desktop 1 remembers closed windows");
  $("[data-reset]").click();
  assert.equal(dockApps(), "finder:0,dockwindow:0,safari:2,notes:1");
  assert.ok($("[data-reset]").hidden);
  assert.equal($$(".reveal.in").length, $$(".reveal").length, "reveals fall back without IntersectionObserver");
});

test("demo listens for keys only inside itself", { skip }, async () => {
  const { w, $ } = await page(json(null));
  $("[data-tab]").click();
  w.document.body.dispatchEvent(new w.KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
  assert.equal($("[data-switcher]").hidden, false, "Escape outside the demo is ignored");
});
