--[[
	NewGUI · UI/Widgets
	控件库。所有控件:
		· 宽度/高度用百分比(基准轴), 位置用 scale → 随屏幕大小自动变化
		· 圆角/字号/描边用 Theme 的像素级绑定 → 屏幕变化时重算
		· 没有 emoji, 图标走 Assets(图片) → Glyph(矢量) 双通道

	返回的控件对象都是 table, 带 :Set(...) 之类的小方法, 不直接暴露实例细节,
	需要底层实例时用 object.instance。
]]

local Scale = require("Core.Scale")
local Theme = require("Core.Theme")
local Glyph = require("Core.Glyph")
local Assets = require("Core.Assets")
local Util = require("Core.Util")

local Widgets = {}
local metrics = Theme.metrics
local palette = Theme.palette

--============================ 内部工具 ============================--
--[=[
	创建实例。属性逐个 pcall 设置: 不同 Roblox 版本/执行器支持的属性集合不一样,
	缺一个属性不应该让整个控件挂掉(仅调试模式下提示)。
]=]
local function newInstance(kind, parent, props)
	local instance = Instance.new(kind)
	for key, value in pairs(props or {}) do
		local ok, err = pcall(function()
			instance[key] = value
		end)
		if not ok then
			warn("[NewGUI] 属性不支持已跳过: " .. kind .. "." .. key .. " (" .. tostring(err) .. ")")
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

--[=[ 所有控件共用的"卡片底" ]=]
local function card(instance, cornerKind, strokeColor)
	instance.BorderSizePixel = 0
	Theme.corner(instance, cornerKind or "control")
	if strokeColor ~= false then
		Theme.stroke(instance, strokeColor or palette.windowStroke, Theme.strokeWidth.thin)
	end
	return instance
end

--[=[ 高度 = 基准轴百分比 ]=]
local function heightOf(instance, percent)
	Scale.bind(instance, function()
		return { Size = UDim2.new(1, 0, 0, Scale.px(percent)) }
	end)
	return instance
end

--[=[ 图标: 有图片用图片, 没有用矢量 ]=]
local function attachIcon(parent, iconName, opts)
	opts = opts or {}
	local holder = newInstance("Frame", parent, {
		Name = "Icon",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
	})
	Scale.bind(holder, function()
		local side = Scale.px(opts.size or metrics.iconSize)
		if opts.heightPercent then
			side = math.min(side, Scale.px(opts.heightPercent) * 0.62)
		end
		return {
			Size = UDim2.fromOffset(side, side),
		}
	end)

	local color = opts.color or palette.textDim
	local glyph = Glyph.draw(holder, iconName, { color = color, stroke = 2, padding = 8 })

	local image = newInstance("ImageLabel", holder, {
		Name = "Image",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ImageTransparency = 1,
		Visible = false,
		ZIndex = holder.ZIndex + 1,
	})

	Assets.load(iconName, function(asset)
		if not asset or not holder.Parent then
			return
		end
		image.Image = asset
		image.ImageColor3 = color
		image.Visible = true
		Util.tween(image, { ImageTransparency = 0 }, 0.15)
		if glyph then
			glyph.instance.Visible = false
		end
	end)

	return holder, glyph, image
end
Widgets.attachIcon = attachIcon

--============================ 分隔线 / 间距 ============================--
function Widgets.separator(parent, opts)
	opts = opts or {}
	local line = newInstance("Frame", parent, {
		Name = "Separator",
		BackgroundColor3 = palette.divider,
		BorderSizePixel = 0,
		LayoutOrder = opts.order or 0,
	})
	heightOf(line, opts.thickness or 0.14)
	return line
end

--[=[ 纵向列表容器(自动间距 + 自动内边距) ]=]
function Widgets.list(parent, opts)
	opts = opts or {}
	local holder = newInstance("Frame", parent, {
		Name = opts.name or "List",
		BackgroundTransparency = 1,
		Size = opts.size or UDim2.fromScale(1, 1),
	})
	if opts.position then
		holder.Position = opts.position
	end
	local layout = newInstance("UIListLayout", holder, {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = opts.align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = opts.verticalAlign or Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, 0),
	})
	Scale.bind(layout, function()
		return { Padding = UDim.new(0, Scale.px(opts.gap or metrics.gap)) }
	end)
	if opts.padding ~= false and opts.padding ~= nil then
		Theme.padding(holder, opts.padding)
	end
	return holder, layout
end

