--[[
	NewGUI · 测试用 Roblox 环境桩(stub)

	只在本地/CI 里跑: 给 tools/sim.py 提供 Instance/game/Enum/task 等最小可用实现,
	让整套 UI 构建代码能在没有 Roblox 的环境里跑一遍, 用来抓运行时错误。
	不参与 dist 打包。
]]

local M = {}

--============================ 工具 ============================--
local function isCallable(value)
	return type(value) == "function" or (type(value) == "table" and getmetatable(value) and getmetatable(value).__call)
end

local function shallowCopy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

M.errors = {}

local function record(kind, message)
	table.insert(M.errors, kind .. ": " .. tostring(message))
end
M.record = record

--============================ Signal ============================--
local function newSignal(name)
	local signal = { _name = name, _handlers = {} }
	function signal:Connect(fn)
		local conn = { Connected = true }
		table.insert(self._handlers, conn)
		conn.fn = fn
		function conn:Disconnect()
			self.Connected = false
			for index, item in ipairs(signal._handlers) do
				if item == self then
					table.remove(signal._handlers, index)
					break
				end
			end
		end
		function conn:Fire(...)
			local ok, err = pcall(fn, ...)
			if not ok then
				record("连接回调", err)
			end
		end
		return conn
	end
	function signal:Once(fn)
		return self:Connect(fn)
	end
	function signal:Wait()
		return nil
	end
	function signal:Fire(...)
		for _, conn in ipairs(shallowCopy(self._handlers)) do
			if conn.Connected then
				local ok, err = pcall(conn.fn, ...)
				if not ok then
					record("信号 " .. tostring(self._name), err)
				end
			end
		end
	end
	return signal
end

M.newSignal = newSignal

--============================ 数据类型 ============================--
local function vector2(x, y)
	local v = { X = x or 0, Y = y or 0 }
	v.Magnitude = math.sqrt(v.X * v.X + v.Y * v.Y)
	function v:__add(other)
		return vector2(self.X + other.X, self.Y + other.Y)
	end
	function v:__sub(other)
		return vector2(self.X - other.X, self.Y - other.Y)
	end
	return setmetatable(v, {
		__index = function(t, k)
			if k == "Magnitude" then
				return math.sqrt(t.X * t.X + t.Y * t.Y)
			end
			if k == "Unit" then
				local magnitude = math.max(math.sqrt(t.X * t.X + t.Y * t.Y), 1e-6)
				return vector2(t.X / magnitude, t.Y / magnitude)
			end
			return nil
		end,
		__add = function(a, b)
			return vector2(a.X + b.X, a.Y + b.Y)
		end,
		__sub = function(a, b)
			return vector2(a.X - b.X, a.Y - b.Y)
		end,
	})
end

local function vector3(x, y, z)
	return { X = x or 0, Y = y or 0, Z = z or 0 }
end

local function color3(r, g, b)
	local c = { R = r or 0, G = g or 0, B = b or 0 }
	c.__type = "Color3"
	return setmetatable(c, {
		__index = {
			Lerp = function(self, other, alpha)
				return color3(
					self.R + (other.R - self.R) * alpha,
					self.G + (other.G - self.G) * alpha,
					self.B + (other.B - self.B) * alpha
				)
			end,
		},
	})
end

--============================ Instance ============================--
local EVENT_NAMES = {
	Changed = true,
	ChildAdded = true,
	ChildRemoved = true,
	DescendantAdded = true,
	Destroying = true,
	AncestryChanged = true,
	MouseEnter = true,
	MouseLeave = true,
	MouseMoved = true,
	MouseButton1Click = true,
	MouseButton1Down = true,
	MouseButton1Up = true,
	InputBegan = true,
	InputChanged = true,
	InputEnded = true,
	Focused = true,
	FocusLost = true,
	Activated = true,
	RenderStepped = true,
	Heartbeat = true,
	Stepped = true,
	PreRender = true,
	Completed = true,
}

local function getPropertyChangedSignal(prop)
	return newSignal("GetPropertyChangedSignal(" .. tostring(prop) .. ")")
end

local instanceMethods = {}

