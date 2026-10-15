--[[
	NewGUI · tools/mock_render.lua
	Luau 渲染模拟器: 在桩环境里解析 UDim2 布局 → 生成 SVG。

	用途: 本地/CI 检查界面在真实尺寸下长什么样(位置、层级、百分比缩放是否符合预期),
	生成的 SVG 由 tools/svg2png.mjs 转成 PNG。只为开发预览服务, 不参与 dist 打包。

	支持的子集(覆盖本库用到的全部特性):
		Frame / TextLabel / TextButton / TextBox / ImageLabel / ScrollingFrame / CanvasGroup
		UICorner / UIStroke / UIPadding / UIListLayout / UIGridLayout / UISizeConstraint
		AnchorPoint / Rotation / ZIndex / BackgroundTransparency / TextXAlignment / TextYAlignment
]]

local M = {}

local FONT_STACK = {
	Gotham = "DejaVu Sans, Verdana, sans-serif",
	GothamMedium = "DejaVu Sans, Verdana, sans-serif",
	GothamBold = "DejaVu Sans, Verdana, sans-serif",
	GothamBlack = "DejaVu Sans, Verdana, sans-serif",
	Code = "DejaVu Sans Mono, monospace",
	SourceSans = "DejaVu Sans, Verdana, sans-serif",
	SourceSansBold = "DejaVu Sans, Verdana, sans-serif",
	Arial = "DejaVu Sans, sans-serif",
}

local GUI_CLASSES = {
	Frame = true,
	TextLabel = true,
	TextButton = true,
	TextBox = true,
	ImageLabel = true,
	ImageButton = true,
	ScrollingFrame = true,
	CanvasGroup = true,
	ViewportFrame = true,
}

--============================ 基础取值 ============================--
local function prop(instance, key, default)
	local value = instance[key]
	if value == nil then
		return default
	end
	return value
end

local function toHex(color, alpha)
	local r = math.floor((color.R or 0) * 255 + 0.5)
	local g = math.floor((color.G or 0) * 255 + 0.5)
	local b = math.floor((color.B or 0) * 255 + 0.5)
	local a = alpha == nil and 1 or alpha
	if a >= 1 then
		return string.format("#%02X%02X%02X", r, g, b)
	end
	return string.format("rgba(%d,%d,%d,%.3f)", r, g, b, a)
end

local function offsetOf(axis)
	if type(axis) == "number" then
		return axis
	end
	return axis and axis.Offset or 0
end

local function scaleOf(axis)
	if type(axis) == "number" then
		return axis
	end
	return axis and axis.Scale or 0
end

local function ceil(n)
	return math.floor(n + 0.999)
end

local function esc(text)
	text = tostring(text or "")
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	text = string.gsub(text, '"', "&quot;")
	return text
end

--============================ 布局树 ============================--
local function findChild(instance, className)
	for _, child in ipairs(instance:GetChildren()) do
		if child.ClassName == className then
			return child
		end
	end
	return nil
end

local function sizeConstraint(instance)
	local constraint = findChild(instance, "UISizeConstraint")
	if not constraint then
		return nil
	end
	return {
		min = prop(constraint, "MinSize", { X = 0, Y = 0 }),
		max = prop(constraint, "MaxSize", { X = 1e5, Y = 1e5 }),
	}
end

local function paddingOf(instance)
	local padding = findChild(instance, "UIPadding")
	if not padding then
		return { left = 0, right = 0, top = 0, bottom = 0 }
	end
	return {
		left = offsetOf(prop(padding, "PaddingLeft", { Offset = 0 })),
		right = offsetOf(prop(padding, "PaddingRight", { Offset = 0 })),
		top = offsetOf(prop(padding, "PaddingTop", { Offset = 0 })),
		bottom = offsetOf(prop(padding, "PaddingBottom", { Offset = 0 })),
	}
end

