# DogBar landing page

Static, dependency-free site. Deploy with `landing` as the output root. No build step.

Production: https://dogbar.hristijan.dev/ (Cloudflare DNS configured and HTTPS verified).

Working Vercel address: https://dockwindow.vercel.app/

The Vercel project is `dockwindow` in the connected account. Only the site files are uploaded, not native app sources or this README. `vercel.json` keeps deployment static. Canonical and social image URLs use the production domain. The repository is public on GitHub.

## Custom domain setup

The subdomain `dogbar.hristijan.dev` is attached to this Vercel project. Its authoritative DNS provider is Cloudflare. In Cloudflare, open **hristijan.dev > DNS > Records > Add record**:

| Field | Value |
| --- | --- |
| Type | CNAME |
| Name | dogbar |
| Target | a03bcfc7b14d0c0e.vercel-dns-017.com |
| Proxy status | DNS only, grey cloud |
| TTL | Auto |

This record is now configured. For future DNS changes, save and check the domain under Vercel project **dockwindow > Settings > Domains**. Vercel provisions HTTPS once DNS is configured. This target was returned for this project, not a universal Vercel target. Registration and nameservers remain at the existing provider.

```
landing/
  index.html      page, feature visuals (HTML/CSS) and UI glyph symbols
  styles.css      all styling, responsive and reduced-motion rules
  script.js       interactive hero demo and scroll reveals
  analytics.js    PostHog (cookieless) and the custom events listed under Analytics
  llms.txt        plain-markdown summary for AI assistants and answer engines
  release.js      Mac download CTAs, driven by release.json / preview.json
  release.json    notarized release manifest (owned by the release process)
  preview.json    self-signed preview manifest (owned by the preview process)
  assets/         app icon rasters; feature-*.svg and mascot poses are no longer used anywhere
  assets/apps/    real macOS app icons for the demo (96px PNG, made by tools/app-icons.mjs)
  tools/          art and icon builds (not deployed)
  tests/          node:test suites (not deployed)
```

## Visual thesis

Calm and Mac-native. A deep purple band carries the brand at the top and bottom; everything between is light paper with ink type, hairline borders and soft shadows. The product demo is the one picture that matters: a clean, code-drawn Mac desktop that fits beside the headline, with a guided tour that dims the desktop to point at the detail instead of zooming, so nothing is ever cropped. Yellow appears only on Download. One informal touch: a short handwritten benefit list in the hero, set in the Mac's own handwriting fonts. The dog is the app icon in the nav, the demo Dock, the comparison table, the Get section and the footer, and nowhere else: no stickers, ink outlines, tilted cards or mascot art.

## Content plan

Each section has one job, and the headings alone tell the story.

