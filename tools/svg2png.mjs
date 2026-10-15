#!/usr/bin/env node
/** SVG → PNG(sharp 渲染)。用法: node tools/svg2png.mjs in.svg out.png [scale] */
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";

const require = createRequire(import.meta.url);
const [input, output, scaleArg] = process.argv.slice(2);
if (!input || !output) {
  console.error("用法: node tools/svg2png.mjs <in.svg> <out.png> [scale]");
  process.exit(2);
}

const sharp = require("sharp");
const scale = Number(scaleArg || 1);
const svg = fs.readFileSync(input);

let pipeline = sharp(svg, { density: Math.round(72 * scale) });
if (scale !== 1) {
  const meta = await sharp(svg).metadata();
  pipeline = pipeline.resize(Math.round((meta.width || 0) * scale), Math.round((meta.height || 0) * scale));
}
await pipeline.png().toFile(output);
console.log(`[svg2png] ${path.basename(output)} (${scale}x)`);
