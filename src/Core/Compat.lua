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