- **Hero (promise and proof side by side).** Left: the category ("A better alt-tab and Dock for Mac") as a small eyebrow, the headline "Window management your Mac should have shipped with.", one benefit sentence with no shortcut names, a four-item handwritten list in plain words (see every window when you alt-tab; hover an app in the Dock to preview its windows; a separate Dock on every desktop; see how many windows each app has), Download, then "Watch the demo" (replays the tour). Right: the demo, sized so the whole screen, tour bar and caption fit in a laptop viewport.
- **Demo.** The screen is a close copy of macOS: a thin bezel, the real menu bar (Apple menu, bold app name, that app's own menus, status icons, clock), Safari's toolbar and macOS window shadows. Only the front window is shown, so every change is one window replacing another. A guided tour plays three short scenes while the demo is on screen. First, the isolated Docks: Desktop 1’s Dock shows Finder, then Safari, Slack and Notes; a HUD with a direction arrow and "Desktop 2" appears, Desktop 2 slides in with its own wallpaper like macOS Spaces, and its own Dock shows Music, Chrome, TV and Photos instead, then back. The page makes no claim that pins are shared across desktops. Then the day plan is on screen, a pointer hovers Safari and the desktop dims as both previews rise from the Dock, the pointer rests on "Hotel booking" (outlined and lifted, the screen unchanged) and only the click brings that window in; last, the window switcher (with a keycap overlay showing the default Option+Tab) steps to the Slack chat and releasing swaps it in. Nothing zooms or dims in the desktop scene; the Dock change is visible on its own. Under the screen there is only a slim bar: three step labels with progress lines (click one to jump there) and a small icon-only play/pause button, then a one-line caption. There is no separate control row. The demo plays like a video: the screen is `inert`, `aria-hidden` and ignores the mouse, so nothing inside it can be clicked, hovered or focused. Only the chapters and play/pause are controls. Pause freezes the walkthrough mid-scene (a play clock banks the remaining time, and on-screen animations pause), and Play continues from the same moment. Screen readers get a short plain description of the three scenes instead of step-by-step narration; the visible caption has no live region. The scenario is everyday trip planning: Desktop 1 (Planning) has two Safari windows, a Lisbon day plan and a hotel booking, plus a friends’ Slack chat and a Notes packing list; Desktop 2 (Personal) has Music, a Sunday hike in Chrome, TV and Photos. Finder leads both Docks, as on macOS. Before playback starts, and as the still under reduced motion, the opening frame shows Desktop 1 with its Dock. All names, URLs and messages are fictional.
- **Before/after (core benefit).** "Cmd+Tab knows apps. You work in windows." macOS Cmd+Tab’s three app icons next to DogBar’s four named window tiles. Each tile carries its app icon, so two Safari tiles visibly belong to one app.
- **Three supporting benefits.** An isolated Dock for every desktop; preview before you switch; count windows at a glance (with drag-to-resize and no magnification). Each has a small code-drawn scene with real app icons and a one-sentence explanation.
- **Comparison (objection).** "What your Mac leaves out." A five-row table, macOS against DogBar, with a red cross for what macOS lacks and a green check for what DogBar adds (each with a screen-reader "No"/"Yes"). Rows describe the keyboard switcher and Dock hover previews specifically. macOS already offers individual-window selection in Mission Control ([Apple guide](https://support.apple.com/en-ie/guide/mac-help/mchlp2469/27/mac/27)); the comparison does not claim otherwise. Dock resizing is left out because macOS can resize its Dock too. A note below covers Native Dock mode, matching the Settings copy: it keeps previews and the switcher, while per-desktop Docks and dots need DogBar’s Dock. Pause brings the regular Dock back.
- **Get DogBar (convert).** App icon, the same download CTA, status note and checksum, three setup steps (install, allow Accessibility and Screen Recording with the reason for each, press Option+Tab) and the unnotarized-preview instructions when that channel is live.
- **FAQ.** Four short answers: keeping Apple’s Dock, why the permissions, getting the normal Dock back (Pause DogBar / Restore Native Dock in the menu bar), switcher keys.

## Copy style

Plain, human words, in the voice of the hero's handwritten list: say what you get ("see every window when you alt-tab"), not how it is built. Short sentences, everyday terms like "alt-tab" and "window", no "scope", "individual" or "focus" where a simpler word works. Shortcut names appear only where they teach the shortcut (the before/after, setup steps, FAQ), never in the hero promise.

## CTA hierarchy

"Download for Mac" is the only primary button and the only yellow on the page (a test enforces that every rule using `--yellow` styles `.btn-download`). "Watch the demo" is a plain underlined text link in both places. The nav’s "Get DogBar" is an outline pill that jumps to the Get section. While unavailable, the download stays yellow with a quiet hatch, a "Coming soon" tag, no hover lift, default cursor and no `href`.

## Interaction thesis

1. **Entrance.** Hero copy fades up in a short stagger; the demo follows.
2. **Guided tour.** A pointer, a swipe HUD and a light dim behind open previews show each idea. There is no zoom: an earlier camera zoom cropped the previews and windows. It starts 0.7 s after the demo is half on screen, pauses when it scrolls away and resumes when it returns, unless someone pressed Pause. It never moves focus. Under reduced motion it never starts on its own; the opening frame stays as a still, and Play still works without animation.
3. **State changes.** Picking a preview brings forward only that window and says the other Safari window stayed put. Switching desktops slides the new desktop in with the swipe HUD and swaps the Dock while pins stay. Option+Tab opens a tile per window.
4. **Scroll.** Feature visuals fade up once; in the before/after, DogBar’s tiles arrive one by one.

All motion collapses under `prefers-reduced-motion`. The demo listens for no keys and no clicks on the screen.

## Research rationale

References were checked live in October 2026. We borrowed patterns, not copy or visuals.

- [Postiz](https://postiz.com): an outcome headline, the product in action right after it, feature blocks that pair a short claim with a real screen, and an FAQ at the end. We took that order (promise, product, benefits, objections, FAQ) and left out its doodles, logo strips, audience cards and testimonial wall, because DogBar has no verified adoption to show and one audience.
- [Marc Lou](https://marclou.com): one plain, confident first-person line and very little chrome. This is why the headline is short and literal.
- [SuperX](https://superx.so): every feature block follows the same pattern of label, headline, one paragraph and one visual. We used that rhythm for the feature grid. Its stats and creator counts were not copied: there are no invented metrics here.
- [AltTab](https://alt-tab.app/) ("Find the right window. Keep your flow.") and [DockDoor](https://dockdoor.net) ("Every window, one hover away."): Mac window tools that lead with the window-level benefit, use one product illustration and repeat a single "Download for Mac". They confirm the category language visitors already know; DogBar’s wording is its own.
- [rcmd](https://lowtechguys.com/rcmd/): a before/after of "Cmd+Tab, Tab, Tab" against its own shortcut, with keycaps. This is the model for the Cmd+Tab versus Option+Tab comparison and the keycap-styled demo button.
- [CleanShot X](https://cleanshot.com): a calm, Mac-native palette with one primary CTA repeated at the end.
- 2026 trend roundups ([SaaSFrame](https://www.saasframe.io/blog/10-saas-landing-page-trends-for-2026-with-real-examples), [SaaS Hero](https://www.saashero.net/design/top-landing-page-design-trends/)) agree on outcome-led heroes, an ungated interactive demo in or right under the hero, real use contexts over abstract illustration, and purposeful micro-animation. We used those, and skipped the ones that would add noise or need proof we lack (logo bars, review badges, personalisation, dark glassmorphism everywhere).

## Demo windows and app icons

Window content is code: spans styled in `styles.css`, sized in container query units so the same markup renders on the desk, in Dock previews and in switcher tiles. Feature visuals use their own `fx-*` and `thumb-*` classes, never the demo hooks (`.win`, `.dock-btn`, `.tile`, `.pv`, `[data-app]`), because the demo and its tests query those page-wide. The Finder, Safari, Slack, Notes and Music icons in `assets/apps/` are rendered from the apps installed on a Mac and re-encoded at 96px with no dependencies:

```
node landing/tools/app-icons.mjs
```

The repository README shows the demo as three GIFs in `.github/readme/`. Re-record them after changing the demo (needs Google Chrome, ffmpeg and Node 22+; Chrome runs headless with a throwaway profile):

```
node landing/tools/record-demo-gifs.mjs
```

These icons are trademarks of their owners and appear only to depict those apps in the demo and feature visuals.

## Download CTAs and release channels

Both download CTAs (hero and banner) ship as placeholder `<a>` elements without `href`: not focusable, labelled "Download for Mac, Coming soon", with a note that the public release is being prepared. `release.js` first checks same-origin `/release.json` (no-store). A notarized release takes priority and turns both into real links when every check passes:

- `available === true` and `notarized === true` (strict booleans)
- `version` like `1.0`, `1.0.0` or `1.0.0-beta.2`
- `architecture === "arm64"`, `sha256` is 64 hex characters, `minimumMacOS` like `26.0`
- `url` is exactly `/downloads/DogBar-<version>-arm64.dmg`, or the same path on this page's own HTTPS origin
- the page itself is served over HTTPS

Live CTAs get `href`, `download`, an "Apple Silicon" tag and the note "Version X · Apple Silicon · macOS 26+". The banner also shows the SHA-256. A missing manifest, network error, bad JSON or failed validation keeps that channel unavailable. Contract defaults:

```json
{ "available": false, "version": null, "url": null, "sha256": null, "architecture": "arm64", "minimumMacOS": "26.0", "notarized": false }
```

## Feature art

The page no longer shows the four illustrated `assets/feature-*.svg` files: they were hard to read at a glance. The repository README no longer embeds them either, so they and `assets/mascot-poses/` are unused (still deployed, since everything in `landing/` is uploaded); `node landing/tools/build-art.mjs` still rebuilds them. On the page, every feature visual is HTML and CSS with real app icons, wrapped in a `figure.feature-art` with `role="img"` and a full `aria-label`.

## Tests

```
node --test 'landing/tests/*.test.cjs'
JSDOM_PATH=/path/to/node_modules/jsdom node --test 'landing/tests/*.test.cjs'
```

`release.test.cjs` needs only Node: manifest verification, shipped markup, colour and art checks. `dom.test.cjs` drives the page and demo in jsdom, which this repo does not install. Point `JSDOM_PATH` at any local copy, otherwise it skips.

## Copy guardrails

The page avoids claims the app has not verified. It makes no speed claims and no guarantee about never switching Space. It does not mention App Store, pricing, testimonials or full Liquid Glass. It discloses unnotarized previews explicitly and names Apple Silicon only when a validated download is live. The page has no GitHub link yet, and there is no waitlist.

### Explicit preview channel

When no notarized release is available, `release.js` checks `/preview.json`. It accepts only `available: true`, `notarized: false`, `channel: "preview"`, `signing: "self-signed"`, a positive build number and an explicit `X.Y.Z-preview.N` version, with the same HTTPS origin, exact filename and SHA-256 checks. Both yellow CTAs then show Preview; both status notes say Unnotarized preview. The footer exposes installation instructions and the checksum. A valid notarized release always wins and hides preview-only help.

The preview DMG lives in ignored `landing/downloads/` and must be included in deployment uploads. It is intentionally not committed to the private source repository. Keep older published images available in subsequent deployments. Both manifests use no-store; versioned DMGs use immutable caching and attachment disposition. Build and verification instructions are in `Docs/PreviewDistribution.md` at the repository root. The notarized build/stage workflow remains unchanged.

### Feature sizing regression

Feature figures use `.feature-art`; Music cover thumbnails use `.album-art`. Keep their selectors separate. Feature figures explicitly fill their grid column with automatic height, while cover thumbnails use small fixed dimensions. `tests/layout.test.cjs` checks the CSS cascade so album-cover styles cannot shrink the four feature visuals, that their icons keep fixed sizes, and that `[hidden] { display: none !important; }` stays the last rule so closed preview and switcher shells never paint. It uses the same optional jsdom setup as the interaction tests and does not claim browser pixel-layout validation.

## Analytics

PostHog Cloud EU, project **DogBar** (id 328829), personal organization, not the Native Teams one. `analytics.js` loads it only on `dogbar.hristijan.dev` and `dockwindow.vercel.app`; local copies send nothing (`?analytics=debug` logs the events to the console instead).

It runs in cookieless mode (`cookieless_mode: "always"`, with "Enable cookieless tracking" on in the project): nothing is stored on the visitor's device, so the page needs no consent banner. The trade-offs: a visitor is counted once per day, so a return visit tomorrow is a new visitor and funnels use a one-day window; there is no session replay. Person profiles are off and nobody is identified.

Every event carries `traffic_type` (`ai`, `search`, `social`, `campaign`, `referral`, `direct`) and `traffic_source` (for example `chatgpt`, `google.com`, `news.ycombinator.com`, or the `utm_source`). AI assistants are matched by referrer or by `utm_source`, which ChatGPT adds to its links. Custom events also carry `release_channel` (`live`, `preview`, `unavailable`). Use `?utm_source=...&utm_campaign=...` on every link you post so each post can be measured.

| Event | Properties | Question it answers |
| --- | --- | --- |
| `$pageview`, `$pageleave`, `$autocapture`, heatmaps, web vitals | PostHog defaults (scroll depth, device, country) | How many visitors, from where, on what devices, and is the page fast |
| `download_clicked` | `location` (hero, get), `available`, `version` | The conversion. Clicks while unavailable measure demand before a release |
| `watch_demo_clicked` | `location` | Do people ask for the demo |
| `demo_started` | `trigger` (auto, play_button, chapter, watch_demo_link), `chapter` | Does the demo get seen at all |
| `demo_scene_watched` | `scene` (1 to 3: A Dock per desktop, Preview from the Dock, Switch to any window), `chapter`, `scenes_watched` | How far people watch; once per scene per page view. Scene numbers before the November 2026 reorder meant Preview, Switch, Desktops |
| `demo_watched_all` | | Watched every scene |
| `demo_control_clicked` | `action` (play, pause, chapter), `chapter` | Do people steer the demo, and which chapter they jump to |
| `section_viewed` | `section` (demo, switcher_compare, features, comparison, get, faq), `order` | Where the page loses people |
| `faq_opened` | `question` | What visitors worry about |
| `install_help_opened` | | How many need help with the unnotarized preview |
| `checksum_copied` | | Careful, high-intent visitors |
| `nav_clicked` | `target`, `location` (nav, footer) | Which sections people look for |
| `outbound_link_clicked` | `url`, `location` | Who leaves for Apple's instructions |

The **DogBar launch** dashboard in PostHog (the project's home dashboard) charts these: visitors and download clicks per day, conversion by traffic type, the visit-to-download funnel, sources, AI-assistant visits, demo watch depth, page depth, download buttons, FAQ questions and install help. PostHog's built-in Web analytics view covers countries, devices, entry paths and web vitals. Keep event names stable: renaming one splits its history.

## Responsive layout and search information

The comparison uses a fixed-layout table with explicit columns: 64/18/18 on wider screens and 56/22/22 on phones. The DogBar header can wrap; its decorative icon is omitted below 640px so the name fits. The tour controls can shrink and wrap, window-switcher tiles use a two-column grid on phones, and previews can shrink within their screen. Navigation and CTAs wrap rather than rely on a horizontal page crop. These are source-level fixes for narrow phones, tablets, wide displays and browser zoom; rendered viewport checks remain necessary.

The page identifies DogBar in plain text, includes compatibility and preview-status answers, and serves canonical/social metadata, `robots.txt`, a single-URL `sitemap.xml`, and static JSON-LD for the website, application and visible FAQ. `llms.txt` (linked from the page head) restates the product, requirements, comparison and FAQ facts as plain markdown for AI assistants, and `robots.txt` names the AI search and assistant crawlers as welcome. Keep `llms.txt` in step with the page; in particular, update its "Requirements and status" section when a notarized release replaces the preview. Release versions and download links remain owned by the existing manifests. The structured data contains no invented price, rating, adoption or notarization claims. A regression check keeps FAQ answers aligned with the visible text.

Search guidance used:

- [Google: AI features and your website](https://developers.google.com/search/docs/appearance/ai-features): normal crawlability, useful textual content and consistent structured data apply; no special AI schema or AI text file is required.
- [Google: mobile-first indexing](https://developers.google.com/search/docs/crawling-indexing/mobile/mobile-sites-mobile-first-indexing): use responsive HTML with the same meaningful content on mobile and desktop.
- [Google: software application structured data](https://developers.google.com/search/docs/appearance/structured-data/software-app): describe the real app. We omit offers and reviews because they are not established, so this is factual entity markup, not a claim of eligibility for app rich results.
- [Google: FAQ rich-result restrictions](https://developers.google.com/search/blog/2023/08/howto-faq-changes): FAQ markup is not a promise of a Google FAQ rich result for this utility site.
- [Bing: AI Performance guidance](https://www.bing.com/webmasters/help/ai-performance-9f8e7d6c): clear headings, concise sections, tables and FAQ answers help engines understand and reference content.

No ranking, indexing or answer-engine citation is guaranteed. Search Console and Bing Webmaster Tools ownership/submission are separate owner actions; no new account setup is part of this change.
