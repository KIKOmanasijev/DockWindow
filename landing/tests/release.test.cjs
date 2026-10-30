// Release manifest contract and static page/art checks. Node built-ins only.
//   node --test landing/tests/
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { verifyRelease, verifyPreview, macOSLabel } = require("../release.js");

const ROOT = path.join(__dirname, "..");
const PAGE = "https://dogbar.hristijan.dev/";
const HASH = "a".repeat(64);
const valid = (over = {}) => ({
  available: true, version: "1.0.0", url: "/downloads/DogBar-1.0.0-arm64.dmg", sha256: HASH,
  architecture: "arm64", minimumMacOS: "14.0", notarized: true, ...over,
});

test("contract defaults stay unavailable", () => {
  const defaults = { available: false, version: null, url: null, sha256: null, architecture: "arm64", minimumMacOS: "14.0", notarized: false };
  assert.equal(verifyRelease(defaults, PAGE), null);
});

test("a complete notarized manifest goes live", () => {
  assert.deepEqual(verifyRelease(valid(), PAGE), {
    version: "1.0.0", href: "/downloads/DogBar-1.0.0-arm64.dmg", fileName: "DogBar-1.0.0-arm64.dmg", sha256: HASH, minimumMacOS: "14.0",
  });
  assert.ok(verifyRelease(valid({ url: "https://dogbar.hristijan.dev/downloads/DogBar-1.0.0-arm64.dmg" }), PAGE));
  assert.ok(verifyRelease(valid({ version: "1.2", url: "/downloads/DogBar-1.2-arm64.dmg" }), PAGE));
  assert.ok(verifyRelease(valid({ version: "1.0.0-beta.2", url: "/downloads/DogBar-1.0.0-beta.2-arm64.dmg" }), PAGE));
  assert.equal(verifyRelease(valid({ sha256: "AB".repeat(32) }), PAGE).sha256, "ab".repeat(32));
});

test("loose truthiness never turns the CTA on", () => {
  for (const over of [
    { available: "true" }, { available: 1 }, { notarized: "yes" }, { notarized: undefined }, { notarized: false },
  ]) assert.equal(verifyRelease(valid(over), PAGE), null, JSON.stringify(over));
});

test("version, hash and architecture are strict", () => {
  for (const over of [
    { version: "" }, { version: null }, { version: 1 }, { version: "v1.0.0" }, { version: "1" }, { version: "1.0/../x" },
    { sha256: null }, { sha256: "a".repeat(63) }, { sha256: "g".repeat(64) }, { sha256: "a".repeat(65) },
    { architecture: "x86_64" }, { architecture: "universal" }, { architecture: undefined },
    { minimumMacOS: 14 }, { minimumMacOS: "" }, { minimumMacOS: "fourteen" },
  ]) assert.equal(verifyRelease(valid(over), PAGE), null, JSON.stringify(over));
});

test("only this origin's exact /downloads/ .dmg over HTTPS is accepted", () => {
  for (const url of [
    null, "", "DogBar-1.0.0-arm64.dmg", "downloads/DogBar-1.0.0-arm64.dmg", "/downloads/DogBar-1.0.1-arm64.dmg",
    "/downloads/DogBar-1.0.0-arm64.dmg?x=1", "/downloads/DogBar-1.0.0-arm64.dmg#x", "/downloads/DogBar-1.0.0-x86_64.dmg",
    "/downloads/DogBar-1.0.0-arm64.zip", "/x/../downloads/DogBar-1.0.0-arm64.dmg", "//evil.example/downloads/DogBar-1.0.0-arm64.dmg",
    "http://dogbar.hristijan.dev/downloads/DogBar-1.0.0-arm64.dmg", "https://dockwindow.vercel.app/downloads/DogBar-1.0.0-arm64.dmg",
    "https://github.com/KIKOmanasijev/DockWindow/releases/download/v1.0.0/DogBar-1.0.0-arm64.dmg", "javascript:alert(1)",
  ]) assert.equal(verifyRelease(valid({ url }), PAGE), null, String(url));
  assert.equal(verifyRelease(valid(), "http://dogbar.hristijan.dev/"), null, "page served over plain HTTP");
  assert.equal(verifyRelease(valid(), "not a url"), null);
});

test("non-object manifests are rejected", () => {
  for (const data of [null, undefined, "", "{}", 42, true, [], [valid()]]) assert.equal(verifyRelease(data, PAGE), null);
});

test("macOS requirement label", () => {
  assert.equal(macOSLabel("14.0"), "macOS 14+");
  assert.equal(macOSLabel("14"), "macOS 14+");
  assert.equal(macOSLabel("14.2"), "macOS 14.2+");
});

test("shipped release.json follows the contract", () => {
  const data = JSON.parse(fs.readFileSync(path.join(ROOT, "release.json"), "utf8"));
  for (const key of ["available", "version", "url", "sha256", "architecture", "minimumMacOS", "notarized"]) {
    assert.ok(Object.hasOwn(data, key), `release.json has ${key}`);
  }
  // A placeholder never verifies, and a manifest marked available must fully verify.
  if (data.available === true) assert.ok(verifyRelease(data, PAGE), "available manifest passes every check");
  else assert.equal(verifyRelease(data, PAGE), null);
});

test("shipped preview manifest uses the explicit unnotarized channel", () => {
  const data = JSON.parse(fs.readFileSync(path.join(ROOT, "preview.json"), "utf8"));
  assert.equal(data.notarized, false);
  assert.equal(verifyRelease(data, PAGE), null);
  assert.ok(verifyPreview(data, PAGE));
});

