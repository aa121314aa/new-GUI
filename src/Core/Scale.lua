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

local Signal = require("Core.Signal")

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
