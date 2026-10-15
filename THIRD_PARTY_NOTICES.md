# 第三方资源说明

本项目界面代码为自有实现，运行时不依赖任何第三方 UI 库。随仓库分发的资源如下：

## 图标资产 — Lucide

- 位置：`dist/assets/icons/*.png`（由 `tools/make_icons.mjs` 从 Lucide 的 SVG 光栅化而来）
- 来源：https://github.com/lucide-icons/lucide （npm 包 `lucide-static`）
- 版本：记录在 `dist/assets/icons/manifest.json`
- 许可：**ISC License**

```
ISC License

Copyright (c) Lucide Icons and Contributors

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
```

`src/Core/Glyph.lua` 中的矢量图标路径同样取自 Lucide，遵循同一许可。

## 预览图字体（不随仓库分发）

- 字体：Noto Sans SC（思源黑体简体）
- 用途：仅 `tools/preview.py` 在本地渲染文档预览图时使用；字体文件由
  `tools/fetch_fonts.mjs` 下载到 `tools/.cache/fonts/`，已被 `.gitignore` 排除。
- 许可：**SIL Open Font License 1.1**

## 构建工具（仅开发环境，不随脚本分发）

- [sharp](https://sharp.pixelplumbing.com/)（Apache-2.0）— SVG → PNG 光栅化
- [lupa](https://github.com/scoder/lupa)（MIT）— 本地/CI 里跑 Lua 语法检查与端到端模拟
- [lucide-static](https://www.npmjs.com/package/lucide-static)（ISC）— 图标源文件
