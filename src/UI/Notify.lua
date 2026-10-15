--[[
	NewGUI · UI/Notify
	轻提示(toast)。右上角堆叠, 百分比尺寸, 自动淡出。
	用法: Notify.send(parentGui, { title = "已保存", text = "设置写入本地", kind = "success" })
]]

local Scale = require("Core.Scale")
local Theme = require("Core.Theme")
local Util = require("Core.Util")
local Glyph = require("Core.Glyph")
local Compat = require("Core.Compat")

local Notify = {}

local palette = Theme.palette
local metrics = Theme.metrics

local kindStyles = {
	info = { color = palette.accent, icon = "info" },
	success = { color = palette.success, icon = "check" },
	warn = { color = palette.warning, icon = "info" },
	error = { color = palette.danger, icon = "x" },
}

--[=[
	Notify.new(parentGui, opts) → 通知管理器
		notify:send({ title = "", text = "", kind = "info", duration = 3 })
]=]
function Notify.new(parentGui, opts)
	opts = opts or {}
	local stack = Instance.new("Frame")
	stack.Name = "NewGUI_Notify"
	stack.BackgroundTransparency = 1
	stack.AnchorPoint = Vector2.new(1, 0)
	stack.Position = UDim2.fromScale(0.985, 0.06)
	stack.ZIndex = opts.zIndex or 2000
	stack.Parent = parentGui
	Scale.bind(stack, function()
		return { Size = UDim2.new(0.24, 0, 0.5, 0) }
	end)

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, 0)
	layout.Parent = stack
	Scale.bind(layout, function()
		return { Padding = UDim.new(0, Scale.px(0.7)) }
	end)

	local order = 0
	local object = { instance = stack, count = 0 }

	function object:send(config)
		config = config or {}
		local kind = kindStyles[config.kind or "info"] or kindStyles.info
		order = order + 1
		self.count = self.count + 1

		local card = Instance.new("Frame")
		card.Name = "Toast"
		card.BackgroundColor3 = palette.header
		card.BorderSizePixel = 0
		card.LayoutOrder = order
		card.AnchorPoint = Vector2.new(1, 0)
		card.Position = UDim2.fromScale(1, 0)
		card.BackgroundTransparency = 1
		card.Parent = stack
		Theme.corner(card, "control")
		Theme.stroke(card, palette.windowStroke, Theme.strokeWidth.thin)
		Scale.bind(card, function()
			return { Size = UDim2.fromOffset(Scale.px(19), Scale.px(config.tall and 6.4 or 5.2)) }
		end)

		-- 左侧色条
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.BackgroundColor3 = kind.color
		bar.BorderSizePixel = 0
		bar.Size = UDim2.fromScale(0.018, 1)
		bar.Parent = card
		Theme.corner(bar, "small")

		local iconHolder = Instance.new("Frame")
		iconHolder.Name = "Icon"
		iconHolder.BackgroundTransparency = 1
		iconHolder.Position = UDim2.fromScale(0.05, 0.5)
		iconHolder.AnchorPoint = Vector2.new(0, 0.5)
		iconHolder.Parent = card
		Scale.bind(iconHolder, function()
			local side = Scale.px(2.4)
			return { Size = UDim2.fromOffset(side, side) }
		end)
		Glyph.draw(iconHolder, kind.icon, { color = kind.color, stroke = 2.4, padding = 4 })

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Text = config.title or "提示"
		title.TextColor3 = palette.text
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextTruncate = Enum.TextTruncate.AtEnd
		title.Position = UDim2.fromScale(0.2, 0.12)
		title.Size = UDim2.fromScale(0.76, config.text and 0.38 or 0.76)
		title.Parent = card
		Theme.fontSize(title, metrics.fontSmall, Theme.font.medium)

		if config.text then
			local body = Instance.new("TextLabel")
			body.Name = "Text"
			body.BackgroundTransparency = 1
			body.Text = config.text
			body.TextColor3 = palette.textDim
			body.TextXAlignment = Enum.TextXAlignment.Left
			body.TextYAlignment = Enum.TextYAlignment.Top
			body.TextWrapped = true
			body.TextTruncate = Enum.TextTruncate.AtEnd
			body.Position = UDim2.fromScale(0.2, 0.5)
			body.Size = UDim2.fromScale(0.76, 0.38)
			body.Parent = card
			Theme.fontSize(body, metrics.fontTiny, Theme.font.regular)
		end

		-- 入场: 背景淡入 + 轻微右移
		card.Position = UDim2.new(1, Scale.px(3), 0, 0)
		Util.tween(card, { BackgroundTransparency = 0.05, Position = UDim2.fromScale(1, 0) }, 0.18)

		local closed = false
		local function dismiss()
			if closed then
				return
			end
			closed = true
			local out = Util.tween(card, {
				BackgroundTransparency = 1,
				Position = UDim2.new(1, Scale.px(3), 0, 0),
			}, 0.16)
			out.Completed:Connect(function()
				if card.Parent then
					card:Destroy()
				end
				self.count = self.count - 1
			end)
		end

		card.Active = true
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = card.ZIndex + 3
		hit.Parent = card
		hit.MouseButton1Click:Connect(dismiss)

		if config.duration ~= false then
			Compat.Delay(config.duration or 3, dismiss)
		end
		return dismiss
	end

	function object:Destroy()
		pcall(function()
			stack:Destroy()
		end)
	end

	return object
end

--[=[
	一次性快捷方法: 每个父级复用一个通知层(弱引用, 父级销毁后自动回收)
]=]
local managers = setmetatable({}, { __mode = "k" })

function Notify.send(parentGui, config)
	local manager = managers[parentGui]
	if not manager or not manager.instance.Parent then
		manager = Notify.new(parentGui)
		managers[parentGui] = manager
	end
	return manager:send(config)
end

function Notify.clear()
	for parentGui, manager in pairs(managers) do
		manager:Destroy()
	end
	managers = setmetatable({}, { __mode = "k" })
end

return Notify
