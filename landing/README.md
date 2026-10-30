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
  assets/         mascot raster derived from Resources/IconConcepts/dog-windows.png,
                  plus four authored feature SVGs (mascot embedded as data URI)
```

## Visual thesis

A loud purple cartoon desk: the dog mascot's violet as the primary surface, cream and lavender as relief, and inky hand-drawn borders with hard offset shadows. Realistic macOS windows, Docks and switchers sit inside it like props in a picture book.

## Content plan

- **Hero.** The DogBar name is the loudest element. The promise is "Switch windows, not apps." A live cartoon Mac demo is the one dominant visual. The primary action is "Try the demo" (in-page). Availability note: "In development. macOS 14+".
- **Support (features).** Four alternating rows, each with its own illustration: per-window switcher, a Dock per desktop, hover previews, count dots and resizing. Each row has one sentence.
- **Detail.** A deep-purple band about settings: scopes, previews on the native Dock, and Pause/Restore.
- **Final CTA.** An honest status note covering active development, required permissions and no public download yet. Its action returns to the demo.

## Interaction thesis

1. **Entrance.** The hero mascot sticker drops in and the headline settles with a short stagger.
2. **Demo state changes.** Switching desktops swaps the Dock and windows while pins stay. Option+Tab pops a tile per window, and Dock previews spring from the hovered icon.
3. **Hover and press.** Ink-shadowed buttons and feature art lift on hover and squash on press. Feature art tilts in on scroll.

All motion collapses under `prefers-reduced-motion`. The demo only listens for keys inside itself (Escape, arrows), never globally.

## Copy guardrails

The page avoids claims the app has not verified. It makes no speed claims and no guarantee about never switching Space. It does not mention App Store, notarization, pricing, downloads, testimonials or full Liquid Glass. It does not link to the private repository.