test("page ships download CTAs in the unavailable state", () => {
  const html = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
  const ctas = html.match(/<a\b[^>]*\bdata-download\b[^>]*>/g) || [];
  assert.equal(ctas.length, 2, "hero and banner CTAs");
  for (const tag of ctas) {
    assert.doesNotMatch(tag, /\bhref=/, "no href until a verified manifest");
    assert.doesNotMatch(tag, /\bdownload=/);
    const described = tag.match(/aria-describedby="([^"]+)"/);
    assert.ok(described && html.includes(`id="${described[1]}"`), "status note is linked");
  }
  assert.doesNotMatch(html, /\.dmg/, "no artifact path in markup");
  assert.match(html, /Apple has not notarized this preview/, "preview status is disclosed");
  assert.match(html, /<script src="release\.js" defer><\/script>/);
});

test("no em dashes in landing sources", () => {
  for (const file of ["index.html", "styles.css", "script.js", "release.js", "README.md", "tools/build-art.mjs", "tools/png.mjs", "tools/app-icons.mjs", "tests/dom.test.cjs", "tests/release.test.cjs"]) {
    assert.doesNotMatch(fs.readFileSync(path.join(ROOT, file), "utf8"), /\u2014/, file);
  }
});

test("feature art is standalone and uses a distinct mascot pose each", () => {
  const poses = new Set();
  for (const [file, id] of [["feature-switcher.svg", "sw"], ["feature-desktops.svg", "dk"], ["feature-previews.svg", "pv"], ["feature-dock.svg", "dd"]]) {
    const svg = fs.readFileSync(path.join(ROOT, "assets", file), "utf8");
    assert.match(svg, new RegExp(`<title id="${id}-t">[^<]+</title>`), `${file} title`);
    assert.match(svg, new RegExp(`<desc id="${id}-d">[^<]+</desc>`), `${file} desc`);
    const pose = svg.match(new RegExp(`<image id="${id}-pose"[^>]*href="(data:image/png;base64,[A-Za-z0-9+/=]+)"`));
    assert.ok(pose, `${file} embeds its pose as a PNG data URI`);
    poses.add(pose[1]);
    for (const [, ref] of svg.matchAll(/\bhref="([^"]*)"/g)) {
      assert.ok(ref.startsWith("#") || ref.startsWith("data:image/"), `${file} has no external reference: ${ref.slice(0, 40)}`);
    }
    assert.doesNotMatch(svg, /-fc\d|-face"|#7A3E14/i, `${file} has no circular face crop or detached paws`);
    assert.doesNotMatch(svg, /DockWindow/, `${file} uses the DogBar brand`);
  }
  assert.equal(poses.size, 4, "four different poses");
});

test("download CTA is yellow while decorative UI uses cream and lavender", () => {
  const css = fs.readFileSync(path.join(ROOT, "styles.css"), "utf8");
  const rule = (sel) => (css.match(new RegExp(`(?:^|\\n)${sel.replace(/[.[\]()]/g, "\\$&")} \\{([^}]*)\\}`)) || [])[1] || "";
  assert.match(rule(".btn-download"), /background: var\(--yellow\)/);
  assert.match(rule(".btn-download:not([href])"), /var\(--yellow\)/, "coming soon retains the action color");
  assert.match(rule(".btn-download:not([href])"), /cursor: default/);
  assert.doesNotMatch(css, /\.btn-download:not\(\[href\]\):hover/, "no hover lift while unavailable");
  for (const selector of [".promise", ".pv-hint", ".chip-key", ".status-pill .dot", ".detail .section-title"]) {
    assert.doesNotMatch(rule(selector), /var\(--yellow\)/, selector);
  }
});

test("hero demo uses local app icons and no hosted assets", () => {
  const script = fs.readFileSync(path.join(ROOT, "script.js"), "utf8");
  const icons = [...script.matchAll(/img: "(assets\/[^"]+)"/g)].map((m) => m[1]);
  assert.ok(icons.length >= 5);
  for (const icon of icons) {
    const buf = fs.readFileSync(path.join(ROOT, icon));
    assert.equal(buf.subarray(1, 4).toString(), "PNG", icon);
    assert.ok(buf.length < 20000, `${icon} stays small`);
  }
  const html = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
  const css = fs.readFileSync(path.join(ROOT, "styles.css"), "utf8");
  const localMarkup = html.replace(/<(?:link rel="canonical"|meta property="og:[a-z:]+")[^>]*>/g, "")
    .replace(/<a\b[^>]*href="https:\/\/support\.apple\.com\/102445"[^>]*>/g, "");
  for (const [file, text] of [["index.html", localMarkup], ["styles.css", css], ["script.js", script]]) {
    assert.doesNotMatch(text, /(?:src|href)="https?:|url\(["']?https?:|@import/, `${file} loads nothing remote`);
  }
});

test("only an explicit self-signed preview manifest enables preview downloads", () => {
  const preview = valid({ version: "0.1.0-preview.1", url: "/downloads/DogBar-0.1.0-preview.1-arm64.dmg", notarized: false, channel: "preview", signing: "self-signed", build: "2" });
  assert.equal(verifyRelease(preview, PAGE), null);
  assert.equal(verifyPreview(preview, PAGE).channel, "preview");
  for (const over of [{ notarized: true }, { notarized: "false" }, { channel: "release" }, { signing: "adhoc" }, { signing: undefined }, { build: "" }, { build: 2 }, { version: "0.1.0" }, { url: "https://evil.example/test.dmg" }, { sha256: "bad" }]) {
    assert.equal(verifyPreview({ ...preview, ...over }, PAGE), null, JSON.stringify(over));
  }
  assert.equal(verifyPreview(preview, "http://dogbar.hristijan.dev"), null);
});