--============================ 文本 ============================--
--[=[
	Widgets.label(parent, "文本", { font = "body", color = "text", align = Enum.TextXAlignment.Left })
	字号关键字: title / body / small / tiny
]=]
function Widgets.label(parent, text, opts)
	opts = opts or {}
	local fontMap = {
		title = { metrics.fontTitle, Theme.font.medium },
		body = { metrics.fontBody, Theme.font.regular },
		small = { metrics.fontSmall, Theme.font.regular },
		tiny = { metrics.fontTiny, Theme.font.regular },
	}
	local entry = fontMap[opts.font or "body"]
	local wrapped = opts.wrapped == true
	local label = newInstance("TextLabel", parent, {
		Name = opts.name or "Label",
		BackgroundTransparency = 1,
		Text = text or "",
		TextColor3 = opts.color or palette.text,
		TextXAlignment = opts.align or Enum.TextXAlignment.Left,
		TextYAlignment = wrapped and Enum.TextYAlignment.Top or (opts.verticalAlign or Enum.TextYAlignment.Center),
		TextWrapped = wrapped,
		TextTruncate = wrapped and nil or Enum.TextTruncate.AtEnd,
		RichText = false,
		LayoutOrder = opts.order or 0,
		Size = opts.size or UDim2.new(1, 0, 0, 0),
	})
	Theme.fontSize(label, opts.fontPercent or entry[1], opts.fontFace or entry[2])
	if not opts.size then
		heightOf(label, opts.height or metrics.labelHeight)
	end
	return label
end

--============================ 按钮 ============================--
--[=[
	Widgets.button(parent, "执行", {
		icon = "bolt",
		variant = "primary" | "ghost" | "danger",
		callback = function() end,
	})
]=]
function Widgets.button(parent, text, opts)
	opts = opts or {}
	local variant = opts.variant or "default"
	local background = opts.background
	if not background then
		if variant == "primary" then
			background = palette.accent
		elseif variant == "danger" then
			background = palette.danger
		elseif variant == "ghost" then
			background = palette.card
		else
			background = palette.card
		end
	end

	local button = newInstance("TextButton", parent, {
		Name = opts.name or "Button",
		BackgroundColor3 = background,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = opts.order or 0,
		Size = opts.size or UDim2.new(1, 0, 0, 0),
	})
	card(button, opts.corner or "control")
	Theme.padding(button, opts.padding or 1.0)
	if not opts.size then
		heightOf(button, opts.height or metrics.rowHeight)
	end

	local textLabel
	local iconHolder
	if opts.icon then
		iconHolder = attachIcon(button, opts.icon, {
			size = opts.iconSize or metrics.iconSize,
			color = opts.iconColor or palette.text,
			heightPercent = opts.height or metrics.rowHeight,
		})
		iconHolder.Position = UDim2.fromScale(opts.iconAtLeft == false and 1 or 0, 0.5)
		iconHolder.AnchorPoint = Vector2.new(opts.iconAtLeft == false and 1 or 0, 0.5)
	end

	textLabel = newInstance("TextLabel", button, {
		Name = "Text",
		BackgroundTransparency = 1,
		Text = text or "",
		TextColor3 = opts.textColor or palette.text,
		Font = opts.font or Theme.font.medium,
		TextXAlignment = opts.align or Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromScale(1, 1),
	})
	Theme.fontSize(textLabel, opts.fontPercent or metrics.fontBody)

	local hoverColor = opts.hoverColor
	if not hoverColor then
		if variant == "primary" then
			hoverColor = palette.accent:Lerp(palette.white, 0.12)
		elseif variant == "danger" then
			hoverColor = palette.danger:Lerp(palette.white, 0.12)
		else
			hoverColor = palette.cardHover
		end
	end

	local enabled = true
	local object = { instance = button, textLabel = textLabel, icon = iconHolder }
	local baseColor = background

	button.MouseEnter:Connect(function()
		if enabled then
			Util.tween(button, { BackgroundColor3 = hoverColor }, 0.1)
		end
	end)
	button.MouseLeave:Connect(function()
		if enabled then
			Util.tween(button, { BackgroundColor3 = baseColor }, 0.12)
		end
	end)
	button.MouseButton1Down:Connect(function()
		if enabled then
			Util.tween(button, { BackgroundColor3 = baseColor:Lerp(palette.black, 0.25) }, 0.06)
		end
	end)
	button.MouseButton1Up:Connect(function()
		if enabled then
			Util.tween(button, { BackgroundColor3 = hoverColor }, 0.08)
		end
	end)
	button.MouseButton1Click:Connect(function()
		if enabled and opts.callback then
			local ok, err = pcall(opts.callback, object)
			if not ok then
				warn("[NewGUI] 按钮回调报错: " .. tostring(err))
			end
		end
	end)

	function object:SetText(value)
		textLabel.Text = value
		return self
	end

	function object:SetEnabled(value)
		enabled = value == true
		button.TextColor3 = palette.textFaint
		textLabel.TextColor3 = enabled and (opts.textColor or palette.text) or palette.textFaint
		button.BackgroundTransparency = enabled and 0 or 0.45
		return self
	end

	function object:Destroy()
		button:Destroy()
	end

	return object
