// CSS cascade regressions; jsdom checks styles, not browser pixel layout.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const ROOT = path.join(__dirname, "..");
const JSDOM = (() => {
  for (const id of [process.env.JSDOM_PATH, "jsdom"].filter(Boolean)) {
    try { return require(id).JSDOM; } catch {}
  }
  return null;
})();

test("feature illustrations never inherit album-cover dimensions", { skip: !JSDOM && "jsdom not found" }, () => {
  const dom = new JSDOM(fs.readFileSync(path.join(ROOT, "index.html"), "utf8"));
  try {
    const { document } = dom.window;
    const style = document.createElement("style");
    style.textContent = fs.readFileSync(path.join(ROOT, "styles.css"), "utf8");
    document.head.append(style);
    const figures = [...document.querySelectorAll(".feature figure")];
    assert.equal(figures.length, 5);
    for (const figure of figures) {
      assert.ok(figure.classList.contains("feature-art"));
      assert.equal(figure.matches(".music .art, .album-art"), false);
      assert.equal(figure.querySelectorAll(".album-art, .art").length, 0);
      const computed = dom.window.getComputedStyle(figure);
      assert.equal(computed.width, "100%", "fill the feature column");
      assert.equal(computed.height, "auto", "grow with the visual inside");
    }
    // App icons inside the feature visuals keep their own fixed sizes.
    const icon = document.querySelector(".feature-grid .fx-dock-app img");
    assert.equal(dom.window.getComputedStyle(icon).width, "34px");
    // Cmd+Tab icons scale by width and keep their square shape instead of stretching.
    const appIcon = dom.window.getComputedStyle(document.querySelector(".fx-app img"));
    assert.equal(appIcon.width, "100%");
    assert.equal(appIcon.height, "auto");
    assert.equal(appIcon.aspectRatio, "1");
    const music = document.createElement("div");
    music.className = "music";
    music.innerHTML = '<i class="album-art"></i>';
    document.body.append(music);
    const cover = dom.window.getComputedStyle(music.firstElementChild);
    assert.equal(cover.width, "2.6em");
    assert.equal(cover.height, "2.6em");
  } finally { dom.window.close(); }
});

test("the semantic [hidden] rule stays last, after every component and media rule", () => {
  const css = fs.readFileSync(path.join(ROOT, "styles.css"), "utf8").trim();
  assert.match(css, /\[hidden\] \{ display: none !important; \}$/);
});

test("closed preview, switcher and HUD shells stay invisible", { skip: !JSDOM && "jsdom not found" }, () => {
  const dom = new JSDOM(fs.readFileSync(path.join(ROOT, "index.html"), "utf8"), {
    url: "https://dogbar.hristijan.dev/", runScripts: "outside-only", pretendToBeVisual: true,
  });
  try {
    const w = dom.window;
    const d = w.document;
    const style = d.createElement("style");
    style.textContent = fs.readFileSync(path.join(ROOT, "styles.css"), "utf8");
    d.head.append(style);
    w.matchMedia = () => ({ matches: false, addEventListener() {} });
    const $ = (s) => d.querySelector(s);
    const display = (selector) => w.getComputedStyle($(selector)).display;

    // Before the script runs every overlay is closed and paints nothing.
    for (const sel of ["[data-preview]", "[data-switcher]", "[data-keys]", "[data-swipe]"]) {
      assert.equal($(sel).hidden, true, sel);
      assert.equal(display(sel), "none", `${sel}: no empty bubble, overlay or pointer`);
    }
    w.eval(fs.readFileSync(path.join(ROOT, "script.js"), "utf8"));
    assert.equal(display("[data-preview]"), "flex", "the opening frame shows Safari's previews");
    assert.equal(display("[data-switcher]"), "none");
    assert.equal(display("[data-keys]"), "none");
    assert.equal(display("[data-swipe]"), "none");
    assert.equal(display("[data-preview-help]"), "none");
    assert.equal(w.getComputedStyle($("[data-demo]")).pointerEvents, "none", "the screen ignores the mouse");
  } finally { dom.window.close(); }
});
