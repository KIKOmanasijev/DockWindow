# DogBar launch video project

**Current delivery: 38-second silent animatic, not a product recording.** The non-interactive command `screencapture -x -m` failed with `could not create image from display`. No real app image was captured. The draft therefore uses explicitly marked recording slates, typography, drawn strokes and the repository mascot. It does not fabricate macOS UI or claim a feature was observed. The more-realistic final cut requires your recordings.

- [Storyboard](STORYBOARD.md): caption and action per beat.
- [Recording guide](RECORDING-GUIDE.md): exact setup, shots and recording settings.
- `output/dogbar-animatic-wide.mp4`: 1920×1080, 30 fps, H.264/yuv420p, fast-start MP4.
- `output/dogbar-animatic-square.mp4`: 1080×1080, independently laid out, same timing.
- `output/*-contact.jpg`, `output/*-frames/`, `output/qa.json`: frame extraction and technical QA.

## Run offline

Prerequisites: Python 3.10+, Node/npm (script convenience only), FFmpeg/ffprobe on PATH. The edit is Python/Pillow + FFmpeg; no React, Remotion, browser, screen control or Swift dependencies. Initial setup downloads only pinned Pillow into this folder's virtual environment:

```sh
cd /private/var/www/DockWindow/marketing/demo-video
npm run setup
npm run render
npm run qa
```

Or use your own Python with Pillow 12.2.0: `python3 scripts/render.py` and `python3 scripts/qa.py`.

## Replace slates with actual footage

Edit `edit.json`: set each scene's `source` to a relative path such as `raw/04-hover.mov`, `start` to the trim-in time, and retain `duration` for this cut. Source audio is discarded. The renderer checks file existence and sufficient length; it fails instead of silently freezing a too-short clip. Photos (`.png`, `.jpg`, `.jpeg`) work and receive a visible “Still” label. The full source is contained without distortion or automatic cropping. Square output preserves the full screen rather than cutting away previews; dedicated close-up captures may read better on phones.

First render drafts, extract frames and inspect them. Then set `verified: true` **only after** checking the clip shows the stated real action, contains no personal data, and its result remains visible. `npm run final` blocks if any of the six required sources/verification flags are absent. `verified` is a human editorial assertion, not automatic proof. For the desktop, hover and switcher scenes, use moving footage before calling the result a demo. A still can illustrate appearance but cannot demonstrate interaction.

Optional hand-drawn annotations: per scene, add `annotations: [{"at": 2, "points": [[0.45,0.8],[0.5,0.75],[0.55,0.8]]}]`. Points are normalized within the footage box. Add dense circle/arrow paths around **actual** targets after inspecting your clip. They draw over 0.6 s. No pointer or UI interaction is generated. The default underline animation stays outside the footage.

This version uses crisp cuts so the real Space movement remains legible. Source-driven cursor movement is preferable to any synthetic cursor. Nothing touches DogBar settings, its process or its installed build. Nothing writes to `landing/`.

## Music slot

`edit.json` has `"music": null`: the exports intentionally have no audio stream. After you provide a licensed track, place it in `raw/music.wav` and set `music` to that path. The renderer loops it to length, mixes at 18% and fades the ends. Record source, licence, author and attribution requirements in `MUSIC-LICENSE.md` before publishing; null is the safe default. Do not assume a track is cleared because it is on YouTube or labeled “royalty free”.

## Verification limits

One frame per second is decoded from each output, plus technical metadata checks. These frames verify layout/timing at one-second intervals, not every transition frame. No real-time playback, perceived motion smoothness or audio listening has been performed. Current drafts contain no real UI to verify. Re-run QA after swapping sources; review full motion yourself before posting to Reddit/Product Hunt or the website.

See [LICENCES.md](LICENCES.md) for dependencies and assets. No commits or pushes are part of this project.
