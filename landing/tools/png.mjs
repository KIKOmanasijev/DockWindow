// Minimal RGBA PNG codec for the art build. Node built-ins only.
import { inflateSync, deflateSync } from "node:zlib";

const SIG = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

export function decodePNG(buf) {
  if (!buf.subarray(0, 8).equals(SIG)) throw new Error("not a PNG");
  let pos = 8, width = 0, height = 0;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString("latin1", pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (type === "IHDR") {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      const [depth, color, , , interlace] = data.subarray(8, 13);
      if (depth !== 8 || color !== 6 || interlace !== 0) throw new Error("only 8-bit RGBA, non-interlaced PNGs");
    } else if (type === "IDAT") idat.push(data);
    else if (type === "IEND") break;
    pos += 12 + len;
  }
  const raw = inflateSync(Buffer.concat(idat));
  const stride = width * 4;
  const px = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    const f = raw[y * (stride + 1)];
    const row = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let x = 0; x < stride; x++) {
      const a = x >= 4 ? px[y * stride + x - 4] : 0;
      const b = y ? px[(y - 1) * stride + x] : 0;
      const c = x >= 4 && y ? px[(y - 1) * stride + x - 4] : 0;
      let v = row[x];
      if (f === 1) v += a;
      else if (f === 2) v += b;
      else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) v += paeth(a, b, c);
      px[y * stride + x] = v & 255;
    }
  }
  return { width, height, data: px };
}

function paeth(a, b, c) {
  const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}

const CRC = new Int32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c;
});
const crc32 = (buf) => {
  let c = -1;
  for (const b of buf) c = CRC[(c ^ b) & 255] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
};
const chunk = (type, data) => {
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0);
  out.write(type, 4, "latin1");
  data.copy(out, 8);
  out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
  return out;
};

// Adaptive per-row filtering (minimum sum of absolute differences), zlib level 9.
export function encodePNG({ width, height, data }) {
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  const cand = Array.from({ length: 5 }, () => Buffer.alloc(stride));
  for (let y = 0; y < height; y++) {
    let best = 0, bestSum = Infinity;
    for (let f = 0; f < 5; f++) {
      let sum = 0;
      for (let x = 0; x < stride; x++) {
        const v = data[y * stride + x];
        const a = x >= 4 ? data[y * stride + x - 4] : 0;
        const b = y ? data[(y - 1) * stride + x] : 0;
        const c = x >= 4 && y ? data[(y - 1) * stride + x - 4] : 0;
        const p = f === 0 ? 0 : f === 1 ? a : f === 2 ? b : f === 3 ? (a + b) >> 1 : paeth(a, b, c);
        const out = (v - p) & 255;
        cand[f][x] = out;
        sum += out < 128 ? out : 256 - out;
      }
      if (sum < bestSum) { bestSum = sum; best = f; }
    }
    raw[y * (stride + 1)] = best;
    cand[best].copy(raw, y * (stride + 1) + 1);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr.set([8, 6, 0, 0, 0], 8);
  return Buffer.concat([SIG, chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw, { level: 9 })), chunk("IEND", Buffer.alloc(0))]);
}

// Crop to the solid subject (alpha above `solid`) plus a margin, optionally mirror.
export function cropToSubject(img, { solid = 200, margin = 6, flip = false } = {}) {
  const { width, height, data } = img;
  let x0 = width, y0 = height, x1 = -1, y1 = -1;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if (data[(y * width + x) * 4 + 3] > solid) {
        if (x < x0) x0 = x; if (x > x1) x1 = x;
        if (y < y0) y0 = y; if (y > y1) y1 = y;
      }
    }
  }
  x0 = Math.max(0, x0 - margin); y0 = Math.max(0, y0 - margin);
  x1 = Math.min(width - 1, x1 + margin); y1 = Math.min(height - 1, y1 + margin);
  const w = x1 - x0 + 1, h = y1 - y0 + 1;
  const out = Buffer.alloc(w * h * 4);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const sx = x0 + (flip ? w - 1 - x : x);
      data.copy(out, (y * w + x) * 4, ((y0 + y) * width + sx) * 4, ((y0 + y) * width + sx) * 4 + 4);
    }
  }
  return { width: w, height: h, data: out };
}

// Area-average downscale in premultiplied alpha, so edges never pick up dark fringes.
// Fully transparent pixels get zero RGB, which also keeps the file small.
export function downscale(img, targetWidth) {
  const { width: sw, height: sh, data } = img;
  const tw = Math.min(sw, Math.round(targetWidth));
  const th = Math.max(1, Math.round((sh * tw) / sw));
  const sx = sw / tw, sy = sh / th;
  const out = Buffer.alloc(tw * th * 4);
  for (let ty = 0; ty < th; ty++) {
    const yA = ty * sy, yB = yA + sy;
    for (let tx = 0; tx < tw; tx++) {
      const xA = tx * sx, xB = xA + sx;
      let r = 0, g = 0, b = 0, a = 0, area = 0;
      for (let y = Math.floor(yA); y < Math.ceil(yB); y++) {
        const wy = Math.min(yB, y + 1) - Math.max(yA, y);
        for (let x = Math.floor(xA); x < Math.ceil(xB); x++) {
          const w = wy * (Math.min(xB, x + 1) - Math.max(xA, x));
          const i = (y * sw + x) * 4;
          const al = data[i + 3] / 255;
          r += data[i] * al * w; g += data[i + 1] * al * w; b += data[i + 2] * al * w;
          a += al * w; area += w;
        }
      }
      const o = (ty * tw + tx) * 4;
      const alpha = a / area;
      const a8 = Math.round(alpha * 255);
      if (a8 === 0) continue;
      out[o] = Math.round(r / a); out[o + 1] = Math.round(g / a); out[o + 2] = Math.round(b / a);
      out[o + 3] = a8;
    }
  }
  return { width: tw, height: th, data: out };
}
