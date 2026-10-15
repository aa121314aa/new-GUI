#!/usr/bin/env python3
"""
NewGUI 预览渲染: 在 Roblox 环境桩里构建真实界面 → 解析布局 → 输出 SVG/PNG。

用法:
    python3 tools/preview.py                          # 桌面 1280x720
    python3 tools/preview.py --size 720x1280 --name phone
    python3 tools/preview.py --only orb                # 只画悬浮球(关掉窗口)
    python3 tools/preview.py --theme 紫罗兰
"""
import argparse
import base64
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lupa import LuaRuntime  # noqa: E402
from sim import start_icon_server  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--size", default="1280x720")
    parser.add_argument("--name", default="preview")
    parser.add_argument("--out-dir", default=str(ROOT / "docs" / "images"))
    parser.add_argument("--theme", default="霓虹蓝")
    parser.add_argument("--only", default="all", choices=["all", "orb", "window"])
    parser.add_argument("--scale", default="1")
    parser.add_argument("--workdir", default="/tmp/newgui_preview")
    parser.add_argument("--no-png", action="store_true")
    args = parser.parse_args()

    width, height = (int(value) for value in args.size.split("x"))
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    workdir = Path(args.workdir)
    if workdir.exists():
        shutil.rmtree(workdir)
    workdir.mkdir(parents=True, exist_ok=True)

    server, base_url = start_icon_server(ROOT / "dist" / "assets" / "icons")
    lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
    stub = lua.execute((ROOT / "tools" / "roblox_stub.lua").read_text(encoding="utf-8"))

    # ---- 执行器文件 API(真的落盘) ----
    def to_text(value):
        return value.decode("utf-8", "surrogateescape") if isinstance(value, bytes) else str(value)

    def resolve(path):
        return workdir / to_text(path).replace("\\", "/")

    def write_file(path, data):
        target = resolve(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data if isinstance(data, bytes) else to_text(data).encode())
        return None

    def read_file(path):
        target = resolve(path)
        return target.read_bytes() if target.exists() else None

    stub.writeFile = write_file
    stub.readFile = read_file
    stub.isFile = lambda path: resolve(path).is_file()
    stub.isFolder = lambda path: resolve(path).is_dir()

    def make_folder(path):
        resolve(path).mkdir(parents=True, exist_ok=True)
        return None

    def http_get(url):
        import urllib.request

        if isinstance(url, bytes):
            url = url.decode("utf-8", "replace")
        try:
            with urllib.request.urlopen(url, timeout=5) as response:
                return response.read()
        except Exception:
            return None

    stub.makeFolder, stub.httpGet = make_folder, http_get
    stub.install({b"viewportWidth": width, b"viewportHeight": height})

    renderer = lua.execute((ROOT / "tools" / "mock_render.lua").read_text(encoding="utf-8"))

    lua.globals().NEWGUI_NO_AUTOSTART = True
    lib = lua.execute((ROOT / "dist" / "library.lua").read_text(encoding="utf-8"))
    lua.globals().__lib = lib
    lua.globals().__renderer = renderer

    # 中文必须以 UTF-8 字节传给 lupa(encoding=None 时 str 会按 latin-1 处理)
    lua.execute(
        f"""
		local lib = __lib
		lib.Config.assets.remote.base = "{base_url}"
		lib.applyTheme("{args.theme}")
		__handle = lib.start({{ title = "NewGUI 演示", subtitle = "百分比自适应 · %s", openOnStart = true }})
		""".replace("%s", args.size).encode("utf-8")
    )

    if args.only == "orb":
        lua.execute("__handle:Close()")

    # ---- 图片映射: rbxasset 路径 → base64 data URI ----
    image_map = {}
    for png in sorted(workdir.rglob("*.png")):
        key = f"rbxasset://stub/{png.relative_to(workdir).as_posix()}"
        image_map[key] = "data:image/png;base64," + base64.b64encode(png.read_bytes()).decode()

    # lupa(encoding=None) 下, 直接给 Lua 表赋 Python 值会变成 POBJECT;
    # 通过"函数调用参数"传入才会正确转换成 Lua 字符串。
    set_entry = lua.eval("function(map, key, value) map[key] = value end")
    image_table = lua.table()
    for key, value in image_map.items():
        set_entry(image_table, key.encode("utf-8"), value.encode("utf-8"))
    renderer.setImageMap(image_table)

    handle_gui = lua.eval("function() return __handle.gui end")
    svg = renderer.toSvg(handle_gui(), width, height, "#20242E")
    if isinstance(svg, bytes):
        svg = svg.decode("utf-8", "replace")

    svg_path = out_dir / f"{args.name}.svg"
    svg_path.write_text(svg, encoding="utf-8")
    print(f"[preview] SVG → {svg_path.relative_to(ROOT)} ({width}x{height}, {len(svg) // 1024} KB)")

    if not args.no_png:
        png_path = out_dir / f"{args.name}.png"
        env = dict(os.environ)
        fontconfig = ROOT / "tools" / ".cache" / "fontconfig" / "fonts.conf"
        if fontconfig.exists():
            env["FONTCONFIG_FILE"] = str(fontconfig)
        subprocess.run(
            ["node", str(ROOT / "tools" / "svg2png.mjs"), str(svg_path), str(png_path), args.scale],
            cwd=ROOT / "tools",
            check=True,
            env=env,
        )
        print(f"[preview] PNG → {png_path.relative_to(ROOT)}")

    server.shutdown()


if __name__ == "__main__":
    main()
