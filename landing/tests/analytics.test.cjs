// Analytics: traffic-source rules, privacy settings and the files AI crawlers read.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.join(__dirname, "..");
const read = (file) => fs.readFileSync(path.join(ROOT, file), "utf8");
const { classifySource } = require("../analytics.js");
const HOST = "dogbar.hristijan.dev";

test("AI assistants are recognised by referrer or utm_source", () => {
  assert.deepEqual(classifySource("https://chatgpt.com/", "", HOST), { type: "ai", name: "chatgpt" });
  assert.deepEqual(classifySource("", "?utm_source=chatgpt.com", HOST), { type: "ai", name: "chatgpt" });
  assert.deepEqual(classifySource("https://www.perplexity.ai/search?q=x", "", HOST), { type: "ai", name: "perplexity" });
  assert.deepEqual(classifySource("https://claude.ai/chat/1", "", HOST), { type: "ai", name: "claude" });
  assert.deepEqual(classifySource("https://gemini.google.com/app", "", HOST), { type: "ai", name: "gemini" });
  assert.deepEqual(classifySource("https://copilot.microsoft.com/", "", HOST), { type: "ai", name: "copilot" });
});

test("search, social, campaigns, referrals and direct visits", () => {
  assert.deepEqual(classifySource("https://www.google.com/", "", HOST), { type: "search", name: "google.com" });
  assert.deepEqual(classifySource("https://www.google.co.uk/", "", HOST), { type: "search", name: "google.co.uk" });
  assert.deepEqual(classifySource("https://duckduckgo.com/", "", HOST), { type: "search", name: "duckduckgo.com" });
  assert.deepEqual(classifySource("https://news.ycombinator.com/item?id=1", "", HOST), { type: "social", name: "news.ycombinator.com" });
  assert.deepEqual(classifySource("https://old.reddit.com/r/macapps", "", HOST), { type: "social", name: "old.reddit.com" });
  assert.deepEqual(classifySource("https://x.com/", "?utm_source=Newsletter", HOST), { type: "campaign", name: "newsletter" });
  assert.deepEqual(classifySource("https://someblog.dev/post", "", HOST), { type: "referral", name: "someblog.dev" });
  assert.deepEqual(classifySource("", "", HOST), { type: "direct", name: "direct" });
  assert.deepEqual(classifySource(`https://${HOST}/#faq`, "", HOST), { type: "direct", name: "direct" });
  assert.deepEqual(classifySource("not a url", "", HOST), { type: "direct", name: "direct" });
});

test("tracking stays cookieless, replay-free and limited to the live site", () => {
  const js = read("analytics.js");
  assert.match(js, /cookieless_mode: "always"/);
  assert.match(js, /person_profiles: "never"/);
  assert.match(js, /disable_session_recording: true/);
  assert.match(js, /const LIVE_HOSTS = \["dogbar\.hristijan\.dev", "dockwindow\.vercel\.app"\]/);
  assert.match(js, /const HOST = "https:\/\/eu\.i\.posthog\.com"/, "EU data residency");
  assert.doesNotMatch(js, /identify\(|localStorage|document\.cookie/);
});

test("analytics loads before the page scripts that report to it", () => {
  const html = read("index.html");
  const order = ["analytics.js", "release.js", "script.js"].map((f) => html.indexOf(`<script src="${f}" defer></script>`));
  assert.ok(order.every((i) => i > 0), "all three scripts are on the page");
  assert.deepEqual([...order].sort((a, b) => a - b), order);
});

test("AI crawlers are welcome and get a plain summary", () => {
  const robots = read("robots.txt");
  for (const bot of ["OAI-SearchBot", "ChatGPT-User", "Claude-SearchBot", "PerplexityBot", "Google-Extended"]) {
    assert.match(robots, new RegExp(`User-agent: ${bot}\\n`));
  }
  assert.doesNotMatch(robots, /Disallow: \/\s*$/m);
  const llms = read("llms.txt");
  assert.match(llms, /^# DogBar\n\n> /);
  assert.match(llms, /macOS 14 or later/);
  assert.doesNotMatch(llms, /—/, "no em dashes");
  assert.match(read("index.html"), /<link rel="alternate" type="text\/markdown"[^>]*href="\/llms\.txt">/);
});
