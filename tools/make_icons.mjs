#!/usr/bin/env node
/**
 * NewGUI 图标生成器
 *
 * 从 Lucide (ISC License) 拉取 SVG 图标 → 渲染成白色描边 PNG(透明底),
 * 输出到 dist/assets/icons/ 。白色是为了让 Roblox 侧可以用 ImageColor3 染色,
 * 一个图标适配所有主题色。
 *
 * 用法:
 *   node tools/make_icons.mjs [--size 128] [--cache tools/.cache]
 */
import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

const args = process.argv.slice(2);
const getArg = (name, fallback) => {
  const index = args.indexOf(name);
  return index >= 0 && args[index + 1] ? args[index + 1] : fallback;
};

const SIZE = Number(getArg("--size", 128));
const CACHE = path.resolve(ROOT, getArg("--cache", "tools/.cache"));
const LUCIDE_VERSION = "1.57.0";
const OUT = path.join(ROOT, "dist", "assets", "icons");
const STROKE_COLOR = getArg("--color", "#ffffff");

function ensureLucide() {
  const iconsDir = path.join(CACHE, "lucide", "icons");
  if (fs.existsSync(iconsDir)) return iconsDir;

  fs.mkdirSync(CACHE, { recursive: true });
  const tarball = path.join(CACHE, "lucide-static.tgz");
  const url = `https://registry.npmjs.org/lucide-static/-/lucide-static-${LUCIDE_VERSION}.tgz`;
  console.log(`[icons] 下载 Lucide ${LUCIDE_VERSION} …`);
  execFileSync("curl", ["-sSL", "-o", tarball, url], { stdio: "inherit" });
  execFileSync("tar", ["xzf", tarball, "-C", CACHE], { stdio: "inherit" });
  fs.renameSync(path.join(CACHE, "package"), path.join(CACHE, "lucide"));
  return iconsDir;
}

function normalizeSvg(source, color) {
  return source
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/currentColor/g, color)
    .replace(/\swidth="[^"]*"/, ` width="24"`)
    .replace(/\sheight="[^"]*"/, ` height="24"`);
}

async function main() {
  let sharp;
  try {
    sharp = require("sharp");
  } catch {
    console.error("[icons] 需要 sharp: 在 tools/ 下 npm install sharp");
    process.exit(2);
  }

  const iconsDir = ensureLucide();
  const map = JSON.parse(fs.readFileSync(path.join(ROOT, "tools", "icon-map.json"), "utf8"));
  fs.mkdirSync(OUT, { recursive: true });

  const manifest = { source: `lucide-static v${LUCIDE_VERSION}`, license: "ISC", size: SIZE, icons: {} };
  let generated = 0;
  const missing = [];

  for (const [name, fileName] of Object.entries(map)) {
    const svgName = fileName.replace(/\.png$/, ".svg");
    const svgPath = path.join(iconsDir, svgName);
    if (!fs.existsSync(svgPath)) {
      missing.push(`${name} (${svgName})`);
      continue;
    }
    const svg = normalizeSvg(fs.readFileSync(svgPath, "utf8"), STROKE_COLOR);
    const buffer = await sharp(Buffer.from(svg), { density: 384 })
      .resize(SIZE, SIZE, { fit: "contain", background: { r: 0, g: 0, b: 0, alpha: 0 } })
      .png({ compressionLevel: 9 })
      .toBuffer();
    fs.writeFileSync(path.join(OUT, fileName), buffer);
    manifest.icons[name] = fileName;
    generated += 1;
  }

  fs.writeFileSync(path.join(OUT, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
  console.log(`[icons] 生成 ${generated} 个 PNG → ${path.relative(ROOT, OUT)} (${SIZE}px, 白色描边)`);
  if (missing.length) console.log(`[icons] 跳过(Lucide 无此图标): ${missing.join(", ")}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
