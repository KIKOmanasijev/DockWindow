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
    assert.equal(figures.length, 4);
    for (const figure of figures) {
      assert.ok(figure.classList.contains("feature-art"));
      assert.equal(figure.matches(".music .art, .album-art"), false);
      const computed = dom.window.getComputedStyle(figure);
      assert.equal(computed.width, "100%", "fill the feature column");
      assert.equal(computed.height, "auto", "preserve the image aspect ratio");
      assert.equal(dom.window.getComputedStyle(figure.querySelector("img")).width, "100%");
    }
    const music = document.createElement("div");
    music.className = "music";
    music.innerHTML = '<i class="album-art"></i>';
    document.body.append(music);
    const cover = dom.window.getComputedStyle(music.firstElementChild);
    assert.equal(cover.width, "2.6em");
    assert.equal(cover.height, "2.6em");
  } finally { dom.window.close(); }
});