function instanceMethods:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	if self._destroying then
		self._destroying:Fire()
	end
	local parent = rawget(self, "_parent")
	if parent and parent._children then
		for index, child in ipairs(parent._children) do
			if child == self then
				table.remove(parent._children, index)
				break
			end
		end
	end
	self._parent = nil
	self._destroyedFlag = true
end

function instanceMethods:GetChildren()
	return shallowCopy(self._children or {})
end

function instanceMethods:GetDescendants()
	local out = {}
	local function walk(node)
		for _, child in ipairs(node._children or {}) do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end

function instanceMethods:FindFirstChild(name)
	for _, child in ipairs(self._children or {}) do
		if child.Name == name then
			return child
		end
	end
	return nil
end

function instanceMethods:WaitForChild(name, timeout)
	local found = self:FindFirstChild(name)
	if found then
		return found
	end
	-- 桩环境里不做真等待, 直接造一个(保证启动流程不卡死)
	local child = M.newInstance("Frame")
	child.Name = name
	child.Parent = self
	return child
end

function instanceMethods:IsA(class)
	if self.ClassName == class then
		return true
	end
	-- 粗略继承表
	local abstract = {
		Frame = "GuiObject",
		TextLabel = "GuiObject",
		TextButton = "GuiObject",
		ImageLabel = "GuiObject",
		ScrollingFrame = "GuiObject",
		CanvasGroup = "GuiObject",
		Folder = "Instance",
		ScreenGui = "LayerCollector",
	}
	return abstract[self.ClassName] == class or class == "Instance"
end

function instanceMethods:GetPropertyChangedSignal(prop)
	if not self._signals then
		self._signals = {}
	end
	self._signals[prop] = self._signals[prop] or getPropertyChangedSignal(prop)
	return self._signals[prop]
end

function instanceMethods:SetAttribute() end
function instanceMethods:GetAttribute()
	return nil
end

function instanceMethods:Clone()
	return M.newInstance(self.ClassName)
end

function instanceMethods:GetFullName()
	return self.Name
end

function instanceMethods:ClearAllChildren()
	for _, child in ipairs(shallowCopy(self._children or {})) do
		child:Destroy()
	end
end

function instanceMethods:GetGuiObjectsAtPosition()
	return {}
end

local instanceMeta

instanceMeta = {
	__index = function(self, key)
		local stored = rawget(self, "_props")
		if stored and stored[key] ~= nil then
			return stored[key]
		end
		local method = instanceMethods[key]
		if method then
			return method
		end
		if EVENT_NAMES[key] then
			self._events = self._events or {}
			self._events[key] = self._events[key] or newSignal(key)
			return self._events[key]
		end
		if key == "Parent" then
			return rawget(self, "_parent")
		elseif key == "ClassName" then
			return rawget(self, "_className")
		end
		-- 真实 Roblox 不会返回 nil 的常用属性(桩里补上默认值, 保持行为一致)
		local classDefaults = M.CLASS_DEFAULTS[rawget(self, "_className")]
		if classDefaults and classDefaults[key] ~= nil then
			return classDefaults[key]
		end
		local defaults = M.PROPERTY_DEFAULTS
		if defaults[key] ~= nil then
			return defaults[key]
		end
		if key == "Name" then
			return rawget(self, "_name")
		elseif key == "_className" or key == "_parent" then
			return rawget(self, key)
		elseif key == "AbsolutePosition" then
			return vector2(10, 10)
		elseif key == "AbsoluteSize" then
			return vector2(120, 40)
		elseif key == "AbsoluteContentSize" then
			return vector2(120, 300)
		end
		return nil
	end,
	__newindex = function(self, key, value)
		if key == "Parent" then
			local oldParent = rawget(self, "_parent")
			if oldParent and oldParent._children then
				for index, child in ipairs(oldParent._children) do
					if child == self then
						table.remove(oldParent._children, index)
						break
					end
				end
			end
			rawset(self, "_parent", value)
			if value then
				value._children = value._children or {}
				table.insert(value._children, self)
			end
			return
		end
		if type(value) == "function" then
			-- 桩里允许挂方法(如 :Moved 之类), 直接存
		end
		local props = rawget(self, "_props")
		if not props then
			props = {}
			rawset(self, "_props", props)
		end
		local previous = props[key]
		props[key] = value
		if previous ~= value and self._signals and self._signals[key] then
			self._signals[key]:Fire(value)
		end
		return
	end,
	__tostring = function(self)
		return "Instance(" .. tostring(rawget(self, "_className")) .. ")"
	end,
}

