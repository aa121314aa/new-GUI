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

local Scale = require("Core.Scale")
local Theme = require("Core.Theme")
local Config = require("Core.Config")
local Compat = require("Core.Compat")
local Assets = require("Core.Assets")
local Storage = require("Core.Storage")
local Widgets = require("UI.Widgets")
local Glyph = require("Core.Glyph")
local Version = require("Version")
local Util = require("Core.Util")

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
