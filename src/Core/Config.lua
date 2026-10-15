--[[
	NewGUI · Core/Config
	运行时配置。窗口尺寸、悬浮球尺寸等全部按"基准轴百分比"描述。
]]

local Scale = require("Core.Scale")

local Config = {}

--============================ 悬浮球 ============================--
Config.orb = {
	-- 长方形(宽 > 高), 像素风小圆角
	width = 7.6, -- % 基准轴
	height = 6.0, -- % 基准轴
	x = 2.6, -- % 视口宽(贴近左边)
	y = 18.0, -- % 视口高
	zIndex = 1000,
	draggable = true,
	-- 图标
	icon = "sparkle",
	iconSize = 3.1, -- % 基准轴
	-- 圆角/描边
	corner = 0.85, -- % 基准轴(像素风: 小)
	strokeWidth = 0.14,
}

--============================ 主窗口 ============================--
-- width/height/min/max 全部是"视口百分比"(X 按视口宽算, Y 按视口高算)
Config.window = {
	width = 62.0, -- 打开时的宽度 % 视口宽
	height = 58.0, -- 打开时的高度 % 视口高
	minWidth = 30.0, -- 缩放下限 % 视口宽
	minHeight = 34.0, -- 缩放下限 % 视口高
	maxWidth = 94.0, -- 缩放上限 % 视口宽(超宽屏不至于拉满)
	maxHeight = 92.0, -- 缩放上限 % 视口高

	headerHeight = 6.4, -- 标题栏高度 % 基准轴
	statusHeight = 3.4, -- 状态栏高度 % 基准轴
	sidebarRatio = 0.18, -- 侧边栏宽度 = 窗口宽度 × 该比例
	sidebarMin = 11.0, -- 侧边栏最小宽度 % 基准轴
	sidebarMax = 22.0, -- 侧边栏最大宽度 % 基准轴
	corner = 1.30, -- 窗口圆角 % 基准轴(像素风小圆角)
	open = false,
}

--============================ 行为 ============================--
Config.behavior = {
	keybind = Enum.KeyCode.RightControl, -- 开关窗口
	toggleOnOrbClick = true,
	dragThreshold = 4, -- 拖动判定阈值(像素)
	fadeDuration = 0.12, -- 动画时长(秒)
	minimizeOnToggle = false, -- 关闭窗口时是否最小化到悬浮球
	saveLayout = true, -- 记住窗口/悬浮球位置
}

--============================ 资产 ============================--
Config.assets = {
	-- 图标名 → 文件名(null 表示用矢量回退, 不联网)
	icons = {
		sparkle = "sparkle.png",
		grid = "layout-grid.png",
		settings = "settings.png",
		info = "info.png",
		close = "x.png",
		minimize = "minus.png",
		search = "search.png",
		player = "user-round.png",
		sliders = "sliders-horizontal.png",
		terminal = "square-terminal.png",
		check = "check.png",
		chevron = "chevron-down.png",
		arrow = "arrow-right.png",
		bolt = "zap.png",
		eye = "eye.png",
		shield = "shield.png",
		trash = "trash-2.png",
		copy = "copy.png",
		book = "book-open.png",
	},
	-- 图标光栅尺寸(像素)。执行器用 getcustomasset 上传, 太大了浪费
	iconResolution = 128,
	-- 首次运行的远程拉取地址(可选; 本地无资产时自动找)
	remote = {
		enabled = true,
		base = "https://raw.githubusercontent.com/aa121314aa/new-GUI/main/dist/assets/icons/",
		timeoutHint = true,
	},
	-- 执行器工作目录
	folder = "NewGUI",
	iconFolder = "NewGUI/assets/icons",
}

--============================ 开发者 ============================--
Config.dev = {
	debug = false, -- 打印详细日志
	windowId = "NewGUI",
}

--[=[
	百分比 → 像素的工具(转发 Scale, 方便脚本里 Config.px(...) 直接写)
]=]
function Config.px(percent)
	return Scale.px(percent)
end

function Config.u(percent)
	return Scale.u(percent)
end

return Config
