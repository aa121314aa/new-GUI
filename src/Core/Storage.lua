--[[
	NewGUI · Core/Storage
	极轻量持久化(窗口位置/尺寸/悬浮球位置)。
	用 readfile/writefile + HttpService:JSONEncode, 不支持文件 API 时静默降级为"不保存"。
]]

local Compat = require("Core.Compat")
local Config = require("Core.Config")

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