end

--[=[
	纯图标按钮(用于标题栏关闭/最小化)
]=]
function Widgets.iconButton(parent, iconName, opts)
	opts = opts or {}
	local button = newInstance("TextButton", parent, {
		Name = opts.name or "IconButton",
		BackgroundColor3 = opts.background or palette.card,
		BackgroundTransparency = opts.transparent and 1 or 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = opts.order or 0,
	})
	card(button, opts.corner or "small")
	Scale.bind(button, function()
		local side = Scale.px(opts.size or metrics.controlHeight)
		return { Size = opts.size and UDim2.fromOffset(side, side) or UDim2.fromOffset(side, side) }
	end)

	attachIcon(button, iconName, {
		size = (opts.iconSize or metrics.iconSize * 0.8),
		color = opts.iconColor or palette.textDim,
	})

	local hoverColor = opts.hoverColor or palette.cardHover
	button.MouseEnter:Connect(function()
		Util.tween(button, { BackgroundColor3 = hoverColor, BackgroundTransparency = 0 }, 0.1)
	end)
	button.MouseLeave:Connect(function()
		Util.tween(button, {
			BackgroundColor3 = opts.background or palette.card,
			BackgroundTransparency = opts.transparent and 1 or 0,
		}, 0.12)
	end)
	button.MouseButton1Click:Connect(function()
		if opts.callback then
			local ok, err = pcall(opts.callback)
			if not ok then
				warn("[NewGUI] 图标按钮报错: " .. tostring(err))
			end
		end
	end)

	return { instance = button, Destroy = function()
		button:Destroy()
	end }
end

--============================ 开关 ============================--
function Widgets.toggle(parent, opts)
	opts = opts or {}
	local row = newInstance("Frame", parent, {
		Name = opts.name or "Toggle",
		BackgroundColor3 = palette.card,
		LayoutOrder = opts.order or 0,
		Size = UDim2.new(1, 0, 0, 0),
	})
	card(row, "control")
	Theme.padding(row, 1.0)
	heightOf(row, opts.height or metrics.rowHeight)

	-- 左侧图标 + 文本
	if opts.icon then
		local icon = attachIcon(row, opts.icon, { size = opts.iconSize or metrics.iconSize, heightPercent = opts.height or metrics.rowHeight, color = opts.iconColor or palette.textDim })
		icon.Position = UDim2.fromScale(0.012, 0.5)
	end

	local label = newInstance("TextLabel", row, {
		Name = "Label",
		BackgroundTransparency = 1,
		Text = opts.text or "",
		TextColor3 = palette.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromScale(opts.icon and 0.62 or 0.7, 1),
		Position = UDim2.fromScale(opts.icon and 0.075 or 0.012, 0),
	})
	Theme.fontSize(label, metrics.fontBody, Theme.font.medium)

	-- 右侧开关
	local track = newInstance("Frame", row, {
		Name = "Track",
		BackgroundColor3 = palette.cardHover,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.985, 0.5),
	})
	Theme.corner(track, "pill")
	Scale.bind(track, function()
		local heightPx = Scale.px(opts.height or metrics.rowHeight) * 0.5
		local knob = math.max(heightPx * 0.72, 6)
		return {
			Size = UDim2.fromOffset(knob * 1.9, knob),
		}
	end)

	local knob = newInstance("Frame", track, {
		Name = "Knob",
		BackgroundColor3 = palette.white,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.22, 0.5),
	})
	Theme.corner(knob, "pill")
	Scale.bind(knob, function()
		local heightPx = Scale.px(opts.height or metrics.rowHeight) * 0.5
		local size = math.max(heightPx * 0.74, 6)
		return { Size = UDim2.fromOffset(size, size) }
	end)

	local state = opts.default == true
	local object = { instance = row, value = state }

	local function render(animate)
		local color = state and palette.accent or palette.cardHover
		if animate then
			Util.tween(track, { BackgroundColor3 = color }, 0.12)
		else
			track.BackgroundColor3 = color
		end
		-- 旋钮位置: 关=0.22, 开=0.78(两端留出半径)
		local target = UDim2.fromScale(state and 0.78 or 0.22, 0.5)
		if animate then
			Util.tween(knob, { Position = target }, 0.12)
		else
			knob.Position = target
		end
	end

	local function setValue(value, animate)
		state = value == true
		object.value = state
		render(animate)
		if opts.changed then
			local ok, err = pcall(opts.changed, state, object)
			if not ok then
				warn("[NewGUI] toggle.changed 报错: " .. tostring(err))
			end
		end
	end

	local clickArea = newInstance("TextButton", row, {
		Name = "ClickArea",
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = row.ZIndex + 4,
	})
	clickArea.MouseButton1Click:Connect(function()
		setValue(not state, true)
	end)
	clickArea.MouseEnter:Connect(function()
		Util.tween(row, { BackgroundColor3 = palette.cardHover }, 0.1)
	end)
	clickArea.MouseLeave:Connect(function()
		Util.tween(row, { BackgroundColor3 = palette.card }, 0.12)
	end)

	function object:Set(value)
		setValue(value, true)
		return self
	end

	function object:Get()
		return state
	end

	render(false)
	return object
