#!/usr/bin/env python3
"""
NewGUI 开发入口: make.py <命令>

    build      打包 src → dist (NewGUI.lua / library.lua)
    sim        端到端模拟 + 断言
    preview    渲染预览图(桌面/手机/1080p)
    icons      重新光栅化图标资产(需要 tools/node_modules/sharp)
    fonts      下载预览用中文字体
    check      语法自检(所有 src + dist 模块)
    all        build → sim → preview
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def run(*args, **kwargs):
    print(f"\n$ {' '.join(str(a) for a in args)}")
    return subprocess.run([str(a) for a in args], cwd=ROOT, **kwargs)


def build():
    return run(sys.executable, "tools/build.py")


def sim():
    return run(sys.executable, "tools/sim.py")


def preview():
    results = [
        run(sys.executable, "tools/preview.py"),
        run(sys.executable, "tools/preview.py", "--size", "720x1280", "--name", "phone"),
        run(sys.executable, "tools/preview.py", "--size", "1920x1080", "--name", "desktop-1080p"),
    ]
    return next((r for r in results if r.returncode), results[-1])


def icons():
    return run("node", "make_icons.mjs", cwd=ROOT / "tools")


def fonts():
    return run("node", "fetch_fonts.mjs", cwd=ROOT / "tools")


def check():
    """用 lupa 逐个编译 src 与 dist 的模块, 抓语法错误。"""
    try:
        from lupa import LuaRuntime
    except ImportError:
        print("需要 lupa: pip3 install --break-system-packages lupa")
        return None

    lua = LuaRuntime(unpack_returned_tuples=True)
    compile_only = lua.eval("function(source) return load(source) ~= nil end")
    failures = []
    targets = sorted((ROOT / "src").rglob("*.lua")) + [
        ROOT / "dist" / "NewGUI.lua",
        ROOT / "dist" / "library.lua",
        ROOT / "tools" / "roblox_stub.lua",
        ROOT / "tools" / "mock_render.lua",
    ]
    for path in targets:
        source = path.read_text(encoding="utf-8")
        ok = compile_only(source)
        if not ok:
            failures.append(path)
            print(f"  ✗ {path.relative_to(ROOT)}")
    print(f"[check] 语法检查 {len(targets)} 个文件, 失败 {len(failures)} 个")
    return 1 if failures else 0


def syntax_safe(step):
    """跑目标前先做语法检查, 有问题直接返回非 0。"""
    rc = check()
    if rc:
        print("[make] 语法检查未通过, 中止")
        return rc
    return step()


COMMANDS = {
    "build": lambda: syntax_safe(build),
    "sim": lambda: syntax_safe(lambda: (build().returncode or 0) or sim().returncode),
    "preview": preview,
    "icons": icons,
    "fonts": fonts,
    "check": check,
    "all": lambda: syntax_safe(lambda: (build().returncode or 0) or sim().returncode or preview().returncode),
}


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "all"
    if command not in COMMANDS:
        print(__doc__)
        return 2
    result = COMMANDS[command]()
    return result if isinstance(result, int) else (result.returncode if result else 0)


if __name__ == "__main__":
    sys.exit(main())
