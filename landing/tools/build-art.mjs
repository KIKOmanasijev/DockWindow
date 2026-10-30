// Builds the four standalone DogBar feature illustrations in landing/assets/.
// Each SVG is self-contained: mascot poses and the app icon are embedded as PNG
// data URIs, because SVGs loaded through <img> cannot fetch external rasters.
//
//   node landing/tools/build-art.mjs
//
// Inputs: assets/mascot-poses/{switcher,desktops,previews,dock}.png (transparent
// cutouts) and assets/dog-96.png (the app icon, used for DogBar in each Dock).
import { readFileSync, writeFileSync } from "node:fs";
import { decodePNG, encodePNG, cropToSubject, downscale } from "./png.mjs";

const ASSETS = new URL("../assets/", import.meta.url);
const APP_ICON = "data:image/png;base64," + readFileSync(new URL("dog-96.png", ASSETS)).toString("base64");

const C = {
  ink: "#1D0B3F", purple: "#7B2FF2", deep: "#5B16C9", blob: "#8E4CFF",
  lav: "#EFE5FF", lav2: "#DCCBFF", cream: "#FFF8EA",
};
const FONT = `font-family="ui-rounded, 'SF Pro Rounded', 'Arial Rounded MT Bold', system-ui, sans-serif"`;

// Pose anchor points below were measured on 440px-wide crops; `pt` maps them onto the canvas.
const MEASURED = 440;
function pose(id, name, { x, y, w }) {
  const img = cropToSubject(decodePNG(readFileSync(new URL(`mascot-poses/${name}.png`, ASSETS))));
  // About 1.9x the drawn size keeps fur crisp on 2x screens without bloating the file.
  const small = downscale(img, Math.min(MEASURED, Math.round(w * 1.9)));
  const h = +((w * small.height) / small.width).toFixed(2);
  const uri = "data:image/png;base64," + encodePNG(small).toString("base64");
  return {
    svg: `<image id="${id}-pose" x="${x}" y="${y}" width="${w}" height="${h}" href="${uri}"/>`,
    pt: (px, py) => [+(x + (px / MEASURED) * w).toFixed(1), +(y + (py / MEASURED) * w).toFixed(1)],
  };
}