end

--============================ 滑块 ============================--
function Widgets.slider(parent, opts)
	opts = opts or {}
	local min = opts.min or 0
	local max = opts.max or 100
	local step = opts.step
	local value = math.clamp(opts.default or min, min, max)

	local row = newInstance("Frame", parent, {
		Name = opts.name or "Slider",
		BackgroundTransparency = 1,
		LayoutOrder = opts.order or 0,
		Size = UDim2.new(1, 0, 0, 0),
	})
	Scale.bind(row, function()
		local base = Scale.px(opts.height or metrics.rowHeight)
		return { Size = UDim2.new(1, 0, 0, base) }
	end)

	if opts.text then
		local label = newInstance("TextLabel", row, {
			Name = "Label",
			BackgroundTransparency = 1,
			Text = opts.text,
			TextColor3 = palette.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromScale(0.62, 0.5),
			Position = UDim2.fromScale(0.01, 0),
		})
		Theme.fontSize(label, metrics.fontSmall, Theme.font.regular)
	end

	local valueLabel = newInstance("TextLabel", row, {
		Name = "Value",
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = opts.valueColor or palette.accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromScale(0.36, 0.5),
		Position = UDim2.fromScale(0.63, 0),
	})
	Theme.fontSize(valueLabel, metrics.fontSmall, Theme.font.mono)

	local track = newInstance("Frame", row, {
		Name = "Track",
		BackgroundColor3 = palette.cardHover,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.01, 0, 1, 0),
		Size = UDim2.fromScale(0.98, 0.28),
	})
	Theme.corner(track, "pill")

	local fill = newInstance("Frame", track, {
		Name = "Fill",
		BackgroundColor3 = palette.accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
	})
	Theme.corner(fill, "pill")

	local thumb = newInstance("Frame", track, {
		Name = "Thumb",
		BackgroundColor3 = palette.white,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
	})
	Theme.corner(thumb, "pill")
	Scale.bind(thumb, function()
		local side = Scale.px(opts.thumbSize or metrics.sliderThumb)
		return { Size = UDim2.fromOffset(side, side) }
	end)

	local object = { instance = row, value = value }

	local function render()
		local alpha = (max > min) and ((value - min) / (max - min)) or 0
		fill.Size = UDim2.fromScale(alpha, 1)
		thumb.Position = UDim2.fromScale(alpha, 0.5)
		local text = tostring(step and value or (math.floor(value * 10 + 0.5) / 10))
		if opts.suffix then
			text = text .. " " .. opts.suffix
		end
		valueLabel.Text = text
	end

	local function setValue(nextValue, fire)
		nextValue = math.clamp(nextValue, min, max)
		if step and step > 0 then
			nextValue = min + math.floor((nextValue - min) / step + 0.5) * step
		end
		value = nextValue
		object.value = value
		render()
		if fire ~= false and opts.changed then
			local ok, err = pcall(opts.changed, value, object)
			if not ok then
				warn("[NewGUI] slider.changed 报错: " .. tostring(err))
			end
		end
	end

	-- 拖动: 整行作为热区, 按下即跳转 + 拖动
	local dragging = false
	local clickArea = newInstance("TextButton", row, {
		Name = "Area",
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = row.ZIndex + 2,
	})

	local function valueFromX(x)
		local abs = track.AbsolutePosition
		local width = track.AbsoluteSize.X
		local alpha = Scale.clamp((x - abs.X) / math.max(width, 1), 0, 1)
		return min + alpha * (max - min)
	end

	local UserInputService = game:GetService("UserInputService")
	clickArea.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			setValue(valueFromX(input.Position.X), true)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			setValue(valueFromX(input.Position.X), true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)

	function object:Set(nextValue)
		setValue(nextValue, true)
		return self
	end

	function object:Get()
		return value
	end

	render()
	return object
