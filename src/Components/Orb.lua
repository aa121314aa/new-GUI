--[[
	NewGUI · Components/Orb
	长方形悬浮球(像素风小圆角)。

	特点:
		· 尺寸 = 基准轴百分比(Config.orb.width / height), 位置 = 视口百分比 → 转屏/改窗口自动跟随
		· 圆角 = 百分比像素值(Config.orb.corner, 默认 0.85% ≈ 720p 下 6px, 克制的像素风)
		· 可拖动(带阈值判定: 拖动不会误触发点击), 松开后位置按百分比存盘
		· 图标: 优先用 Assets 下载的 PNG, 没有则用 Glyph 矢量图标
]]

local Scale = require("Core.Scale")
local Theme = require("Core.Theme")
local Compat = require("Core.Compat")
local Config = require("Core.Config")
local Assets = require("Core.Assets")
local Storage = require("Core.Storage")
local Glyph = require("Core.Glyph")
local Signal = require("Core.Signal")
local Util = require("Core.Util")

local UserInputService = game:GetService("UserInputService")

local Orb = {}
Orb.__index = Orb

--============================ 创建 ============================--
--[=[
	Orb.new(parentGui, opts)
	opts 可覆盖 Config.orb 的任意字段。
	返回对象:
		orb.Activated      —— 点击(非拖动)信号
		orb.Moved          —— 拖动结束信号
		orb:SetVisible(b)
		orb:Destroy()
]=]
function Orb.new(parentGui, opts)
	local self = setmetatable({}, Orb)

	self.options = setmetatable(opts or {}, { __index = Config.orb })
	self.Activated = Signal.new("Orb.Activated")
	self.Moved = Signal.new("Orb.Moved")
	self._connections = {}
	self._destroyed = false
	self._dragging = false
	self._moved = false

	local options = self.options

	--============================ 影子(像素风: 直接偏移 2px) ============================--
	local shadow = Instance.new("Frame")
	shadow.Name = "OrbShadow"
	shadow.BackgroundColor3 = Theme.palette.shadow
	shadow.BackgroundTransparency = 0.65
	shadow.BorderSizePixel = 0
	shadow.ZIndex = options.zIndex
	shadow.AnchorPoint = Vector2.new(0, 0)
	shadow.Parent = parentGui
	Theme.corner(shadow, options.corner)
	self.shadow = shadow

	--============================ 主体 ============================--
	local orb = Instance.new("Frame")
	orb.Name = "NewGUI_Orb"
	orb.BackgroundColor3 = Theme.palette.orb
	orb.BorderSizePixel = 0
	orb.ClipsDescendants = false
	orb.Active = true -- 允许拖拽/点击
	orb.ZIndex = options.zIndex + 1
	orb.AnchorPoint = Vector2.new(0, 0)
	orb.Parent = parentGui
	Theme.corner(orb, options.corner)
	self.stroke = Theme.stroke(orb, Theme.palette.orbStroke, options.strokeWidth)
	self.orb = orb

	--============================ 图标 ============================--
	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "Icon"
	iconHolder.BackgroundTransparency = 1
	iconHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	iconHolder.Position = UDim2.fromScale(0.5, 0.5)
	iconHolder.Size = UDim2.fromScale(1, 1)
	iconHolder.ZIndex = orb.ZIndex + 1
	iconHolder.Parent = orb
	-- 图标 = 基准轴的 options.iconSize%, 换算成"相对悬浮球"的比例(比例恒定, 无需跟随屏幕)
	self._refreshIcon = function()
		local widthFraction = options.iconSize / math.max(options.width, 0.01)
		local heightFraction = options.iconSize / math.max(options.height, 0.01)
		iconHolder.Size = UDim2.new(
			math.min(widthFraction, 0.86),
			0,
			math.min(heightFraction, 0.86),
			0
		)
	end
	self._refreshIcon()
	self.iconHolder = iconHolder

	-- 矢量兜底图标(先建好, 图片到了再隐藏)
	self.glyph = Glyph.draw(iconHolder, options.icon, {
		color = Theme.palette.orbIcon,
		stroke = 2,
		padding = 8,
	})

	-- 图片图标(异步; 没有执行器文件权限时保持 nil, 用矢量图)
	self.image = Instance.new("ImageLabel")
	self.image.Name = "IconImage"
	self.image.BackgroundTransparency = 1
	self.image.Size = UDim2.fromScale(1, 1)
	self.image.ImageTransparency = 1
	self.image.Visible = false
	self.image.ZIndex = iconHolder.ZIndex + 1
	self.image.Parent = iconHolder

	Assets.load(options.icon, function(asset)
		if self._destroyed or not asset then
			return
		end
		self.image.Image = asset
		self.image.Visible = true
		Util.tween(self.image, { ImageTransparency = 0 }, 0.15)
		if self.glyph then
			self.glyph.instance.Visible = false -- 有图片了, 矢量图退场
		end
	end)

	--============================ 位置(百分比 + 存盘) ============================--
	self.position = { x = options.x / 100, y = options.y / 100 }
	local saved = Config.behavior.saveLayout and Storage.get("orb") or nil
	if type(saved) == "table" and tonumber(saved.x) and tonumber(saved.y) then
		self.position.x = tonumber(saved.x)
		self.position.y = tonumber(saved.y)
	end

	local function applyPosition()
		-- 位置 = 视口百分比; 尺寸 = 基准轴百分比(像素) → 屏幕变化时一起重算
		orb.Position = UDim2.fromScale(self.position.x, self.position.y)
		scaleAndPlace()
	end

	--[=[ 尺寸 + 影子偏移(两者必须同一套算法, 否则会错位) ]=]
	function scaleAndPlace()
		local widthPx = Scale.px(options.width)
		local heightPx = Scale.px(options.height)
		orb.Size = UDim2.fromOffset(widthPx, heightPx)
		local shadowOffset = math.max(1, Scale.px(0.22))
		shadow.Size = UDim2.fromOffset(widthPx, heightPx)
		shadow.Position = UDim2.new(
			self.position.x,
			shadowOffset,
			self.position.y,
			shadowOffset
		)
	end
	self._scaleAndPlace = scaleAndPlace

	self._applyPosition = applyPosition
	applyPosition()
	table.insert(self._connections, Scale.onChange(applyPosition))

	--============================ 交互 ============================--
	local function setState(state)
		local target
		if state == "hover" then
			target = Theme.palette.orbHover
		elseif state == "press" then
			target = Theme.palette.orbPress
		else
			target = Theme.palette.orb
		end
		Util.tween(orb, { BackgroundColor3 = target }, Config.behavior.fadeDuration)
	end

	local function isPrimary(input)
		local t = input.UserInputType
		return t == Enum.UserInputType.MouseButton1
			or t == Enum.UserInputType.Touch
			or t == Enum.UserInputType.MouseMovement
	end

	local dragOrigin, positionOrigin = nil, nil

	local function startDrag(position)
		self._dragging = true
		self._moved = false
		dragOrigin = position
		positionOrigin = Vector2.new(self.position.x, self.position.y)
	end

	local function sizeFraction()
		-- 悬浮球占"视口"的比例(用于边界钳制)
		return Vector2.new(Scale.widthFraction(options.width), Scale.heightFraction(options.height))
	end

	local function moveDrag(position)
		if not self._dragging or not dragOrigin then
			return
		end
		local delta = position - dragOrigin
		if not self._moved and delta.Magnitude < Config.behavior.dragThreshold then
			return
		end
		self._moved = true

		local viewport = Scale.viewport
		local fraction = sizeFraction()
		local nx = positionOrigin.x + delta.X / math.max(viewport.X, 1)
		local ny = positionOrigin.y + delta.Y / math.max(viewport.Y, 1)
		nx = Scale.clamp(nx, -0.02, math.max(-0.02, 1 - fraction.X + 0.02))
		ny = Scale.clamp(ny, 0, math.max(0, 1 - fraction.Y))
		self.position.x, self.position.y = nx, ny
		applyPosition()
		setState("press")
	end

	local function endDrag(fired)
		local wasDragging = self._dragging
		local moved = self._moved
		self._dragging = false
		self._moved = false
		dragOrigin = nil
		if not wasDragging then
			return
		end
		setState("default")
		if moved then
			if Config.behavior.saveLayout then
				Storage.set("orb", { x = self.position.x, y = self.position.y })
			end
			self.Moved:Fire(self.position)
		elseif fired then
			setState("hover")
			self.Activated:Fire()
		end
	end

	local function toVector(input)
		return Vector2.new(input.Position.X, input.Position.Y)
	end

	table.insert(
		self._connections,
		orb.InputBegan:Connect(function(input)
			if not isPrimary(input) then
				return
			end
			startDrag(toVector(input))
			setState("press")
		end)
	)

	table.insert(
		self._connections,
		orb.InputEnded:Connect(function(input)
			if not isPrimary(input) then
				return
			end
			endDrag(true)
		end)
	)

	table.insert(
		self._connections,
		UserInputService.InputChanged:Connect(function(input)
			if not self._dragging then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				moveDrag(toVector(input))
			end
		end)
	)

	table.insert(
		self._connections,
		UserInputService.InputEnded:Connect(function(input)
			if not self._dragging then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				-- 指针在球外松开: 结束拖动, 不触发点击
				local inside = Util.pointInGui(orb, toVector(input))
				endDrag(inside)
			end
		end)
	)

	table.insert(
		self._connections,
		orb.MouseEnter:Connect(function()
			if not self._dragging then
				setState("hover")
			end
		end)
	)
	table.insert(
		self._connections,
		orb.MouseLeave:Connect(function()
			if not self._dragging then
				setState("default")
			end
		end)
	)
	if orb.MouseMoved then
		-- 触屏拖动时的轻微高亮(部分执行器有该事件)
		table.insert(
			self._connections,
			orb.MouseMoved:Connect(function()
				if not self._dragging then
					setState("hover")
				end
			end)
		)
	end

	return self