const defs = (id, { appIcon = false } = {}) => `
<defs>
  ${appIcon ? `<clipPath id="${id}-dogclip"><rect width="40" height="40" rx="10"/></clipPath>
  <symbol id="${id}-dog" viewBox="0 0 40 40"><image href="${APP_ICON}" width="40" height="40" clip-path="url(#${id}-dogclip)"/><rect x="1" y="1" width="38" height="38" rx="9.5" fill="none" stroke="${C.ink}" stroke-width="2"/></symbol>` : ""}
  <symbol id="${id}-finder" viewBox="0 0 40 40"><rect x="1" y="1" width="38" height="38" rx="9.5" fill="#BFE3FF" stroke="${C.ink}" stroke-width="2"/><path d="M10 1.5h12c-3 8-4 16-3 24 2 0 3 0 4 .5-1 4-1 8 0 13H10A9 9 0 0 1 1.5 30V10A9 9 0 0 1 10 1.5z" fill="#3B9BFF"/><rect x="1" y="1" width="38" height="38" rx="9.5" fill="none" stroke="${C.ink}" stroke-width="2"/><path d="M12 13v5M29 13v5M11 27c5 4 14 4 19 0" stroke="${C.ink}" stroke-width="2.4" stroke-linecap="round" fill="none"/></symbol>
  <symbol id="${id}-safari" viewBox="0 0 40 40"><rect x="1" y="1" width="38" height="38" rx="9.5" fill="#F4F8FF" stroke="${C.ink}" stroke-width="2"/><circle cx="20" cy="20" r="14" fill="#2F8CFF" stroke="${C.ink}" stroke-width="2"/><path d="M26 14 21.5 21.5 14 26 18.5 18.5z" fill="#fff" stroke="${C.ink}" stroke-width="1.4" stroke-linejoin="round"/><path d="M26 14 21.5 21.5 18.5 18.5z" fill="#FF4F5E"/></symbol>
  <symbol id="${id}-notes" viewBox="0 0 40 40"><rect x="1" y="1" width="38" height="38" rx="9.5" fill="#FFFDF5" stroke="${C.ink}" stroke-width="2"/><path d="M1.5 12V10A8.5 8.5 0 0 1 10 1.5h20A8.5 8.5 0 0 1 38.5 10v2z" fill="#FFC93C"/><path d="M1.5 12h37" stroke="${C.ink}" stroke-width="1.6"/><path d="M8 19h24M8 25h24M8 31h16" stroke="#C9C2B0" stroke-width="2" stroke-linecap="round"/></symbol>
  <symbol id="${id}-term" viewBox="0 0 40 40"><rect x="1" y="1" width="38" height="38" rx="9.5" fill="#25223A" stroke="${C.ink}" stroke-width="2"/><path d="M9 14l7 5-7 5M19 27h11" stroke="#7CF29A" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round" fill="none"/></symbol>
  <symbol id="${id}-music" viewBox="0 0 40 40"><rect x="1" y="1" width="38" height="38" rx="9.5" fill="#FF4D6D" stroke="${C.ink}" stroke-width="2"/><path d="M16 27V12l13-3v15" stroke="#fff" stroke-width="2.6" fill="none" stroke-linejoin="round"/><circle cx="13.5" cy="27.5" r="3.6" fill="#fff"/><circle cx="26.5" cy="24.5" r="3.6" fill="#fff"/></symbol>
  <pattern id="${id}-dots" width="26" height="26" patternUnits="userSpaceOnUse"><circle cx="4" cy="4" r="1.8" fill="${C.blob}"/></pattern>
</defs>`;

const bg = (id) => `
<rect width="640" height="480" fill="${C.purple}"/>
<rect width="640" height="480" fill="url(#${id}-dots)"/>
<circle cx="600" cy="40" r="120" fill="${C.blob}" opacity=".55"/>
<circle cx="30" cy="470" r="110" fill="${C.deep}" opacity=".45"/>`;

const sparkle = (x, y, s = 1, fill = C.cream) =>
  `<path transform="translate(${x} ${y}) scale(${s})" d="M0-12C1-4 4-1 12 0 4 1 1 4 0 12-1 4-4 1-12 0-4-1-1-4 0-12z" fill="${fill}" stroke="${C.ink}" stroke-width="2" stroke-linejoin="round"/>`;

const icon = (id, name, x, y, size) => `<use href="#${id}-${name}" x="${x}" y="${y}" width="${size}" height="${size}"/>`;

const lights = (x, y, r = 4.5) =>
  [["#FF5F57", 0], ["#FEBC2E", 1], ["#28C840", 2]]
    .map(([f, i]) => `<circle cx="${x + i * r * 3}" cy="${y}" r="${r}" fill="${f}" stroke="${C.ink}" stroke-width="1.3"/>`).join("");