end
--============================ 分组标题 ============================--
function Widgets.section(parent, title, opts)
	opts = opts or {}
	local row = newInstance("Frame", parent, {
		Name = "Section",
		BackgroundTransparency = 1,
		LayoutOrder = opts.order or 0,
		Size = UDim2.new(1, 0, 0, 0),
	})
	Scale.bind(row, function()
		return { Size = UDim2.new(1, 0, 0, Scale.px(opts.height or metrics.labelHeight * 1.35)) }
	end)

	local label = newInstance("TextLabel", row, {
		Name = "Title",
		BackgroundTransparency = 1,
		Text = string.upper(title or ""),
		TextColor3 = opts.color or palette.textFaint,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(1, 1),
	})
	Theme.fontSize(label, metrics.fontTiny, Theme.font.bold)
	return row
end

--============================ 滚动容器 ============================--
function Widgets.scroll(parent, opts)
	opts = opts or {}
	local scroll = newInstance("ScrollingFrame", parent, {
		Name = opts.name or "Scroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = palette.accent,
		ScrollBarImageTransparency = 0.35,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Size = opts.size or UDim2.fromScale(1, 1),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	})
	Scale.bind(scroll, function()
		return { ScrollBarThickness = math.max(2, Scale.round(Scale.px(0.35))) }
	end)

	local layout = newInstance("UIListLayout", scroll, {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 0),
	})
	Scale.bind(layout, function()
		return { Padding = UDim.new(0, Scale.px(opts.gap or metrics.gap)) }
	end)
	Theme.padding(scroll, opts.padding or metrics.gap)
	return scroll
end

--============================ 输入框 ============================--
function Widgets.input(parent, opts)
	opts = opts or {}
	local row = newInstance("Frame", parent, {
		Name = opts.name or "Input",
		BackgroundColor3 = palette.card,
		LayoutOrder = opts.order or 0,
		Size = UDim2.new(1, 0, 0, 0),
	})
	card(row, "control")
	Theme.padding(row, 1.0)
	heightOf(row, opts.height or metrics.rowHeight)

	if opts.icon then
		local icon = attachIcon(row, opts.icon, { size = metrics.iconSize, heightPercent = opts.height or metrics.rowHeight, color = palette.textFaint })
		icon.Position = UDim2.fromScale(0, 0.5)
	end

	local box = newInstance("TextBox", row, {
		Name = "Box",
		BackgroundTransparency = 1,
		Text = opts.default or "",
		PlaceholderText = opts.placeholder or "",
		PlaceholderColor3 = palette.textFaint,
		TextColor3 = palette.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Size = UDim2.fromScale(opts.icon and 0.9 or 1, 1),
		Position = UDim2.fromScale(opts.icon and 0.1 or 0, 0),
	})
	Theme.fontSize(box, metrics.fontBody, Theme.font.regular)

	local object = { instance = row, textBox = box }

	local function fire(kind, value)
		if opts[kind] then
			local ok, err = pcall(opts[kind], value, object)
			if not ok then
				warn("[NewGUI] input." .. kind .. " 报错: " .. tostring(err))
			end
		end
	end

	box.Focused:Connect(function()
		Util.tween(row, { BackgroundColor3 = palette.cardHover }, 0.1)
	end)
	box.FocusLost:Connect(function(enterPressed)
		Util.tween(row, { BackgroundColor3 = palette.card }, 0.12)
		if enterPressed then
			fire("submitted", box.Text)
		end
		fire("changed", box.Text)
	end)

	function object:Get()
		return box.Text
	end

	function object:Set(value)
		box.Text = value or ""
		return self
	end

	return object
end

