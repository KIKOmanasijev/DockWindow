// Renders the real macOS app icons used by the hero demo into landing/assets/apps/.
// macOS only: AppKit draws each installed app's icon (osascript, JavaScript for
// Automation), then png.mjs re-encodes it at 96px. No dependencies, nothing hosted.
//
//   node landing/tools/app-icons.mjs
//
// Icons belong to their makers; the page shows them only to depict those apps.
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync, realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { decodePNG, encodePNG, cropToSubject, downscale } from "./png.mjs";

const OUT = new URL("../assets/apps/", import.meta.url);
const SIZE = 96; // Dock icons draw at up to 42 CSS px, so this covers 2x screens.
const APPS = {
  finder: "/System/Library/CoreServices/Finder.app",
  safari: "/Applications/Safari.app",
  slack: "/Applications/Slack.app",
  notes: "/System/Applications/Notes.app",
  music: "/System/Applications/Music.app",
};

// Draws the icon at 2x the target into an RGBA bitmap and writes it as PNG.
const JXA = `
ObjC.import("AppKit");
function run(argv) {
  const [app, out, px] = [argv[0], argv[1], Number(argv[2])];
  const icon = $.NSWorkspace.sharedWorkspace.iconForFile(app);
  const rep = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
    null, px, px, 8, 4, true, false, $.NSDeviceRGBColorSpace, 0, 0);
  rep.size = $.NSMakeSize(px, px);
  $.NSGraphicsContext.saveGraphicsState;
  $.NSGraphicsContext.setCurrentContext($.NSGraphicsContext.graphicsContextWithBitmapImageRep(rep));
  icon.drawInRectFromRectOperationFraction($.NSMakeRect(0, 0, px, px), $.NSZeroRect, $.NSCompositingOperationCopy, 1);
  $.NSGraphicsContext.restoreGraphicsState;
  rep.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $({})).writeToFileAtomically(out, true);
}`;

mkdirSync(OUT, { recursive: true });
for (const [key, app] of Object.entries(APPS)) {
  const file = fileURLToPath(new URL(`${key}.png`, OUT));
  // Resolve symlinks (Safari lives in a cryptex), or AppKit adds an alias arrow.
  execFileSync("osascript", ["-l", "JavaScript", "-e", JXA, realpathSync(app), file, String(SIZE * 2)]);
  // Trim the icon grid's transparent margin and soft shadow; CSS draws the ink outline.
  const png = encodePNG(downscale(cropToSubject(decodePNG(readFileSync(file)), { solid: 160, margin: 0 }), SIZE));
  writeFileSync(file, png);
  console.log(`${key}.png ${png.length} bytes`);
}
