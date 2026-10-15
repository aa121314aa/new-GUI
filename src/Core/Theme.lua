--[[
	NewGUI · Core/Theme
	配色 + 圆角令牌。圆角是"像素风"的小数值(默认 0.92% 基准轴 ≈ 720p 下约 6px),
	所有控件都从这里取圆角, 想统一改大小只改这一处。
]]

local Scale = require("Core.Scale")

local Theme = {}

--============================ 调色板 ============================--
-- 深色 + 一点霓虹点缀, 适合大多数游戏画面(不刺眼、不和游戏 UI 打架)
Theme.palette = {
	-- 悬浮球
	orb = Color3.fromRGB(24, 26, 34),
	orbHover = Color3.fromRGB(34, 37, 48),
	orbPress = Color3.fromRGB(18, 19, 26),
	orbStroke = Color3.fromRGB(72, 78, 98),
	orbIcon = Color3.fromRGB(236, 238, 245),
	orbGlow = Color3.fromRGB(88, 140, 255),

	-- 窗口
	window = Color3.fromRGB(20, 21, 28),
	windowStroke = Color3.fromRGB(58, 62, 80),
	header = Color3.fromRGB(27, 29, 38),
	sidebar = Color3.fromRGB(24, 26, 34),
	content = Color3.fromRGB(21, 22, 30),
	card = Color3.fromRGB(30, 32, 42),
	cardHover = Color3.fromRGB(37, 40, 52),
	divider = Color3.fromRGB(45, 48, 62),

	-- 文字
	text = Color3.fromRGB(238, 240, 248),
	textDim = Color3.fromRGB(150, 155, 172),
	textFaint = Color3.fromRGB(104, 109, 126),

	-- 强调 / 状态
	accent = Color3.fromRGB(88, 140, 255),
	accentDark = Color3.fromRGB(58, 100, 200),
	success = Color3.fromRGB(72, 199, 142),
	warning = Color3.fromRGB(240, 178, 74),
	danger = Color3.fromRGB(235, 88, 92),

	-- 通用
	black = Color3.fromRGB(0, 0, 0),
	white = Color3.fromRGB(255, 255, 255),
	shadow = Color3.fromRGB(0, 0, 0),
	transparent = Color3.fromRGB(0, 0, 0),
}

--============================ 圆角令牌(百分比) ============================--
-- 想让圆角更方/更圆, 只改这里。像素风 = 数值小。
Theme.radius = {
	window = 1.30, -- 主窗口
	panel = 1.00, -- 卡片 / 面板
	control = 0.92, -- 按钮 / 输入框 / 下拉
	small = 0.70, -- 标签 / 小徽章
	orb = 0.85, -- 悬浮球(长方形, 圆角克制)
	pill = 50, -- 完全胶囊形(用 50% 实现, 不受上面约束)
}

Theme.strokeWidth = {
	thin = 0.11,
	normal = 0.14,
	thick = 0.18,
}

Theme.transparency = {
	window = 0.02,
	scrim = 0.55,
	glow = 0.35,
}

Theme.font = {
	regular = Enum.Font.Gotham,
	medium = Enum.Font.GothamMedium,
	bold = Enum.Font.GothamBold,
	mono = Enum.Font.Code,
}

--============================ 尺寸令牌(全部 = 基准轴百分比) ============================--
Theme.metrics = {
	rowHeight = 5.0, -- 列表行 / 按钮
	controlHeight = 4.4, -- 小控件
	headerHeight = 6.4, -- 窗口标题栏
	labelHeight = 2.4,
	gap = 1.0, -- 控件间距
	gapSmall = 0.6,
	sectionGap = 1.6,
	contentPadding = 1.8,
	-- 字号(百分比)
	fontTitle = 3.0,
	fontBody = 2.45,
	fontSmall = 2.1,
	fontTiny = 1.85,
	-- 控件内部细节
	knobSize = 3.2, -- 开关滑块
	sliderThumb = 2.8,
	iconSize = 2.6,
	tabHeight = 4.6, -- 侧边栏导航项高度
	tabPadding = 0.8,
}

--============================ 自适应圆角 ============================--
--[=[
	给实例加一个"随屏幕百分比变化"的圆角。
		Theme.corner(orb, "orb")   -- 用令牌名
		Theme.corner(orb, 0.85)    -- 直接给百分比
		Theme.corner(up, "pill")   -- 50% 胶囊
	圆角是像素值, 所以内部用 Scale.bind 在屏幕变化时重算。
]=]
function Theme.corner(instance, kind)
	local fixed = type(kind) == "number" and kind or nil
	local tokenName = (not fixed) and (kind or "control") or nil

	local corner = Instance.new("UICorner")
	corner.Parent = instance
	-- 每次重算都重新读令牌 → 运行时改 Theme.radius 后触发 Theme.refresh() 即可生效
	Scale.bind(corner, function()
		local percent = fixed or (Theme.radius[tokenName] or Theme.radius.control)
		if percent >= 50 then
			return { CornerRadius = UDim.new(1, 0) }
		end
		return { CornerRadius = Scale.u(percent) }
	end)
	return corner
end

--[=[ 强制所有绑定重算一次(改主题半径/像素尺寸后调用) ]=]
function Theme.refresh()
	Scale.Changed:Fire(Scale.viewport)
end

--[=[ 统一描边(厚度随屏幕百分比变化) ]=]
function Theme.stroke(parent, color, widthPercent)
	local ui = Instance.new("UIStroke")
	ui.Color = color or Theme.palette.windowStroke
	ui.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ui.LineJoinMode = Enum.LineJoinMode.Round
	ui.Parent = parent
	Scale.bind(ui, function()
		return { Thickness = math.max(1, Scale.px(widthPercent or Theme.strokeWidth.normal)) }
	end)
	return ui
end

--[=[
	给文本设置"百分比字号"(自带上下限钳制)
		Theme.fontSize(label, 3.1, Theme.font.medium)
]=]
function Theme.fontSize(instance, percent, font)
	if font then
		instance.Font = font
	end
	Scale.bind(instance, function()
		return { TextSize = Scale.font(percent) }
	end)
	return instance
end

--[=[ 百分比内边距 ]=]
function Theme.padding(parent, percent)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 0)
	padding.PaddingBottom = UDim.new(0, 0)
	padding.PaddingLeft = UDim.new(0, 0)
	padding.PaddingRight = UDim.new(0, 0)
	padding.Parent = parent
	Scale.bind(padding, function()
		local value = Scale.u(percent)
		return {
			PaddingTop = value,
			PaddingBottom = value,
			PaddingLeft = value,
			PaddingRight = value,
		}
	end)
	return padding
end

--[=[
	整体调色板替换(需要在创建 UI 之前调用, 或之后手动 Refresh)
]=]
function Theme.setPalette(overrides)
	for key, value in pairs(overrides or {}) do
		Theme.palette[key] = value
	end
end

function Theme.setRadius(overrides)
	for key, value in pairs(overrides or {}) do
		Theme.radius[key] = value
	end
end

return Theme
