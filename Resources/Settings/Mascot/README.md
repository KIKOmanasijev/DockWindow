# Settings mascot assets

Generated with the built-in image_gen tool, directed by GPT6.1Sol. The image tool renders the pixels. These are static supporting illustrations; native UI integration belongs to the Settings implementation.

| File | Use | Size | Bytes |
| --- | --- | --- | ---: |
| guide.png | Calm seated dog presenting a separately drawn control toward viewer-right | 640 × 640 RGBA | 383282 |
| search.png | Curious seated dog for an empty Settings search state | 640 × 640 RGBA | 366445 |

## Identity and generation

Inspected all four Resources/Onboarding/Mascot poses, the onboarding guide rig/body and MascotRig.swift, and landing/assets/mascot-poses/desktops.png. Guide uses onboarding guide.png and permissions.png as image references; search uses permissions.png and welcome.png. Existing artwork was left untouched.

Preserved the cream swept forehead tuft, muzzle, chest and paws; caramel floppy ears; golden coat; brown eyes and nose; curled cream-tipped tail; soft painted fur and warm lighting. The Settings versions use patient closed-mouth smiles and no props or baked UI.

### Guide prompt

Use case: identity-preserve. Create a new restrained Settings supporting mascot pose by editing the referenced DogBar dog. References are exact character identity and rendering style: keep same cream swept forehead tuft, cream muzzle/chest/paw tips, caramel floppy ears and golden body, large brown eyes, brown nose, curled cream-tipped tail, delicate painted fur and warm upper-left light. Full-body seated little dog, calm closed-mouth friendly smile, one forepaw gently extended toward viewer-right presenting an adjacent control that will be drawn separately in native UI. Other forepaw resting, exactly two forelegs total plus two seated hind paws; all limbs anatomically clear. No actual control, UI, props, text, cards, magnifier, sparkles or scenery. Compact relaxed pose, no big celebratory gesture. Entire silhouette and extended paw comfortably inside square canvas with 10% transparent margin. Genuine RGBA transparent background, clean fur edges, no ground shadow or glow. Utility Settings artwork readable at 80–128 points, preserve existing dog identity closely.

### Search prompt

Use case: identity-preserve. Create a new restrained empty Settings search supporting mascot pose by editing the referenced DogBar dog. Exact same dog identity and delicate painted fur rendering: cream swept forehead tuft, muzzle/chest/paw tips, caramel floppy ears, golden body, brown eyes and nose, curled cream-tipped tail, warm upper-left light. Full-body seated dog, both forepaws resting naturally between two seated hind paws (four limbs total), slight curious head tilt, ears relaxed, gaze looking gently toward viewer-left as though searching for something nearby; patient closed-mouth smile, curious and helpful, not sad or confused. Pose distinct from guide. No magnifying glass, props, UI, text, symbols, badges, scenery, shadow or glow. Small utility illustration readable at 96–144 points, compact silhouette, full tail and all paws visible, comfortable 10% transparent margins on every side, no clipping. Genuine RGBA transparent background, clean edges. Preserve the existing reference dog identity closely.

## Usage and validation

Use aspect-fit with the entire square canvas. Suggested guide size: 80–128 pt beside a control or short explanatory section; search: 96–144 pt in an empty result state. Keep surrounding copy and controls native and independently accessible. Treat these images as decorative when nearby text conveys the meaning. Avoid enlarging them into hero artwork.

Both files have genuine alpha range 0–255. Visible bounds (alpha > 8; left/top inclusive, right/bottom exclusive): guide (55, 34, 589, 602), search (75, 42, 547, 596). Whole limbs and tails remain within the canvas; no extra paws, text, UI, ground shadow or background. Inspected generated originals and a 96/128 px contact sheet over light/dark backgrounds. Fine fur naturally simplifies at small size; face and gesture remain readable. No native app integration or tests were performed.

Finals were downsampled with Lanczos to 640 px and losslessly PNG-optimized, preserving RGBA. No palette reduction or alpha thresholding. Full-resolution generated originals remain outside the repository at:
- /Users/kiko/.codex/generated_images/01a19bd6-f7e8-7b22-93a0-ba21668fb159/exec-960391d6-fd95-4c6c-b9c5-10c4dbe02aa9.png
- /Users/kiko/.codex/generated_images/01a19bd6-f7e8-7b22-93a0-ba21668fb159/exec-e93b44c5-03cf-49a6-b483-0ea27869fb4d.png

These flattened PNGs are not compatible with independent limb animation in the onboarding rig. Integration, motion and final in-app layout remain with the UI implementer.
