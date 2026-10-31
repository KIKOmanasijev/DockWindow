// DogBar analytics: PostHog in cookieless mode, so nothing is stored on the visitor's
// device and no consent banner is needed. Only the production site and its Vercel
// address send events; local copies stay silent (add ?analytics=debug to log instead).
// The events and the question each one answers are listed in README.md (Analytics).
(() => {
  "use strict";

  const TOKEN = "phc_kRpqsTn5CZ2b8yMYjvwFkGMoZo2jXAPEFWhuEK6D9MkU"; // public project token, safe in page source
  const HOST = "https://eu.i.posthog.com";
  const LIVE_HOSTS = ["dogbar.hristijan.dev", "dockwindow.vercel.app"];

  // Assistants and AI search engines that send visitors, tagged so their traffic can be
  // compared with search, social and direct visits.
  const AI_SOURCES = [
    ["chatgpt", /(^|\.)(chatgpt\.com|openai\.com)$/],
    ["perplexity", /(^|\.)perplexity\.ai$/],
    ["claude", /(^|\.)claude\.ai$/],
    ["gemini", /^(gemini|bard)\.google\.com$/],
    ["copilot", /^copilot\.microsoft\.com$/],
    ["grok", /(^|\.)grok\.com$/],
    ["deepseek", /(^|\.)deepseek\.com$/],
    ["you", /(^|\.)you\.com$/],
    ["phind", /(^|\.)phind\.com$/],
  ];
  const SEARCH = /(^|\.)(google\.[a-z.]+|bing\.com|duckduckgo\.com|search\.yahoo\.com|ecosia\.org|search\.brave\.com|yandex\.[a-z]+|baidu\.com|kagi\.com|startpage\.com)$/;
  const SOCIAL = /(^|\.)(x\.com|twitter\.com|t\.co|reddit\.com|news\.ycombinator\.com|linkedin\.com|lnkd\.in|facebook\.com|threads\.net|bsky\.app|youtube\.com|producthunt\.com|github\.com)$/;

  // One label per visit: utm_source first (ChatGPT adds utm_source=chatgpt.com to its
  // links, and campaign links carry their own), then the referrer's host.
  function classifySource(referrer, search, ownHost) {
    const utm = (new URLSearchParams(search).get("utm_source") || "").trim().toLowerCase();
    let host = "";
    try { host = referrer ? new URL(referrer).hostname.toLowerCase() : ""; } catch { host = ""; }
    const bare = host.replace(/^www\./, "");
    for (const [name, re] of AI_SOURCES) {
      if (re.test(host) || re.test(utm)) return { type: "ai", name };
    }
    if (utm) return { type: "campaign", name: utm };
    if (!host || host === ownHost) return { type: "direct", name: "direct" };
    if (SEARCH.test(host)) return { type: "search", name: bare };
    if (SOCIAL.test(host)) return { type: "social", name: bare };
    return { type: "referral", name: bare };
  }

  if (typeof module === "object" && module.exports) {
    module.exports = { classifySource };
    return;
  }

  const live = LIVE_HOSTS.includes(location.hostname);
  const debug = /[?&]analytics=debug\b/.test(location.search);
  const source = classifySource(document.referrer, location.search, location.hostname);

  if (live) {
    // Official PostHog loader snippet.
    !function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.crossOrigin="anonymous",p.async=!0,p.src=s.api_host.replace(".i.posthog.com","-assets.i.posthog.com")+"/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],Object.defineProperty(u,"toString",{configurable:!0,enumerable:!0,writable:!0,value:function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e}}),Object.defineProperty(u.people,"toString",{configurable:!0,enumerable:!0,writable:!0,value:function(){return u.toString(1)+".people (stub)"}}),o="init capture register register_once register_for_session unregister unregister_for_session getFeatureFlag getFeatureFlagResult isFeatureEnabled reloadFeatureFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSessionId getSurveys getActiveMatchingSurveys renderSurvey canRenderSurvey getNextSurveyStep identify setPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags reset get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException loadToolbar get_property getSessionProperty createPersonProfile opt_in_capturing opt_out_capturing has_opted_in_capturing has_opted_out_capturing clear_opt_in_out_capturing debug".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);

    window.posthog.init(TOKEN, {
      api_host: HOST,
      ui_host: "https://eu.posthog.com",
      defaults: "2026-08-30",
      cookieless_mode: "always", // requires "Enable cookieless tracking" in project settings (on)
      person_profiles: "never",
      autocapture: true, // clicks feed heatmaps and after-the-fact questions
      capture_heatmaps: true,
      capture_dead_clicks: true,
      capture_performance: { web_vitals: true },
      disable_session_recording: true, // not available without cookies
      disable_surveys: true,
      // Every event, including page views, carries where the visit came from.
      before_send: (event) => {
        if (event) Object.assign(event.properties, { traffic_type: source.type, traffic_source: source.name });
        return event;
      },
      debug,
    });
  }

  function track(name, props = {}) {
    // Which download was on offer when this happened: release, preview or unavailable.
    const all = { release_channel: document.documentElement.dataset.release || "unavailable", ...props };
    if (live) window.posthog.capture(name, all);
    else if (debug) console.info("[analytics]", name, { traffic_type: source.type, traffic_source: source.name, ...all });
  }
  // Once per page view per key, for "did they ever see or do X" questions.
  const seen = new Set();
  function trackOnce(key, name, props) {
    if (seen.has(key)) return;
    seen.add(key);
    track(name, props);
  }
  window.dogbarTrack = track;
  window.dogbarTrackOnce = trackOnce;

  // ---------- Clicks ----------
  const where = (el) => (el.closest(".nav") ? "nav" : el.closest(".hero") ? "hero" : el.closest(".get") ? "get" : el.closest(".footer") ? "footer" : "page");

  document.addEventListener("click", (e) => {
    const el = e.target instanceof Element ? e.target : null;
    if (!el) return;

    const dl = el.closest("[data-download]");
    if (dl) {
      // A click on the "Coming soon" button counts too: it measures demand before a release.
      const available = dl.hasAttribute("href");
      const version = available ? (dl.getAttribute("download") || "").replace(/^DogBar-|-arm64\.dmg$/g, "") : null;
      track("download_clicked", { location: where(dl), available, version });
      return;
    }
    if (el.closest("[data-demo-start]")) { track("watch_demo_clicked", { location: where(el) }); return; }

    const link = el.closest("a[href]");
    if (!link) return;
    const href = link.getAttribute("href");
    if (href.startsWith("#")) {
      if (link.closest(".nav, .footer")) track("nav_clicked", { target: href.slice(1) || "top", location: where(link) });
      return;
    }
    let url;
    try { url = new URL(href, location.href); } catch { return; }
    if (url.hostname !== location.hostname) track("outbound_link_clicked", { url: url.href, location: where(link) });
  });

  // ---------- Questions and intent ----------
  // Which FAQ answers people open, and whether they need help installing the preview.
  document.querySelectorAll("#faq details, [data-preview-help]").forEach((d) => {
    d.addEventListener("toggle", () => {
      if (!d.open) return;
      if (d.matches("[data-preview-help]")) { trackOnce("install-help", "install_help_opened", {}); return; }
      const question = d.querySelector("summary")?.textContent.trim() || "";
      trackOnce(`faq:${question}`, "faq_opened", { question });
    });
  });
  // Copying the checksum signals a careful, high-intent visitor.
  document.querySelectorAll("[data-download-hash]").forEach((el) => {
    el.addEventListener("copy", () => trackOnce("checksum", "checksum_copied", {}));
  });

  // ---------- How far down the story people get ----------
  // One event per section, the first time its top passes 60% of the screen height
  // (a ratio threshold would never fire for sections taller than the screen).
  const SECTIONS = [
    ["demo", "#demo"], ["switcher_compare", ".feature-wide"], ["features", ".feature-grid"],
    ["comparison", ".modes"], ["get", "#get"], ["faq", "#faq"],
  ];
  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        const section = entry.target.dataset.trackSection;
        trackOnce(`section:${section}`, "section_viewed", { section, order: SECTIONS.findIndex(([n]) => n === section) + 1 });
        io.unobserve(entry.target);
      }
    }, { rootMargin: "0px 0px -40% 0px" });
    for (const [name, sel] of SECTIONS) {
      const el = document.querySelector(sel);
      if (el) { el.dataset.trackSection = name; io.observe(el); }
    }
  }
})();
