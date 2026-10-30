// DogBar landing: Mac download CTAs driven by the same-origin release.json.
// The page ships in the honest "coming soon" state. Links only go live for a
// manifest that passes every check in verifyRelease. No dependencies.
(() => {
  "use strict";

  const FILE = (version) => `DogBar-${version}-arm64.dmg`;
  const VERSION = /^\d{1,4}\.\d{1,4}(?:\.\d{1,4})?(?:-[0-9A-Za-z]+(?:\.[0-9A-Za-z]+)*)?$/;
  const SHA256 = /^[0-9a-f]{64}$/i;
  const MACOS = /^\d{2}(?:\.\d{1,2}){0,2}$/;

  // Returns a normalized release, or null unless the manifest is complete,
  // notarized and points at this exact origin's /downloads/ .dmg over HTTPS.
  function verifyRelease(data, pageHref) {
    if (!data || typeof data !== "object" || Array.isArray(data)) return null;
    const { available, notarized, version, url, sha256, architecture, minimumMacOS } = data;
    if (available !== true || notarized !== true || architecture !== "arm64") return null;
    if (typeof version !== "string" || version.length > 40 || !VERSION.test(version)) return null;
    if (typeof sha256 !== "string" || !SHA256.test(sha256)) return null;
    if (typeof minimumMacOS !== "string" || !MACOS.test(minimumMacOS)) return null;
    if (typeof url !== "string") return null;

    let page;
    try { page = new URL(pageHref); } catch { return null; }
    if (page.protocol !== "https:") return null;
    const path = `/downloads/${FILE(version)}`;
    if (url !== path && url !== page.origin + path) return null;

    return { version, href: path, fileName: FILE(version), sha256: sha256.toLowerCase(), minimumMacOS };
  }

  // "14.0" reads as "macOS 14+", "14.2" as "macOS 14.2+".
  function macOSLabel(minimum) {
    const [major, ...rest] = minimum.split(".");
    return `macOS ${rest.every((n) => Number(n) === 0) ? major : minimum}+`;
  }

  // Switches every CTA on the page to the live download. Text only, never markup.
  function renderRelease(doc, release) {
    const meta = `Version ${release.version} · Apple Silicon · ${macOSLabel(release.minimumMacOS)}`;
    doc.querySelectorAll("[data-download]").forEach((a) => {
      a.setAttribute("href", release.href);
      a.setAttribute("download", release.fileName);
      a.setAttribute("type", "application/x-apple-diskimage");
      const tag = a.querySelector("[data-download-tag]");
      if (tag) tag.textContent = "Apple Silicon";
    });
    doc.querySelectorAll("[data-download-note]").forEach((p) => { p.textContent = meta; });
    doc.querySelectorAll("[data-download-hash]").forEach((p) => {
      const code = p.querySelector("code");
      if (code) code.textContent = release.sha256;
      p.hidden = false;
    });
    doc.documentElement.dataset.release = "live";
  }

  async function loadRelease(win) {
    if (typeof win.fetch !== "function") return null;
    const ctrl = typeof win.AbortController === "function" ? new win.AbortController() : null;
    const timer = ctrl ? setTimeout(() => ctrl.abort(), 8000) : 0;
    try {
      const res = await win.fetch("/release.json", {
        cache: "no-store", credentials: "same-origin", mode: "same-origin",
        headers: { Accept: "application/json" }, signal: ctrl ? ctrl.signal : undefined,
      });
      if (!res || !res.ok) return null;
      return verifyRelease(await res.json(), win.location.href);
    } catch {
      return null; // Network, abort or parse failure: stay on "coming soon".
    } finally {
      clearTimeout(timer);
    }
  }

  const api = { verifyRelease, macOSLabel, renderRelease, loadRelease };

  if (typeof module === "object" && module.exports) {
    module.exports = api;
  } else if (typeof window === "object" && window.document) {
    loadRelease(window).then((release) => { if (release) renderRelease(window.document, release); });
  }
})();
