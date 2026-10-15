--[[
	NewGUI  —  百分比自适应的 Roblox 客户端 UI 库(执行器专用)
	本文件由 tools/build.py 自动生成, 请勿手改; 改源码请改 src/ 下的模块。

	用法:
		loadstring(game:HttpGet("https://raw.githubusercontent.com/aa121314aa/new-GUI/main/dist/NewGUI.lua"))()
	版本: 见 NewGUI.Version
]]

local __modules = {}
local __cache = {}

local function require(name)
	local cached = __cache[name]
	if cached ~= nil then
		return cached
	end
	local factory = __modules[name]
	if factory == nil then
		error("[NewGUI] 模块不存在: " .. tostring(name) .. " (打包遗漏?)", 2)
	end
	local result = factory()
	if result == nil then
		result = true
	end
	__cache[name] = result
	return result
end

__modules['Components_Orb'] = function()
--[[
	NewGUI · Components/Orb
	长方形悬浮球(像素风小圆角)。

	特点:
		· 尺寸 = 基准轴百分比(Config.orb.width / height), 位置 = 视口百分比 → 转屏/改窗口自动跟随
		· 圆角 = 百分比像素值(Config.orb.corner, 默认 0.85% ≈ 720p 下 6px, 克制的像素风)
		· 可拖动(带阈值判定: 拖动不会误触发点击), 松开后位置按百分比存盘
		· 图标: 优先用 Assets 下载的 PNG, 没有则用 Glyph 矢量图标
]]

local Scale = require("Core_Scale")
local Theme = require("Core_Theme")
local Compat = require("Core_Compat")
local Config = require("Core_Config")
local Assets = require("Core_Assets")
local Storage = require("Core_Storage")
local Glyph = require("Core_Glyph")
local Signal = require("Core_Signal")
local Util = require("Core_Util")

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
end

__modules['Core_Assets'] = function()
--[[
	NewGUI · Core/Assets
	图片资产加载器(悬浮球/窗口图标用)。

	加载顺序:
		1. 执行器工作目录里已有的缓存文件     (NewGUI/assets/icons/xxx.png)
		2. 从仓库 raw 地址下载到工作目录      (只下缺失的那些, 下完缓存, 以后不再联网)
		3. 都不行 → 返回 nil, 调用方自动回退到 Core/Glyph 的矢量图标

	所以: 有网=全套图片图标; 无网/无文件权限=矢量图标, UI 不会因为一张图挂掉。
]]

local Compat = require("Core_Compat")
local Config = require("Core_Config")

local Assets = {}

local cache = {} -- name → assetPath | false(失败)
local failedAt = {} -- name → 上次失败时间(用于冷却, 避免失败后疯狂重试)
local pending = {} -- name → { callback, ... } 并发合并

-- 失败后多久允许自动重试(秒)。冷却期内重复请求直接回退矢量图标, 不重复打网络。
local RETRY_DELAY = 8
local folderReady = false
local stats = { downloaded = 0, cached = 0, failed = 0, fetched = 0 }

--============================ 基础 ============================--
--[=[ 确保工作目录存在 ]=]
local function ensureFolder()
	if folderReady then
		return true
	end
	if not Compat.IsFolder(Config.assets.folder) then
		Compat.MakeFolder(Config.assets.folder)
	end
	if not Compat.IsFolder(Config.assets.iconFolder) then
		Compat.MakeFolder(Config.assets.iconFolder)
	end
	folderReady = Compat.IsFolder(Config.assets.iconFolder)
	return folderReady
end

local function fileName(name)
	local mapped = Config.assets.icons[name]
	return mapped or (name .. ".png")
end

--[=[ PNG 魔数校验, 防止把 HTML 错误页当图片写进缓存 ]=]
local function looksLikePng(data)
	return type(data) == "string" and #data > 8 and string.sub(data, 1, 4) == "\137PNG"
end

--[=[ 资产系统是否可用(执行器要有 writefile + getcustomasset) ]=]
function Assets.usable()
	local info = Compat.Detect()
	return info.hasFile and info.hasCustomAsset
end

--[=[ 已经缓存好的资产路径(同步) ]=]
function Assets.path(name)
	if cache[name] and cache[name] ~= false then
		return cache[name]
	end
	return nil
end

function Assets.stats()
	return stats, Assets.usable()
end

--============================ 加载 ============================--
local function finish(name, result)
	local waiters = pending[name]
	pending[name] = nil
	if not waiters then
		return
	end
	for _, callback in ipairs(waiters) do
		Compat.Spawn(function()
			local ok, err = pcall(callback, result)
			if not ok then
				warn("[NewGUI] 资产回调报错(" .. name .. "): " .. tostring(err))
			end
		end)
	end
end

local function resolve(name)
	local path = Config.assets.iconFolder .. "/" .. fileName(name)

	-- 1) 本地缓存
	if Compat.IsFile(path) then
		local asset = Compat.GetCustomAsset(path)
		if asset then
			stats.cached = stats.cached + 1
			return asset
		end
	end

	-- 2) 远程下载
	if Config.assets.remote.enabled then
		local url = Config.assets.remote.base .. fileName(name)
		local body, err = Compat.HttpGet(url)
		if body and looksLikePng(body) then
			local ok = Compat.WriteFile(path, body)
			if ok and Compat.IsFile(path) then
				stats.fetched = stats.fetched + 1
				stats.downloaded = stats.downloaded + 1
				local asset = Compat.GetCustomAsset(path)
				if asset then
					return asset
				end
			end
		elseif body then
			warn("[NewGUI] 资产内容异常(不是 PNG): " .. url)
			stats.failed = stats.failed + 1
		else
			warn("[NewGUI] 资产下载失败: " .. tostring(err))
			stats.failed = stats.failed + 1
		end
	end

	return nil
end

--[=[
	异步取资产。callback(assetPath or nil) —— nil 时调用方走矢量兜底。
	force = true 时跳过"最近失败"的冷却, 立刻重试(界面上的重试按钮用)。
]=]
function Assets.load(name, callback, force)
	if not Assets.usable() then
		-- 明确不支持 → 立刻回退, 不浪费时间
		if callback then
			Compat.Spawn(function()
				callback(nil)
			end)
		end
		return
	end

	local cached = cache[name]
	local cooling = cached == false and not force and (os.clock() - (failedAt[name] or 0)) < RETRY_DELAY
	if cached ~= nil and not cooling then
		if callback then
			Compat.Spawn(function()
				callback(cached or nil)
			end)
		end
		return
	end

	if pending[name] then
		if callback then
			table.insert(pending[name], callback)
		end
		return
	end

	pending[name] = { callback }
	Compat.Spawn(function()
		local ok, asset = pcall(function()
			ensureFolder()
			return resolve(name)
		end)
		if not ok then
			warn("[NewGUI] 资产加载异常(" .. name .. "): " .. tostring(asset))
			asset = nil
		end
		if asset then
			cache[name] = asset
			failedAt[name] = nil
		else
			-- 记下失败时间: 过了冷却期再请求会自动重试
			cache[name] = false
			failedAt[name] = os.clock()
		end
		finish(name, asset)
	end)
end

--[=[
	清除"失败"标记, 让之前失败的资产可以重新拉取。返回被重置的条目数。
]=]
function Assets.retryFailed(disableCooldown)
	local count = 0
	for name, value in pairs(cache) do
		if value == false and not pending[name] then
			count = count + 1
			cache[name] = nil
			failedAt[name] = nil
		end
	end
	if disableCooldown then
		RETRY_DELAY = 0
	end
	return count
end

--[=[
	同步式获取(会阻塞等待)。适合初始化少量关键图标; 优先用 load()。
]=]
function Assets.loadSync(name, timeout)
	Assets.load(name, function(asset)
		cache["=" .. name] = asset or false
	end)
	local deadline = os.clock() + (timeout or 6)
	while cache["=" .. name] == nil and os.clock() < deadline do
		Compat.Wait(0.05)
	end
	local result = cache["=" .. name]
	cache["=" .. name] = nil
	return result or nil
end

--[=[ 批量预加载 ]=]
function Assets.preload(names, callback)
	local remaining = #names
	if remaining == 0 then
		if callback then
			callback()
		end
		return
	end
	for _, name in ipairs(names) do
		Assets.load(name, function()
			remaining = remaining - 1
			if remaining <= 0 and callback then
				callback()
			end
		end)
	end
end

--[=[ 清空本地缓存文件(下次运行重新下载) ]=]
function Assets.clearCache()
	local count = 0
	for name in pairs(Config.assets.icons) do
		local path = Config.assets.iconFolder .. "/" .. fileName(name)
		if Compat.IsFile(path) then
			local remove = Compat.Global("delfile")
			if type(remove) == "function" then
				pcall(remove, path)
				count = count + 1
			end
		end
		cache[name] = nil
		failedAt[name] = nil
	end
	return count
end

return Assets
end

