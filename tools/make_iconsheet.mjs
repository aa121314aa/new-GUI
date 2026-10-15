#!/usr/bin/env node
/** 生成图标清单预览图(深色底), 方便肉眼检查资产是否正确 */
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const sharp = require("sharp");
const ICONS = path.join(ROOT, "dist", "assets", "icons");
const OUT = path.join(ROOT, "docs", "images", "icons-preview.png");

const map = JSON.parse(fs.readFileSync(path.join(ROOT, "tools", "icon-map.json"), "utf8"));
const entries = Object.entries(map);
const cell = 96, pad = 24, cols = 7;
const rows = Math.ceil(entries.length / cols);
const width = cols * cell + pad * 2;
const height = rows * cell + pad * 2;

const composites = [];
for (const [index, [, file]] of entries.entries()) {
  const col = index % cols, row = Math.floor(index / cols);
  const resized = await sharp(path.join(ICONS, file)).resize(56, 56, { fit: "contain" }).png().toBuffer();
  composites.push({
    input: resized,
    left: pad + col * cell + (cell - 56) / 2,
    top: pad + row * cell + (cell - 56) / 2 - 6,
  });
}

await sharp({
  create: { width, height, channels: 4, background: { r: 20, g: 21, b: 28, alpha: 1 } },
})
  .composite(composites)
  .png()
  .toFile(OUT);
console.log(`[icons] 预览图 → ${path.relative(ROOT, OUT)} (${entries.length} 个图标)`);
