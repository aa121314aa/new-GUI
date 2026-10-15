--[[
	NewGUI · UI/Window
	主窗口: 标题栏 + 侧边栏导航 + 内容区 + 状态栏。

	· 尺寸/位置全部百分比(基准轴/视口), UISizeConstraint 做上下限, 转屏自动跟随
	· 标题栏拖动、右下角缩放, 位置尺寸落盘
	· 用 CanvasGroup 做整窗淡入淡出(单一属性补间, 不掉帧)
	· Overlay 层专门放下拉菜单等浮层, 不受内容区裁剪影响
]]

local Scale = require("Core.Scale")
local Theme = require("Core.Theme")
local Compat = require("Core.Compat")
local Config = require("Core.Config")
local Storage = require("Core.Storage")
local Widgets = require("UI.Widgets")
local Signal = require("Core.Signal")
local Util = require("Core.Util")

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Window = {}
Window.__index = Window

local metrics = Theme.metrics
local palette = Theme.palette

--============================ 创建 ============================--
function Window.new(parentGui, opts)
	local self = setmetatable({}, Window)
	opts = opts or {}
	self.options = opts
	self.pages = {}
	self._connections = {}
	self._destroyed = false
	self._opened = false
	self.Closed = Signal.new("Window.Closed")
	self.Opened = Signal.new("Window.Opened")

	local windowConfig = Config.window
	self.size = {
		width = windowConfig.width / 100,
		height = windowConfig.height / 100,
	}
	local saved = Config.behavior.saveLayout and Storage.get("window") or nil
	if type(saved) == "table" and tonumber(saved.width) and tonumber(saved.height) then
		self.size.width = tonumber(saved.width)
		self.size.height = tonumber(saved.height)
	end
	self.position = nil -- 打开时根据悬浮球/屏幕计算

	--============================ 根容器 ============================--
	-- CanvasGroup 用来做整窗淡入淡出; 老客户端没有这个类时回退成普通 Frame
	local root, hasCanvasGroup = nil, false
	local ok, canvas = pcall(function()
		return Instance.new("CanvasGroup")
	end)
	if ok and canvas then
		root, hasCanvasGroup = canvas, true
	else
		root = Instance.new("Frame")
	end
	self.hasCanvasGroup = hasCanvasGroup
	root.Name = "NewGUI_Window"
	root.BackgroundColor3 = palette.window
	root.BorderSizePixel = 0
	root.AnchorPoint = Vector2.new(0, 0)
	root.ZIndex = opts.zIndex or 900
	root.Visible = false
	if hasCanvasGroup then
		root.GroupTransparency = 1
	end
	root.Parent = parentGui
	Theme.corner(root, windowConfig.corner)
	Theme.stroke(root, palette.windowStroke, Theme.strokeWidth.normal)
	self.root = root

	Scale.bind(root, function()
		return {
			Size = UDim2.new(self.size.width, 0, self.size.height, 0),
		}
	end)

	-- 上下限钳制(视口百分比 → 像素)
	local constraint = Instance.new("UISizeConstraint")
	constraint.Parent = root
	Scale.bind(constraint, function()
		local viewport = Scale.viewport
		return {
			MaxSize = Vector2.new(viewport.X * windowConfig.maxWidth / 100, viewport.Y * windowConfig.maxHeight / 100),
			MinSize = Vector2.new(viewport.X * windowConfig.minWidth / 100, viewport.Y * windowConfig.minHeight / 100),
		}
	end)

	--============================ 标题栏 ============================--
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundColor3 = palette.header
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, 0)
	header.Parent = root
	header.ZIndex = root.ZIndex + 1
	Scale.bind(header, function()
		return { Size = UDim2.new(1, 0, 0, Scale.px(windowConfig.headerHeight)) }
	end)
	-- 标题栏内容都在 CanvasGroup 根节点内, 圆角裁剪由根节点负责

	local titleIcon = Widgets.attachIcon(header, opts.icon or "sparkle", {
		size = metrics.iconSize,
		heightPercent = windowConfig.headerHeight,
		color = palette.accent,
	})
	titleIcon.Position = UDim2.fromScale(0.012, 0.5)
	titleIcon.ZIndex = header.ZIndex + 2
	if titleIcon.GetChildren then
		for _, child in ipairs(titleIcon:GetChildren()) do
			child.ZIndex = header.ZIndex + 3
			for _, grandchild in ipairs(child:GetChildren()) do
				grandchild.ZIndex = header.ZIndex + 4
			end
		end
	end

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Text = opts.title or "NewGUI"
	title.TextColor3 = palette.text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Size = UDim2.fromScale(0.3, 1)
	title.Position = UDim2.fromScale(0.045, 0)
	title.ZIndex = header.ZIndex + 2
	title.Parent = header
	Theme.fontSize(title, metrics.fontTitle, Theme.font.bold)

	if opts.subtitle then
		local subtitle = Instance.new("TextLabel")
		subtitle.Name = "Subtitle"
		subtitle.BackgroundTransparency = 1
		subtitle.Text = opts.subtitle
		subtitle.TextColor3 = palette.textFaint
		subtitle.TextXAlignment = Enum.TextXAlignment.Left
		subtitle.Size = UDim2.fromScale(0.42, 1)
		subtitle.Position = UDim2.fromScale(0.35, 0)
		subtitle.ZIndex = header.ZIndex + 2
		subtitle.Parent = header
		Theme.fontSize(subtitle, metrics.fontTiny, Theme.font.regular)
		self.subtitle = subtitle
	end

	-- 右侧按钮: 最小化 / 关闭 / (可选)开发者信息
	local closeButton = Widgets.iconButton(header, "x", {
		transparent = true,
		iconColor = palette.textDim,
		hoverColor = palette.danger,
		callback = function()
			self:Close()
		end,
	})
	closeButton.instance.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.instance.Position = UDim2.fromScale(0.994, 0.5)
	closeButton.instance.ZIndex = header.ZIndex + 3
	closeButton.instance.Parent = header
	self.closeButton = closeButton

	local minimizeButton = Widgets.iconButton(header, "minus", {
		transparent = true,
		iconColor = palette.textDim,
		hoverColor = palette.cardHover,
		callback = function()
			self:Minimize()
		end,
	})
	minimizeButton.instance.AnchorPoint = Vector2.new(1, 0.5)
	minimizeButton.instance.ZIndex = header.ZIndex + 3
	minimizeButton.instance.Parent = header
	Scale.bind(minimizeButton.instance, function()
		return { Position = UDim2.new(1, -Scale.px(5.0), 0.5, 0) }
	end)
	self.minimizeButton = minimizeButton

	-- 拖动区
	local dragArea = Instance.new("TextButton")
	dragArea.Name = "DragArea"
	dragArea.BackgroundTransparency = 1
	dragArea.Text = ""
	dragArea.Size = UDim2.fromScale(0.72, 1)
	dragArea.Position = UDim2.fromScale(0, 0)
	dragArea.ZIndex = header.ZIndex + 1
	dragArea.Parent = header

	--============================ 侧边栏 ============================--
	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.BackgroundColor3 = palette.sidebar
	sidebar.BorderSizePixel = 0
	sidebar.Position = UDim2.fromScale(0, 0)
	sidebar.Parent = root
	sidebar.ZIndex = root.ZIndex + 1
	self.sidebar = sidebar

	local sidebarList = Widgets.list(sidebar, { gap = 0.45, padding = false })
	sidebarList.Size = UDim2.fromScale(1, 1)
	sidebarList.Position = UDim2.fromScale(0, 0)
	self.sidebarList = sidebarList


	--============================ 内容区 ============================--
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundColor3 = palette.content
	content.BorderSizePixel = 0
	content.Parent = root
	content.ZIndex = root.ZIndex + 1
	self.content = content
	-- 页面容器(每个页面一个滚动框, 切换显示)
	local pageHolder = Instance.new("Frame")
	pageHolder.Name = "Pages"
	pageHolder.BackgroundTransparency = 1
	pageHolder.Size = UDim2.fromScale(1, 1)
	pageHolder.Parent = content
	self.pageHolder = pageHolder

	-- 状态栏
	local status = Instance.new("Frame")
	status.Name = "Status"
	status.BackgroundColor3 = palette.header
	status.BackgroundTransparency = 0.25
	status.BorderSizePixel = 0
	status.AnchorPoint = Vector2.new(0, 1)
	status.Position = UDim2.fromScale(0, 1)
	status.Parent = content
	status.ZIndex = content.ZIndex + 2
	self.statusBar = status

	local statusLeft = Instance.new("TextLabel")
	statusLeft.Name = "Info"
	statusLeft.BackgroundTransparency = 1
	statusLeft.Text = ""
	statusLeft.TextColor3 = palette.textFaint
	statusLeft.TextXAlignment = Enum.TextXAlignment.Left
	statusLeft.Size = UDim2.fromScale(0.72, 1)
	statusLeft.Position = UDim2.fromScale(0.015, 0)
	statusLeft.Parent = status
	Theme.fontSize(statusLeft, metrics.fontTiny, Theme.font.mono)
	self.statusLeft = statusLeft

	local statusRight = Instance.new("TextLabel")
	statusRight.Name = "Right"
	statusRight.BackgroundTransparency = 1
	statusRight.Text = ""
	statusRight.TextColor3 = palette.textFaint
	statusRight.TextXAlignment = Enum.TextXAlignment.Right
	statusRight.Size = UDim2.fromScale(0.26, 1)
	statusRight.AnchorPoint = Vector2.new(1, 0)
	statusRight.Position = UDim2.fromScale(0.985, 0)
	statusRight.Parent = status
	Theme.fontSize(statusRight, metrics.fontTiny, Theme.font.mono)
	self.statusRight = statusRight

	--[=[
		所有"像素级"布局集中在这里, 屏幕变化时重算一次。
		(尺寸/位置仍用百分比/UDim scale, 这里是给需要像素的地方兜底)
	]=]
	self._layout = Scale.bind(root, function()
		local viewport = Scale.viewport
		local headerPx = Scale.px(windowConfig.headerHeight)
		local statusPx = Scale.px(windowConfig.statusHeight)

		-- 窗口当前像素宽度(考虑 UISizeConstraint 钳制)
		local windowWidthPx = Scale.clamp(
			viewport.X * self.size.width,
			viewport.X * windowConfig.minWidth / 100,
			viewport.X * windowConfig.maxWidth / 100
		)

		-- 侧边栏: 窗口宽度的 ratio, 但限制在 基准轴 的 min~max 之间
		local sidebarPx = Scale.clamp(
			windowWidthPx * windowConfig.sidebarRatio,
			Scale.px(windowConfig.sidebarMin),
			Scale.px(windowConfig.sidebarMax)
		)
		local sidebarScale = sidebarPx / math.max(windowWidthPx, 1)
		self.sidebarScale = sidebarScale

		sidebar.Size = UDim2.new(sidebarScale, 0, 1, -headerPx)
		sidebar.Position = UDim2.new(0, 0, 0, headerPx)
		sidebar.Visible = true
		self.sidebarList.Size = UDim2.fromScale(1, 1)

		content.Size = UDim2.new(1 - sidebarScale, 0, 1, -headerPx - statusPx)
		content.Position = UDim2.new(sidebarScale, 0, 0, headerPx)
		pageHolder.Size = UDim2.new(1, 0, 1, -statusPx)
		status.Size = UDim2.new(1, 0, 0, statusPx)

		return {}
	end)
	--============================ 浮层 ============================--
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 400
	overlay.Parent = root
	self.overlay = overlay

	--============================ 缩放把手 ============================--
	local grip = Instance.new("TextButton")
	grip.Name = "ResizeGrip"
	grip.BackgroundTransparency = 1
	grip.Text = ""
	grip.AnchorPoint = Vector2.new(1, 1)
	grip.Position = UDim2.fromScale(1, 1)
	grip.Parent = root
	Scale.bind(grip, function()
		return { Size = UDim2.fromOffset(Scale.px(2.2), Scale.px(2.2)) }
	end)
	do
		local dots = Instance.new("Frame")
		dots.Name = "Dots"
		dots.BackgroundTransparency = 1
		dots.Size = UDim2.fromScale(1, 1)
		dots.AnchorPoint = Vector2.new(1, 1)
		dots.Position = UDim2.fromScale(1, 1)
		dots.Parent = grip
		-- 三个小方块, 像素风缩放提示
		for index = 1, 3 do
			local dot = Instance.new("Frame")
			dot.Name = "Dot" .. index
			dot.BackgroundColor3 = palette.textFaint
			dot.BorderSizePixel = 0
			dot.AnchorPoint = Vector2.new(1, 1)
			dot.Parent = dots
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 1)
			corner.Parent = dot
			Scale.bind(dot, function()
				local side = Scale.px(0.42)
				local offset = Scale.px(0.72)
				return {
					Size = UDim2.fromOffset(side, side),
					Position = UDim2.new(1, -offset * (index - 1), 1, -offset * (index - 1)),
				}
			end)
		end
	end

	--============================ 拖动 ============================--
	self:_setupDragging(dragArea, grip)

	--============================ 快捷键 ============================--
	local keyConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Config.behavior.keybind then
			self:Toggle()
		end
	end)
	table.insert(self._connections, keyConnection)

	-- 位置: 打开时再算, 但屏幕变化需要跟着走
	table.insert(self._connections, Scale.onChange(function()
		if self._opened and self.position then
			root.Position = UDim2.fromScale(self.position.x, self.position.y)
		end
	end))

	return self