__modules['Core_Compat'] = function()
--[[
	NewGUI · Core/Compat
	执行器适配层。把"各家执行器不一样的东西"全部收在这里:
		· 检测执行器 / 能力(HTTP、文件读写、自定义资产、gethui)
		· 找到合适的 GUI 父级(gethui → CoreGui → PlayerGui)
		· GUI 保护(protect_gui / syn.protect_gui)
		· 统一 HTTP / 文件 API

	支持: Synapse X / Script-Ware / Krnl / Fluxus / Wave / Hydrogen(Nihon) / Electron / Solara …
	没有执行器时(Studio)会自动降级到 PlayerGui, 逻辑仍可跑通。
]]

local Compat = {}

local Players = game:GetService("Players")

-- Lua 5.1 / Luau 通用 unpack
Compat.unpack = table.unpack or unpack

--[=[
	读取执行器全局(优先 getgenv(), 退回 _G)
]=]
local function rawEnv()
	local getter = rawget(_G, "getgenv")
	if type(getter) == "function" then
		local ok, env = pcall(getter)
		if ok and type(env) == "table" then
			return env
		end
	end
	return _G
end

function Compat.Env()
	local ok, env = pcall(rawEnv)
	return (ok and env) or _G
end

--[=[ 从执行器环境里安全取全局名 ]=]
function Compat.Global(name)
	local env = Compat.Env()
	local ok, value = pcall(function()
		return env[name]
	end)
	if ok and value ~= nil then
		return value
	end
	ok, value = pcall(function()
		return rawget(_G, name)
	end)
	if ok then
		return value
	end
	return nil
end

local function hasFunction(name)
	return type(Compat.Global(name)) == "function"
end

--[=[
	执行器检测。返回:
		{ name, isExecutor, isStudio, hasHttpGet, hasFile, hasCustomAsset, hasGethui }
]=]
function Compat.Detect()
	if Compat._info then
		return Compat._info
	end

	local info = {
		name = "未知环境",
		isExecutor = false,
		isStudio = false,
		hasHttpGet = false,
		hasFile = false,
		hasCustomAsset = false,
		hasGethui = false,
	}

	local ok, studio = pcall(function()
		return game:GetService("RunService"):IsStudio()
	end)
	info.isStudio = ok and studio == true

	-- 逐个指纹识别(顺序 = 常见程度)
	local fingerprints = {
		{ "Synapse X", function()
			return Compat.Global("syn") ~= nil
		end },
		{ "Script-Ware", function()
			local sw = Compat.Global("swh") or Compat.Global("SW")
			return sw ~= nil
		end },
		{ "Krnl", function()
			return rawget(_G, "KRNL_LOADED") ~= nil or rawget(_G, "KRNL_VER") ~= nil
		end },
		{ "Fluxus", function()
			return Compat.Global("fluxus") ~= nil or Compat.Global("Fluxus") ~= nil
		end },
		{ "Wave", function()
			return Compat.Global("Wave") ~= nil
		end },
		{ "Hydrogen / Nihon", function()
			return Compat.Global("Hydrogen") ~= nil or Compat.Global("Nihon") ~= nil
		end },
		{ "Electron", function()
			return Compat.Global("electron") ~= nil or Compat.Global("Electron") ~= nil
		end },
		{ "Solara", function()
			return Compat.Global("Solara") ~= nil
		end },
		{ "SirHurt", function()
			local ok2, val = pcall(function()
				return is_sirhurt_closure
			end)
			return ok2 and val ~= nil
		end },
	}

	for _, entry in ipairs(fingerprints) do
		local ok2, hit = pcall(entry[2])
		if ok2 and hit then
			info.name = entry[1]
			info.isExecutor = true
			break
		end
	end

	info.hasHttpGet = hasFunction("request") or hasFunction("http_request") or hasFunction("httpget")
	info.hasFile = hasFunction("writefile") and hasFunction("isfile")
	info.hasCustomAsset = hasFunction("getcustomasset")
	info.hasGethui = hasFunction("gethui")

	-- 通用执行器: 有文件/HTTP 能力但指纹未命中
	if not info.isExecutor and (info.hasFile or info.hasHttpGet or info.hasCustomAsset) then
		info.name = "通用执行器"
		info.isExecutor = true
	end
	if not info.isExecutor and info.isStudio then
		info.name = "Roblox Studio"
	end

	info.canUseAssets = info.hasFile and info.hasCustomAsset
	Compat._info = info
	return info
end

function Compat.IsExecutor()
	return Compat.Detect().isExecutor
end

--[=[
	尝试提升线程身份(部分执行器需要 identity 8 才能写 CoreGui)
]=]
function Compat.Elevate()
	local fn = Compat.Global("setthreadidentity") or Compat.Global("set_thread_identity")
	if type(fn) == "function" then
		pcall(fn, 8)
		return true
	end
	local syn = Compat.Global("syn")
	if type(syn) == "table" and type(syn.set_thread_identity) == "function" then
		pcall(syn.set_thread_identity, 8)
		return true
	end
	return false
end

local function canParentTo(instance)
	local ok = pcall(function()
		local probe = Instance.new("Folder")
		probe.Parent = instance
		probe:Destroy()
	end)
	return ok
end

--[=[
	找 GUI 父级: gethui() → CoreGui → PlayerGui
]=]
function Compat.GuiParent()
	local gethui = Compat.Global("gethui")
	if type(gethui) == "function" then
		local ok, parent = pcall(gethui)
		if ok and typeof(parent) == "Instance" then
			return parent, "gethui"
		end
	end

	local ok, core = pcall(function()
		return game:GetService("CoreGui")
	end)
	if ok and core and canParentTo(core) then
		return core, "CoreGui"
	end

	-- 有些执行器要先提权才能写 CoreGui
	if Compat.Elevate() then
		if ok and core and canParentTo(core) then
			return core, "CoreGui"
		end
	end

	local player = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait() or Players.LocalPlayer
	return player:WaitForChild("PlayerGui", 15), "PlayerGui"
end

--[=[
	保护 GUI(防止游戏的反作弊/自定义 CoreGui 清理逻辑删掉它)
]=]
function Compat.Protect(gui)
	if typeof(gui) ~= "Instance" then
		return false
	end
	local protect = Compat.Global("protect_gui")
	if type(protect) == "function" then
		local ok = pcall(protect, gui)
		if ok then
			return true
		end
	end
	local syn = Compat.Global("syn")
	if type(syn) == "table" and type(syn.protect_gui) == "function" then
		local ok = pcall(syn.protect_gui, gui)
		if ok then
			return true
		end
	end
	return false
end

--============================ HTTP ============================--
--[=[
	统一 HTTP GET。返回 body 或 nil, err
]=]
function Compat.HttpGet(url, timeout)
	assert(type(url) == "string", "[NewGUI] Compat.HttpGet 需要 URL 字符串")

	local request = Compat.Global("request")
	if type(request) == "function" then
		local ok, res = pcall(request, {
			Url = url,
			Method = "GET",
			Headers = { ["User-Agent"] = "NewGUI" },
		})
		if ok and type(res) == "table" and res.StatusCode and res.Body then
			if res.StatusCode >= 200 and res.StatusCode < 300 then
				return res.Body
			end
			return nil, "HTTP " .. tostring(res.StatusCode)
		end
	end

	local httpRequest = Compat.Global("http_request")
	if type(httpRequest) == "function" then
		local ok, res = pcall(httpRequest, { Url = url, Method = "GET" })
		if ok and type(res) == "table" and res.Body then
			return res.Body
		end
		ok, res = pcall(httpRequest, url)
		if ok and type(res) == "string" then
			return res
		end
	end

	local httpget = Compat.Global("httpget")
	if type(httpget) == "function" then
		local ok, res = pcall(httpget, url)
		if ok and type(res) == "string" then
			return res
		end
	end

	-- game:HttpGet (多数执行器注入)
	local ok, res = pcall(function()
		return game:HttpGet(url, true)
	end)
	if ok and type(res) == "string" then
		return res
	end

	-- Studio / 原生环境兜底(需开启 HTTP 请求, 且域名在允许列表内)
	local httpService = game:GetService("HttpService")
	local ok2, res2 = pcall(function()
		return httpService:GetAsync(url)
	end)
	if ok2 and type(res2) == "string" then
		return res2
	end

	return nil, "无法发起 HTTP 请求(执行器不支持或 HTTP 已禁用)"
end

--============================ 文件 ============================--
function Compat.WriteFile(path, data)
	local fn = Compat.Global("writefile")
	if type(fn) ~= "function" then
		return false, "该执行器不支持 writefile"
	end
	local ok, err = pcall(fn, path, data)
	if not ok then
		return false, tostring(err)
	end
	return true
end

function Compat.ReadFile(path)
	local fn = Compat.Global("readfile")
	if type(fn) ~= "function" then
		return nil, "该执行器不支持 readfile"
	end
	local ok, data = pcall(fn, path)
	if not ok then
		return nil, tostring(data)
	end
	return data