--============================ 下拉选择 ============================--
--[=[
	Widgets.dropdown(parent, {
		options = { "选项A", "选项B" },
		default = "选项A",
		overlay = overlayFrame,        -- 菜单挂载处(通常是窗口的 Overlay 层)
		changed = function(value) end,
	})
]=]
function Widgets.dropdown(parent, opts)
	opts = opts or {}
	local options = opts.options or {}
	local current = opts.default or options[1]

	local row = newInstance("Frame", parent, {
		Name = opts.name or "Dropdown",
		BackgroundColor3 = palette.card,
		LayoutOrder = opts.order or 0,
		Size = UDim2.new(1, 0, 0, 0),
	})
	card(row, "control")
	Theme.padding(row, 1.0)
	heightOf(row, opts.height or metrics.rowHeight)

	if opts.icon then
		local icon = attachIcon(row, opts.icon, { size = metrics.iconSize, heightPercent = opts.height or metrics.rowHeight, color = palette.textDim })
		icon.Position = UDim2.fromScale(0, 0.5)
	end

	local label = newInstance("TextLabel", row, {
		Name = "Value",
		BackgroundTransparency = 1,
		Text = tostring(current),
		TextColor3 = palette.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromScale(0.78, 1),
		Position = UDim2.fromScale(opts.icon and 0.1 or 0, 0),
	})
	Theme.fontSize(label, metrics.fontBody, Theme.font.medium)

	local chevron = attachIcon(row, "chevron-down", { size = metrics.iconSize * 0.9, heightPercent = metrics.rowHeight, color = palette.textDim })
	chevron.Position = UDim2.fromScale(1, 0.5)
	chevron.AnchorPoint = Vector2.new(1, 0.5)

	local button = newInstance("TextButton", row, {
		Name = "Hit",
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = row.ZIndex + 3,
	})

	local object = { instance = row, value = current }
	local menuOpen = false
	local menu

	local function closeMenu()
		if menu then
			menu:Destroy()
			menu = nil
		end
		menuOpen = false
	end

	local function openMenu()
		if menuOpen or not opts.overlay then
			return
		end
		menuOpen = true

		local overlay = opts.overlay
		local rowAbs = row.AbsolutePosition
		local overlayAbs = overlay.AbsolutePosition
		local rowSize = row.AbsoluteSize
		local itemHeight = Scale.px(opts.height or metrics.rowHeight) * 0.92

		menu = newInstance("Frame", overlay, {
			Name = "DropdownMenu",
			BackgroundColor3 = palette.header,
			BorderSizePixel = 0,
			ZIndex = 500,
			Position = UDim2.fromOffset(rowAbs.X - overlayAbs.X, rowAbs.Y - overlayAbs.Y + rowSize.Y + Scale.px(0.4)),
		})
		card(menu, "control", palette.windowStroke)
		menu.Size = UDim2.fromOffset(rowSize.X, itemHeight * #options + Scale.px(0.6) * 2)

		local list = newInstance("Frame", menu, {
			Name = "List",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		})
		Theme.padding(list, 0.3)
		local menuLayout = newInstance("UIListLayout", list, {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 0),
		})
		Scale.bind(menuLayout, function()
			return { Padding = UDim.new(0, Scale.px(0.25)) }
		end)

		for index, option in ipairs(options) do
			local item = newInstance("TextButton", list, {
				Name = "Item" .. index,
				BackgroundColor3 = palette.card,
				BackgroundTransparency = 0.65,
				AutoButtonColor = false,
				Text = "",
				LayoutOrder = index,
			})
			card(item, "small")
			Scale.bind(item, function()
				return { Size = UDim2.new(1, 0, 0, itemHeight) }
			end)
			local itemLabel = newInstance("TextLabel", item, {
				BackgroundTransparency = 1,
				Text = tostring(option),
				TextColor3 = tostring(option) == tostring(current) and palette.accent or palette.text,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.fromScale(0.92, 1),
				Position = UDim2.fromScale(0.06, 0),
			})
			Theme.fontSize(itemLabel, metrics.fontBody, Theme.font.regular)

			item.MouseEnter:Connect(function()
				Util.tween(item, { BackgroundTransparency = 0 }, 0.08)
			end)
			item.MouseLeave:Connect(function()
				Util.tween(item, { BackgroundTransparency = 0.65 }, 0.1)
			end)
			item.MouseButton1Click:Connect(function()
				current = option
				object.value = option
				label.Text = tostring(option)
				closeMenu()
				if opts.changed then
					local ok, err = pcall(opts.changed, option, object)
					if not ok then
						warn("[NewGUI] dropdown.changed 报错: " .. tostring(err))
					end
				end
			end)
		end

		-- 点外面关闭
		local scrim = newInstance("TextButton", overlay, {
			Name = "DropdownScrim",
			BackgroundTransparency = 1,
			Text = "",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 499,
		})
		scrim.MouseButton1Click:Connect(function()
			closeMenu()
		end)
		menu.Destroying:Connect(function()
			if scrim.Parent then
				scrim:Destroy()
			end
		end)
	end

	button.MouseButton1Click:Connect(function()
		if menuOpen then
			closeMenu()
		else
			openMenu()
		end
	end)
	button.MouseEnter:Connect(function()
		Util.tween(row, { BackgroundColor3 = palette.cardHover }, 0.1)
	end)
	button.MouseLeave:Connect(function()
		Util.tween(row, { BackgroundColor3 = palette.card }, 0.12)
	end)

	function object:Set(value)
		current = value
		object.value = value
		label.Text = tostring(value)
		return self
	end

	function object:Get()
		return current
	end

	function object:Close()
		closeMenu()
	end

	return object
