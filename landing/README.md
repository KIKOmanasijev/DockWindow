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
  index.html      page and inline app-icon symbols
  styles.css      all styling, responsive and reduced-motion rules
  script.js       interactive hero demo and scroll reveals
  release.js      Mac download CTAs, driven by release.json
  release.json    release manifest (owned by the release process)
  assets/         app icon rasters, mascot pose cutouts and four feature SVGs
  assets/apps/    real macOS app icons for the demo (96px PNG, made by tools/app-icons.mjs)
  tools/          art and icon builds (not deployed)
  tests/          node:test suites (not deployed)
```

## Visual thesis

A loud purple cartoon desk: the dog mascot's violet as the primary surface, cream and lavender as relief, and inky hand-drawn borders with hard offset shadows. Inside it sits a believable Mac: real app icons and real-looking app windows, drawn in HTML and CSS and framed in the same thick ink.

## Content plan

- **Hero.** The DogBar name is the loudest element. Promise: "Switch windows, not apps." One line of proof: "Cmd+Tab brings back an app. DogBar brings back the exact window you meant." The demo is the one dominant visual.
- **Hero demo scenario.** Launch day on Desktop 1 (Work): Safari has two windows, a pull request review and the staging site, next to Slack (#onboarding-launch) and a Notes checklist that says "Check step 2 on staging". The page opens with Safari's Dock previews already showing both windows and a sticker, "2 Safari windows. Pick one.", so the benefit reads without clicking. Desktop 2 (Personal) has its own Dock: one Safari window and Music. Every name, URL and message is fictional (Fernway, Wanderly); no personal data or screenshots.
- **Support (features).** Four alternating rows, each with one sentence-sized idea and its own illustration. In each, the dog does the feature.
- **Detail.** A deep-purple band about settings: scopes, previews on the native Dock, and Pause/Restore.
- **Get DogBar.** A cream banner near the footer with the same download CTA, permissions note and demo link. The nav pill and footer link here.

## CTA hierarchy

"Download for Mac" is the only button: brand purple, cream text, ink border and hard shadow, larger than anything near it. On the purple hero a cream ring sets it apart from the background; on the cream banner the purple carries it alone. "Try the demo" is a plain underlined link with a play glyph, never a second button. While unavailable, the download stays purple and dominant but hatched, with a yellow "Coming soon" tag, no hover lift, default cursor and no `href`.

## Interaction thesis

1. **Entrance.** The hero mascot sticker drops in, the headline settles with a short stagger, and the suggested "Staging: Welcome" preview nudges a few times.
2. **Demo state changes.** Picking a preview brings forward only that window and says the other Safari window stayed put. Hovering or focusing a preview outlines its window on the desk. Switching desktops swaps the Dock and windows while pins stay. Option+Tab pops a tile per window.
3. **Hover and press.** The live download button and feature art lift on hover and squash on press. Feature art tilts in on scroll.

All motion collapses under `prefers-reduced-motion`. The demo only listens for keys inside itself (Escape, arrows), never globally. The opening preview does not take focus and survives outside clicks; any demo interaction replaces it, and Reset brings it back. Activating a Dock icon from the keyboard moves focus into its previews, and Escape returns it.

## Demo windows and app icons

Window content is code: spans styled in `styles.css`, sized in container query units so the same markup renders on the desk, in Dock previews and in switcher tiles. The Finder, Safari, Slack, Notes and Music icons in `assets/apps/` are rendered from the apps installed on a Mac and re-encoded at 96px with no dependencies:

```
node landing/tools/app-icons.mjs
```

These icons are trademarks of their owners and appear only to depict those apps in the demo.

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

The four `assets/feature-*.svg` files are generated and self-contained, because SVGs shown through `<img>` cannot load external images. Mascot poses (`assets/mascot-poses/*.png`) and the app icon are cropped, downscaled and embedded as PNG data URIs. Rebuild after changing a pose or a layout:

```
node landing/tools/build-art.mjs
```

The DogBar app icon (`dog-96.png`, `dog-640.jpg`) stays the identity in the nav, favicon, settings sketch and each illustrated Dock.

## Tests

```
node --test 'landing/tests/*.test.cjs'
JSDOM_PATH=/path/to/node_modules/jsdom node --test 'landing/tests/*.test.cjs'
```

`release.test.cjs` needs only Node: manifest verification, shipped markup and art checks. `dom.test.cjs` drives the page and demo in jsdom, which this repo does not install. Point `JSDOM_PATH` at any local copy, otherwise it skips.

## Copy guardrails

The page avoids claims the app has not verified. It makes no speed claims and no guarantee about never switching Space. It does not mention App Store, pricing, testimonials or full Liquid Glass. It discloses unnotarized previews explicitly and names Apple Silicon only when a validated download is live. It does not link to the private repository, and there is no waitlist.

### Explicit preview channel

When no notarized release is available, `release.js` checks `/preview.json`. It accepts only `available: true`, `notarized: false`, `channel: "preview"`, `signing: "self-signed"`, a positive build number and an explicit `X.Y.Z-preview.N` version, with the same HTTPS origin, exact filename and SHA-256 checks. Both purple CTAs then show Preview; both status notes say Unnotarized preview. The footer exposes installation instructions and the checksum. A valid notarized release always wins and hides preview-only help.

The preview DMG lives in ignored `landing/downloads/` and must be included in deployment uploads. It is intentionally not committed to the private source repository. Keep older published images available in subsequent deployments. Both manifests use no-store; versioned DMGs use immutable caching and attachment disposition. Build and verification instructions are in `Docs/PreviewDistribution.md` at the repository root. The notarized build/stage workflow remains unchanged.