end

--============================ 拖动 / 缩放 ============================--
function Window:_setupDragging(dragArea, grip)
	local windowConfig = Config.window

	-- 拖动
	local dragging, dragStart, startPos = false, nil, nil
	dragArea.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			dragStart = Vector2.new(input.Position.X, input.Position.Y)
			startPos = self.root.AbsolutePosition
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local current = Vector2.new(input.Position.X, input.Position.Y)
			local delta = current - dragStart
			local viewport = Scale.viewport
			local size = self.root.AbsoluteSize
			local x = Scale.clamp(startPos.X + delta.X, -size.X * 0.35, viewport.X - size.X * 0.35)
			local y = Scale.clamp(startPos.Y + delta.Y, 0, viewport.Y - Scale.px(metrics.labelHeight * 1.6))
			self.position = { x = x / math.max(viewport.X, 1), y = y / math.max(viewport.Y, 1) }
			self.root.Position = UDim2.fromScale(self.position.x, self.position.y)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if not dragging then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
			if self.position and Config.behavior.saveLayout then
				Storage.set("window", {
					x = self.position.x,
					y = self.position.y,
					width = self.size.width,
					height = self.size.height,
				})
			end
		end
	end)

	-- 缩放
	local resizing, resizeStart, startSize = false, nil, nil
	grip.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			resizing = true
			resizeStart = Vector2.new(input.Position.X, input.Position.Y)
			startSize = self.root.AbsoluteSize
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not resizing then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local current = Vector2.new(input.Position.X, input.Position.Y)
			local delta = current - resizeStart
			local viewport = Scale.viewport
			local width = Scale.clamp(startSize.X + delta.X, Scale.px(windowConfig.minWidth), viewport.X * 0.96)
			local height = Scale.clamp(startSize.Y + delta.Y, Scale.px(windowConfig.minHeight), viewport.Y * 0.96)
			self.size.width = width / math.max(viewport.X, 1)
			self.size.height = height / math.max(viewport.Y, 1)
			self.root.Size = UDim2.new(self.size.width, 0, self.size.height, 0)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if not resizing then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			resizing = false
			if not Config.behavior.saveLayout then
				return
			end
			Storage.set("window", {
				x = self.position and self.position.x,
				y = self.position and self.position.y,
				width = self.size.width,
				height = self.size.height,
			})
		end
	end)