-- 计算一个子节点相对父容器内容区的矩形
local function layoutRect(instance, parentRect, index)
	local size = prop(instance, "Size", { X = { Scale = 1, Offset = 0 }, Y = { Scale = 1, Offset = 0 } })
	local position = prop(instance, "Position", { X = { Scale = 0, Offset = 0 }, Y = { Scale = 0, Offset = 0 } })

	local width = parentRect.w * scaleOf(size.X) + offsetOf(size.X)
	local height = parentRect.h * scaleOf(size.Y) + offsetOf(size.Y)
	local x = parentRect.x + parentRect.w * scaleOf(position.X) + offsetOf(position.X)
	local y = parentRect.y + parentRect.h * scaleOf(position.Y) + offsetOf(position.Y)

	local anchor = prop(instance, "AnchorPoint", { X = 0, Y = 0 })
	x = x - width * (anchor.X or 0)
	y = y - height * (anchor.Y or 0)

	local constraint = sizeConstraint(instance)
	if constraint then
		width = math.max(constraint.min.X or 0, math.min(constraint.max.X or 1e5, width))
		height = math.max(constraint.min.Y or 0, math.min(constraint.max.Y or 1e5, height))
	end

	return { x = x, y = y, w = width, h = height }
end

--============================ 绘制指令 ============================--
local drawList = {}
local drawSequence = 0
local clipStack = {} -- ClipsDescendants 的容器会限制子节点绘制范围

