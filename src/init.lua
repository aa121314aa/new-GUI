--[[
	NewGUI · init
	入口: 起悬浮球 + 主窗口。

	执行器里直接用:
		local NewGUI = loadstring(game:HttpGet(".../dist/NewGUI.lua"))()
		-- 或者只拿库: local lib = loadstring(...)()
		-- NewGUI.Orb / NewGUI.Window / NewGUI.Widgets / NewGUI.Theme / NewGUI.Config 都可单独用

	可选参数:
		start({
			title = "我的脚本", subtitle = "v1.0",
			pages = { ... },              -- 追加自定义页面
			openOnStart = false,          -- 启动就展开窗口
			global = true,                -- 挂 getgenv().NewGUI
			theme = "紫罗兰",
		})
]]

local Config = require("Core.Config")
local Scale = require("Core.Scale")
local Theme = require("Core.Theme")
local Compat = require("Core.Compat")
local Storage = require("Core.Storage")
local Assets = require("Core.Assets")
local Version = require("Version")
local Signal = require("Core.Signal")
local Util = require("Core.Util")

local Orb = require("Components.Orb")
local Window = require("UI.Window")
local Widgets = require("UI.Widgets")
local Pages = require("UI.Pages")
local Notify = require("UI.Notify")
local Glyph = require("Core.Glyph")

local NewGUI = {
	Version = Version,
	Config = Config,
	Scale = Scale,
	Theme = Theme,
	Compat = Compat,
	Storage = Storage,
	Assets = Assets,
	Signal = Signal,
	Util = Util,
	Glyph = Glyph,
	Orb = Orb,
	Window = Window,
	Widgets = Widgets,
	Pages = Pages,
	Notify = Notify,

	Ready = Signal.new("NewGUI.Ready"),
	Unloaded = Signal.new("NewGUI.Unloaded"),

	_instance = nil,
}

--============================ 主题预设 ============================--
local THEME_PRESETS = {
	["霓虹蓝"] = {
		accent = Color3.fromRGB(88, 140, 255),
		accentDark = Color3.fromRGB(58, 100, 200),
		orbGlow = Color3.fromRGB(88, 140, 255),
		orbStroke = Color3.fromRGB(72, 78, 98),
	},
	["紫罗兰"] = {
		accent = Color3.fromRGB(150, 110, 255),
		accentDark = Color3.fromRGB(110, 78, 210),
		orbGlow = Color3.fromRGB(150, 110, 255),
		orbStroke = Color3.fromRGB(84, 76, 120),
	},
	["薄荷绿"] = {
		accent = Color3.fromRGB(72, 199, 142),
		accentDark = Color3.fromRGB(46, 150, 104),
		orbGlow = Color3.fromRGB(72, 199, 142),
		orbStroke = Color3.fromRGB(70, 104, 90),
	},
	["橙金"] = {
		accent = Color3.fromRGB(240, 178, 74),
		accentDark = Color3.fromRGB(190, 132, 42),
		orbGlow = Color3.fromRGB(240, 178, 74),
		orbStroke = Color3.fromRGB(110, 92, 60),
	},
	["玫红"] = {
		accent = Color3.fromRGB(235, 96, 140),
		accentDark = Color3.fromRGB(186, 62, 104),
		orbGlow = Color3.fromRGB(235, 96, 140),
		orbStroke = Color3.fromRGB(110, 70, 88),
	},
}

function NewGUI.applyTheme(name)
	local preset = THEME_PRESETS[name]
	if not preset then
		return false
	end
	for key, value in pairs(preset) do
		Theme.palette[key] = value
	end
	Storage.set("theme", name)
	return true
end

--============================ 启动 ============================--
local function buildScreenGui(parent)
	local gui = Instance.new("ScreenGui")
	gui.Name = "NewGUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = Config.dev.displayOrder or 999
	gui.Enabled = true
	gui.Parent = parent
	return gui
end