end

function Compat.IsFile(path)
	local fn = Compat.Global("isfile")
	if type(fn) ~= "function" then
		return false
	end
	local ok, res = pcall(fn, path)
	return ok and res == true
end

function Compat.IsFolder(path)
	local fn = Compat.Global("isfolder")
	if type(fn) ~= "function" then
		return false
	end
	local ok, res = pcall(fn, path)
	return ok and res == true
end

--[=[ 逐级创建文件夹, 兼容不支持递归创建的执行器 ]=]
function Compat.MakeFolder(path)
	local fn = Compat.Global("makefolder")
	if type(fn) ~= "function" then
		return false
	end
	local acc = nil
	for part in string.gmatch(path, "[^/\\]+") do
		acc = acc and (acc .. "/" .. part) or part
		if not Compat.IsFolder(acc) then
			pcall(fn, acc)
		end
	end
	return true
end

--[=[ 把执行器工作目录里的文件变成 Roblox 能用的 asset 路径 ]=]
function Compat.GetCustomAsset(path)
	local fn = Compat.Global("getcustomasset")
	if type(fn) ~= "function" then
		return nil, "该执行器不支持 getcustomasset"
	end
	local ok, res = pcall(fn, path)
	if ok and type(res) == "string" and #res > 0 then
		return res
	end
	return nil, tostring(res)
end

--============================ 任务 ============================--
function Compat.Spawn(fn, ...)
	if task and task.spawn then
		return task.spawn(fn, ...)
	end
	local co = coroutine.create(fn)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		warn("[NewGUI] 协程报错: " .. tostring(err))
	end
	return co
end

function Compat.Wait(seconds)
	if task and task.wait then
		return task.wait(seconds)
	end
	return wait(seconds)
end

function Compat.Delay(seconds, fn, ...)
	if task and task.delay then
		return task.delay(seconds, fn, ...)
	end
	local args = { ... }
	return Compat.Spawn(function()
		Compat.Wait(seconds)
		fn(unpack(args))
	end)
end

return Compat
end

__modules['Core_Config'] = function()
--[[
	NewGUI · Core/Config
	运行时配置。窗口尺寸、悬浮球尺寸等全部按"基准轴百分比"描述。
]]

local Scale = require("Core_Scale")

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
end

__modules['Core_Glyph'] = function()
--[[
	NewGUI · Core/Glyph
	纯矢量图标绘制器(不依赖任何网络资产)。

	用途:
		1. 没有网络 / 执行器不支持 getcustomasset 时, 悬浮球和窗口仍要有图标 —— 用这里的矢量图标兜底。
		2. 想加自定义图标时, 直接写 SVG path 数据(支持 M L H V C Q A Z 与相对指令),
		   这里有一个小型路径解析器, 会把它转成旋转的 Frame 折线。

	坐标系: 与 Lucide 一致 —— 0..24 的视口, 描边宽度 2。
	调用:
		Glyph.draw(iconFrame, "sparkle", { color = Color3.new(1,1,1), stroke = 2 })
]]

local Scale = require("Core_Scale")
local Signal = require("Core_Signal")

local Glyph = {}

-- Luau 有 math.atan2, 标准 Lua 只有 math.atan(y, x); 这里统一
local function atan2(y, x)
	if math.atan2 then
		return math.atan2(y, x)
	end
	return math.atan(y, x)
end

