# DogBar landing page

Static, dependency-free site. Deploy with `landing` as the output root. No build step.

Production: https://dogbar.hristijan.dev/ (Cloudflare DNS configured and HTTPS verified).

Working Vercel address: https://dockwindow.vercel.app/

The Vercel project is `dockwindow` in the connected account. Only the site files are uploaded, not native app sources or this README. `vercel.json` keeps deployment static. Canonical and social image URLs use the production domain. The repository remains private.

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
  release.js      Mac download CTAs, driven by release.json / preview.json
  release.json    notarized release manifest (owned by the release process)
  preview.json    self-signed preview manifest (owned by the preview process)
  assets/         app icon rasters; feature-*.svg and mascot poses are kept for the repo README only
  assets/apps/    real macOS app icons for the demo (96px PNG, made by tools/app-icons.mjs)
  tools/          art and icon builds (not deployed)
  tests/          node:test suites (not deployed)
```

## Visual thesis

Calm and Mac-native. A deep purple band carries the brand at the top and bottom; everything between is light paper with ink type, hairline borders and soft shadows. The product demo is the one picture that matters: a clean, code-drawn Mac desktop that fits beside the headline, with a guided tour that dims the desktop to point at the detail instead of zooming, so nothing is ever cropped. Yellow appears only on Download. One informal touch: a short handwritten benefit list in the hero, set in the Mac's own handwriting fonts. The dog is the app icon in the nav, the demo Dock, the comparison table, the Get section and the footer, and nowhere else: no stickers, ink outlines, tilted cards or mascot art.

## Content plan

Each section has one job, and the headings alone tell the story.

- **Hero (promise and proof side by side).** Left: the category ("A better alt-tab and Dock for Mac") as a small eyebrow, the headline "Window management your Mac should have shipped with.", one benefit sentence with no shortcut names, a four-item handwritten list in plain words (see every window when you alt-tab; hover an app in the Dock to preview its windows; a separate Dock on every desktop; see how many windows each app has), Download, then "Watch the demo" (replays the tour). Right: the demo, sized so the whole screen, tour bar and caption fit in a laptop viewport.
- **Demo.** The screen is a close copy of macOS: a thin bezel, the real menu bar (Apple menu, bold app name, that app's own menus, status icons, clock), Safari's toolbar and macOS window shadows. Only the front window is shown, so every change is one window replacing another. A guided tour plays three short scenes while the demo is on screen: the day plan is on screen, a pointer hovers Safari and the desktop dims as both previews rise from the Dock, hovering Hotel booking peeks at it and a click brings it in; Option+Tab (with a keycap overlay) steps to the Slack chat and releasing swaps it in; a HUD with a direction arrow and "Desktop 2" appears, Desktop 2 slides in with its own wallpaper like macOS Spaces, and its Dock shows different apps, then back. Nothing zooms or dims in this scene; the Dock change is visible on its own. Under the screen there is only a slim bar: three step labels with progress lines (click one to jump there) and a small icon-only play/pause button, then a one-line caption. There is no separate control row. The Mac itself stays interactive (hover or click Dock icons, pick or close windows in previews), and inside the demo Option+Tab works like the real thing: hold Option, tap Tab (Shift goes back, arrows move), let go to switch, Escape cancels. A screen-reader description on the demo explains this. Any hands-on use ends the tour. The scenario is everyday trip planning: Desktop 1 (Planning) has two Safari windows, a Lisbon day plan and a hotel booking, plus a friends’ Slack chat and a Notes packing list; Desktop 2 (Personal) has a Sunday hike and Music. Safari’s two previews open on arrival with Hotel booking suggested. All names, URLs and messages are fictional.
- **Before/after (core benefit).** "Cmd+Tab knows apps. You work in windows." macOS Cmd+Tab’s three app icons next to DogBar’s four named window tiles. Each tile carries its app icon, so two Safari tiles visibly belong to one app.
- **Three supporting benefits.** Preview before you switch; a Dock for every desktop; count windows at a glance (with drag-to-resize and no magnification). Each has a small code-drawn scene with real app icons and a one-sentence explanation.
- **Comparison (objection).** "What your Mac leaves out." A five-row table, macOS against DogBar, with a red cross for what macOS lacks and a green check for what DogBar adds (each with a screen-reader "No"/"Yes"). Rows describe the keyboard switcher and Dock hover previews specifically. macOS already offers individual-window selection in Mission Control ([Apple guide](https://support.apple.com/en-ie/guide/mac-help/mchlp2469/27/mac/27)); the comparison does not claim otherwise. Dock resizing is left out because macOS can resize its Dock too. A note below covers Native Dock mode, matching the Settings copy: it keeps previews and the switcher, while per-desktop Docks and dots need DogBar’s Dock. Pause brings the regular Dock back.
- **Get DogBar (convert).** App icon, the same download CTA, status note and checksum, three setup steps (install, allow Accessibility and Screen Recording with the reason for each, press Option+Tab) and the unnotarized-preview instructions when that channel is live.
- **FAQ.** Four short answers: keeping Apple’s Dock, why the permissions, getting the normal Dock back (Pause DogBar / Restore Native Dock in the menu bar), switcher keys.

## Copy style

Plain, human words, in the voice of the hero's handwritten list: say what you get ("see every window when you alt-tab"), not how it is built. Short sentences, everyday terms like "alt-tab" and "window", no "scope", "individual" or "focus" where a simpler word works. Shortcut names appear only where they teach the shortcut (the before/after, setup steps, FAQ), never in the hero promise.

## CTA hierarchy

"Download for Mac" is the only primary button and the only yellow on the page (a test enforces that every rule using `--yellow` styles `.btn-download`). "Watch the demo" is a plain underlined text link in both places. The nav’s "Get DogBar" is an outline pill that jumps to the Get section. While unavailable, the download stays yellow with a quiet hatch, a "Coming soon" tag, no hover lift, default cursor and no `href`.

## Interaction thesis

1. **Entrance.** Hero copy fades up in a short stagger; the demo follows.
2. **Guided tour.** A pointer, a swipe HUD and a light dim behind open previews show each idea. There is no zoom: an earlier camera zoom cropped the previews and windows. It starts 0.7 s after the demo is half on screen, pauses when it scrolls away, never moves focus, sets the caption to `aria-live="off"` while playing, and stops for good on any pointer, key or focus inside the demo outside the tour bar. Under reduced motion it never starts on its own; the static opening example (Safari previews, "Hotel booking" suggested) stays, and Play still works without animation.
3. **Hands-on state changes.** Picking a preview brings forward only that window and says the other Safari window stayed put. Hovering or focusing a preview shows its window on top, outlined, as a peek. Switching desktops slides the new desktop in with the swipe HUD and swaps the Dock while pins stay. Option+Tab opens a tile per window.
4. **Scroll.** Feature visuals fade up once; in the before/after, DogBar’s tiles arrive one by one.

All motion collapses under `prefers-reduced-motion`. The demo only listens for keys inside itself (Escape, arrows), never globally. The opening preview does not take focus and survives outside clicks; any demo interaction replaces it, and Reset brings it back. Activating a Dock icon from the keyboard moves focus into its previews, and Escape returns it.

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

These icons are trademarks of their owners and appear only to depict those apps in the demo and feature visuals.

## Download CTAs and release channels

Both download CTAs (hero and banner) ship as placeholder `<a>` elements without `href`: not focusable, labelled "Download for Mac, Coming soon", with a note that the public release is being prepared. `release.js` first checks same-origin `/release.json` (no-store). A notarized release takes priority and turns both into real links when every check passes:

- `available === true` and `notarized === true` (strict booleans)
- `version` like `1.0`, `1.0.0` or `1.0.0-beta.2`
- `architecture === "arm64"`, `sha256` is 64 hex characters, `minimumMacOS` like `14.0`
- `url` is exactly `/downloads/DogBar-<version>-arm64.dmg`, or the same path on this page's own HTTPS origin
- the page itself is served over HTTPS

Live CTAs get `href`, `download`, an "Apple Silicon" tag and the note "Version X · Apple Silicon · macOS 14+". The banner also shows the SHA-256. A missing manifest, network error, bad JSON or failed validation keeps that channel unavailable. Contract defaults:

```json
{ "available": false, "version": null, "url": null, "sha256": null, "architecture": "arm64", "minimumMacOS": "14.0", "notarized": false }
```

## Feature art

The page no longer shows the four illustrated `assets/feature-*.svg` files: they were hard to read at a glance. They stay in `assets/` because the repository README embeds them, and `node landing/tools/build-art.mjs` still rebuilds them from `assets/mascot-poses/`. On the page, every feature visual is HTML and CSS with real app icons, wrapped in a `figure.feature-art` with `role="img"` and a full `aria-label`.

## Tests

```
node --test 'landing/tests/*.test.cjs'
JSDOM_PATH=/path/to/node_modules/jsdom node --test 'landing/tests/*.test.cjs'
```

`release.test.cjs` needs only Node: manifest verification, shipped markup, colour and art checks. `dom.test.cjs` drives the page and demo in jsdom, which this repo does not install. Point `JSDOM_PATH` at any local copy, otherwise it skips.

## Copy guardrails

The page avoids claims the app has not verified. It makes no speed claims and no guarantee about never switching Space. It does not mention App Store, pricing, testimonials or full Liquid Glass. It discloses unnotarized previews explicitly and names Apple Silicon only when a validated download is live. It does not link to the private repository, and there is no waitlist.

### Explicit preview channel

When no notarized release is available, `release.js` checks `/preview.json`. It accepts only `available: true`, `notarized: false`, `channel: "preview"`, `signing: "self-signed"`, a positive build number and an explicit `X.Y.Z-preview.N` version, with the same HTTPS origin, exact filename and SHA-256 checks. Both yellow CTAs then show Preview; both status notes say Unnotarized preview. The footer exposes installation instructions and the checksum. A valid notarized release always wins and hides preview-only help.

The preview DMG lives in ignored `landing/downloads/` and must be included in deployment uploads. It is intentionally not committed to the private source repository. Keep older published images available in subsequent deployments. Both manifests use no-store; versioned DMGs use immutable caching and attachment disposition. Build and verification instructions are in `Docs/PreviewDistribution.md` at the repository root. The notarized build/stage workflow remains unchanged.

### Feature sizing regression

Feature figures use `.feature-art`; Music cover thumbnails use `.album-art`. Keep their selectors separate. Feature figures explicitly fill their grid column with automatic height, while cover thumbnails use small fixed dimensions. `tests/layout.test.cjs` checks the CSS cascade so album-cover styles cannot shrink the four feature visuals, that their icons keep fixed sizes, and that `[hidden] { display: none !important; }` stays the last rule so closed preview and switcher shells never paint. It uses the same optional jsdom setup as the interaction tests and does not claim browser pixel-layout validation.