-- 按类别的默认值(Roblox 真实默认)
M.CLASS_DEFAULTS = {
	ScrollingFrame = { ClipsDescendants = true, CanvasSize = nil },
	CanvasGroup = { ClipsDescendants = true },
	Frame = { ClipsDescendants = false },
}

M.PROPERTY_DEFAULTS = {
	ZIndex = 1,
	LayoutOrder = 0,
	Rotation = 0,
	TextSize = 14,
	BackgroundTransparency = 0,
	ImageTransparency = 0,
	TextTransparency = 0,
	GroupTransparency = 0,
	Visible = true,
	Text = "",
	ClipsDescendants = false,
	BorderSizePixel = 1,
	Active = false,
	Selectable = false,
	ScrollBarThickness = 4,
	CanvasSize = nil,
}

function M.newInstance(className)
	local object = setmetatable({
		_children = {},
		_parent = nil,
		_props = {},
		_className = className or "Instance",
		_name = className or "Instance",
	}, instanceMeta)
	return object
end

--============================ 环境装配 ============================--
function M.install(options)
	options = options or {}

	_G.Instance = { new = function(className)
		return M.newInstance(className)
	end }
	_G.Vector2 = { new = vector2, zero = vector2(0, 0) }
	_G.Vector3 = { new = vector3 }
	_G.Color3 = {
		new = color3, -- 0..1
		fromRGB = function(r, g, b) -- 0..255 → 0..1(与 Roblox 一致)
			return color3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
		end,
		fromHSV = function(h, sat, v)
			-- 简化版 HSV → RGB(够预览用)
			local i = math.floor(h * 6)
			local f = h * 6 - i
			local p, q, t = v * (1 - sat), v * (1 - f * sat), v * (1 - (1 - f) * sat)
			local r, g, b
			local m = i % 6
			if m == 0 then r, g, b = v, t, p
			elseif m == 1 then r, g, b = q, v, p
			elseif m == 2 then r, g, b = p, v, t
			elseif m == 3 then r, g, b = p, q, v
			elseif m == 4 then r, g, b = t, p, v
			else r, g, b = v, p, q end
			return color3(r, g, b)
		end,
	}
	_G.UDim = { new = function(scale, offset)
		return { Scale = scale or 0, Offset = offset or 0 }
	end }
	_G.UDim2 = {
		new = function(xs, xo, ys, yo)
			return { X = { Scale = xs or 0, Offset = xo or 0 }, Y = { Scale = ys or 0, Offset = yo or 0 } }
		end,
		fromScale = function(xs, ys)
			return { X = { Scale = xs or 0, Offset = 0 }, Y = { Scale = ys or 0, Offset = 0 } }
		end,
		fromOffset = function(xo, yo)
			return { X = { Scale = 0, Offset = xo or 0 }, Y = { Scale = 0, Offset = yo or 0 } }
		end,
	}
	_G.TweenInfo = { new = function(...)
		return { ... }
	end }

	_G.task = {
		spawn = function(fn, ...)
			local ok, err = pcall(fn, ...)
			if not ok then
				record("task.spawn", err)
			end
			return true
		end,
		delay = function(_, fn, ...)
			local ok, err = pcall(fn, ...)
			if not ok then
				record("task.delay", err)
			end
			return true
		end,
		defer = function(fn, ...)
			local ok, err = pcall(fn, ...)
			if not ok then
				record("task.defer", err)
			end
			return true
		end,
		wait = function()
			return 0
		end,
	}
	_G.wait = function()
		return 0
	end
	_G.spawn = function(fn, ...)
		return task.spawn(fn, ...)
	end

	_G.unpack = _G.unpack or table.unpack

	_G.typeof = function(value)
		if type(value) == "table" and getmetatable(value) == instanceMeta then
			return "Instance"
		end
		return type(value)
	end

	-- Enum: 自动生成并缓存, 保证 == 比较成立
	local enumCache = {}
	_G.Enum = setmetatable({}, {
		__index = function(_, category)
			enumCache[category] = enumCache[category] or setmetatable({}, {
				__index = function(cat, item)
					local value = { Name = item, Value = 0, EnumType = category }
					rawset(cat, item, value)
					return value
				end,
			})
			return enumCache[category]
		end,
	})

	-- Luau 专属函数补齐
	if not math.atan2 then
		math.atan2 = function(y, x)
			return math.atan(y, x)
		end
	end
	if not string.split then
		string.split = function(text, separator)
			local out = {}
			for part in string.gmatch(text, "([^" .. separator .. "]+)") do
				table.insert(out, part)
			end
			return out
		end
	end
	if not table.find then
		table.find = function(list, value)
			for index, item in ipairs(list) do
				if item == value then
					return index
				end
			end
			return nil
		end
	end

	-- math.clamp(luau 有, lua 没有)
	if not math.clamp then
		math.clamp = function(n, minimum, maximum)
			if n < minimum then
				return minimum
			elseif n > maximum then
				return maximum
			end
			return n
		end
	end

	-- 服务
	local services = {}
	local function service(name)
		if services[name] then
			return services[name]
		end
		local instance = M.newInstance(name)
		instance.Name = name
		services[name] = instance
		return instance
	end

	local camera = M.newInstance("Camera")
	camera.ViewportSize = vector2(options.viewportWidth or 1280, options.viewportHeight or 720)
	camera.Parent = M.newInstance("Workspace")

	local workspaceInstance = M.newInstance("Workspace")
	workspaceInstance.Camera = camera
	workspaceInstance.CurrentCamera = camera
	services.Workspace = workspaceInstance

	local localPlayer = M.newInstance("Player")
	localPlayer.Name = "LocalPlayer"
	local playerGui = M.newInstance("PlayerGui")
	playerGui.Name = "PlayerGui"
	playerGui.Parent = localPlayer
	services.LocalPlayer = localPlayer

	local players = service("Players")
	players.LocalPlayer = localPlayer

	local runService = service("RunService")
	runService.IsStudio = function()
		return false
	end

	local tweenService = service("TweenService")
	function tweenService:Create(instance, info, props)
		local completed = newSignal("Tween.Completed")
		local tween = { Completed = completed }
		function tween:Play()
			if tween._played then
				return
			end
			tween._played = true
			-- 桩环境直接跳到目标值
			for key, value in pairs(props) do
				pcall(function()
					instance[key] = value
				end)
			end
			completed:Fire(Enum.PlaybackState.Completed)
		end
		function tween:Cancel() end
		function tween:Pause() end
		return tween
	end

	local httpService = service("HttpService")
	function httpService:JSONEncode(value)
		local function encode(v)
			local t = type(v)
			if t == "nil" then
				return "null"
			elseif t == "boolean" or t == "number" then
				return tostring(v)
			elseif t == "string" then
				return string.format("%q", v)
			elseif t == "table" then
				local isArray = #v > 0
				local parts = {}
				if isArray then
					for _, item in ipairs(v) do
						table.insert(parts, encode(item))
					end
					return "[" .. table.concat(parts, ",") .. "]"
				end
				for key, item in pairs(v) do
					table.insert(parts, string.format("%q", tostring(key)) .. ":" .. encode(item))
				end
				return "{" .. table.concat(parts, ",") .. "}"
			end
			return "null"
		end
		return encode(value)
	end
	function httpService:JSONDecode(text)
		return M.jsonDecode(text)
	end
	function httpService:GetAsync(url)
		return M.httpGet and M.httpGet(url) or nil
	end

	_G.workspace = workspaceInstance
	_G.game = {
		GetService = function(_, name)
			if name == "CoreGui" then
				error("CoreGui 访问被拒绝(模拟真实受限环境)", 2)
			end
			if name == "Players" then
				return players
			end
			if name == "RunService" then
				return runService
			end
			if name == "TweenService" then
				return tweenService
			end
			if name == "HttpService" then
				return httpService
			end
			return service(name)
		end,
		HttpGet = function(_, url)
			if M.httpGet then
				local ok, result = pcall(M.httpGet, url)
				if ok and result then
					return result
				end
			end
			error("Http 已禁用(桩环境)", 2)
		end,
		Players = players,
		Workspace = workspaceInstance,
	}
	_G.shared = {}
	_G.getgenv = function()
		return _G
	end
	_G.printidentity = function() end
	_G.setthreadidentity = function() end
	_G.warn = _G.warn or print

	-- 执行器文件/资产 API(桩里真的读写磁盘, 方便端到端验证资产流程)
	_G.writefile = function(path, data)
		if not M.writeFile then
			error("桩环境未启用文件写入", 2)
		end
		return M.writeFile(path, data)
	end
	_G.readfile = function(path)
		if not M.readFile then
			error("桩环境未启用文件读取", 2)
		end
		return M.readFile(path)
	end
	_G.isfile = function(path)
		if not M.isFile then
			error("桩环境未启用 isfile", 2)
		end
		return M.isFile(path)
	end
	_G.isfolder = function(path)
		if not M.isFolder then
			error("桩环境未启用 isfolder", 2)
		end
		return M.isFolder(path)
	end
	_G.makefolder = function(path)
		if not M.makeFolder then
			error("桩环境未启用 makefolder", 2)
		end
		return M.makeFolder(path)
	end
	_G.getcustomasset = function(path)
		if not M.isFile or not M.isFile(path) then
			error("文件不存在: " .. tostring(path), 2)
		end
		return "rbxasset://stub/" .. tostring(path)
	end
	_G.request = function(options)
		if not M.httpGet then
			error("桩环境未启用 request", 2)
		end
		local body, code = M.httpGet(options.Url)
		if not body then
			error("HTTP " .. tostring(code), 2)
		end
		return { StatusCode = code or 200, Body = body, Success = true }
	end

	return {
		services = services,
		camera = camera,
		workspace = workspaceInstance,
		players = players,
		screenGuiParent = playerGui,
	}
