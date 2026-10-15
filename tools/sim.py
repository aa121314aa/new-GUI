#!/usr/bin/env python3
"""
NewGUI 端到端模拟: 在 Roblox 环境桩里真的跑一遍 dist/library.lua,
检查"构建 UI → 切换页面 → 改分辨率 → 下载资产 → 存盘 → 卸载"整条链路。

用法:
    python3 tools/sim.py [--serve-icons dist/assets/icons] [--workdir /tmp/newgui_sim]
"""
import argparse
import http.server
import os
import shutil
import socketserver
import sys
import threading
from pathlib import Path

try:
    from lupa import LuaRuntime
except ImportError:
    print("需要 lupa: pip3 install --break-system-packages lupa")
    sys.exit(2)

ROOT = Path(__file__).resolve().parent.parent
STUB = ROOT / "tools" / "roblox_stub.lua"
BUNDLE = ROOT / "dist" / "library.lua"


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def start_icon_server(directory: Path):
    """把 dist/assets/icons 用本地 HTTP 服务出去, 模拟仓库 raw 下载。"""
    handler = lambda *a, **kw: QuietHandler(*a, directory=str(directory), **kw)
    server = socketserver.TCPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, f"http://127.0.0.1:{server.server_address[1]}/"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--workdir", default="/tmp/newgui_sim")
    parser.add_argument("--serve-icons", default=str(ROOT / "dist" / "assets" / "icons"))
    parser.add_argument("--viewport", default="1280x720")
    parser.add_argument("--offline", action="store_true", help="不启本地图标服务, 验证离线矢量回退")
    parser.add_argument("--autostart", action="store_true", help="改用 dist/NewGUI.lua(自带启动)测试")
    args = parser.parse_args()

    icons_dir = Path(args.serve_icons)
    has_icons = icons_dir.exists() and any(icons_dir.glob("*.png"))

    workdir = Path(args.workdir)
    if workdir.exists():
        shutil.rmtree(workdir)
    workdir.mkdir(parents=True, exist_ok=True)

    server = None
    base_url = "http://127.0.0.1:1/"  # 故意不可达, 用来测回退
    if has_icons and not args.offline:
        server, base_url = start_icon_server(icons_dir)

    width, height = (int(v) for v in args.viewport.split("x"))

    # encoding=None: Lua 字符串 ↔ Python bytes 一一对应(和 Luau 的字节语义一致, PNG 才能正确比对)
    lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)

    # ---- 文件 API(真的落盘到 workdir) ----
    def _text(value):
        if isinstance(value, bytes):
            return value.decode("utf-8", errors="surrogateescape")
        return str(value)

    def _resolve(path):
        return workdir / _text(path).replace("\\", "/")

    def write_file(path, data):
        target = _resolve(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data if isinstance(data, bytes) else _text(data).encode("utf-8"))
        return None

    def read_file(path):
        target = _resolve(path)
        if not target.exists():
            return None
        return target.read_bytes()

    def is_file(path):
        return _resolve(path).is_file()

    def is_folder(path):
        return _resolve(path).is_dir()

    def make_folder(path):
        _resolve(path).mkdir(parents=True, exist_ok=True)
        return None

    # ---- HTTP(request/httpget), 真发请求 ----
    def http_get(url):
        import urllib.request

        if isinstance(url, bytes):
            url = url.decode("utf-8", errors="replace")
        try:
            with urllib.request.urlopen(str(url), timeout=5) as response:
                return response.read()
        except Exception as error:
            print(f"  [sim] HTTP 失败 {url}: {error}")
            return None

    stub = lua.execute(STUB.read_text(encoding="utf-8"))
    stub.writeFile = write_file
    stub.readFile = read_file
    stub.isFile = is_file
    stub.isFolder = is_folder
    stub.makeFolder = make_folder
    stub.httpGet = http_get

    env = stub.install({b"viewportWidth": width, b"viewportHeight": height})

    if args.autostart:
        # 自带启动版本: require 时就建好界面, 这里验证不会抛错且句柄可用
        bundle = (ROOT / "dist" / "NewGUI.lua").read_text(encoding="utf-8")
        lua.globals().__bundle = bundle.encode("utf-8")
        NewGUI = lua.execute("return load(__bundle)()")
        instance = lua.eval("function() return rawget(_G, \"NewGUI\") end")()
        alive = lua.eval(
            """
			function(lib)
				if lib == nil then return false end
				return lib._instance ~= nil and lib._instance.window ~= nil and lib._instance.gui.Parent ~= nil
			end
			"""
        )(instance if instance is not None else NewGUI)
        print(f"[sim] 自动启动模式: {'界面已就绪' if alive else '失败'}")
        if not alive:
            sys.exit(1)
    else:
        bundle = BUNDLE.read_text(encoding="utf-8")
        NewGUI = lua.execute(bundle)

    test = f"""
	local NewGUI = __test_newgui
	local results = {{}}
	local function check(name, condition, detail)
		table.insert(results, {{ name = name, ok = condition and true or false, detail = detail }})
	end

	check("库表结构", type(NewGUI) == "table" and NewGUI.start ~= nil)
	check("版本信息", NewGUI.Version.version ~= nil, NewGUI.Version.version)

	NewGUI.Config.dev.debug = true
	NewGUI.Config.assets.remote.base = "{base_url}"
	NewGUI.Config.assets.folder = "NewGUI"
	NewGUI.Config.assets.iconFolder = "NewGUI/assets/icons"
	-- 自带启动的用例里首次启动时地址还没设对, 这里模拟用户点"重新下载图标资产"
	NewGUI.Assets.retryFailed(true)

	local handle = NewGUI.start({{ title = "模拟测试", openOnStart = true }})
	check("启动成功", handle ~= nil and handle.window ~= nil and handle.orb ~= nil)
	check("GUI 父级", handle.gui ~= nil and handle.gui.Parent ~= nil, handle.parentName)

	-- 百分比缩放自检
	local scale = NewGUI.Scale
	check("缩放基准", math.abs(scale.axis() - {min(width, height)}) < 0.001, scale.axis())
	-- 悬浮球宽 = 基准轴百分比 → 像素(不是视口 scale)
	local orbWidthPx = handle.orb.orb.Size.X.Offset
	local expectedWidthPx = scale.px(NewGUI.Config.orb.width)
	check("悬浮球宽度=基准轴百分比", math.abs(orbWidthPx - expectedWidthPx) < 0.01,
		orbWidthPx .. " vs " .. expectedWidthPx)
	check("悬浮球高宽比", math.abs(handle.orb.orb.Size.Y.Offset - scale.px(NewGUI.Config.orb.height)) < 0.01,
		handle.orb.orb.Size.Y.Offset)
	-- 位置用视口 scale(百分比)
	local orbPos = handle.orb.orb.Position
	check("悬浮球位置=视口百分比", orbPos.X.Scale >= 0 and orbPos.X.Scale <= 1 and orbPos.Y.Scale >= 0 and orbPos.Y.Scale <= 1,
		orbPos.X.Scale .. "," .. orbPos.Y.Scale)
	local expectedCorner = scale.px(NewGUI.Config.orb.corner)
	local corner = nil
	for _, child in ipairs(handle.orb.orb:GetChildren()) do
		if child.ClassName == "UICorner" then
			corner = child.CornerRadius.Offset
		end
	end
	check("圆角为小像素值", corner ~= nil and corner > 0 and corner <= 12, corner)

	-- 页面切换
	local window = handle.window
	check("页面数量", #window.pages >= 5, #window.pages)
	window:SelectPage(3)
	check("切换页面", window.pages[3].scroll.Visible == true and window.pages[1].scroll.Visible == false)
	window:SelectPage(1)

	-- 分辨率变化 → 全部重算(转屏)
	local camera = workspace.CurrentCamera
	camera.ViewportSize = Vector2.new({height}, {width})
	camera:GetPropertyChangedSignal("ViewportSize"):Fire(Vector2.new({height}, {width}))
	check("转屏后基准轴", math.abs(scale.axis() - {min(width, height)}) < 0.001, scale.axis())
	local statusText = window.statusLeft.Text
	check("状态栏跟随刷新", statusText ~= nil and #statusText > 0, statusText)
	camera.ViewportSize = Vector2.new({width}, {height})
	camera:GetPropertyChangedSignal("ViewportSize"):Fire(Vector2.new({width}, {height}))

	-- 资产: 预加载 + 检查落盘
	local done = false
	local names = {{}}
	for name in pairs(NewGUI.Config.assets.icons) do
		table.insert(names, name)
	end
	NewGUI.Assets.preload(names, function()
		done = true
	end)
	check("资产回调完成", done == true)
	local stats = NewGUI.Assets.stats()
	local offline = OFFline_FLAG
	if offline then
		-- 离线: 下载失败 → 回退矢量图标, 界面必须照常工作
		check("离线时资产不可用", type(NewGUI.Assets.path("sparkle")) ~= "string", "fallback")
		local glyphChildren = 0
		for _, child in ipairs(handle.orb.iconHolder:GetChildren()) do
			if child.Name == "Glyph_sparkle" then
				glyphChildren = #child:GetChildren()
			end
		end
		check("矢量图标已绘制", glyphChildren > 0, glyphChildren .. " 条线段")
	else
		check("资产下载/缓存", (stats.downloaded + stats.cached) > 0, stats.downloaded .. "/" .. stats.cached)
		local orbAsset = NewGUI.Assets.path("sparkle")
		check("悬浮球图标可用", type(orbAsset) == "string", orbAsset)
	end

	-- 存盘
	NewGUI.Storage.set("probe", {{ answer = 42 }})
	local raw = readfile("NewGUI/settings.json")
	check("设置已写入", raw ~= nil and string.find(raw, "probe") ~= nil)

	-- 拖动/点击模拟: 直接移动悬浮球位置
	handle.orb.position = {{ x = 0.42, y = 0.33 }}
	handle.orb._applyPosition()
	local position = handle.orb.orb.Position
	check("悬浮球位置为 scale", position.X.Scale == 0.42 and position.Y.Scale == 0.33)

	-- 通知
	handle:Notify({{ title = "测试", text = "通知系统", kind = "success" }})

	-- 连接泄漏检查: 桩里的 UserInputService 记录所有 InputBegan 监听
	local beforeRebuild = 0
	local uis = game:GetService("UserInputService")
	if uis._events and uis._events.InputBegan then
		beforeRebuild = #uis._events.InputBegan._handlers
	end

	-- 关闭 / 重新构建 / 卸载
	window:Close()
	check("关闭窗口", window:IsOpen() == false)
	NewGUI.applyTheme("紫罗兰")
	NewGUI.Theme.refresh()
	local rebuilt = handle:Rebuild()
	check("重建界面", rebuilt ~= nil and rebuilt.window ~= nil)
	rebuilt:Unload()
	check("卸载后句柄失效", NewGUI._instance == nil)

	-- 卸载后所有全局输入监听都应断开
	local afterUnload = 0
	if uis._events and uis._events.InputBegan then
		afterUnload = #uis._events.InputBegan._handlers
	end
	check("全局输入监听已清理", afterUnload == 0, "卸载前 " .. beforeRebuild .. " → 卸载后 " .. afterUnload)

	return results
	"""

    test = test.replace("OFFline_FLAG", "true" if args.offline else "false")
    test = test.replace("{base_url}", base_url).replace("{width}", str(width)).replace("{height}", str(height))
    test = test.replace("{min(width, height)}", str(min(width, height)))

    globals_table = lua.globals()
    globals_table.__test_newgui = NewGUI
    rows = lua.execute(test.encode("utf-8"))

    # lupa(encoding=None) 会把 Lua 字符串/键都映射成 bytes, 这里统一取值
    def field(row, key, default=None):
        for candidate in (key, key.encode("utf-8")):
            if candidate in row:
                value = row[candidate]
                if isinstance(value, bytes):
                    return value.decode("utf-8", errors="replace")
                return value
        return default

    failures = []
    print(f"{'结果':<6} 检查项")
    print("-" * 60)
    for row in rows.values():
        ok = field(row, "ok") is True or field(row, "ok") == 1
        name = field(row, "name", "?")
        detail_value = field(row, "detail")
        status = "PASS" if ok else "FAIL"
        detail = f"  → {detail_value}" if detail_value is not None and not ok else ""
        if not ok:
            failures.append(str(name))
        print(f"{status:<6} {name}{detail}")

    errors = stub.errors
    if errors and len(errors) > 0:
        print("-" * 60)
        print(f"运行期捕获到 {len(errors)} 条错误:")
        for index, err in enumerate(errors.values() if hasattr(errors, "values") else errors, 1):
            print(f"  {index}. {err}")
            failures.append(f"运行错误 {index}")

    icon_files = list((workdir / "NewGUI" / "assets" / "icons").glob("*.png")) if (workdir / "NewGUI").exists() else []
    print("-" * 60)
    print(f"落盘资产: {len(icon_files)} 个 PNG → {workdir}")
    settings = workdir / "NewGUI" / "settings.json"
    print(f"设置文件: {'已生成' if settings.exists() else '未生成'}")

    if server:
        server.shutdown()

    if failures:
        print(f"\n[sim] 失败 {len(failures)} 项: {', '.join(failures)}")
        sys.exit(1)
    print("\n[sim] 全部通过")
    sys.exit(0)


if __name__ == "__main__":
    main()
