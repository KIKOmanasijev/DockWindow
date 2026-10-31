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
async function page(fetchImpl, url = "https://dogbar.hristijan.dev/", { reduceMotion = false, inView = false } = {}) {
  const dom = new JSDOM(HTML, { url, runScripts: "outside-only", pretendToBeVisual: true });
  const w = dom.window;
  w.matchMedia = () => ({ matches: reduceMotion, addEventListener() {} });
  // Optional stand-in for IntersectionObserver that reports everything as on screen.
  if (inView) {
    w.IntersectionObserver = class {
      constructor(cb) { this.cb = cb; }
      observe(el) { this.cb([{ target: el, isIntersecting: true }], this); }
      unobserve() {}
    };
  }
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
  assert.equal(p.calls.length, 2);
  assert.equal(p.calls[0].input, "/release.json");
  assert.equal(p.calls[1].input, "/preview.json");
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
  assert.equal($(".nav-cta").getAttribute("href"), "#get");
  assert.ok($("#get [data-download]") && $(".hero [data-download]"), "CTA in hero and in the banner");
});

test("hero leads with a benefit, and the dog stays a brand mark", { skip }, async () => {
  const { $, $$ } = await page(json(null));
  const h1 = $("h1");
  assert.ok(h1.closest(".hero"), "the headline is in the hero");
  assert.notEqual(h1.textContent.trim(), "DogBar", "the product name is not the headline");
  assert.match(h1.textContent, /window/i, "the headline names the benefit");
  assert.ok($(".nav .brand").textContent.includes("DogBar"), "the brand lives in the nav");
  assert.equal($$(".hero img").filter((img) => !img.closest(".nav, .mac")).length, 0, "no mascot art around the demo");
  for (const img of $$("img")) assert.doesNotMatch(img.getAttribute("src"), /mascot|feature-[a-z]+\.svg/, img.getAttribute("src"));
});

test("feature visuals are labelled pictures that never collide with demo hooks", { skip }, async () => {
  const { $$ } = await page(json(null));
  const figures = $$("#features figure.feature-art");
  assert.equal(figures.length, 4);
  for (const fig of figures) {
    assert.equal(fig.getAttribute("role"), "img");
    assert.ok((fig.getAttribute("aria-label") || "").length > 40, "each visual has a text equivalent");
    assert.equal(fig.querySelectorAll("a, button, input, [tabindex]").length, 0, "pictures hold no controls");
  }
  assert.equal($$("#features .win, #features .dock-btn, #features .tile, #features .pv, #features .pv-name, #features [data-app]").length, 0,
    "demo selectors stay scoped to the demo");
  // The before/after names both Safari windows, the core benefit.
  assert.deepEqual($$(".compare .is-dogbar .fx-name").map((n) => n.textContent), ["Lisbon day plan", "Hotel booking", "#lisbon-trip", "Packing list"]);
  assert.equal($$(".compare .fx-switch-apps .fx-app").length, 3, "Cmd+Tab shows one icon per app");
  assert.ok($$("#faq details summary").length >= 3, "short FAQ");

  // Each DogBar tile carries its app icon, so two tiles visibly come from Safari.
  const badges = $$(".compare .is-dogbar .fx-tile").map((t) => t.querySelector(".fx-badge")?.getAttribute("src"));
  assert.deepEqual(badges, ["assets/apps/safari.png", "assets/apps/safari.png", "assets/apps/slack.png", "assets/apps/notes.png"]);
  // Dots match the scenario: Safari has two windows, Slack one, Finder none.
  const dots = (app) => $$(`#features .fx-pop + .fx-dock img[src$="${app}.png"] + .fx-dots i`).length;
  assert.deepEqual([dots("finder"), dots("safari"), dots("slack")], [0, 2, 1]);
});

test("hero copy sells benefits without shortcut jargon", { skip }, async () => {
  const { $, $$ } = await page(json(null));
  assert.doesNotMatch($(".lede").textContent, /Option|Cmd|Command|Tab\b|⌥|⌘/);
  assert.equal($$(".scribbles li").length, 4, "short handwritten benefit list");
  for (const li of $$(".scribbles li")) assert.doesNotMatch(li.textContent, /Option|Cmd|Tab\b/);
});

