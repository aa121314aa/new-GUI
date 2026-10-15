--[[
	NewGUI · Core/Assets
	图片资产加载器(悬浮球/窗口图标用)。

	加载顺序:
		1. 执行器工作目录里已有的缓存文件     (NewGUI/assets/icons/xxx.png)
		2. 从仓库 raw 地址下载到工作目录      (只下缺失的那些, 下完缓存, 以后不再联网)
		3. 都不行 → 返回 nil, 调用方自动回退到 Core/Glyph 的矢量图标

	所以: 有网=全套图片图标; 无网/无文件权限=矢量图标, UI 不会因为一张图挂掉。
]]

local Compat = require("Core.Compat")
local Config = require("Core.Config")

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