end

--============================ 按键绑定 ============================--
local KEY_ALIASES = {
	RightControl = "R-Ctrl",
	LeftControl = "L-Ctrl",
	RightShift = "R-Shift",
	LeftShift = "L-Shift",
	RightAlt = "R-Alt",
	LeftAlt = "L-Alt",
	MouseButton1 = "鼠标左键",
	MouseButton2 = "鼠标右键",
}

function Widgets.keybind(parent, opts)
	opts = opts or {}
	local current = opts.default or Enum.KeyCode.RightControl
	local listening = false

	local row = newInstance("Frame", parent, {
		Name = opts.name or "Keybind",
		BackgroundColor3 = palette.card,
		LayoutOrder = opts.order or 0,
		Size = UDim2.new(1, 0, 0, 0),
	})
	card(row, "control")
	Theme.padding(row, 1.0)
	heightOf(row, opts.height or metrics.rowHeight)

	if opts.icon then
		local icon = attachIcon(row, opts.icon, { size = metrics.iconSize, heightPercent = opts.height or metrics.rowHeight, color = palette.textDim })
		icon.Position = UDim2.fromScale(0, 0.5)
	end

	local label = newInstance("TextLabel", row, {
		Name = "Label",
		BackgroundTransparency = 1,
		Text = opts.text or "",
		TextColor3 = palette.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromScale(0.55, 1),
		Position = UDim2.fromScale(opts.icon and 0.1 or 0, 0),
	})
	Theme.fontSize(label, metrics.fontBody, Theme.font.medium)

	local keyBox = newInstance("Frame", row, {
		Name = "Key",
		BackgroundColor3 = palette.cardHover,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
	})
	card(keyBox, "small", palette.divider)
	Scale.bind(keyBox, function()
		local height = Scale.px(opts.height or metrics.rowHeight) * 0.62
		return { Size = UDim2.fromOffset(math.max(Scale.px(6.4), height * 1.7), height) }
	end)

	local keyLabel = newInstance("TextLabel", keyBox, {
		Name = "KeyLabel",
		BackgroundTransparency = 1,
		Text = KEY_ALIASES[current.Name] or current.Name,
		TextColor3 = palette.text,
		Size = UDim2.fromScale(1, 1),
	})
	Theme.fontSize(keyLabel, metrics.fontSmall, Theme.font.medium)

	local button = newInstance("TextButton", row, {
		Name = "Hit",
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = row.ZIndex + 2,
	})

	local object = { instance = row, value = current }
	local connection

	local function stopListening()
		listening = false
		if connection then
			connection:Disconnect()
			connection = nil
		end
		keyLabel.TextColor3 = palette.text
		keyBox.BackgroundColor3 = palette.cardHover
	end

	local UserInputService = game:GetService("UserInputService")

	local function startListening()
		if listening then
			return
		end
		listening = true
		keyLabel.Text = "按下按键…"
		keyLabel.TextColor3 = palette.accent
		keyBox.BackgroundColor3 = palette.card

		connection = UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			local key = input.KeyCode
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
				key = input.UserInputType == Enum.UserInputType.MouseButton1 and Enum.KeyCode.MouseButton1 or Enum.KeyCode.MouseButton2
			elseif input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end

			if key == Enum.KeyCode.Escape then
				keyLabel.Text = KEY_ALIASES[current.Name] or current.Name
				stopListening()
				return
			end
			if key == Enum.KeyCode.Backspace then
				current = Enum.KeyCode.Unknown
				object.value = current
				keyLabel.Text = "未绑定"
				stopListening()
				if opts.changed then
					pcall(opts.changed, current, object)
				end
				return
			end

			current = key
			object.value = current
			keyLabel.Text = KEY_ALIASES[key.Name] or key.Name
			stopListening()
			if opts.changed then
				local ok, err = pcall(opts.changed, current, object)
				if not ok then
					warn("[NewGUI] keybind.changed 报错: " .. tostring(err))
				end
			end
		end)
	end

	button.MouseButton1Click:Connect(function()
		if listening then
			stopListening()
			keyLabel.Text = KEY_ALIASES[current.Name] or current.Name
		else
			startListening()
		end
	end)

	function object:Get()
		return current
	end

	function object:Set(key)
		current = key
		object.value = key
		keyLabel.Text = KEY_ALIASES[key.Name] or key.Name
		return self
	end

	function object:Cancel()
		stopListening()
		keyLabel.Text = KEY_ALIASES[current.Name] or current.Name
		return self
	end

	return object
end

