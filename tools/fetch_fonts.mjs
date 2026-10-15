#!/usr/bin/env node
/**
 * 下载预览渲染用的中文字体(Noto Sans SC, SIL OFL 1.1)。
 *
 * 沙箱/CI 环境通常没有系统字体, 预览图里的中文会变成方块; 这个脚本把字体
 * 放进 tools/.cache/fonts (gitignored), 并生成 fontconfig 配置供 sharp 使用。
 *
 * 用法: node tools/fetch_fonts.mjs
 */
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const FONT_DIR = path.join(ROOT, "tools", ".cache", "fonts");
const FONT_CACHE = path.join(ROOT, "tools", ".cache", "fontconfig");
const TARGETS = [
  { name: "NotoSansSC-Regular.otf", repo: "notofonts/noto-cjk", file: "Sans/SubsetOTF/SC/NotoSansSC-Regular.otf" },
  { name: "NotoSansSC-Medium.otf", repo: "notofonts/noto-cjk", file: "Sans/SubsetOTF/SC/NotoSansSC-Medium.otf" },
];

fs.mkdirSync(FONT_DIR, { recursive: true });
fs.mkdirSync(FONT_CACHE, { recursive: true });

for (const target of TARGETS) {
  const destination = path.join(FONT_DIR, target.name);
  if (fs.existsSync(destination) && fs.statSync(destination).size > 1_000_000) {
    console.log(`[fonts] 已有 ${target.name}`);
    continue;
  }
  console.log(`[fonts] 下载 ${target.name} …`);
  // 走 GitHub API(raw 直链在部分沙箱被墙), 无需 token 也可以拉公开文件
  execFileSync(
    "curl",
    [
      "-sL",
      "--max-time",
      "300",
      "-H",
      "Accept: application/vnd.github.raw",
      "-o",
      destination,
      `https://api.github.com/repos/${target.repo}/contents/${target.file}`,
    ],
    { stdio: "inherit" }
  );
  const size = fs.statSync(destination).size;
  if (size < 1_000_000) {
    fs.unlinkSync(destination);
    throw new Error(`下载失败: ${target.name} (${size} 字节)`);
  }
  console.log(`[fonts]   → ${(size / 1024 / 1024).toFixed(1)} MB`);
}

// 生成 fontconfig
const template = fs.readFileSync(path.join(ROOT, "tools", "fonts.conf.template"), "utf8");
const conf = template
  .replace("FONT_DIR_PLACEHOLDER", FONT_DIR)
  .replace("FONT_CACHE_PLACEHOLDER", FONT_CACHE);
const confPath = path.join(FONT_CACHE, "fonts.conf");
fs.writeFileSync(confPath, conf);
console.log(`[fonts] fontconfig → ${path.relative(ROOT, confPath)}`);
console.log(`[fonts] 预览渲染时设置 FONTCONFIG_FILE=${confPath}`);