test("comparison table marks what macOS lacks and DogBar adds", { skip }, async () => {
  const { $, $$ } = await page(json(null));
  const head = $$(".vs thead th").map((th) => th.textContent.trim());
  assert.deepEqual(head.slice(1), ["macOS", "DogBar"]);
  const rows = $$(".vs tbody tr");
  assert.equal(rows.length, 5);
  assert.equal(rows[0].querySelector("th").textContent, "Individual window previews in the keyboard switcher");
  assert.equal(rows[4].querySelector("th").textContent, "Close or minimize from Dock hover previews");
  for (const row of rows) {
    assert.equal(row.querySelector("th").getAttribute("scope"), "row");
    const [mac, dogbar] = [...row.querySelectorAll("td")];
    assert.equal(mac.textContent.trim(), "No");
    assert.ok(mac.querySelector('use[href="#i-no"]'));
    assert.equal(dogbar.textContent.trim(), "Yes");
    assert.ok(dogbar.querySelector('use[href="#i-yes"]'));
  }
  assert.match($(".native-note").textContent, /Native Dock mode/, "keeping Apple's Dock is still explained");
});

test("CTA hierarchy: download is the primary button, the demo a secondary link", { skip }, async () => {
  const { $$ } = await page(json(null));
  for (const scope of [".hero", "#get"]) {
    const actions = $$(`${scope} .actions > *`);
    assert.equal(actions.length, 2, scope);
    assert.ok(actions[0].matches(".btn.btn-download[data-download]"), `${scope}: download comes first`);
    assert.ok(actions[1].matches(".btn-link[data-demo-start]:not(.btn)"), `${scope}: demo is a plain link`);
  }
});