--============================ 侧边栏导航 ============================--
--[=[
	Widgets.tabs(parent, {
		items = { { name = "首页", icon = "grid" }, ... },
		default = 1,
		changed = function(index, name) end,
	})
]=]
function Widgets.tabs(parent, opts)
	opts = opts or {}
	local items = opts.items or {}
	local entries = {}
	local selected = opts.default or 1
	local layout = Widgets.list(parent, { gap = 0.45, padding = opts.padding or metrics.tabPadding })

	local object = { instance = layout, items = entries, value = selected }

	local function render()
		for index, entry in ipairs(entries) do
			local active = index == selected
			Util.tween(entry.row, {
				BackgroundColor3 = active and palette.accent or palette.card,
				BackgroundTransparency = active and 0 or 0.5,
			}, 0.12)
			-- 侧边栏太窄时只留图标(手机竖屏)
			local wideEnough = entry.row.AbsoluteSize.X > Scale.px(7.5)
			entry.label.Visible = wideEnough
			entry.label.TextColor3 = active and palette.white or palette.textDim
			if entry.glyph then
				entry.glyph:SetColor(active and palette.white or palette.textDim)
			end
			if entry.image and entry.image.ImageColor3 then
				entry.image.ImageColor3 = active and palette.white or palette.textDim
			end
		end
	end

	for index, item in ipairs(items) do
		local row = newInstance("Frame", layout, {
			Name = "Tab" .. index,
			BackgroundColor3 = palette.card,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 0),
		})
		card(row, "control", false)
		Scale.bind(row, function()
			return { Size = UDim2.new(1, 0, 0, Scale.px(opts.height or metrics.tabHeight)) }
		end)

		local icon, glyph, image = nil, nil, nil
		if item.icon then
			icon, glyph, image = attachIcon(row, item.icon, { size = metrics.iconSize, heightPercent = opts.height or metrics.controlHeight, color = palette.textDim })
			icon.Position = UDim2.fromScale(0.08, 0.5)
		end

		local label = newInstance("TextLabel", row, {
			Name = "Label",
			BackgroundTransparency = 1,
			Text = item.name or ("页面" .. index),
			TextColor3 = palette.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.fromScale(0.76, 1),
			Position = UDim2.fromScale(item.icon and 0.24 or 0.1, 0),
		})
		Theme.fontSize(label, metrics.fontSmall, Theme.font.medium)

		local hit = newInstance("TextButton", row, {
			Name = "Hit",
			BackgroundTransparency = 1,
			Text = "",
			Size = UDim2.fromScale(1, 1),
			ZIndex = row.ZIndex + 2,
		})
		hit.MouseButton1Click:Connect(function()
			if index == selected then
				return
			end
			selected = index
			object.value = index
			render()
			if opts.changed then
				local ok, err = pcall(opts.changed, index, item.name)
				if not ok then
					warn("[NewGUI] tabs.changed 报错: " .. tostring(err))
				end
			end
		end)
		hit.MouseEnter:Connect(function()
			if index ~= selected then
				Util.tween(row, { BackgroundTransparency = 0.15 }, 0.1)
			end
		end)
		hit.MouseLeave:Connect(function()
			if index ~= selected then
				Util.tween(row, { BackgroundTransparency = 0.5 }, 0.12)
			end
		end)

		entries[#entries + 1] = { row = row, label = label, glyph = glyph, image = image, name = item.name }
	end

	render()

	function object:Destroy()
		layout:Destroy()
		self.instance = nil
	end

	function object:Select(index)
		selected = index
		object.value = index
		render()
		if opts.changed then
			pcall(opts.changed, index, entries[index] and entries[index].name)
		end
		return self
	end

	return object
end

--============================ 徽章 ============================--
function Widgets.badge(parent, text, opts)
	opts = opts or {}
	local badge = newInstance("Frame", parent, {
		Name = "Badge",
		BackgroundColor3 = opts.color or palette.accent,
		BackgroundTransparency = 0.82,
		LayoutOrder = opts.order or 0,
	})
	Theme.corner(badge, "small")
	Scale.bind(badge, function()
		return { Size = UDim2.fromOffset(Scale.px(10.5), Scale.px(opts.height or 2.6)) }
	end)
	local label = newInstance("TextLabel", badge, {
		BackgroundTransparency = 1,
		Text = text or "",
		TextColor3 = opts.textColor or palette.accent,
		Size = UDim2.fromScale(1, 1),
	})
	Theme.fontSize(label, metrics.fontTiny, Theme.font.medium)
	local object = { instance = badge, SetText = function(_, value)
		label.Text = value
	end }
	return object
end

return Widgets
