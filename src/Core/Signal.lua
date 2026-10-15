--[[
	NewGUI · Core/Signal
	极简事件系统。不用 BindableEvent(会被执行器沙盒限制/需要实例), 纯 Lua 实现, 可传任意值。

	用法:
		local Signal = require("Core.Signal")
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
