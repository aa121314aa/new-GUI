#!/usr/bin/env python3
"""
NewGUI 构建脚本: 把 src/ 下的模块打成一个可执行器直接运行的 dist/NewGUI.lua。

做法: 把每个模块包成工厂函数放进 __modules 表, 用自带的 require 解析 "Core.Scale" 这种模块名。
不用 Roblox 的 require(执行器环境里没有 ModuleScript)。
"""
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
DIST = ROOT / "dist"

REQUIRE_PATTERN = re.compile(r'require\(\s*(["\'])([A-Za-z0-9_.\-/]+)\1\s*\)')


def module_name(path: Path) -> str:
    rel = path.relative_to(SRC).with_suffix("")
    return ".".join(rel.parts)


def module_key(name: str) -> str:
    return name.replace(".", "_")


def read_modules():
    modules = {}
    for path in sorted(SRC.rglob("*.lua")):
        name = module_name(path)
        source = path.read_text(encoding="utf-8")
        source = REQUIRE_PATTERN.sub(lambda m: f'require({m.group(1)}{module_key(m.group(2))}{m.group(1)})', source)
        modules[name] = source
    return modules


def build_bundle(entry="init", autostart=True):
    modules = read_modules()
    if entry not in modules:
        raise SystemExit(f"找不到入口模块 {entry} (可用: {sorted(modules)})")

    parts = []
    parts.append(
        """--[[
	NewGUI  —  百分比自适应的 Roblox 客户端 UI 库(执行器专用)
	本文件由 tools/build.py 自动生成, 请勿手改; 改源码请改 src/ 下的模块。

	用法:
		loadstring(game:HttpGet("https://raw.githubusercontent.com/aa121314aa/new-GUI/main/dist/NewGUI.lua"))()
	版本: 见 NewGUI.Version
]]

local __modules = {}
local __cache = {}

local function require(name)
	local cached = __cache[name]
	if cached ~= nil then
		return cached
	end
	local factory = __modules[name]
	if factory == nil then
		error("[NewGUI] 模块不存在: " .. tostring(name) .. " (打包遗漏?)", 2)
	end
	local result = factory()
	if result == nil then
		result = true
	end
	__cache[name] = result
	return result
end

"""
    )

    for name in sorted(modules):
        parts.append(f"__modules[{module_key(name)!r}] = function()\n")
        parts.append(modules[name].rstrip("\n"))
        parts.append("\nend\n\n")

    if autostart:
        parts.append(f"return require({module_key(entry)!r})\n")
    else:
        parts.append("rawget(_G, \"NEWGUI_NO_AUTOSTART\")\n")
        parts.append(f"return require({module_key(entry)!r})\n")

    return "".join(parts)


def main():
    DIST.mkdir(exist_ok=True)
    autostart = build_bundle("init", autostart=True)
    (DIST / "NewGUI.lua").write_text(autostart, encoding="utf-8")

    library_body = autostart.replace(
        "local __modules = {}",
        'local __prevFlag = rawget(_G, "NEWGUI_NO_AUTOSTART")\nrawset(_G, "NEWGUI_NO_AUTOSTART", true)\nlocal __modules = {}',
        1,
    )
    library_body = library_body.replace(
        'return require("init")\n',
        'local __result = require("init")\nrawset(_G, "NEWGUI_NO_AUTOSTART", __prevFlag)\nreturn __result\n',
    )
    (DIST / "library.lua").write_text(library_body, encoding="utf-8")

    size_kb = len(autostart.encode("utf-8")) / 1024
    print(f"[build] dist/NewGUI.lua  ({size_kb:.1f} KB)")
    print(f"[build] dist/library.lua")


if __name__ == "__main__":
    main()