test("demo opens on an everyday trip example: two Safari windows, picked independently", { skip }, async () => {
  const { w, $, $$ } = await page(json(null));
  const cap = () => $("[data-caption]").textContent;
  const dockApps = () => $$(".dock-btn").map((b) => b.dataset.app + ":" + b.querySelectorAll(".dots i").length).join(",");

  // Desktop 1: Safari (day plan + hotel booking), Slack with friends and a Notes packing list, all fictional.
  assert.equal($$(".win").length, 4);
  assert.equal(dockApps(), "finder:0,dockwindow:0,safari:2,slack:1,notes:1");
  assert.equal($(".win.is-front").dataset.win, "s1");
  assert.equal($("[data-front-app]").textContent, "Safari");
  assert.match($('[data-win="s1"]').textContent, /wanderly\.travel[\s\S]*A weekend in Lisbon/);
  assert.match($('[data-win="s2"]').textContent, /casaluz-stays\.travel[\s\S]*Confirm your stay[\s\S]*Book 2 nights/);
  assert.match($('[data-win="k1"]').textContent, /# lisbon-trip[\s\S]*Found a hotel near Alfama/);
  assert.match($('[data-win="n1"]').textContent, /Packing list[\s\S]*Passport/);
  assert.doesNotMatch($("[data-desk]").textContent, /\bPR\b|staging|deploy|review|diff/i, "no developer jargon in the hero");

  // Real app icons, served locally.
  for (const img of $$(".dock-btn img")) assert.match(img.getAttribute("src"), /^assets\/(apps\/[a-z]+|dog-96)\.png$/);

  // The benefit is visible before any interaction: Safari's previews are open.
  const pv = $("[data-preview]");
  assert.equal(pv.hidden, false);
  assert.equal(pv.getAttribute("aria-label"), "Safari window previews");
  assert.ok(pv.classList.contains("is-intro"));
  assert.deepEqual($$(".pv-name").map((n) => n.textContent), ["Lisbon day plan", "Hotel booking"]);
  assert.match($(".pv-hint").textContent, /2 Safari windows/);
  assert.ok($('.pv.is-pick [data-focus="s2"]'), "the hotel booking is the suggested pick");
  assert.equal($('.dock-btn[data-app="safari"]').getAttribute("aria-expanded"), "true");
  assert.match(cap(), /two windows/);
  assert.equal(w.document.activeElement, w.document.body, "the example does not steal focus");

  // The example survives clicks elsewhere on the page.
  w.document.body.dispatchEvent(new w.MouseEvent("pointerdown", { bubbles: true }));
  assert.equal(pv.hidden, false);

  // Each preview maps to its own window.
  $('[data-focus="s2"]').dispatchEvent(new w.FocusEvent("focusin", { bubbles: true }));
  assert.deepEqual($$(".win.peek").map((el) => el.dataset.win), ["s2"]);

  // Picking the booking brings forward only that window; the day plan stays open behind.
  $('[data-focus="s2"]').click();
  assert.ok(pv.hidden);
  assert.equal($(".win.is-front").dataset.win, "s2");
  assert.ok($('[data-win="s1"]') && !$('[data-win="s1"]').classList.contains("is-front"));
  assert.equal($$(".win.peek").length, 0);
  assert.match(cap(), /Hotel booking.*in front\. The other Safari window stayed where it was\./);
  assert.equal(w.document.activeElement, $('.dock-btn[data-app="safari"]'));
});

test("demo: switcher, previews, desktops and reset", { skip }, async () => {
  const { w, $, $$ } = await page(json(null));
  const cap = () => $("[data-caption]").textContent;
  const dockApps = () => $$(".dock-btn").map((b) => b.dataset.app + ":" + b.querySelectorAll(".dots i").length).join(",");
  const key = (k) => $("#demo").dispatchEvent(new w.KeyboardEvent("keydown", { key: k, bubbles: true }));
  const sel = () => $('.tile[aria-current="true"]').dataset.tile;
  for (const b of $$(".dock-btn")) {
    assert.equal(b.getAttribute("aria-controls"), "demo-preview");
    assert.equal(b.hasAttribute("aria-haspopup"), false);
  }

  // Option+Tab: one tile per window, both Safari windows included. Opening it ends the example.
  $("[data-tab]").click();
  assert.ok($("[data-preview]").hidden);
  assert.ok(!$("[data-switcher]").hidden && $$(".tile").length === 4);
  assert.equal(sel(), "s2", cap());
  assert.match(cap(), /4 tiles.*Safari, “Hotel booking”/);
  $("[data-tab]").click();
  assert.equal(sel(), "k1");
  key("ArrowRight");
  key("ArrowRight");
  assert.equal(sel(), "s1", "arrows wrap");
  key("ArrowLeft");
  $("[data-release]").click();
  assert.ok($("[data-switcher]").hidden && $(".win.is-front").dataset.win === "n1", cap());
  $("[data-tab]").click();
  key("Escape");
  assert.ok($("[data-switcher]").hidden && $(".win.is-front").dataset.win === "n1", "escape cancels");

  // Keyboard activation moves focus into the previews; Escape returns it to the Dock.
  const safari = $('.dock-btn[data-app="safari"]');
  safari.focus();
  safari.dispatchEvent(new w.MouseEvent("click", { bubbles: true, detail: 0 }));
  assert.ok(!$("[data-preview]").hidden && $$(".pv").length === 2 && !$(".pv-hint"));
  assert.ok($("[data-preview]").contains(w.document.activeElement), "focus moved into previews");
  key("Escape");
  assert.ok($("[data-preview]").hidden);
  assert.equal(w.document.activeElement, $('.dock-btn[data-app="safari"]'));

  // A regular preview closes on an outside click, unlike the opening example.
  $('.dock-btn[data-app="slack"]').click();
  assert.equal($$(".pv").length, 1);
  w.document.body.dispatchEvent(new w.MouseEvent("pointerdown", { bubbles: true }));
  assert.ok($("[data-preview]").hidden);

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

  // Desktop 2 has its own Dock; Safari shows only the window that lives there.
  $('[data-desk-btn="2"]').click();
  assert.equal(dockApps(), "finder:0,dockwindow:0,safari:1,music:1");
  assert.equal($('[data-desk-btn="2"]').getAttribute("aria-pressed"), "true");
  assert.deepEqual($$("[data-space].on").map((el) => el.dataset.space), ["2"], "menu bar shows Desktop 2");
  assert.match(cap(), /Safari \(1 dot\), Music \(1 dot\)/);
  assert.match($('[data-win="s3"]').textContent, /Sunday hike/);
  assert.equal($$('[data-win="m1"] .album-art').length, 3, "album covers use their own class");
  assert.equal($$("[data-desk] .art").length, 0, "no clash with the feature figures' .art");
  $('[data-desk-btn="1"]').click();
  assert.equal(dockApps(), "finder:0,dockwindow:0,slack:1,notes:1", "desktop 1 remembers closed windows");

  // Reset restores the scenario and the opening example, from either desktop.
  $('[data-desk-btn="2"]').click();
  $("[data-reset]").click();
  assert.equal($('[data-desk-btn="1"]').getAttribute("aria-pressed"), "true");
  assert.equal(dockApps(), "finder:0,dockwindow:0,safari:2,slack:1,notes:1");
  assert.ok($("[data-reset]").hidden);
  assert.ok(!$("[data-preview]").hidden && $(".pv-hint"));
  assert.equal(w.document.activeElement, $("[data-tab]"));
  assert.equal($$(".reveal.in").length, $$(".reveal").length, "reveals fall back without IntersectionObserver");
});

test("demo listens for keys only inside itself", { skip }, async () => {
  const { w, $ } = await page(json(null));
  $("[data-tab]").click();
  w.document.body.dispatchEvent(new w.KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
  assert.equal($("[data-switcher]").hidden, false, "Escape outside the demo is ignored");
});

test("explicit preview enables both downloads with honest status and installation help", { skip }, async () => {
  const preview = { ...MANIFEST, version: "0.1.0-preview.1", url: "/downloads/DogBar-0.1.0-preview.1-arm64.dmg", notarized: false, channel: "preview", signing: "self-signed", build: "2" };
  const p = await page(async (input) => ({ ok: true, json: async () => input === "/preview.json" ? preview : null }));
  assert.deepEqual(p.calls.map((c) => c.input), ["/release.json", "/preview.json"]);
  assert.equal(p.d.documentElement.dataset.release, "preview");
  for (const a of p.$$("[data-download]")) {
    assert.equal(a.getAttribute("href"), preview.url);
    assert.equal(a.getAttribute("download"), "DogBar-0.1.0-preview.1-arm64.dmg");
    assert.match(a.textContent, /Preview/);
    assert.doesNotMatch(a.textContent, /Coming soon/);
  }
  for (const note of p.$$("[data-download-note]")) assert.match(note.textContent, /Unnotarized preview/);
  assert.equal(p.$("[data-preview-help]").hidden, false);
  assert.equal(p.$("[data-download-hash] code").textContent, preview.sha256);
  const production = await page(json(MANIFEST));
  assert.equal(production.calls.length, 1, "notarized release takes priority");
  assert.equal(production.$("[data-preview-help]").hidden, true);
});

test("hovering a windowless Dock app does not open an empty preview", { skip }, async () => {
  const p = await page(json(null));
  const e = new p.w.Event("pointerover", { bubbles: true });
  Object.defineProperty(e, "pointerType", { value: "mouse" });
  p.$('.dock-btn[data-app="finder"]').dispatchEvent(e);
  await new Promise((resolve) => p.w.setTimeout(resolve, 160));
  assert.equal(p.$("[data-preview]").hidden, true);
  assert.equal(p.$(".pv-empty"), null);
});

const pause = (w, ms) => new Promise((r) => w.setTimeout(r, ms));

test("guided tour autoplays on screen, stays quiet for screen readers and never takes focus", { skip }, async () => {
  const p = await page(json(null), undefined, { inView: true });
  const { w, $, $$ } = p;
  assert.equal($("#demo").dataset.tour, "stopped", "waits a moment before starting");
  await pause(w, 760);
  assert.equal($("#demo").dataset.tour, "playing");
  assert.equal($("[data-caption]").getAttribute("aria-live"), "off", "no running commentary");
  assert.equal($("[data-tour-label]").textContent, "Pause tour");
  assert.ok($("[data-cursor]").classList.contains("is-on"), "the pointer is visible");
  assert.ok($('[data-tour-step="0"]').classList.contains("is-active"));
  assert.equal($('[data-tour-step="0"]').getAttribute("aria-current"), "step");
  assert.equal(w.document.activeElement, w.document.body, "the tour does not move focus");
  assert.equal($$(".reveal.in").length, $$(".reveal").length, "reveals still run");

  // Using the demo hands it over for good: camera, pointer and announcements reset.
  $('.dock-btn[data-app="slack"]').dispatchEvent(new w.MouseEvent("pointerdown", { bubbles: true }));
  assert.equal($("#demo").dataset.tour, "stopped");
  assert.equal($("[data-cam]").style.transform, "");
  assert.ok(!$("[data-cursor]").classList.contains("is-on"));
  assert.ok($("[data-keys]").hidden);
  assert.equal($("[data-caption]").getAttribute("aria-live"), "polite");
  assert.equal($("[data-tour-label]").textContent, "Play tour");
  await pause(w, 1200);
  assert.equal($("#demo").dataset.tour, "stopped", "pending tour steps do not resume");
});

test("tour steps can be chosen and the tour paused; reduced motion never autoplays", { skip }, async () => {
  const still = await page(json(null), undefined, { inView: true, reduceMotion: true });
  await pause(still.w, 760);
  assert.equal(still.$("#demo").dataset.tour, "stopped");
  assert.equal(still.$("[data-preview]").hidden, false, "the static opening example remains");

  const { w, $ } = still;
  $('[data-tour-step="2"]').click();
  assert.equal($("#demo").dataset.tour, "playing", "a person can still start it");
  assert.ok($('[data-tour-step="2"]').classList.contains("is-active"));
  assert.ok($('[data-tour-step="0"]').classList.contains("is-done"));
  await pause(w, 1700);
  assert.deepEqual([...w.document.querySelectorAll("[data-space].on")].map((el) => el.dataset.space), ["2"], "the pointer switched desktops");
  assert.match($("[data-cam]").style.transform, /scale\(1\.8\)/, "zoomed into the Dock");
  assert.equal($$dockApps(w), "finder:0,dockwindow:0,safari:1,music:1", "the Dock changed with the desktop");
  $("[data-tour-toggle]").click();
  assert.equal($("#demo").dataset.tour, "stopped");
  assert.equal($("[data-cam]").style.transform, "");
});

function $$dockApps(w) {
  return [...w.document.querySelectorAll(".dock-btn")].map((b) => b.dataset.app + ":" + b.querySelectorAll(".dots i").length).join(",");
}