end

--============================ 方法 ============================--
function Orb:SetVisible(visible)
	self.orb.Visible = visible
	self.shadow.Visible = visible
	return self
end

function Orb:SetIconSize(percent)
	self.options.iconSize = percent
	if self._refreshIcon then
		self._refreshIcon()
	end
	return self
end

--[=[ 把图标换成另一张(会重新走资产加载 → 矢量兜底) ]=]
function Orb:SetIcon(name)
	self.options.icon = name
	self.image.ImageTransparency = 1
	self.image.Visible = false
	if self.glyph then
		self.glyph:Destroy()
	end
	self.glyph = Glyph.draw(self.iconHolder, name, { color = Theme.palette.orbIcon, stroke = 2, padding = 8 })
	Assets.load(name, function(asset)
		if self._destroyed or not asset then
			return
		end
		self.image.Image = asset
		self.image.Visible = true
		self.image.ImageTransparency = 0
		if self.glyph then
			self.glyph.instance.Visible = false
		end
	end)
	return self
end

function Orb:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, connection in ipairs(self._connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	self._connections = {}
	self.Activated:Destroy()
	self.Moved:Destroy()
	if self.glyph then
		self.glyph:Destroy()
		self.glyph = nil
	end
	pcall(function()
		self.image:Destroy()
		self.stroke:Destroy()
		self.orb:Destroy()
		self.shadow:Destroy()
	end)
end

return Orb
