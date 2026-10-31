# Draft verification

- Both delivered MP4s: 38.000 s, 30 fps, H.264, yuv420p; 1920×1080 and 1080×1080 respectively. Fast-start encoding enabled. No audio track.
- Decoded/extracted 38 frames per format at 1 fps. Visually inspected both contact sheets (76 sampled frames): captions fit; slate areas remain explicitly marked; mascot and CTA fit both layouts. Long holds are reserved for the real screen actions.
- Syntax checks passed for both Python scripts.
- In a temporary folder, exercised source-video decoding/trimming, still input, annotation drawing and final-mode encoding using an explicitly synthetic QA fixture. No QA fixture is included as product footage. This checks pipeline plumbing, not DogBar functionality.
- Attempted final export against the actual manifest: correctly refused at `01-spaces` because recording/verification is missing.
- Non-interactive screenshot capture failed; no real footage or screenshots are included. Did not use Computer Use, browser automation, app control or Swift tests. Did not modify DogBar settings or the installed app.
- Did not watch in real time, listen to music, inspect every transition frame or observe product interactions. Real footage QA and a full playback review remain necessary after replacing slates.
- The Reddit reference page was read, but its video was not viewable through the available non-browser fetch. No claim of matching its exact pacing or visual quality.

Re-run `npm run qa` after any edit. Frame files and technical JSON are under `output/` and intentionally excluded from Git, alongside raw media and exports.
