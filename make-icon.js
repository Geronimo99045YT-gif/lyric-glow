// Draws the Lyric Glow icon (a glowing vinyl on a dark tile) and writes app/icon.ico + app/icon.png.
// No dependencies: renders pixels directly and encodes PNG/ICO by hand.   Run: node make-icon.js
const fs = require('fs'), path = require('path'), zlib = require('zlib');

const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const smooth = (e0, e1, x) => { const t = clamp((x - e0) / (e1 - e0)); return t * t * (3 - 2 * t); };
const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);
const PINK = [255, 77, 141], BLUE = [24, 214, 255], VIOLET = [122, 92, 255];

function over(dst, src, a) { // src colour with alpha a over dst {c:[r,g,b], a}
  const oa = a + dst.a * (1 - a);
  if (oa <= 0) return { c: [0, 0, 0], a: 0 };
  return { c: dst.c.map((v, i) => (src[i] * a + v * dst.a * (1 - a)) / oa), a: oa };
}

function pixel(x, y, size) {
  const px = 1 / size;               // one pixel in normalised units, for anti-aliasing
  const cx = x - .5, cy = y - .5, d = Math.hypot(cx, cy), ang = Math.atan2(cy, cx);
  let p = { c: [0, 0, 0], a: 0 };

  // rounded-square tile
  const q = [Math.abs(cx) - (.5 - .2), Math.abs(cy) - (.5 - .2)];
  const sdf = Math.hypot(Math.max(q[0], 0), Math.max(q[1], 0)) + Math.min(Math.max(q[0], q[1]), 0) - .2;
  const tile = 1 - smooth(-px, px, sdf);
  p = over(p, mix([28, 16, 52], [7, 6, 12], clamp(x * .5 + y * .7)), tile);

  // soft colour glow hugging the record
  const g = Math.exp(-Math.pow((d - .4) / .09, 2));
  const gc = mix(PINK, BLUE, clamp(.5 + .5 * Math.sin(ang * 1 + 1)));
  p = over(p, gc, clamp(g * .55) * tile);

  // record body
  const disc = 1 - smooth(.4 - px, .4 + px, d);
  let shade = 14 + 4 * (1 - d / .4);
  if (d > .2 && d < .385) shade += 5 * (.5 + .5 * Math.sin(d * 520));                    // grooves
  if (d > .17 && d < .39) shade += 55 * Math.pow(Math.max(0, Math.cos(2 * (ang - .8))), 10); // light sheen
  p = over(p, [shade, shade, shade + 5], disc);

  // rim highlight
  const rim = Math.exp(-Math.pow((d - .395) / .006, 2)) * .35;
  p = over(p, mix(PINK, BLUE, .5), rim * disc);

  // label
  const label = 1 - smooth(.155 - px, .155 + px, d);
  p = over(p, mix(PINK, VIOLET, clamp((cx + cy) / .3 + .5)).map((v, i) => v + (BLUE[i] - v) * clamp((cx - cy) / .5 + .15)), label);
  p = over(p, [0, 0, 0], (1 - smooth(.155 - px, .155 + px, d)) * Math.exp(-Math.pow((d - .155) / .004, 2)) * .5);

  // spindle hole
  p = over(p, [7, 6, 12], 1 - smooth(.024 - px, .024 + px, d));
  return p;
}

function render(size) {
  const buf = Buffer.alloc(size * size * 4), S = size > 64 ? 2 : 3; // supersample for smooth edges
  for (let j = 0; j < size; j++) for (let i = 0; i < size; i++) {
    let r = 0, g = 0, b = 0, a = 0;
    for (let sj = 0; sj < S; sj++) for (let si = 0; si < S; si++) {
      const p = pixel((i + (si + .5) / S) / size, (j + (sj + .5) / S) / size, size);
      r += p.c[0] * p.a; g += p.c[1] * p.a; b += p.c[2] * p.a; a += p.a;
    }
    const n = S * S, o = (j * size + i) * 4;
    buf[o] = a ? r / a : 0; buf[o + 1] = a ? g / a : 0; buf[o + 2] = a ? b / a : 0; buf[o + 3] = Math.round(255 * a / n);
  }
  return buf;
}

const crcT = new Int32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; return c; });
const crc = b => { let c = -1; for (const v of b) c = crcT[(c ^ v) & 255] ^ (c >>> 8); return (c ^ -1) >>> 0; };
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]), c = Buffer.alloc(4); c.writeUInt32BE(crc(td));
  return Buffer.concat([len, td, c]);
}
function png(size, rgba) {
  const raw = Buffer.alloc((size * 4 + 1) * size);
  for (let y = 0; y < size; y++) { raw[y * (size * 4 + 1)] = 0; rgba.copy(raw, y * (size * 4 + 1) + 1, y * size * 4, (y + 1) * size * 4); }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4); ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

const sizes = [256, 64, 48, 32, 16];
const pngs = sizes.map(s => png(s, render(s)));
const head = Buffer.alloc(6); head.writeUInt16LE(1, 2); head.writeUInt16LE(sizes.length, 4);
let off = 6 + 16 * sizes.length;
const dir = sizes.map((s, i) => {
  const e = Buffer.alloc(16); e[0] = s === 256 ? 0 : s; e[1] = s === 256 ? 0 : s; e.writeUInt16LE(1, 4); e.writeUInt16LE(32, 6);
  e.writeUInt32LE(pngs[i].length, 8); e.writeUInt32LE(off, 12); off += pngs[i].length; return e;
});
const out = path.join(__dirname, 'app');
fs.writeFileSync(path.join(out, 'icon.ico'), Buffer.concat([head, ...dir, ...pngs]));
fs.writeFileSync(path.join(out, 'icon.png'), pngs[0]);
console.log('wrote icon.ico + icon.png');