end

-- 简易 JSON 解析(只支持本库用到的结构)
function M.jsonDecode(text)
	local pos = 1
	local function skip()
		while pos <= #text and string.match(string.sub(text, pos, pos), "%s") do
			pos = pos + 1
		end
	end
	local parseValue
	local function parseString()
		pos = pos + 1
		local out = {}
		while pos <= #text do
			local char = string.sub(text, pos, pos)
			if char == '"' then
				pos = pos + 1
				break
			elseif char == "\\" then
				local nextChar = string.sub(text, pos + 1, pos + 1)
				if nextChar == "n" then
					table.insert(out, "\n")
				elseif nextChar == "t" then
					table.insert(out, "\t")
				else
					table.insert(out, nextChar)
				end
				pos = pos + 2
			else
				table.insert(out, char)
				pos = pos + 1
			end
		end
		return table.concat(out)
	end

	parseValue = function()
		skip()
		local char = string.sub(text, pos, pos)
		if char == "{" then
			pos = pos + 1
			local object = {}
			skip()
			if string.sub(text, pos, pos) == "}" then
				pos = pos + 1
				return object
			end
			while true do
				skip()
				local key = parseString()
				skip()
				pos = pos + 1 -- :
				object[key] = parseValue()
				skip()
				local sep = string.sub(text, pos, pos)
				pos = pos + 1
				if sep == "}" then
					break
				end
			end
			return object
		elseif char == "[" then
			pos = pos + 1
			local array = {}
			skip()
			if string.sub(text, pos, pos) == "]" then
				pos = pos + 1
				return array
			end
			while true do
				table.insert(array, parseValue())
				skip()
				local sep = string.sub(text, pos, pos)
				pos = pos + 1
				if sep == "]" then
					break
				end
			end
			return array
		elseif char == '"' then
			return parseString()
		elseif string.sub(text, pos, pos + 3) == "true" then
			pos = pos + 4
			return true
		elseif string.sub(text, pos, pos + 4) == "false" then
			pos = pos + 5
			return false
		elseif string.sub(text, pos, pos + 3) == "null" then
			pos = pos + 4
			return nil
		else
			local numberText = string.match(text, "^[-%d%.eE+]+", pos)
			pos = pos + #numberText
			return tonumber(numberText)
		end
	end
	return parseValue()
end

return M
