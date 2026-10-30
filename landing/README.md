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
  tools/          art build (not deployed)
  tests/          node:test suites (not deployed)
```

## Visual thesis

A loud purple cartoon desk: the dog mascot's violet as the primary surface, cream and lavender as relief, and inky hand-drawn borders with hard offset shadows. Realistic macOS windows, Docks and switchers sit inside it like props in a picture book.

## Content plan

- **Hero.** The DogBar name is the loudest element. The promise is "Switch windows, not apps." A live cartoon Mac demo is the one dominant visual. Actions: the Mac download CTA (shows "Coming soon" until a release is verified) and "Try the demo".
- **Support (features).** Four alternating rows, each with one sentence-sized idea and its own illustration. In each, the dog does the feature: works Option and Tab, walks a new window to Desktop 2, peeks at Dock previews, lifts the Dock's resize grip.
- **Detail.** A deep-purple band about settings: scopes, previews on the native Dock, and Pause/Restore.
- **Get DogBar.** A cream banner near the footer with the same download CTA, permissions note and "Try the demo". The nav pill and footer link here.

## Interaction thesis

1. **Entrance.** The hero mascot sticker drops in and the headline settles with a short stagger.
2. **Demo state changes.** Switching desktops swaps the Dock and windows while pins stay. Option+Tab pops a tile per window, and Dock previews spring from the hovered icon.
3. **Hover and press.** Ink-shadowed buttons and feature art lift on hover and squash on press. Feature art tilts in on scroll. The unavailable download CTA stays flat and dashed, so it never pretends to be clickable.

All motion collapses under `prefers-reduced-motion`. The demo only listens for keys inside itself (Escape, arrows), never globally. Activating a Dock icon from the keyboard moves focus into its previews, and Escape returns it.

## Download CTAs and release.json

Both download CTAs (hero and banner) ship as placeholder `<a>` elements without `href`: not focusable, labelled "Download for Mac, Coming soon", with a note that the public release is being prepared. `release.js` fetches same-origin `/release.json` (no-store) and turns both into real links only when every check passes:

- `available === true` and `notarized === true` (strict booleans)
- `version` like `1.0`, `1.0.0` or `1.0.0-beta.2`
- `architecture === "arm64"`, `sha256` is 64 hex characters, `minimumMacOS` like `14.0`
- `url` is exactly `/downloads/DogBar-<version>-arm64.dmg`, or the same path on this page's own HTTPS origin
- the page itself is served over HTTPS

Live CTAs get `href`, `download`, an "Apple Silicon" tag and the note "Version X · Apple Silicon · macOS 14+". The banner also shows the SHA-256. A missing file, network error, bad JSON or any failed check keeps the unavailable state. Contract defaults:

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

The page avoids claims the app has not verified. It makes no speed claims and no guarantee about never switching Space. It does not mention App Store, pricing, testimonials or full Liquid Glass. It says nothing about notarization, and it names Apple Silicon only once a verified release is live. It does not link to the private repository, and there is no waitlist.