function content(kind, x, y, w, h) {
  const line = (lx, ly, lw, c = "#D8D0EA") => `<rect x="${lx}" y="${ly}" width="${lw}" height="${Math.max(4, h * 0.035)}" rx="2" fill="${c}"/>`;
  if (kind === "safari") {
    return `<rect x="${x + w * 0.2}" y="${y + 5}" width="${w * 0.6}" height="${Math.max(8, h * 0.08)}" rx="${h * 0.04}" fill="#fff" stroke="#CFC4E6" stroke-width="1.2"/>
      <rect x="${x + w * 0.08}" y="${y + h * 0.2}" width="${w * 0.5}" height="${h * 0.07}" rx="3" fill="${C.ink}" opacity=".75"/>
      <rect x="${x + w * 0.08}" y="${y + h * 0.33}" width="${w * 0.4}" height="${h * 0.38}" rx="6" fill="${C.lav2}"/>
      <circle cx="${x + w * 0.2}" cy="${y + h * 0.45}" r="${h * 0.05}" fill="#FFC93C"/>
      <path d="M${x + w * 0.1} ${y + h * 0.69}l${w * 0.1}-${h * 0.14} ${w * 0.08} ${h * 0.08} ${w * 0.07}-${h * 0.1} ${w * 0.11} ${h * 0.16}z" fill="${C.purple}" opacity=".7"/>
      ${line(x + w * 0.54, y + h * 0.35, w * 0.36)}${line(x + w * 0.54, y + h * 0.46, w * 0.3)}${line(x + w * 0.54, y + h * 0.57, w * 0.34)}${line(x + w * 0.08, y + h * 0.8, w * 0.8)}`;
  }
  if (kind === "notes") {
    return `<rect x="${x}" y="${y}" width="${w * 0.32}" height="${h}" fill="#FFF4CC"/>
      ${line(x + w * 0.05, y + h * 0.1, w * 0.2, "#E8C66A")}${line(x + w * 0.05, y + h * 0.24, w * 0.18, "#E2D7B5")}${line(x + w * 0.05, y + h * 0.38, w * 0.2, "#E2D7B5")}
      <rect x="${x + w * 0.4}" y="${y + h * 0.1}" width="${w * 0.4}" height="${h * 0.08}" rx="3" fill="${C.ink}" opacity=".75"/>
      ${line(x + w * 0.4, y + h * 0.3, w * 0.48)}${line(x + w * 0.4, y + h * 0.42, w * 0.42)}${line(x + w * 0.4, y + h * 0.54, w * 0.5)}${line(x + w * 0.4, y + h * 0.66, w * 0.3)}`;
  }
  if (kind === "term") {
    const fs = Math.max(7, h * 0.09);
    return `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="#25223A"/>
      <text x="${x + w * 0.06}" y="${y + h * 0.22}" font-family="ui-monospace, Menlo, monospace" font-size="${fs}" fill="#7CF29A">~/app $ swift build</text>
      <text x="${x + w * 0.06}" y="${y + h * 0.4}" font-family="ui-monospace, Menlo, monospace" font-size="${fs}" fill="#CFC9E8">Build complete!</text>
      <text x="${x + w * 0.06}" y="${y + h * 0.58}" font-family="ui-monospace, Menlo, monospace" font-size="${fs}" fill="#7CF29A">~/app $ ▍</text>`;
  }
  if (kind === "music") {
    const s = Math.min(w * 0.24, h * 0.36);
    const cols = ["#FF4D6D", "#FFC93C", C.purple, "#3B9BFF", "#28C840", "#FF8A3D"];
    return cols.map((c, i) => `<rect x="${x + w * 0.07 + (i % 3) * (s + w * 0.06)}" y="${y + h * 0.1 + Math.floor(i / 3) * (s + h * 0.1)}" width="${s}" height="${s}" rx="5" fill="${c}" stroke="${C.ink}" stroke-width="1.2"/>`).join("");
  }
  return "";
}

