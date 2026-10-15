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

local Scale = require("Core.Scale")
local Signal = require("Core.Signal")

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