end

--============================ 页面 ============================--
--[=[
	window:AddPage({ name = "首页", icon = "grid", build = function(scroll, page) end })
]=]
function Window:AddPage(page)
	local scroll = Widgets.scroll(self.pageHolder, { gap = metrics.gap, padding = metrics.contentPadding })
	scroll.Name = "Page_" .. (page.name or #self.pages + 1)
	scroll.Visible = false
	scroll.ZIndex = self.content.ZIndex + 1

	local entry = {
		name = page.name,
		icon = page.icon,
		scroll = scroll,
		objects = {},
	}
	self.pages[#self.pages + 1] = entry

	if page.build then
		local ok, err = pcall(page.build, scroll, self)
		if not ok then
			warn("[NewGUI] 页面构建失败(" .. tostring(page.name) .. "): " .. tostring(err))
			Widgets.label(scroll, "页面加载出错: " .. tostring(err), { color = palette.danger })
		end
	end
	return entry
end

function Window:SelectPage(index)
	index = math.clamp(index, 1, math.max(#self.pages, 1))
	for i, page in ipairs(self.pages) do
		page.scroll.Visible = i == index
	end
	self.currentPage = index
	return self
end

function Window:BuildNavigation()
	local items = {}
	for _, page in ipairs(self.pages) do
		items[#items + 1] = { name = page.name, icon = page.icon }
	end
	if #items == 0 then
		return
	end

	-- 幂等: 先清掉旧的导航, 避免重复叠加(会挤成两层)
	if self.tabs then
		pcall(function()
			self.tabs:Destroy()
		end)
		self.tabs = nil
	end

	self.tabs = Widgets.tabs(self.sidebarList, {
		items = items,
		default = self.currentPage or 1,
		height = metrics.tabHeight,
		changed = function(index)
			self:SelectPage(index)
		end,
	})
	self:SelectPage(self.currentPage or 1)
	return self
end

--============================ 开关 ============================--
function Window:_dockPosition(orbPosition)
	local windowConfig = Config.window
	local viewport = Scale.viewport
	local width = self.size.width
	local height = self.size.height

	local x, y
	if orbPosition then
		-- 优先停在悬浮球右侧(留一点间隙), 放不下就停左侧
		local gap = Scale.widthFraction(1.2)
		local orbWidth = Scale.widthFraction(Config.orb.width)
		local rightX = orbPosition.x + orbWidth + gap
		if rightX + width <= 0.98 then
			x = rightX
		else
			x = orbPosition.x - width - gap
		end
		y = orbPosition.y
	else
		x = (1 - width) / 2
		y = (1 - height) / 2
	end

	return {
		x = Scale.clamp(x, 0.01, math.max(0.01, 1 - width - 0.01)),
		y = Scale.clamp(y, 0.02, math.max(0.02, 1 - height - 0.02)),
	}
end

function Window:Open(orbPosition)
	if self._opened or self._destroyed then
		return self
	end
	self._opened = true

	if not self.position then
		local saved = Config.behavior.saveLayout and Storage.get("window") or nil
		if type(saved) == "table" and tonumber(saved.x) and tonumber(saved.y) then
			self.position = { x = tonumber(saved.x), y = tonumber(saved.y) }
		else
			self.position = self:_dockPosition(orbPosition)
		end
	end

	self.root.Position = UDim2.fromScale(self.position.x, self.position.y)
	self.root.Visible = true
	if self.hasCanvasGroup then
		Util.tween(self.root, { GroupTransparency = 0 }, Config.behavior.fadeDuration * 1.6)
	else
		self.root.BackgroundTransparency = 0
	end
	do
		-- 轻微弹入: 尺寸从 97% 回到 100%
		local w, h = self.size.width, self.size.height
		self.root.Size = UDim2.new(w * 0.97, 0, h * 0.97, 0)
		Util.tween(
			self.root,
			{ Size = UDim2.new(w, 0, h, 0) },
			0.16,
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out
		)
	end

	self.Opened:Fire()
	return self
end

function Window:Close()
	if not self._opened or self._destroyed then
		return self
	end
	if self.hasCanvasGroup then
		local fade = Util.tween(self.root, { GroupTransparency = 1 }, Config.behavior.fadeDuration)
		fade.Completed:Connect(function()
			if not self._destroyed then
				self.root.Visible = false
			end
		end)
	else
		self.root.Visible = false
	end
	self._opened = false
	self.Closed:Fire()
	return self
end

function Window:Toggle(orbPosition)
	if self._opened then
		self:Close()
	else
		self:Open(orbPosition)
	end
	return self
end

function Window:Minimize()
	if self.onMinimize then
		pcall(self.onMinimize)
	end
	self:Close()
	return self
end

function Window:IsOpen()
	return self._opened
end

--============================ 文本 ============================--
function Window:SetStatus(left, right)
	if left ~= nil then
		self.statusLeft.Text = left
	end
	if right ~= nil then
		self.statusRight.Text = right
	end
	return self
end

function Window:SetSubtitle(text)
	if self.subtitle then
		self.subtitle.Text = text
	end
	return self
end

--============================ 销毁 ============================--
function Window:Destroy()
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
	self.Closed:Destroy()
	self.Opened:Destroy()
	pcall(function()
		self.root:Destroy()
	end)
end

return Window