let clipSeq = 0;
function win(id, x, y, w, h, { kind, title, shadow = true, opacity = 1 }) {
  const tb = Math.max(14, Math.min(26, h * 0.16));
  const r = Math.min(12, h * 0.09);
  const cid = `${id}-w${clipSeq++}`;
  return `<g opacity="${opacity}">
    ${shadow ? `<rect x="${x + 5}" y="${y + 6}" width="${w}" height="${h}" rx="${r}" fill="${C.ink}"/>` : ""}
    <clipPath id="${cid}"><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}"/></clipPath>
    <g clip-path="url(#${cid})">
      <rect x="${x}" y="${y}" width="${w}" height="${h}" fill="#FBF9FF"/>
      <rect x="${x}" y="${y}" width="${w}" height="${tb}" fill="${kind === "term" ? "#3A3654" : "#ECE5F8"}"/>
      ${content(kind, x, y + tb, w, h - tb)}
    </g>
    <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="none" stroke="${C.ink}" stroke-width="3"/>
    <path d="M${x} ${y + tb}h${w}" stroke="${C.ink}" stroke-width="1.5"/>
    ${lights(x + tb * 0.55, y + tb / 2, Math.max(2.6, tb * 0.17))}
    ${title && w > 110 ? `<text x="${x + w / 2 + tb}" y="${y + tb / 2 + tb * 0.17}" text-anchor="middle" ${FONT} font-weight="700" font-size="${tb * 0.48}" fill="${kind === "term" ? "#E8E4F7" : C.ink}">${title}</text>` : ""}
  </g>`;
}

function dock(id, x, y, items, size, gap, { pad = 12, divider = true, dotR = 2.6 } = {}) {
  const w = items.reduce((acc, it) => acc + (it === "|" ? gap * 1.6 : size + gap), -gap) + pad * 2;
  const h = size + pad * 2 + dotR * 3;
  const at = {};
  let cx = x + pad;
  let out = `<rect x="${x + 4}" y="${y + 5}" width="${w}" height="${h}" rx="${size * 0.42}" fill="${C.ink}"/>
    <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${size * 0.42}" fill="#FBF7FF" fill-opacity=".9" stroke="${C.ink}" stroke-width="3"/>`;
  for (const it of items) {
    if (it === "|") {
      if (divider) out += `<path d="M${cx + gap * 0.3} ${y + pad}v${size}" stroke="${C.ink}" stroke-width="2" stroke-linecap="round" opacity=".45"/>`;
      cx += gap * 1.6;
      continue;
    }
    const [name, dots = 0] = it;
    at[name] = cx + size / 2;
    out += icon(id, name, cx, y + pad, size);
    for (let d = 0; d < dots; d++) {
      out += `<circle cx="${cx + size / 2 + (d - (dots - 1) / 2) * dotR * 3.2}" cy="${y + pad + size + dotR * 2.2}" r="${dotR}" fill="${C.ink}"/>`;
    }
    cx += size + gap;
  }
  return { svg: out, w, h, at };
}

const label = (x, y, text, { anchor = "start", size = 19, fill = C.cream, rot = 0 } = {}) =>
  `<text x="${x}" y="${y}" transform="rotate(${rot} ${x} ${y})" text-anchor="${anchor}" ${FONT} font-weight="800" font-size="${size}" fill="${fill}" stroke="${C.ink}" stroke-width="5" stroke-linejoin="round" paint-order="stroke">${text}</text>`;

const arrow = (d, head) => `<path d="${d}" fill="none" stroke="${C.ink}" stroke-width="7" stroke-linecap="round"/><path d="${d}" fill="none" stroke="${C.cream}" stroke-width="3.2" stroke-linecap="round"/>
  <path d="${head}" fill="none" stroke="${C.ink}" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/><path d="${head}" fill="none" stroke="${C.cream}" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>`;

// Small ink lettering printed on a key cap inside a pose.
const keyCap = ([x, y], text, { size = 15, rot = 0 } = {}) =>
  `<text x="${x}" y="${y}" transform="rotate(${rot} ${x} ${y})" text-anchor="middle" dominant-baseline="central" ${FONT} font-weight="900" font-size="${size}" fill="${C.ink}">${text}</text>`;