--============================ 路径解析 ============================--
local function tokenize(d)
	local tokens = {}
	for cmd, nums in string.gmatch(d, "([MmLlHhVvCcSsQqTtAaZz])([^MmLlHhVvCcSsQqTtAaZz]*)") do
		local args = {}
		for num in string.gmatch(nums, "[-+]?%d*%.?%d+") do
			args[#args + 1] = tonumber(num)
		end
		tokens[#tokens + 1] = { cmd = cmd, args = args }
	end
	return tokens
end

-- 圆弧(A/a) → 三次贝塞尔, 用标准端点参数化
local function arcToPoints(x1, y1, rx, ry, rotation, largeArc, sweep, x2, y2)
	local points = {}
	if rx == 0 or ry == 0 then
		return { { x2, y2 } }
	end
	local phi = math.rad(rotation)
	local cosPhi, sinPhi = math.cos(phi), math.sin(phi)

	local dx2, dy2 = (x1 - x2) / 2, (y1 - y2) / 2
	local x1p = cosPhi * dx2 + sinPhi * dy2
	local y1p = -sinPhi * dx2 + cosPhi * dy2

	rx, ry = math.abs(rx), math.abs(ry)
	local lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
	if lambda > 1 then
		local scale = math.sqrt(lambda)
		rx, ry = rx * scale, ry * scale
	end

	local sign = (largeArc ~= sweep) and 1 or -1
	local numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
	local denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
	local coefficient = sign * math.sqrt(math.max(0, numerator / denominator))
	local cxp = coefficient * (rx * y1p) / ry
	local cyp = coefficient * (-(ry * x1p) / rx)

	local cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2
	local cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2

	local function angle(ux, uy, vx, vy)
		local dot = ux * vx + uy * vy
		local len = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
		local a = math.acos(math.clamp and math.clamp(dot / len, -1, 1) or math.max(-1, math.min(1, dot / len)))
		if ux * vy - uy * vx < 0 then
			a = -a
		end
		return a
	end

	local theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
	local delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
	if sweep == 0 and delta > 0 then
		delta = delta - 2 * math.pi
	elseif sweep == 1 and delta < 0 then
		delta = delta + 2 * math.pi
	end

	local steps = math.max(2, math.ceil(math.abs(delta) / (math.pi / 8)))
	for i = 1, steps do
		local t = theta1 + delta * (i / steps)
		local px, py = math.cos(t) * rx, math.sin(t) * ry
		points[#points + 1] = {
			cosPhi * px - sinPhi * py + cx,
			sinPhi * px + cosPhi * py + cy,
		}
	end
	return points
end

--[=[
	把 path 字符串 → 若干条折线(每条 = {x, y} 数组)
]=]
function Glyph.pathToPolylines(d)
	local tokens = tokenize(d)
	local lines = {}
	local current = {}
	local x, y = 0, 0
	local startX, startY = 0, 0
	local lastCmd = nil

	local function push(px, py, move)
		if move then
			if #current > 1 then
				lines[#lines + 1] = current
			end
			current = { { px, py } }
		else
			current[#current + 1] = { px, py }
		end
	end

	for _, token in ipairs(tokens) do
		local cmd = token.cmd
		local relative = cmd:lower() == cmd
		local upper = string.upper(cmd)
		local args = token.args
		local i = 1

		if upper == "M" or upper == "L" or upper == "T" then
			while i <= #args do
				local nx, ny = args[i], args[i + 1]
				if relative then
					nx, ny = x + nx, y + ny
				end
				if upper == "M" and i == 1 then
					push(nx, ny, true)
					startX, startY = nx, ny
				else
					push(nx, ny, false)
				end
				x, y = nx, ny
				i = i + 2
			end
		elseif upper == "H" or upper == "V" then
			while i <= #args do
				if upper == "H" then
					local nx = relative and x + args[i] or args[i]
					push(nx, y, false)
					x = nx
				else
					local ny = relative and y + args[i] or args[i]
					push(x, ny, false)
					y = ny
				end
				i = i + 1
			end
		elseif upper == "C" or upper == "S" or upper == "Q" then
			local step = (upper == "C" and 6) or 4
			while i <= #args do
				local x1, y1, x2, y2, nx, ny
				if upper == "C" then
					x1, y1, x2, y2, nx, ny = args[i], args[i + 1], args[i + 2], args[i + 3], args[i + 4], args[i + 5]
				elseif upper == "S" then
					x1, y1 = x + (x - (lastCmd and lastCmd.x or x)), y + (y - (lastCmd and lastCmd.y or y))
					x2, y2, nx, ny = args[i], args[i + 1], args[i + 2], args[i + 3]
				else
					x1, y1 = args[i], args[i + 1]
					x2, y2 = args[i], args[i + 1]
					nx, ny = args[i + 2], args[i + 3]
				end
				if relative then
					x1, y1 = x + x1, y + y1
					x2, y2 = x + x2, y + y2
					nx, ny = x + nx, y + ny
				end
				local steps = 8
				for s = 1, steps do
					local t = s / steps
					local mt = 1 - t
					local px, py
					if upper == "Q" then
						px = mt * mt * x + 2 * mt * t * x1 + t * t * nx
						py = mt * mt * y + 2 * mt * t * y1 + t * t * ny
					else
						px = mt * mt * mt * x + 3 * mt * mt * t * x1 + 3 * mt * t * t * x2 + t * t * t * nx
						py = mt * mt * mt * y + 3 * mt * mt * t * y1 + 3 * mt * t * t * y2 + t * t * t * ny
					end
					push(px, py, false)
				end
				lastCmd = { x = x2, y = y2 }
				x, y = nx, ny
				i = i + step
			end
		elseif upper == "A" then
			while i <= #args do
				local nx, ny = args[i + 5], args[i + 6]
				if relative then
					nx, ny = x + nx, y + ny
				end
				local pts = arcToPoints(x, y, args[i], args[i + 1], args[i + 2], args[i + 3], args[i + 4], nx, ny)
				for _, point in ipairs(pts) do
					push(point[1], point[2], false)
				end
				x, y = nx, ny
				i = i + 7
			end
		elseif upper == "Z" then
			push(startX, startY, false)
			if #current > 1 then
				lines[#lines + 1] = current
			end
			current = {}
			x, y = startX, startY
		end
	end

	if #current > 1 then
		lines[#lines + 1] = current
	end
	return lines
end

--============================ 内置图标(同 Lucide, ISC 许可) ============================--
-- 全部是 0..24 视口的描边路径, 和 Lucide 的观感一致。
Glyph.icons = {
	-- 名称与 Config.assets.icons 保持一致(短名), 括号里是 Lucide 原名
	sparkle = "M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z M5 3v4 M19 17v4 M3 5h4 M17 19h4",
	grid = "M3 3h7v7H3z M14 3h7v7h-7z M14 14h7v7h-7z M3 14h7v7H3z", -- layout-grid
	settings = "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.6 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.6a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z",
	info = "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20z M12 16v-4 M12 8h.01",
	close = "M18 6 6 18 M6 6l12 12", -- x
	minimize = "M5 12h14", -- minus
	search = "M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16z M21 21l-4.3-4.3",
	player = "M12 13a4 4 0 1 0 0-8 4 4 0 0 0 0 8z M20 21a8 8 0 0 0-16 0", -- user-round
	sliders = "M10 5H3 M12 19H3 M14 3v4 M16 17v4 M21 12h-9 M21 19h-5 M21 5h-7 M8 10v4 M8 12H3", -- sliders-horizontal
	terminal = "M3 5h18v14H3z M7 9l3 3-3 3 M13 15h4", -- square-terminal
	check = "M20 6 9 17l-5-5",
	chevron = "M6 9l6 6 6-6", -- chevron-down
	arrow = "M5 12h14 M13 5l7 7-7 7", -- arrow-right
	bolt = "M13 2 3 14h9l-1 8 10-12h-9l1-8z", -- zap
	eye = "M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z",
	shield = "M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z",
	trash = "M3 6h18 M8 6V4h8v2 M19 6l-1 14H6L5 6 M10 11v6 M14 11v6", -- trash-2
	copy = "M9 9h11v11H9z M5 15H4V4h11v1",
	book = "M12 7v14 M3 18a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h5a4 4 0 0 1 4 4 4 4 0 0 1 4-4h5a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-6a3 3 0 0 0-3 3 3 3 0 0 0-3-3z", -- book-open
}

--[=[
	别名: 直接用 Lucide 原名也能取到图标(方便从 lucide.dev 复制名字)
]=]
Glyph.aliases = {
	x = "close",
	minus = "minimize",
	zap = "bolt",
	["arrow-right"] = "arrow",
	["chevron-down"] = "chevron",
	["layout-grid"] = "grid",
	["sliders-horizontal"] = "sliders",
	["square-terminal"] = "terminal",
	["user-round"] = "player",
	["trash-2"] = "trash",
	["book-open"] = "book",
	["gear"] = "settings",
	cog = "settings",
	["circle-info"] = "info",
	["circle-x"] = "close",
	["circle-check"] = "check",
}

--[=[ 解析图标名(支持别名), 找不到返回 nil 和已注册的名字列表 ]=]
function Glyph.resolve(name)
	local key = Glyph.icons[name] and name or Glyph.aliases[name]
	if key and Glyph.icons[key] then
		return key
	end
	return nil
end

--[=[ 列出全部可用图标名 ]=]
function Glyph.list()
	local names = {}
	for name in pairs(Glyph.icons) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

--============================ 绘制 ============================--
local function newLine(parent, zIndex)
	local line = Instance.new("Frame")
	line.BackgroundColor3 = parent.BackgroundColor3
	line.BorderSizePixel = 0
	line.ZIndex = zIndex or parent.ZIndex + 1
	line.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0) -- 圆头线, 拼接处不易看出接缝
	corner.Parent = line
	return line
end

--[=[
	把图标画到 parent(Frame)里。
	opts:
		color       线颜色
		stroke      描边宽度(0..24 坐标系, 默认 2)
		zIndex      图层的 ZIndex
		padding     内边距(图标尺寸的百分比, 默认 6)
		thickness   相对父容器尺寸的线宽上限(默认 0.14)
	返回一个带 :Refresh() 和 :Destroy() 的对象。
]=]
function Glyph.draw(parent, iconName, opts)
	opts = opts or {}
	local key = Glyph.resolve(iconName)
	if not key then
		warn("[NewGUI] 未知矢量图标: " .. tostring(iconName) .. " → 改用 info 兜底")
		key = "info"
	end
	local path = Glyph.icons[key]

	local holder = Instance.new("Frame")
	holder.Name = "Glyph_" .. tostring(iconName)
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = opts.zIndex or (parent.ZIndex + 1)
	holder.Parent = parent

	local color = opts.color or parent.BackgroundColor3 or Color3.new(1, 1, 1)
	local stroke = opts.stroke or 2
	local polylines = Glyph.pathToPolylines(path)
	local lines = {}
	local alive = true

	local function refresh()
		if not alive then
			return
		end
		local size = holder.AbsoluteSize
		if size.X < 2 or size.Y < 2 then
			return
		end
		local box = math.min(size.X, size.Y) * (1 - (opts.padding or 6) / 100 * 2)
		local thickness = math.max(1, (box * stroke / 24))
		thickness = math.min(thickness, math.max(1, math.min(size.X, size.Y) * (opts.thickness or 0.16)))
		local originX = (size.X - box) / 2
		local originY = (size.Y - box) / 2
		local unit = box / 24
		local index = 0

		for _, polyline in ipairs(polylines) do
			for i = 1, #polyline - 1 do
				local ax, ay = polyline[i][1], polyline[i][2]
				local bx, by = polyline[i + 1][1], polyline[i + 1][2]
				local x1 = originX + ax * unit
				local y1 = originY + ay * unit
				local x2 = originX + bx * unit
				local y2 = originY + by * unit
				local dx, dy = x2 - x1, y2 - y1
				local length = math.sqrt(dx * dx + dy * dy)
				if length > 0.35 then
					index = index + 1
					local line = lines[index]
					if not line then
						line = newLine(holder, holder.ZIndex + 1)
						line.AnchorPoint = Vector2.new(0.5, 0.5)
						lines[index] = line
					end
					line.BackgroundColor3 = color
					line.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
					line.Size = UDim2.fromOffset(length + thickness * 0.35, thickness)
					line.Rotation = math.deg(atan2(dy, dx))
				end
			end
		end
		-- 多余线段隐藏(图标尺寸变小时)
		for i = index + 1, #lines do
			lines[i].Visible = false
		end
	end

	refresh()
	local connection = Scale.Changed:Connect(refresh)

	local controller = {}
	function controller:Refresh()
		refresh()
	end
	function controller:SetColor(newColor)
		color = newColor
		refresh()
	end
	function controller:Destroy()
		alive = false
		connection:Disconnect()
		if holder.Parent then
			holder:Destroy()
		end
	end
	controller.instance = holder

	if holder.Destroying then
		holder.Destroying:Connect(function()
			alive = false
			connection:Disconnect()
		end)
	end
	return controller
end

--[=[ 预解析所有图标(可选, 提前热身, 避免首帧卡顿) ]=]
function Glyph.warmup()
	for _, path in pairs(Glyph.icons) do
		Glyph.pathToPolylines(path)
	end
end

return Glyph
end

__modules['Core_Scale'] = function()
--[[
	NewGUI · Core/Scale
	百分比缩放系统 —— 整套 UI 唯一的尺寸来源。

	规则(重要):
		· 基准轴 = min(视口宽, 视口高)。手机竖屏是宽, 电脑/平板横屏是高。
		· 所有尺寸都写成"基准轴的百分比", 由 Scale.px() 换算成当时的像素值。
		· 位置一律用 UDim2.fromScale(归一化 0~1), 所以改窗口/转屏后比例不变。
		· 视口变化时 Scale.Changed 触发, 各控件重新换算一次 → 永远按百分比跟随屏幕。

	常用 API:
		Scale.px(2.5)      → 基准轴的 2.5% 等于多少像素
		Scale.u(2.5)       → UDim.new(0, 上面那个像素值)
		Scale.pct(2.5)     → 0.025 (纯 scale 小数, 给 UDim2.fromScale 用)
		Scale.font(3.2)    → 字号(带上下限钳制)
		Scale.viewport     → 当前视口 Vector2
		Scale.Changed      → 视口尺寸/相机变化信号
]]

local Signal = require("Core_Signal")

local Scale = {}

Scale.Changed = Signal.new("Scale.Changed")
Scale.viewport = Vector2.new(1280, 720)

-- 字号钳制范围(像素)。UI 全面按百分比缩放时, 极端分辨率下字号需要护栏才看得清。
Scale.minFontPx = 9
Scale.maxFontPx = 34

--[=[ 基准轴: 屏幕较短边 ]=]
function Scale.axis()
	return math.min(Scale.viewport.X, Scale.viewport.Y)
end

--[=[ 百分比 → 像素 ]=]
function Scale.px(percent)
	return Scale.axis() * ((percent or 0) / 100)
end

--[=[ 百分比 → UDim 偏移 ]=]
function Scale.u(percent)
	return UDim.new(0, Scale.px(percent))
end

--[=[ 百分比 → scale 小数(0.025 这种, 给 UDim2.fromScale 用) ]=]
function Scale.pct(percent)
	return (percent or 0) / 100
end

--[=[
	尺寸/位置的语义工具。

	注意区别(这是最容易搞混的地方):
		· "基准轴百分比"(Config 里绝大多数尺寸) → 像素值 = Scale.px(百分比)
		  例: 悬浮球宽 7.6% → Scale.px(7.6)
		· "视口百分比"(窗口宽高、悬浮球在屏幕上的位置) → 直接用 UDim2 scale
		  例: 窗口宽 62% → UDim2.fromScale(0.62, 0)

	UDim2 的 scale 永远相对"父容器/视口", 所以基准轴百分比必须换算成 Offset。
]=]

--[=[ 基准轴百分比 → UDim2(宽, 高) ]=]
function Scale.size(widthPercent, heightPercent)
	return UDim2.fromOffset(Scale.px(widthPercent), Scale.px(heightPercent))
end

--[=[ 绑定"基准轴百分比"尺寸, 屏幕变化自动重算 ]=]
function Scale.bindSize(instance, widthPercent, heightPercent)
	return Scale.bind(instance, function()
		return { Size = UDim2.fromOffset(Scale.px(widthPercent), Scale.px(heightPercent)) }
	end)
end

--[=[ 视口百分比 → UDim2 位置(x 按视口宽, y 按视口高) ]=]
function Scale.viewportPosition(xPercent, yPercent)
	local viewport = Scale.viewport
	local xPx = viewport.X * (xPercent or 0) / 100
	local yPx = viewport.Y * (yPercent or 0) / 100
	return UDim2.fromOffset(xPx, yPx)
end

--[=[ 基准轴百分比宽度换算成"视口宽度百分比"(用于边界/Dock 计算) ]=]
function Scale.widthFraction(widthPercent)
	return Scale.px(widthPercent) / math.max(Scale.viewport.X, 1)
end

function Scale.heightFraction(heightPercent)
	return Scale.px(heightPercent) / math.max(Scale.viewport.Y, 1)
end

--[=[ 百分比 → 字号(带上下限) ]=]
function Scale.font(percent, minimum, maximum)
	local size = Scale.px(percent)
	local lo = minimum or Scale.minFontPx
	local hi = maximum or Scale.maxFontPx
	return math.floor(math.clamp and math.clamp(size, lo, hi) or math.min(math.max(size, lo), hi) + 0.5)
end

function Scale.round(n)
	return math.floor(n + 0.5)
end

function Scale.clamp(n, minimum, maximum)
	if minimum > maximum then
		minimum, maximum = maximum, minimum
	end
	if n < minimum then
		return minimum
	elseif n > maximum then
		return maximum
	end
	return n
end

function Scale.lerp(a, b, alpha)
	return a + (b - a) * alpha
end

--============================ 绑定重算 ============================--
-- UDim2.fromScale / UDim scale 会自动跟随屏幕, 不需要重算;
-- 但"像素值"属性(字号、圆角、描边、图标线段)必须重算一次。
-- Scale.bind 负责这件事: 现在跑一次, 屏幕变了再跑, 实例销毁时自动断开。

--[=[
	Scale.bind(frame, function()
		return { TextSize = Scale.font(3.2) }
	end)
]=]
function Scale.bind(instance, compute)
	local alive = true

	local function apply()
		if not alive then
			return
		end
		local ok, props = pcall(compute)
		if not ok or type(props) ~= "table" then
			return
		end
		for key, value in pairs(props) do
			pcall(function()
				instance[key] = value
			end)
		end
	end

	apply()
	local connection = Scale.Changed:Connect(apply)

	if instance.Destroying then
		instance.Destroying:Connect(function()
			alive = false
			connection:Disconnect()
		end)
	end
	return apply
end

--[=[ 注册一个"屏幕变化就重跑"的函数, 返回断开函数 ]=]
function Scale.onChange(fn)
	local connection = Scale.Changed:Connect(function()
		local ok, err = pcall(fn)
		if not ok then
			warn("[NewGUI] Scale.onChange 报错: " .. tostring(err))
		end
	end)
	return function()
		connection:Disconnect()
	end
end

--[=[ 当前视口(相机优先, 相机没准备好时用 DrawableSize 兜底) ]=]
local function readViewport()
	local camera = workspace.CurrentCamera
	if camera and camera.ViewportSize and camera.ViewportSize.X > 0 then
		return camera.ViewportSize
	end
	return nil
end

--[=[ 重新读取视口, 有变化才触发 Changed(返回是否变化) ]=]
function Scale.Refresh()
	local viewport = readViewport()
	if not viewport then
		return false
	end
	if viewport.X == Scale.viewport.X and viewport.Y == Scale.viewport.Y then
		return false
	end
	Scale.viewport = viewport
	Scale.Changed:Fire(viewport)
	return true
end

local watching = nil
local cameraConnection = nil

local function watchCamera(camera)
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end
	if not camera then
		return
	end
	cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		Scale.Refresh()
	end)
	Scale.Refresh()
end

--[=[ 初始化(幂等)。init.lua 会自动调用, 也可以手动调用 ]=]
function Scale.Init()
	local camera = workspace.CurrentCamera
	if camera then
		watchCamera(camera)
	end
	if not watching then
		watching = true
		workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			watchCamera(workspace.CurrentCamera)
		end)
		-- 注入瞬间相机可能还没建好, 这里等它出现后自动接管
		local RunService = game:GetService("RunService")
		local bootConnection
		bootConnection = RunService.RenderStepped:Connect(function()
			if Scale.viewport.X > 0 and cameraConnection then
				bootConnection:Disconnect()
				return
			end
			watchCamera(workspace.CurrentCamera)
		end)
	end
	return Scale
end

return Scale
end

__modules['Core_Signal'] = function()
--[[
	NewGUI · Core/Signal
	极简事件系统。不用 BindableEvent(会被执行器沙盒限制/需要实例), 纯 Lua 实现, 可传任意值。

	用法:
		local Signal = require("Core_Signal")
		local clicked = Signal.new("Clicked")
		local conn = clicked:Connect(function(a, b) print(a, b) end)
		clicked:Fire(1, 2)
		conn:Disconnect()
]]

-- Lua 5.1 是 unpack, Luau/5.2+ 是 table.unpack
local unpackValues = table.unpack or unpack

local Signal = {}
Signal.__index = Signal

function Signal.new(name)
	return setmetatable({
		_name = name or "Signal",
		_handlers = {},
		_nextId = 0,
	}, Signal)
end

--[=[ 连接回调, 返回一个带 Connected 字段的连接对象(与 Roblox API 风格一致) ]=]
function Signal:Connect(fn)
	assert(type(fn) == "function", "[NewGUI] Signal:Connect 需要传入函数")
	self._nextId = self._nextId + 1
	local id = self._nextId
	self._handlers[id] = fn

	local conn = { Connected = true, _id = id }
	function conn:Disconnect()
		if not self.Connected then
			return
		end
		self.Connected = false
		self._owner._handlers[self._id] = nil
	end
	conn._owner = self
	return conn
end

--[=[ 只触发一次的连接 ]=]
function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

--[=[ 触发事件; 单个回调出错不会影响其它回调 ]=]
function Signal:Fire(...)
	local snapshot, count = {}, 0
	for id, fn in pairs(self._handlers) do
		count = count + 1
		snapshot[count] = fn
	end
	local n = select("#", ...)
	local args = { ... }
	for i = 1, count do
		local ok, err = pcall(snapshot[i], unpackValues(args, 1, n))
		if not ok then
			warn("[NewGUI] " .. self._name .. " 回调报错: " .. tostring(err))
		end
	end
end

function Signal:DisconnectAll()
	self._handlers = {}
end

-- 让连接对象支持 Trash 回收
function Signal:Destroy()
	self:DisconnectAll()
end

return Signal
end

__modules['Core_Storage'] = function()
--[[
	NewGUI · Core/Storage
	极轻量持久化(窗口位置/尺寸/悬浮球位置)。
	用 readfile/writefile + HttpService:JSONEncode, 不支持文件 API 时静默降级为"不保存"。
]]

local Compat = require("Core_Compat")
local Config = require("Core_Config")

local Storage = {}

local HttpService = game:GetService("HttpService")
local data = nil
local writable = nil

local function filePath()
	return Config.assets.folder .. "/settings.json"
end

local function canWrite()
	if writable ~= nil then
		return writable
	end
	writable = Compat.IsFile(filePath()) or (Compat.Global("writefile") ~= nil and Compat.Global("readfile") ~= nil)
	return writable
end

--[=[ 读取全部设置(带缓存) ]=]
function Storage.all()
	if data then
		return data
	end
	data = {}
	if canWrite() and Compat.IsFile(filePath()) then
		local raw = Compat.ReadFile(filePath())
		if raw and #raw > 0 then
			local ok, decoded = pcall(function()
				return HttpService:JSONDecode(raw)
			end)
			if ok and type(decoded) == "table" then
				data = decoded
			else
				warn("[NewGUI] settings.json 解析失败, 已重置")
			end
		end
	end
	return data
end

function Storage.get(key, default)
	local value = Storage.all()[key]
	if value == nil then
		return default
	end
	return value
end

function Storage.set(key, value)
	Storage.all()[key] = value
	return Storage.save()
end

--[=[ 写入磁盘(自动节流, 频繁拖动不会疯狂写文件) ]=]
local lastSave = 0
local queued = false

function Storage.save(force)
	if not canWrite() then
		return false
	end
	if not force and os.clock() - lastSave < 0.4 then
		if not queued then
			queued = true
			Compat.Delay(0.45, function()
				queued = false
				Storage.save(true)
			end)
		end
		return false
	end
	lastSave = os.clock()
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(data or {})
	end)
	if not ok then
		return false
	end
	local written = Compat.WriteFile(filePath(), encoded)
	if not written and Config.dev.debug then
		warn("[NewGUI] 设置写入失败(执行器无文件权限)")
	end
	return written
end

function Storage.clear()
	data = {}
	return Storage.save(true)
end

return Storage
end

__modules['Core_Theme'] = function()
--[[
	NewGUI · Core/Theme
	配色 + 圆角令牌。圆角是"像素风"的小数值(默认 0.92% 基准轴 ≈ 720p 下约 6px),
	所有控件都从这里取圆角, 想统一改大小只改这一处。
]]

local Scale = require("Core_Scale")

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
end

__modules['Core_Util'] = function()
--[[
	NewGUI · Core/Util
	通用小工具: 属性批量设置、补间、去重连接、毫秒格式化等。
]]

local Compat = require("Core_Compat")

local Util = {}

local TweenService = game:GetService("TweenService")

--[=[ 按百分比/%s 写属性的统一入口: set(inst, { TextSize = 14 }) ]=]
function Util.set(instance, props)
	for key, value in pairs(props or {}) do
		instance[key] = value
	end
	return instance
end

--[=[ 补间到目标属性, 返回 Tween(已在跑) ]=]
function Util.tween(instance, props, duration, style, direction)
	local info = TweenInfo.new(
		duration or 0.12,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)
	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

--[=[ 立刻跳到目标值(不补间), 用于关闭动画等场景 ]=]
function Util.setInstant(instance, props)
	for key, value in pairs(props or {}) do
		pcall(function()
			instance[key] = value
		end)
	end
end

--[=[ 等一个条件成立(带超时), 返回是否成功 ]=]
function Util.waitFor(predicate, timeout)
	local deadline = os.clock() + (timeout or 5)
	while os.clock() < deadline do
		local ok, result = pcall(predicate)
		if ok and result then
			return true
		end
		Compat.Wait(0.05)
	end
	return false
end

--[=[ 生成 [内容] 形式的括号颜色码(有些执行器日志支持) ]=]
function Util.tag(name, color)
	local palette = {
		accent = "RGB(88,140,255)",
		success = "RGB(72,199,142)",
		danger = "RGB(235,88,92)",
		warn = "RGB(240,178,74)",
	}
	return string.format("[%s]", color and palette[color] or name)
end

--[=[ 安全读取实例的某个属性 ]=]
function Util.get(instance, prop, default)
	local ok, value = pcall(function()
		return instance[prop]
	end)
	if ok and value ~= nil then
		return value
	end
	return default
end

--[=[ 判断实例还活着 ]=]
function Util.alive(instance)
	return typeof(instance) == "Instance" and instance.Parent ~= nil
end

--[=[ 数值格式化(短) ]=]
function Util.shortNumber(n)
	n = n or 0
	if n >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.floor(n))
end

--[=[ 向上找带指定名字的祖先 ]=]
function Util.findAncestor(instance, name)
	local current = instance
	while current and current ~= game do
		if current.Name == name then
			return current
		end
		current = current.Parent
	end
	return nil
end

--[=[
	判断某坐标是否落在实例的矩形区域内(用于悬浮球拖拽/点击判定)
]=]
function Util.pointInGui(instance, position)
	local abs = instance.AbsolutePosition
	local size = instance.AbsoluteSize
	return position.X >= abs.X
		and position.X <= abs.X + size.X
		and position.Y >= abs.Y
		and position.Y <= abs.Y + size.Y
end

--[=[ 颜色 → 十六进制(资产生成/调试用) ]=]
function Util.toHex(color)
	return string.format(
		"#%02X%02X%02X",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

return Util
end

__modules['UI_Notify'] = function()
--[[
	NewGUI · UI/Notify
	轻提示(toast)。右上角堆叠, 百分比尺寸, 自动淡出。
	用法: Notify.send(parentGui, { title = "已保存", text = "设置写入本地", kind = "success" })
]]

local Scale = require("Core_Scale")
local Theme = require("Core_Theme")
local Util = require("Core_Util")
local Glyph = require("Core_Glyph")
local Compat = require("Core_Compat")

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
end

__modules['UI_Pages'] = function()
--[[
	NewGUI · UI/Pages
	内置页面。想加自己的页面, 照抄这里的写法即可:

		window:AddPage({
			name = "我的页面",
			icon = "bolt",
			build = function(scroll, window, ctx)
				Widgets.label(scroll, "内容", { font = "title" })
				Widgets.button(scroll, "按钮", { icon = "bolt", callback = function() end })
			end,
		})
	页面里的所有控件都是百分比尺寸, 转屏自动适配。
]]

local Scale = require("Core_Scale")
local Theme = require("Core_Theme")
local Config = require("Core_Config")
local Compat = require("Core_Compat")
local Assets = require("Core_Assets")
local Storage = require("Core_Storage")
local Widgets = require("UI_Widgets")
local Glyph = require("Core_Glyph")
local Version = require("Version")
local Util = require("Core_Util")

local Pages = {}

local palette = Theme.palette
local metrics = Theme.metrics

--============================ 小工具 ============================--
local function v(info, key, default)
	local value = info[key]
	if value == nil then
		return default
	end
	if type(value) == "boolean" then
		return value and "是" or "否"
	end
	return tostring(value)
end

--[=[
	键值对行(左标题 + 右值)
]=]
local function infoRow(parent, index, title, value)
	local row = Instance.new("Frame")
	row.Name = "Info" .. index
	row.BackgroundColor3 = palette.card
	row.BorderSizePixel = 0
	row.LayoutOrder = index
	row.Size = UDim2.new(1, 0, 0, 0)
	row.Parent = parent
	Theme.corner(row, "control")
	Theme.stroke(row, palette.divider, Theme.strokeWidth.thin)
	Theme.padding(row, 1.0)
	Scale.bind(row, function()
		return { Size = UDim2.new(1, 0, 0, Scale.px(metrics.controlHeight)) }
	end)

	Widgets.label(row, title, {
		font = "small",
		color = palette.textDim,
		size = UDim2.fromScale(0.42, 1),
	})
	local valueLabel = Widgets.label(row, value, {
		font = "small",
		color = palette.text,
		align = Enum.TextXAlignment.Right,
		size = UDim2.new(0.58, 0, 1, 0),
	})
	valueLabel.Position = UDim2.fromScale(0.42, 0)
	return valueLabel
end

--============================ 首页 ============================--
function Pages.home(window, ctx)
	return {
		name = "概览",
		icon = "grid",
		build = function(scroll)
			Widgets.label(scroll, "运行环境", { font = "title", order = 1 })
			Widgets.separator(scroll, { order = 2 })

			local info = Compat.Detect()
			local parent, parentName = Compat.GuiParent()
			local viewport = Scale.viewport
			local rows = {
				{ "执行器", info.name },
				{ "GUI 父级", parentName or "未知" },
				{ "保护 GUI", Compat.Global("protect_gui") and "已启用" or "未提供" },
				{ "屏幕分辨率", string.format("%d x %d", viewport.X, viewport.Y) },
				{ "缩放基准(短边)", string.format("%d px", math.floor(Scale.axis())) },
				{ "文件 / 图片资产", Assets.usable() and "可用" or "不可用(使用矢量图标)" },
			}
			for index, entry in ipairs(rows) do
				infoRow(scroll, index, entry[1], entry[2])
			end

			Widgets.section(scroll, "快捷操作", { order = 20 })
			local actions = Widgets.list(scroll, { gap = metrics.gapSmall })
			actions.LayoutOrder = 21

			Widgets.button(actions, "重载界面", {
				icon = "bolt",
				variant = "primary",
				order = 1,
				callback = function()
					if ctx.reload then
						ctx.reload()
					end
				end,
			})
			Widgets.button(actions, "重新下载图标资产", {
				icon = "arrow",
				order = 2,
				callback = function()
					-- 清本地缓存 + 重置失败标记 + 立即重新拉取
					Assets.clearCache()
					Assets.retryFailed(true)
					local names = {}
					for name in pairs(Config.assets.icons) do
						names[#names + 1] = name
					end
					ctx.notify({ title = "开始重新下载图标", kind = "info" })
					Assets.preload(names, function()
						local stats = Assets.stats()
						ctx.notify({
							title = "图标资产已刷新",
							text = string.format("下载 %d · 缓存命中 %d · 失败 %d", stats.downloaded, stats.cached, stats.failed),
							kind = "success",
						})
					end)
				end,
			})
			Widgets.button(actions, "重置窗口位置", {
				icon = "sliders",
				order = 3,
				callback = function()
					Storage.all().window = nil
					Storage.save(true)
					window.position = nil
					ctx.notify({ title = "窗口位置已重置", kind = "success" })
				end,
			})

			Widgets.section(scroll, "缩放说明", { order = 30 })
			Widgets.label(
				scroll,
				"所有控件的尺寸都写成一屏短边的百分比: 例如悬浮球宽 7.6%、高 6.0%、圆角 0.85%。"
					.. "换分辨率、手机转屏、缩小窗口都不会变形, 只会等比缩放。",
				{ font = "small", color = palette.textDim, order = 31, height = metrics.labelHeight * 3 }
			)
			local explain = scroll:FindFirstChild("Label")
			if explain then
				explain.TextWrapped = true
				explain.TextYAlignment = Enum.TextYAlignment.Top
			end
		end,
	}
end

--============================ 界面 ============================--
local THEMES = {
	{ name = "霓虹蓝", accent = Color3.fromRGB(88, 140, 255), stroke = Color3.fromRGB(72, 78, 98) },
	{ name = "紫罗兰", accent = Color3.fromRGB(150, 110, 255), stroke = Color3.fromRGB(84, 76, 120) },
	{ name = "薄荷绿", accent = Color3.fromRGB(72, 199, 142), stroke = Color3.fromRGB(70, 104, 90) },
	{ name = "橙金", accent = Color3.fromRGB(240, 178, 74), stroke = Color3.fromRGB(110, 92, 60) },
	{ name = "玫红", accent = Color3.fromRGB(235, 96, 140), stroke = Color3.fromRGB(110, 70, 88) },
}

function Pages.interface(window, ctx)
	return {
		name = "界面",
		icon = "sliders",
		build = function(scroll)
			Widgets.label(scroll, "外观", { font = "title", order = 1 })
			Widgets.separator(scroll, { order = 2 })
			Widgets.label(scroll, "改配色会重建界面(马上生效), 改圆角是实时的。", {
				font = "small",
				color = palette.textDim,
				order = 3,
			})

			local list = Widgets.list(scroll, { gap = metrics.gapSmall })
			list.LayoutOrder = 4

			local themeNames = {}
			for _, theme in ipairs(THEMES) do
				themeNames[#themeNames + 1] = theme.name
			end

			local savedTheme = Storage.get("theme", "霓虹蓝")
			Widgets.dropdown(list, {
				text = "主题配色",
				icon = "eye",
				options = themeNames,
				default = savedTheme,
				overlay = window.overlay,
				order = 1,
				changed = function(value)
					Storage.set("theme", value)
					ctx.notify({ title = "配色已切换: " .. value, text = "正在重建界面", kind = "success" })
					if ctx.reload then
						ctx.reload()
					end
				end,
			})

			Widgets.slider(list, {
				text = "控件圆角",
				order = 2,
				min = 0.2,
				max = 2.6,
				step = 0.05,
				default = Config.radiusOverride or Theme.radius.control,
				suffix = "%",
				changed = function(value)
					Config.radiusOverride = value
					Theme.radius.control = value
					Theme.radius.small = math.max(0.2, value * 0.75)
					Theme.refresh()
				end,
			})

			Widgets.slider(list, {
				text = "描边粗细",
				order = 3,
				min = 0.06,
				max = 0.4,
				step = 0.01,
				default = Theme.strokeWidth.normal,
				suffix = "%",
				changed = function(value)
					Theme.strokeWidth.normal = value
					Theme.refresh()
				end,
			})

			Widgets.section(list, "窗口", { order = 10 })
			Widgets.keybind(list, {
				text = "开关快捷键",
				icon = "bolt",
				default = Config.behavior.keybind,
				order = 11,
				changed = function(key)
					Config.behavior.keybind = key
					ctx.notify({ title = "快捷键已更新", text = key.Name, kind = "success" })
				end,
			})
			Widgets.toggle(list, {
				text = "记住窗口位置与大小",
				icon = "shield",
				default = Config.behavior.saveLayout,
				order = 12,
				changed = function(value)
					Config.behavior.saveLayout = value
				end,
			})
			Widgets.toggle(list, {
				text = "调试日志",
				icon = "terminal",
				default = Config.dev.debug,
				order = 13,
				changed = function(value)
					Config.dev.debug = value
				end,
			})
		end,
	}
end

--============================ 悬浮球 ============================--
local ORB_ICONS = { "sparkle", "grid", "settings", "zap", "shield", "book-open", "user-round", "terminal" }

function Pages.orb(window, ctx)
	return {
		name = "悬浮球",
		icon = "sparkle",
		build = function(scroll)
			Widgets.label(scroll, "悬浮球", { font = "title", order = 1 })
			Widgets.separator(scroll, { order = 2 })

			local list = Widgets.list(scroll, { gap = metrics.gapSmall })
			list.LayoutOrder = 3

			Widgets.dropdown(list, {
				text = "图标",
				icon = "sparkle",
				options = ORB_ICONS,
				default = Config.orb.icon,
				overlay = window.overlay,
				order = 1,
				changed = function(value)
					Config.orb.icon = value
					if ctx.orb then
						ctx.orb:SetIcon(value)
					end
				end,
			})

			Widgets.slider(list, {
				text = "宽度",
				order = 2,
				min = 5,
				max = 14,
				step = 0.1,
				default = Config.orb.width,
				suffix = "%",
				changed = function(value)
					Config.orb.width = value
					Theme.refresh()
				end,
			})

			Widgets.slider(list, {
				text = "高度",
				order = 3,
				min = 4,
				max = 14,
				step = 0.1,
				default = Config.orb.height,
				suffix = "%",
				changed = function(value)
					Config.orb.height = value
					Theme.refresh()
				end,
			})

			Widgets.slider(list, {
				text = "像素圆角",
				order = 4,
				min = 0,
				max = 3,
				step = 0.05,
				default = Config.orb.corner,
				suffix = "%",
				changed = function(value)
					Config.orb.corner = value
					Theme.refresh()
				end,
			})

			Widgets.slider(list, {
				text = "图标大小",
				order = 5,
				min = 1.2,
				max = 5,
				step = 0.05,
				default = Config.orb.iconSize,
				suffix = "%",
				changed = function(value)
					Config.orb.iconSize = value
					if ctx.orb then
						ctx.orb:SetIconSize(value)
					end
				end,
			})

			Widgets.toggle(list, {
				text = "显示悬浮球",
				icon = "eye",
				default = true,
				order = 6,
				changed = function(value)
					if ctx.orb then
						ctx.orb:SetVisible(value)
					end
				end,
			})

			Widgets.button(list, "恢复默认位置", {
				icon = "arrow",
				order = 7,
				callback = function()
					Storage.all().orb = nil
					Storage.save(true)
					ctx.notify({ title = "悬浮球位置已重置", kind = "success" })
					if ctx.reload then
						ctx.reload()
					end
				end,
			})

			Widgets.section(scroll, "说明", { order = 10 })
			Widgets.label(
				scroll,
				"悬浮球可以拖动, 位置按屏幕百分比保存; 拖动不会误触点击, 松手才判定。点一下即可打开主界面。",
				{ font = "small", color = palette.textDim, order = 11, height = metrics.labelHeight * 3 }
			)
		end,
	}
end

--============================ 素材 ============================--
function Pages.assets(window, ctx)
	return {
		name = "素材",
		icon = "book-open",
		build = function(scroll)
			Widgets.label(scroll, "图片资产", { font = "title", order = 1 })
			Widgets.separator(scroll, { order = 2 })

			local list = Widgets.list(scroll, { gap = metrics.gapSmall })
			list.LayoutOrder = 3

			Widgets.label(
				list,
				"图标优先使用 PNG(执行器 getcustomasset), 失败时自动回退到内置矢量图标。",
				{ font = "small", color = palette.textDim, order = 1, height = metrics.labelHeight * 2.4 }
			)

			local statsRow = infoRow(list, 2, "下载 / 缓存命中", "")
			Scale.bind(statsRow, function()
				local stats, usable = Assets.stats()
				return {
					Text = usable and string.format("%d / %d (失败 %d)", stats.downloaded, stats.cached, stats.failed)
						or "不可用",
				}
			end)

			Widgets.button(list, "预加载全部图标", {
				icon = "arrow",
				variant = "primary",
				order = 3,
				callback = function()
					local names = {}
					for name in pairs(Config.assets.icons) do
						names[#names + 1] = name
					end
					ctx.notify({ title = "开始预加载", text = tostring(#names) .. " 个图标", kind = "info" })
					Assets.preload(names, function()
						ctx.notify({ title = "图标加载完成", kind = "success" })
					end)
				end,
			})

			Widgets.button(list, "清空本地图标缓存", {
				icon = "trash",
				variant = "danger",
				order = 4,
				callback = function()
					local count = Assets.clearCache()
					ctx.notify({ title = "已删除缓存文件", text = tostring(count) .. " 个", kind = "success" })
				end,
			})

			Widgets.section(list, "图标预览(矢量)", { order = 10 })
			local grid = Instance.new("Frame")
			grid.Name = "GlyphGrid"
			grid.BackgroundTransparency = 1
			grid.LayoutOrder = 11
			grid.Size = UDim2.new(1, 0, 0, 0)
			grid.Parent = list
			local columns = 8
			local count = 0
			for name in pairs(Glyph.icons) do
				count = count + 1
			end
			local rows = math.ceil(count / columns)
			Scale.bind(grid, function()
				return { Size = UDim2.new(1, 0, 0, Scale.px(metrics.iconSize * 2.6) * rows * 1.6) }
			end)
			local gridLayout = Instance.new("UIGridLayout")
			gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
			gridLayout.CellSize = UDim2.fromScale(1 / columns, 1 / math.max(rows, 1))
			gridLayout.CellPadding = UDim2.fromScale(0.01, 0.05)
			gridLayout.Parent = grid

			local index = 0
			for name in pairs(Glyph.icons) do
				index = index + 1
				local cell = Instance.new("Frame")
				cell.Name = name
				cell.BackgroundColor3 = palette.card
				cell.BorderSizePixel = 0
				cell.LayoutOrder = index
				cell.Parent = grid
				Theme.corner(cell, "small")
				Glyph.draw(cell, name, { color = palette.textDim, stroke = 2, padding = 22 })
			end
		end,
	}
end

--============================ 关于 ============================--
function Pages.about(window, ctx)
	return {
		name = "关于",
		icon = "info",
		build = function(scroll)
			Widgets.label(scroll, Version.name .. "  " .. Version.version, { font = "title", order = 1 })
			Widgets.label(scroll, Version.description, {
				font = "small",
				color = palette.textDim,
				order = 2,
				height = metrics.labelHeight * 2.4,
			})
			Widgets.separator(scroll, { order = 3 })

			local list = Widgets.list(scroll, { gap = metrics.gapSmall })
			list.LayoutOrder = 4

			infoRow(list, 1, "版本", Version.version .. " (" .. Version.channel .. ")")
			infoRow(list, 2, "仓库", Version.repo)
			infoRow(list, 3, "一键加载", "loadstring(game:HttpGet('" .. Version.raw .. "'))()")

			Widgets.button(list, "复制加载链接", {
				icon = "copy",
				order = 4,
				callback = function()
					local setclipboard = Compat.Global("setclipboard")
					if type(setclipboard) == "function" then
						local ok = pcall(setclipboard, "loadstring(game:HttpGet('" .. Version.raw .. "'))()")
						ctx.notify({
							title = ok and "已复制到剪贴板" or "复制失败",
							kind = ok and "success" or "error",
						})
					else
						ctx.notify({ title = "该执行器没有 setclipboard", kind = "warn" })
					end
				end,
			})

			Widgets.button(list, "卸载界面", {
				icon = "trash",
				variant = "danger",
				order = 5,
				callback = function()
					if ctx.unload then
						ctx.unload()
					end
				end,
			})

			Widgets.section(scroll, "许可", { order = 10 })
			Widgets.label(
				scroll,
				"图标来自 Lucide (ISC License), 已内置矢量回退版本; 界面代码为 NewGUI 项目自有实现。",
				{ font = "small", color = palette.textDim, order = 11, height = metrics.labelHeight * 2.4 }
			)
		end,
	}
end

--[=[ 注册全部内置页面 ]=]
function Pages.install(window, ctx)
	window:AddPage(Pages.home(window, ctx))
	window:AddPage(Pages.interface(window, ctx))
	window:AddPage(Pages.orb(window, ctx))
	window:AddPage(Pages.assets(window, ctx))
	window:AddPage(Pages.about(window, ctx))
	window:BuildNavigation()
	return window
end

return Pages
end

__modules['UI_Widgets'] = function()
--[[
	NewGUI · UI/Widgets
	控件库。所有控件:
		· 宽度/高度用百分比(基准轴), 位置用 scale → 随屏幕大小自动变化
		· 圆角/字号/描边用 Theme 的像素级绑定 → 屏幕变化时重算
		· 没有 emoji, 图标走 Assets(图片) → Glyph(矢量) 双通道

	返回的控件对象都是 table, 带 :Set(...) 之类的小方法, 不直接暴露实例细节,
	需要底层实例时用 object.instance。
]]

local Scale = require("Core_Scale")
local Theme = require("Core_Theme")
local Glyph = require("Core_Glyph")
local Assets = require("Core_Assets")
local Util = require("Core_Util")

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

--[=[
	UserInputService 这类全局连接不会随控件销毁自动断开。
	这里统一挂到实例的 Destroying 上, 避免重建界面后旧控件仍在响应输入。
]=]
local function trackGlobal(instance, connection)
	if instance.Destroying then
		instance.Destroying:Connect(function()
			pcall(function()
				connection:Disconnect()
			end)
		end)
	end
	return connection
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
	-- 全局连接: 控件销毁时自动断开(否则重建界面后会残留在输入事件上)
	trackGlobal(
		row,
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
	)
	trackGlobal(
		row,
		UserInputService.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = false
			end
		end)
	)

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

		connection = trackGlobal(row, UserInputService.InputBegan:Connect(function(input, processed)
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
		end))
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
end

__modules['UI_Window'] = function()
--[[
	NewGUI · UI/Window
	主窗口: 标题栏 + 侧边栏导航 + 内容区 + 状态栏。

	· 尺寸/位置全部百分比(基准轴/视口), UISizeConstraint 做上下限, 转屏自动跟随
	· 标题栏拖动、右下角缩放, 位置尺寸落盘
	· 用 CanvasGroup 做整窗淡入淡出(单一属性补间, 不掉帧)
	· Overlay 层专门放下拉菜单等浮层, 不受内容区裁剪影响
]]

local Scale = require("Core_Scale")
local Theme = require("Core_Theme")
local Compat = require("Core_Compat")
local Config = require("Core_Config")
local Storage = require("Core_Storage")
local Widgets = require("UI_Widgets")
local Signal = require("Core_Signal")
local Util = require("Core_Util")

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
	-- 所有 UserInputService 连接都登记下来, 销毁时统一断开(否则重建后旧窗口仍在响应)
	local connections = self._connections

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

	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
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
	end))

	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
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
	end))

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

	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
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
	end))

	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
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
	end))
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
end

__modules['Version'] = function()
--[[ NewGUI 版本信息 ]]

return {
	name = "NewGUI",
	version = "0.1.0",
	channel = "dev",
	repo = "https://github.com/aa121314aa/new-GUI",
	raw = "https://raw.githubusercontent.com/aa121314aa/new-GUI/main/dist/NewGUI.lua",
	description = "轻量、百分比自适应、多执行器兼容的 Roblox 客户端 UI 库",
}
end

__modules['init'] = function()
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

local Config = require("Core_Config")
local Scale = require("Core_Scale")
local Theme = require("Core_Theme")
local Compat = require("Core_Compat")
local Storage = require("Core_Storage")
local Assets = require("Core_Assets")
local Version = require("Version")
local Signal = require("Core_Signal")
local Util = require("Core_Util")

local Orb = require("Components_Orb")
local Window = require("UI_Window")
local Widgets = require("UI_Widgets")
local Pages = require("UI_Pages")
local Notify = require("UI_Notify")
local Glyph = require("Core_Glyph")

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
end

return require('init')
