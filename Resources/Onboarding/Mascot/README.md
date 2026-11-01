# DogBar onboarding mascot

Four static, transparent full-body poses for the native onboarding wizard. Generated with the built-in `image_gen` tool, directed by GPT6.1Sol; the image tool renders the pixels. Existing app icon and landing artwork are unchanged.

| Asset | Purpose |
| --- | --- |
| `welcome.png` | Relaxed greeting, one paw waving toward the user. |
| `guide.png` | Gaze and presenting forepaw directed toward a product scene on the viewer's right. Draw that scene separately in SwiftUI. |
| `permissions.png` | Patient, reassuring closed-mouth smile with resting paws. No premature success indicator. |
| `celebrate.png` | Delighted reward with both forepaws raised. Use after completion. |

## Generation and reference continuity

Identity references: `Resources/IconConcepts/dog-windows.png` and `landing/assets/mascot-poses/desktops.png`. The welcome image became the shared reference for the remaining poses. Preserve cream swept forehead tuft, muzzle and chest; caramel floppy ears; brown eyes and nose; soft warm upper-left light. Refined shading and delicate fur edges replace the heavier outlines of the older art.

Prompt set: create a square, full-body seated DogBar dog with genuine alpha, consistent camera, lighting and framing, comfortable transparent margins, no props, text, cards, badges, glow, ground shadow or background. Welcome: one forepaw gently waving and direct friendly gaze. Guide: head/gaze and one open forepaw presenting to viewer-right. Permissions: two resting forepaws, slight head tilt and calm closed-mouth smile. Celebrate: two forepaws raised beside shoulders with paw pads visible, delighted smile and two planted hind paws. Celebration received a targeted anatomy correction to remove an extra resting foreleg.

## Native motion

These PNGs are not animated and are not a segmented rig. Swap poses in response to onboarding state; use short opacity transitions and a small settling translation or rotation on state entry. Keep the canvas and bottom anchor stable. Avoid perpetual bouncing, large squash/stretch, or scaling around the face. Do not attempt independent paw animation from a flattened image. Reduce Motion should show the appropriate static pose without movement. No Rive dependency or generated video is required.

Use aspect-fit in a roughly 200–260 pt scene. Keep the entire square canvas, including transparency; allow extra layout space to the right of `guide.png` rather than clipping its extended paw. Source resolution exceeds the 520 px needed for 260 pt at 2×.

## Validation

All final PNGs inspected visually with `view_image` for character continuity, anatomy, cropping, text and background artifacts; alpha and bounds checked with Pillow in read-only mode. RGBA, genuine alpha range 0–255. The generator leaves a few nearly invisible alpha values (1–8) beyond the visible silhouette; use the visible bounds below for assessing margins, not automatic alpha trimming. Original generated alpha is preserved.

| File | Dimensions | Bytes | Alpha | Visible bounds (alpha > 8) |
| --- | --- | ---: | --- | --- |
| `celebrate.png` | 1254 × 1254 | 1,339,126 | 0–255 | `(91, 57, 1108, 1163)` |
| `guide.png` | 1254 × 1254 | 1,352,272 | 0–255 | `(89, 53, 1222, 1188)` |
| `permissions.png` | 1254 × 1254 | 1,340,020 | 0–255 | `(91, 55, 1120, 1195)` |
| `welcome.png` | 1254 × 1254 | 1,339,689 | 0–255 | `(95, 59, 1102, 1184)` |

Bounds use left/top inclusive and right/bottom exclusive pixel coordinates. No visible fur or paws touch the canvas edge. No test suite was run; this delivery contains art assets and documentation only.