--[=[
	NewGUI.start(opts) → 手柄对象
]=]
function NewGUI.start(opts)
	if NewGUI._instance then
		NewGUI._instance:Unload()
	end
	opts = opts or {}

	-- 主题(优先参数 → 存档)
	local themeName = opts.theme or Storage.get("theme", "霓虹蓝")
	NewGUI.applyTheme(themeName)

	-- 缩放系统
	Scale.Init()

	-- GUI 父级
	local parent, parentName = Compat.GuiParent()
	Compat.Elevate()
	local screenGui = buildScreenGui(parent)
	Compat.Protect(screenGui)

	local handle = {
		gui = screenGui,
		parentName = parentName,
		executor = Compat.Detect().name,
		version = Version.version,
		destroyed = false,
	}

	local ctx = {
		notify = function(config)
			return Notify.send(screenGui, config)
		end,
		reload = function()
			handle:Rebuild()
		end,
		unload = function()
			handle:Unload()
		end,
	}

	------------------ 悬浮球 ------------------
	local orb = Orb.new(screenGui)
	handle.orb = orb
	ctx.orb = orb

	local window = Window.new(screenGui, {
		title = opts.title or Version.name,
		subtitle = opts.subtitle or ("v" .. Version.version .. " · " .. Compat.Detect().name),
		icon = opts.icon or "sparkle",
	})
	handle.window = window

	-- 页面
	Pages.install(window, ctx)
	for _, page in ipairs(opts.pages or {}) do
		window:AddPage({
			name = page.name,
			icon = page.icon,
			build = function(scroll)
				page.build(scroll, window, ctx)
			end,
		})
	end
	window:BuildNavigation()

	orb.Activated:Connect(function()
		if Config.behavior.toggleOnOrbClick then
			window:Toggle(orb.position)
		end
	end)
	window.onMinimize = function()
		orb:SetVisible(true)
	end

	------------------ 状态栏 ------------------
	local stats = Assets.stats()
	window:SetStatus(
		string.format("%s · %s · 基准 %dpx", Config.dev.windowId, Compat.Detect().name, math.floor(Scale.axis())),
		string.format("v%s%s", Version.version, stats.downloaded > 0 and (" · 资产 " .. stats.downloaded) or "")
	)
	Scale.onChange(function()
		window:SetStatus(
			string.format(
				"%s · %s · 基准 %dpx",
				Config.dev.windowId,
				Compat.Detect().name,
				math.floor(Scale.axis())
			)
		)
	end)

	------------------ 生命周期 ------------------
	function handle:Rebuild()
		local wasOpen = window:IsOpen()
		handle:Unload(true)
		local nextHandle = NewGUI.start(opts)
		if wasOpen and nextHandle then
			nextHandle.window:Open(nextHandle.orb.position)
		end
		return nextHandle
	end

	function handle:Unload(silent)
		if self.destroyed then
			return
		end
		self.destroyed = true
		Notify.clear()
		pcall(function()
			window:Destroy()
		end)
		pcall(function()
			orb:Destroy()
		end)
		pcall(function()
			screenGui:Destroy()
		end)
		NewGUI._instance = nil
		if not silent then
			NewGUI.Unloaded:Fire()
		end
	end

	-- 句柄方法(用标准写法, 兼容所有环境)
	handle.SetSubtitle = function(_, text)
		window:SetSubtitle(text)
	end
	handle.Notify = function(_, config)
		return Notify.send(screenGui, config)
	end
	handle.Open = function(_)
		return window:Open(orb.position)
	end
	handle.Close = function(_)
		return window:Close()
	end
	handle.AddPage = function(_, page)
		window:AddPage(page)
		window:BuildNavigation()
		return handle
	end
	handle.GetWindow = function(_)
		return window
	end
	handle.GetOrb = function(_)
		return orb
	end

	NewGUI._instance = handle

	-- 挂全局(方便脚本后续调用 NewGUI.Notify 等)
	if opts.global ~= false then
		local env = Compat.Env()
		pcall(function()
			env.NewGUI = NewGUI
		end)
	end

	-- 预加载关键图标(不阻塞启动)
	Assets.preload({ "sparkle", "grid", "settings", "x", "minus", "info", "bolt" })

	if opts.openOnStart or Config.window.open then
		window:Open(orb.position)
	end

	-- 首帧后刷新一次(此时相机/视口一定就绪)
	Compat.Delay(0.2, function()
		Scale.Refresh()
		Scale.Changed:Fire(Scale.viewport)
		if Config.dev.debug then
			print(string.format(
				"[NewGUI] 启动完成 · 执行器=%s · GUI父级=%s · 视口=%dx%d · 基准=%.0fpx",
				Compat.Detect().name,
				parentName,
				Scale.viewport.X,
				Scale.viewport.Y,
				Scale.axis()
			))
		end
	end)

	NewGUI.Ready:Fire(handle)
	return handle
end

--[=[
	require 后自动启动(执行器里 loadstring(...)() 即可直接看到界面)。
	只想要库、不想自动起界面时:
		local NewGUI = loadstring(game:HttpGet(".../dist/NewGUI.lua"))()
		-- 上面这句已经启动了; 若要纯库模式, 用 dist/library.lua
]=]
if not rawget(_G, "NEWGUI_NO_AUTOSTART") then
	local ok, err = pcall(function()
		return NewGUI.start()
	end)
	if not ok then
		warn("[NewGUI] 启动失败: " .. tostring(err))
	end
end

return NewGUI