const wrap = (id, title, desc, body, opts) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 480" width="640" height="480" role="img" aria-labelledby="${id}-t ${id}-d">
<title id="${id}-t">${title}</title>
<desc id="${id}-d">${desc}</desc>
${defs(id, opts)}
${bg(id)}
${body}
</svg>
`;

// 1. Option+Tab switcher: the dog works the keys below the screen.
function switcher() {
  const id = "sw";
  const tiles = [["safari", "safari", "Docs"], ["safari", "safari", "Recipes"], ["notes", "notes", "Groceries"], ["term", "term", "zsh"], ["music", "music", "Up Next"]];
  let t = "";
  tiles.forEach(([ic, kind, title], i) => {
    const x = 92 + i * 94;
    const y = 134;
    if (i === 1) t += `<rect x="${x - 7}" y="${y - 8}" width="96" height="130" rx="14" fill="#fff" fill-opacity=".18" stroke="${C.cream}" stroke-width="3"/>`;
    t += win(id, x, y, 82, 66, { kind, title: "", shadow: false });
    t += icon(id, ic, x + 27, y + 58, 28);
    t += `<text x="${x + 41}" y="${y + 108}" text-anchor="middle" ${FONT} font-weight="700" font-size="12" fill="#F3EEFF">${title}</text>`;
  });
  const dog = pose(id, "switcher", { x: 214, y: 276, w: 228 });
  return wrap(id, "Option+Tab switcher with one tile per window",
    "A cartoon Mac desktop shows the DogBar switcher with five tiles: two Safari windows, Notes, Terminal and Music. Below the screen, the DogBar dog presses the Option and Tab keys with its front paws.",
    `<rect x="44" y="50" width="552" height="272" rx="22" fill="${C.ink}" transform="translate(6 7)"/>
     <rect x="44" y="50" width="552" height="272" rx="22" fill="${C.lav2}" stroke="${C.ink}" stroke-width="4"/>
     <path d="M44 72V72a22 22 0 0 1 22-22h508a22 22 0 0 1 22 22z" fill="#fff" fill-opacity=".6"/>
     <path d="M44 72h552" stroke="${C.ink}" stroke-width="2"/>
     <rect x="44" y="50" width="552" height="272" rx="22" fill="none" stroke="${C.ink}" stroke-width="4"/>
     ${win(id, 80, 88, 250, 150, { kind: "safari", title: "Docs", opacity: 0.45, shadow: false })}
     ${win(id, 300, 104, 260, 176, { kind: "notes", title: "Groceries", opacity: 0.45, shadow: false })}
     <rect x="76" y="116" width="488" height="160" rx="24" fill="#1E1338" fill-opacity=".88" stroke="${C.ink}" stroke-width="3"/>
     ${t}
     ${arrow("M246 30c-28 2-46 26-56 76", "M178 94l12 14 13-12")}
     ${label(258, 36, "2 Safari windows = 2 tiles", { size: 21 })}
     ${dog.svg}
     ${keyCap(dog.pt(226, 344), "⌥", { size: 17, rot: -3 })}
     ${keyCap(dog.pt(366, 318), "tab", { size: 13, rot: -4 })}
     ${label(196, 418, "hold option,", { size: 20, anchor: "end", rot: -3 })}
     ${label(196, 444, "tap tab", { size: 20, anchor: "end", rot: -3 })}
     ${sparkle(70, 360, 1.1)}${sparkle(470, 362, 0.8)}${sparkle(600, 420, 0.9)}${sparkle(612, 300, 0.7)}`);
}

// 2. A Dock per desktop: the dog walks a new window over to Desktop 2.
function desktops() {
  const id = "dk";
  const screen = (x, n, wins, apps) => {
    const d = dock(id, 0, 0, [["finder"], ["dog"], "|", ...apps], 30, 7, { pad: 7, dotR: 2.4 });
    return `<rect x="${x + 6}" y="72" width="276" height="214" rx="18" fill="${C.ink}"/>
      <rect x="${x}" y="66" width="276" height="214" rx="18" fill="${n === 1 ? C.lav2 : C.lav}" stroke="${C.ink}" stroke-width="4"/>
      ${wins}
      <g transform="translate(${x + (276 - d.w) / 2} 218)">${d.svg}</g>
      ${label(x + 14, 52, `Desktop ${n}`, { size: 22, rot: n === 1 ? -3 : 2 })}`;
  };
  const dog = pose(id, "desktops", { x: 236, y: 284, w: 172 });
  return wrap(id, "A separate Dock for each desktop",
    "Two cartoon Mac desktops side by side. Desktop 1 shows Safari and Notes in its Dock. Desktop 2 shows Terminal and Music. Finder and DogBar stay pinned in both. The DogBar dog walks a new, empty window over to Desktop 2.",
    `${screen(28, 1, win(id, 46, 86, 170, 104, { kind: "safari", title: "Docs" }) + win(id, 160, 118, 120, 88, { kind: "notes", title: "List" }), [["safari", 2], ["notes", 1]])}
     ${screen(336, 2, win(id, 352, 86, 176, 104, { kind: "term", title: "zsh" }) + win(id, 470, 118, 126, 88, { kind: "music", title: "Music" }), [["term", 1], ["music", 1]])}
     <path d="M178 352h36M164 376h44M184 400h30" stroke="${C.ink}" stroke-width="7" stroke-linecap="round"/>
     <path d="M178 352h36M164 376h44M184 400h30" stroke="${C.cream}" stroke-width="3.2" stroke-linecap="round"/>
     ${dog.svg}
     ${label(36, 340, "pins stay put", { size: 21, rot: -2 })}
     ${arrow("M104 318V278", "M92 290l12-13 12 13")}
     ${label(604, 400, "new window,", { size: 21, anchor: "end", rot: 2 })}
     ${label(604, 426, "right here", { size: 21, anchor: "end", rot: 2 })}
     ${arrow("M494 372c-12-18-34-26-62-22", "M446 340l-14 10 14 10")}
     ${sparkle(318, 40, 1)}${sparkle(612, 462, 0.8)}${sparkle(150, 456, 0.7)}${sparkle(574, 318, 0.7)}`, { appIcon: true });
}

// 3. Hover previews: the dog lies in front of the screen and peeks up at them.
function previews() {
  const id = "pv";
  const d = dock(id, 0, 0, [["finder"], ["dog"], "|", ["safari", 2], ["notes", 1], ["term", 1]], 40, 9, { pad: 9 });
  const dx = 262;
  const safariX = dx + d.at.safari;
  const px = Math.round(safariX - 152);
  const thumb = (x, title, on) => `
    ${on ? `<rect x="${x - 7}" y="140" width="138" height="140" rx="14" fill="${C.purple}" fill-opacity=".16" stroke="${C.purple}" stroke-width="3"/>` : ""}
    ${win(id, x, 148, 124, 96, { kind: "safari", title: "", shadow: false })}
    ${lights(x + 12, 156, 4.6)}
    <text x="${x + 62}" y="268" text-anchor="middle" ${FONT} font-weight="800" font-size="15" fill="${C.ink}">${title}</text>`;
  const dog = pose(id, "previews", { x: 2, y: 318, w: 232 });
  return wrap(id, "Hover previews for each window",
    "Hovering Safari in the Dock shows a preview of its two windows, Docs and Recipes, each with traffic lights. The cursor picks Recipes to focus that exact window. The DogBar dog lies in front of the screen and peeks up at the previews.",
    `<rect x="36" y="46" width="568" height="350" rx="22" fill="${C.ink}" transform="translate(6 7)"/>
     <rect x="36" y="46" width="568" height="350" rx="22" fill="${C.lav2}" stroke="${C.ink}" stroke-width="4"/>
     ${win(id, 62, 112, 200, 140, { kind: "notes", title: "List", opacity: 0.5, shadow: false })}
     <g transform="translate(6 7)"><rect x="${px}" y="118" width="304" height="176" rx="20" fill="${C.ink}"/></g>
     <rect x="${px}" y="118" width="304" height="176" rx="20" fill="#FFFDFC" stroke="${C.ink}" stroke-width="3.5"/>
     <path d="M${safariX - 14} 292l14 16 14-16" fill="#FFFDFC" stroke="${C.ink}" stroke-width="3.5" stroke-linejoin="round"/>
     <path d="M${safariX - 12} 290h24" stroke="#FFFDFC" stroke-width="5"/>
     ${thumb(px + 16, "Docs", false)}${thumb(px + 164, "Recipes", true)}
     <g transform="translate(${dx} 318)">${d.svg}</g>
     <rect x="${safariX - 26}" y="321" width="52" height="58" rx="14" fill="none" stroke="${C.purple}" stroke-width="3" stroke-dasharray="6 5"/>
     <path d="M${px + 234} 214l0 34 9-8 7 15 7-3-7-15 12-1z" fill="#fff" stroke="${C.ink}" stroke-width="3" stroke-linejoin="round"/>
     ${label(604, 30, "click = that exact window", { size: 20, anchor: "end", rot: 1 })}
     ${arrow(`M560 40c6 40-14 74-${560 - (px + 284)} 96`, `M${px + 296} 124l-12 12 16 4`)}
     ${label(60, 86, "traffic lights work too", { size: 19, rot: -2 })}
     ${arrow(`M150 98c50 0 ${px - 136} 22 ${px - 126} 46`, `M${px + 12} 132l14 12-1-17`)}
     ${dog.svg}
     ${sparkle(250, 438, 0.9)}${sparkle(612, 220, 0.8)}${sparkle(612, 440, 0.7)}`, { appIcon: true });
}

// 4. Count dots and resizing: the dog stands on the Dock and lifts its grip.
function dockDots() {
  const id = "dd";
  const d = dock(id, 0, 0, [["finder"], ["dog"], "|", ["safari", 2], ["notes", 1], ["term", 3], ["music", 1]], 60, 13, { pad: 15, dotR: 4 });
  const dx = (640 - d.w) / 2;
  const top = 300;
  const dog = pose(id, "dock", { x: 170, y: 136, w: 190 });
  const [, gripY] = dog.pt(347, 237);
  const termDots = dx + d.at.term;
  return wrap(id, "Window count dots and a resizable Dock",
    "A large cartoon Dock with one dot per open window: two for Safari, one for Notes, three for Terminal and one for Music. The DogBar dog stands on the Dock and lifts its resize grip, and a dashed outline shows the bigger Dock. The icons keep a fixed size.",
    `<rect x="${dx - 26}" y="${gripY}" width="${d.w + 52}" height="${top + d.h + 16 - gripY}" rx="34" fill="none" stroke="${C.cream}" stroke-width="3" stroke-dasharray="10 9" opacity=".85"/>
     <g transform="translate(${dx} ${top})">${d.svg}</g>
     ${dog.svg}
     ${arrow(`M412 ${gripY + 34}V${gripY - 50}`, `M398 ${gripY - 36}l14-16 14 16`)}
     ${label(436, gripY - 30, "drag to resize", { size: 22, rot: -3 })}
     ${label(36, 72, "icons hold still,", { size: 20, rot: -2 })}
     ${label(36, 98, "no magnification", { size: 20, rot: -2 })}
     ${label(604, 462, "1 dot = 1 window", { size: 22, anchor: "end", rot: 2 })}
     ${arrow(`M${termDots + 66} 440c-8-14-30-26-54-28`, `M${termDots + 26} 402l-14 10 14 10`)}
     ${sparkle(560, 100, 1.1)}${sparkle(80, 452, 0.8)}${sparkle(280, 84, 0.6)}`, { appIcon: true });
}

const out = new URL("../assets/", import.meta.url);
for (const [file, build] of [["feature-switcher.svg", switcher], ["feature-desktops.svg", desktops], ["feature-previews.svg", previews], ["feature-dock.svg", dockDots]]) {
  const svg = build().replace(/[\t ]+$/gm, "");
  writeFileSync(new URL(file, out), svg);
  console.log(file, `${(svg.length / 1024).toFixed(0)} KB`);
}
