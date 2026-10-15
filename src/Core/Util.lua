--[[
	NewGUI · Core/Util
	通用小工具: 属性批量设置、补间、去重连接、毫秒格式化等。
]]

local Compat = require("Core.Compat")

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