local function pushDraw(draw)
	drawSequence = drawSequence + 1
	draw.sequence = drawSequence
	-- 裁剪: 与所有祖先裁剪框求交(ScrollingFrame 里的内容不能画到框外)
	for _, clip in ipairs(clipStack) do
		local x1 = math.max(draw.rect and draw.rect.x or 0, clip.x)
		local y1 = math.max(draw.rect and draw.rect.y or 0, clip.y)
		local x2 = math.min(
			(draw.rect and draw.rect.x or 0) + (draw.rect and draw.rect.w or 0),
			clip.x + clip.w
		)
		local y2 = math.min(
			(draw.rect and draw.rect.y or 0) + (draw.rect and draw.rect.h or 0),
			clip.y + clip.h
		)
		if x2 <= x1 or y2 <= y1 then
			return -- 完全在框外
		end
		if draw.rect then
			draw.rect = { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
		end
	end
	drawList[#drawList + 1] = draw
end

local function cornerRadius(instance, rect)
	local corner = findChild(instance, "UICorner")
	if not corner then
		return 0
	end
	local radius = prop(corner, "CornerRadius", { Scale = 0, Offset = 0 })
	local percent = scaleOf(radius)
	if percent >= 1 then
		return math.min(rect.w, rect.h) / 2
	end
	return percent * math.min(rect.w, rect.h) + offsetOf(radius)
end

local function strokeOf(instance, rect)
	local stroke = findChild(instance, "UIStroke")
	if not stroke then
		return nil
	end
	return {
		color = prop(stroke, "Color", { R = 1, G = 1, B = 1 }),
		thickness = prop(stroke, "Thickness", 1),
		transparency = prop(stroke, "Transparency", 0),
		applyMode = prop(stroke, "ApplyStrokeMode", nil),
	}
end

local function sortChildren(children)
	local indexed = {}
	for index, child in ipairs(children) do
		indexed[index] = { child = child, index = index }
	end
	table.sort(indexed, function(a, b)
		local za, zb = prop(a.child, "ZIndex", 1), prop(b.child, "ZIndex", 1)
		if za == zb then
			return a.index < b.index
		end
		return za < zb
	end)
	local out = {}
	for index, entry in ipairs(indexed) do
		out[index] = entry.child
	end
	return out
end

-- 图标染色: 每个颜色生成一个 mask(白色图标 → mask → 填充目标颜色)
--============================ 遍历 ============================--
local depthLimit = 24

local function withClip(rect, fn)
	clipStack[#clipStack + 1] = rect
	fn()
	clipStack[#clipStack] = nil
end

local function walk(instance, parentRect, depth)
	if depth > depthLimit then
		return
	end
	if prop(instance, "Visible", true) == false then
		return
	end

	local rect = layoutRect(instance, parentRect, 0)
	local isGui = GUI_CLASSES[instance.ClassName] == true

	if not isGui then
		-- 非 GUI 容器(如 Workspace): 直接下探
		for _, child in ipairs(instance:GetChildren()) do
			walk(child, parentRect, depth + 1)
		end
		return
	end

	-- 布局容器(logical children 由 UIListLayout/UIGridLayout 排布)
	local listLayout = findChild(instance, "UIListLayout")
	local gridLayout = findChild(instance, "UIGridLayout")
	local padding = paddingOf(instance)

	local contentRect = {
		x = rect.x + padding.left,
		y = rect.y + padding.top,
		w = math.max(rect.w - padding.left - padding.right, 0),
		h = math.max(rect.h - padding.top - padding.bottom, 0),
	}

	local children = {}
	for _, child in ipairs(instance:GetChildren()) do
		if GUI_CLASSES[child.ClassName] and prop(child, "Visible", true) ~= false then
			children[#children + 1] = child
		end
	end
	children = sortChildren(children)

	-- 先画自己(背景 + 描边 + 文本/图片)
	local backgroundTransparency = prop(instance, "BackgroundTransparency", 0)
	local background = prop(instance, "BackgroundColor3", nil)
	local radius = cornerRadius(instance, rect)
	local stroke = strokeOf(instance, rect)
	local radiusNormalized = math.min(radius, math.min(rect.w, rect.h) / 2)
	local index = prop(instance, "ZIndex", 1)
	local rotation = prop(instance, "Rotation", 0)

	if background and backgroundTransparency < 1 and instance.ClassName ~= "ImageLabel" then
		pushDraw({
			kind = "rect",
			rect = rect,
			radius = radius,
			rotation = rotation,
			fill = toHex(background, 1 - backgroundTransparency),
			z = index,
		})
	end

	if stroke then
		pushDraw({
			kind = "stroke",
			rect = rect,
			radius = radiusNormalized,
			rotation = rotation,
			color = toHex(stroke.color, 1 - stroke.transparency),
			thickness = stroke.thickness,
			z = index + 0.5,
		})
	end

	local text = prop(instance, "Text", nil)
	local isText = instance.ClassName == "TextLabel" or instance.ClassName == "TextButton" or instance.ClassName == "TextBox"
	if isText then
		local fontSize = prop(instance, "TextSize", 14)
		local glyphHolder = findChild(instance, "Glyph")
		if text and #tostring(text) > 0 and not glyphHolder then
			local alignX = prop(instance, "TextXAlignment", nil)
			local alignY = prop(instance, "TextYAlignment", nil)
			local anchorX, x = "start", rect.x + 4
			if alignX and alignX.Name == "Center" then
				anchorX, x = "middle", rect.x + rect.w / 2
			elseif alignX and alignX.Name == "Right" then
				anchorX, x = "end", rect.x + rect.w - 4
			end
			local baseline = rect.y + rect.h / 2
			if alignY and alignY.Name == "Top" then
				baseline = rect.y + fontSize * 0.9
			end
			pushDraw({
				kind = "text",
				x = x,
				y = baseline,
				anchor = anchorX,
				text = tostring(text),
				size = fontSize,
				font = prop(instance, "Font", nil),
				bold = prop(instance, "Font", nil) ~= nil and tostring(prop(instance, "Font", nil).Name):find("Bold") ~= nil,
				color = toHex(prop(instance, "TextColor3", { R = 1, G = 1, B = 1 }), 1 - prop(instance, "TextTransparency", 0)),
				rotation = rotation,
				rect = rect,
				z = index + 3,
			})
		end
		local placeholder = prop(instance, "PlaceholderText", nil)
		if placeholder and #tostring(placeholder) > 0 and (not text or #tostring(text) == 0) then
			pushDraw({
				kind = "text",
				x = rect.x + 4,
				y = rect.y + rect.h / 2,
				anchor = "start",
				text = tostring(placeholder),
				size = prop(instance, "TextSize", 14),
				font = prop(instance, "Font", nil),
				color = toHex(prop(instance, "PlaceholderColor3", { R = 0.5, G = 0.5, B = 0.5 }), 0.9),
				rect = rect,
				z = index + 3,
			})
		end
	end

	if instance.ClassName == "ImageLabel" or instance.ClassName == "ImageButton" then
		local image = prop(instance, "Image", nil)
		local imageTransparency = prop(instance, "ImageTransparency", 0)
		local visible = prop(instance, "Visible", true)
		if image and visible and imageTransparency < 1 then
			pushDraw({
				kind = "image",
				rect = rect,
				rotation = rotation,
				source = tostring(image),
				color = toHex(prop(instance, "ImageColor3", { R = 1, G = 1, B = 1 }), 1),
				alpha = 1 - imageTransparency,
				z = index + 2,
			})
		end
	end

	-- 子节点: 有布局时按布局排, 否则按各自 UDim2
	local clips = prop(instance, "ClipsDescendants", false) == true
	local childWrapper = function(childrenFn)
		if clips then
			withClip(rect, childrenFn)
		else
			childrenFn()
		end
	end

	childWrapper(function()
	if listLayout then
		local order = {}
		for _, child in ipairs(children) do
			order[#order + 1] = child
		end
		table.sort(order, function(a, b)
			local oa, ob = prop(a, "LayoutOrder", 0), prop(b, "LayoutOrder", 0)
			if oa == ob then
				return false
			end
			return oa < ob
		end)

		local gap = offsetOf(prop(listLayout, "Padding", { Scale = 0, Offset = 0 }))
		local contentH = contentRect.h
		local totalH = 0
		local sizes = {}
		for i, child in ipairs(order) do
			local size = prop(child, "Size", { X = { Scale = 1, Offset = 0 }, Y = { Scale = 0, Offset = 0 } })
			local h = contentRect.h * scaleOf(size.Y) + offsetOf(size.Y)
			local w = contentRect.w * scaleOf(size.X) + offsetOf(size.X)
			sizes[i] = { w = w, h = h }
			totalH = totalH + h + (i > 1 and gap or 0)
		end

		local verticalAlign = prop(listLayout, "VerticalAlignment", nil)
		local startY = contentRect.y
		if verticalAlign and verticalAlign.Name == "Center" then
			startY = contentRect.y + (contentH - totalH) / 2
		elseif verticalAlign and verticalAlign.Name == "Bottom" then
			startY = contentRect.y + contentH - totalH
		end

		local cursor = startY
		for i, child in ipairs(order) do
			local horizontalAlign = prop(listLayout, "HorizontalAlignment", nil)
			local x = contentRect.x
			if horizontalAlign and horizontalAlign.Name == "Center" then
				x = contentRect.x + (contentRect.w - sizes[i].w) / 2
			elseif horizontalAlign and horizontalAlign.Name == "Right" then
				x = contentRect.x + contentRect.w - sizes[i].w
			end
			local childRect = { x = x, y = cursor, w = sizes[i].w, h = sizes[i].h }
			walkChild(child, childRect, contentRect, depth)
			cursor = cursor + sizes[i].h + gap
		end
	elseif gridLayout then
		local cell = prop(gridLayout, "CellSize", { X = { Scale = 0, Offset = 50 }, Y = { Scale = 0, Offset = 50 } })
		local cellPadding = prop(gridLayout, "CellPadding", { X = { Scale = 0, Offset = 0 }, Y = { Scale = 0, Offset = 0 } })
		local cellW = contentRect.w * scaleOf(cell.X) + offsetOf(cell.X)
		local cellH = contentRect.h * scaleOf(cell.Y) + offsetOf(cell.Y)
		local padX = contentRect.w * scaleOf(cellPadding.X) + offsetOf(cellPadding.X)
		local padY = contentRect.h * scaleOf(cellPadding.Y) + offsetOf(cellPadding.Y)
		local columns = math.max(1, math.floor((contentRect.w + padX) / math.max(cellW + padX, 1)))
		for i, child in ipairs(children) do
			local col = (i - 1) % columns
			local row = math.floor((i - 1) / columns)
			local childRect = {
				x = contentRect.x + col * (cellW + padX),
				y = contentRect.y + row * (cellH + padY),
				w = cellW,
				h = cellH,
			}
			walkChild(child, childRect, contentRect, depth)
		end
	else
		for _, child in ipairs(children) do
			walkChild(child, nil, contentRect, depth)
		end
	end
	end)
end

-- 子节点的父容器尺寸: 列表布局已算好, 直接覆盖 Position/Size
function walkChild(child, forcedRect, contentRect, depth)
	if forcedRect then
		-- 用"伪造"的父容器尺寸反推出等价 UDim2 结果: 这里直接把 rect 传给下一层
		local node = child
		local function walkForced(instance, rect, d)
			-- 复用 walk 但跳过尺寸计算: 用一个包裹技巧
			return walkWithRect(instance, rect, d)
		end
		return walkForced(node, forcedRect, depth + 1)
	end
	return walk(child, contentRect, depth + 1)
end

-- 与 walk 相同, 但使用外部给定的矩形(用于 UIListLayout / UIGridLayout 已定位的子节点)
function walkWithRect(instance, rect, depth)
	if depth > depthLimit then
		return
	end
	if prop(instance, "Visible", true) == false then
		return
	end

	local originalSize = instance.Size
	local originalPosition = instance.Position
	local originalAnchor = instance.AnchorPoint

	-- 构造一个 1:1 的父容器, 使 layoutRect 正好得到 rect
	instance.Size = UDim2.new(0, rect.w, 0, rect.h)
	instance.Position = UDim2.new(0, 0, 0, 0)
	instance.AnchorPoint = Vector2.new(0, 0)
	local parentRect = { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
	walk(instance, parentRect, depth)

	instance.Size = originalSize
	instance.Position = originalPosition
	instance.AnchorPoint = originalAnchor
end

--============================ SVG 输出 ============================--
--============================ 绘制指令 ============================--
local tintDefs = {}
local tintIndex = 0

local function tintId(color)
	local key = tostring(color)
	if tintDefs[key] then
		return tintDefs[key], tintDefs
	end
	tintIndex = tintIndex + 1
	local id = "tint" .. tintIndex
	tintDefs[key] = id
	return id, tintDefs
end

local function buildTintDefs(images)
	-- images: { { id = "tint1", source = "...", color = "#RRGGBB" } }
	local parts = {}
	for _, entry in ipairs(images) do
		parts[#parts + 1] = string.format(
			'<mask id="%s" maskUnits="userSpaceOnUse" maskContentUnits="userSpaceOnUse" x="0" y="0"><image x="%s" y="%s" width="%s" height="%s" xlink:href="%s" preserveAspectRatio="none"/></mask>',
			entry.id,
			entry.x,
			entry.y,
			entry.w,
			entry.h,
			entry.source
		)
	end
	return table.concat(parts)
end

local function svgHeader(width, height, background, defs)
	return string.format(
		'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="%d" height="%d" viewBox="0 0 %d %d">\n'
			.. '<defs>%s</defs>\n'
			.. '<rect width="%d" height="%d" fill="%s"/>\n',
		width,
		height,
		width,
		height,
		defs or "",
		width,
		height,
		background
	)
end

local function roundedPath(rect, radius)
	local x, y, w, h = rect.x, rect.y, rect.w, rect.h
	local r = math.max(0, math.min(radius or 0, math.min(w, h) / 2))
	if r <= 0.4 then
		return string.format('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f"', x, y, w, h)
	end
	return string.format(
		'<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" rx="%.2f" ry="%.2f"',
		x,
		y,
		w,
		h,
		r,
		r
	)
end

local function rotationTransform(draw)
	if not draw.rotation or draw.rotation == 0 then
		return ""
	end
	local cx = draw.rect.x + draw.rect.w / 2
	local cy = draw.rect.y + draw.rect.h / 2
	return string.format(' transform="rotate(%.2f %.2f %.2f)"', draw.rotation, cx, cy)
end

-- imagePathMap: [rbxasset 路径] = 本地文件路径(base64 由 Python 注入)
local imagePaths = {}

--[=[ 调试: 返回当前绘制指令(需要先调用 toSvg) ]=]
function M.dumpDraws()
	local out = {}
	for index, draw in ipairs(drawList) do
		out[index] = {
			kind = draw.kind,
			x = math.floor((draw.rect and draw.rect.x or draw.x or 0) * 10) / 10,
			y = math.floor((draw.rect and draw.rect.y or draw.y or 0) * 10) / 10,
			w = math.floor((draw.rect and draw.rect.w or 0) * 10) / 10,
			h = math.floor((draw.rect and draw.rect.h or 0) * 10) / 10,
			z = draw.z,
			text = draw.text,
			source = draw.source,
		}
	end
	return out
end

function M.setImageMap(map)
	imagePaths = map or {}
end

--[=[ 调试: 图片映射表当前内容 ]=]
function M.imageMapRef()
	return imagePaths
end

function M.debugImageMap()
	local out = {}
	local count = 0
	for key in pairs(imagePaths) do
		count = count + 1
		if count <= 4 then
			out[#out + 1] = tostring(key)
		end
	end
	return count, table.concat(out, " | ")
end

function M.toSvg(root, viewportWidth, viewportHeight, background)
	drawList = {}
	walk(root, { x = 0, y = 0, w = viewportWidth, h = viewportHeight }, 0)

	-- 先把图片收集起来(需要在 header 里定义 mask)
	local maskEntries = {}
	for _, draw in ipairs(drawList) do
		if draw.kind == "image" then
			local path = imagePaths[draw.source]
			if path then
				local id = tintId(draw.color or "#FFFFFF")
				maskEntries[#maskEntries + 1] = {
					id = id,
					source = path,
					x = string.format("%.2f", draw.rect.x),
					y = string.format("%.2f", draw.rect.y),
					w = string.format("%.2f", draw.rect.w),
					h = string.format("%.2f", draw.rect.h),
				}
				draw.maskId = id
			end
		end
	end
	local defs = buildTintDefs(maskEntries)

	local parts = { svgHeader(viewportWidth, viewportHeight, background or "#101014", defs) }
	local clipIndex = 0

	for _, draw in ipairs(drawList) do
		if draw.kind == "rect" then
			parts[#parts + 1] = roundedPath(draw.rect, draw.radius)
				.. string.format(' fill="%s"%s/>\n', draw.fill, rotationTransform(draw))
		elseif draw.kind == "stroke" then
			parts[#parts + 1] = roundedPath(draw.rect, draw.radius)
				.. string.format(
					' fill="none" stroke="%s" stroke-width="%.2f"%s/>\n',
					draw.color,
					math.max(draw.thickness, 0.5),
					rotationTransform(draw)
				)
		elseif draw.kind == "text" then
			local font = draw.font and FONT_STACK[draw.font.Name] or FONT_STACK.Gotham
			clipIndex = clipIndex + 1
			parts[#parts + 1] = string.format(
				'<text x="%.2f" y="%.2f" font-family="%s" font-size="%.1f" font-weight="%s" fill="%s" text-anchor="%s" dominant-baseline="middle"%s>%s</text>\n',
				draw.x,
				draw.y,
				font,
				draw.size,
				draw.bold and "600" or "500",
				draw.color,
				draw.anchor,
				draw.rotation and draw.rotation ~= 0 and rotationTransform(draw) or "",
				esc(draw.text)
			)
		elseif draw.kind == "image" then
			local path = imagePaths[draw.source]
			if path then
				parts[#parts + 1] = string.format(
					'<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s" mask="url(#%s)"/>\n',
					draw.rect.x,
					draw.rect.y,
					draw.rect.w,
					draw.rect.h,
					draw.color or "#FFFFFF",
					draw.maskId
				)
			else
				-- 没有真实图片时用占位方块提示"这里有一张图"
				parts[#parts + 1] = roundedPath(draw.rect, 2)
					.. string.format(' fill="none" stroke="%s" stroke-width="1" stroke-dasharray="2 2"/>\n', "#6A7086")
			end
		end
	end

	parts[#parts + 1] = "</svg>\n"
	return table.concat(parts)
end

return M
