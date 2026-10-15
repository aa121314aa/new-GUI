# NewGUI API

入口：`loadstring(game:HttpGet(".../dist/library.lua"))()` → 返回 `NewGUI` 表。

```lua
NewGUI.Version      -- { name, version, channel, repo, raw, description }
NewGUI.Config       -- 运行参数(可改)
NewGUI.Scale        -- 百分比缩放系统
NewGUI.Theme        -- 配色 / 圆角 / 尺寸令牌
NewGUI.Compat       -- 执行器适配层
NewGUI.Assets       -- 图片资产
NewGUI.Storage      -- 持久化
NewGUI.Widgets      -- 控件库
NewGUI.Orb / Window / Pages / Notify / Glyph / Util / Signal
NewGUI.start(opts)  -- 启动界面
NewGUI.Ready / Unloaded  -- 生命周期信号
```

---

## 1. 启动

```lua
local handle = NewGUI.start({
    title = "我的脚本",           -- 窗口标题
    subtitle = "v1.0 · by me",    -- 副标题(默认: 版本 + 执行器名)
    icon = "sparkle",             -- 标题图标
    theme = "紫罗兰",             -- 主题: 霓虹蓝/紫罗兰/薄荷绿/橙金/玫红
    openOnStart = false,          -- 启动即展开窗口
    global = true,                -- 挂到 getgenv().NewGUI
    pages = {                     -- 追加自定义页面(见 §4)
        { name = "脚本", icon = "bolt", build = function(scroll, window, ctx) end },
    },
})
```

`Config.window.open = true` 也能让默认启动就展开。

### 句柄方法

| 方法 | 说明 |
| --- | --- |
| `handle:Open()` / `handle:Close()` / `handle.window:Toggle(orbPos)` | 开关窗口 |
| `handle:AddPage(page)` | 追加页面并重建导航 |
| `handle:Notify({ title, text, kind, duration })` | 轻提示，`kind = info/success/warn/error` |
| `handle:SetSubtitle(text)` | 改副标题 |
| `handle:Unload()` | 卸载并销毁全部 GUI |
| `handle:Rebuild()` | 销毁后按原参数重建（切主题会用到） |
| `handle.GetWindow()` / `handle.GetOrb()` | 拿底层对象 |
| `handle.orb.Activated` / `handle.orb.Moved` | 悬浮球信号 |
| `handle.window.Opened` / `handle.window.Closed` | 窗口信号 |

---

## 2. 缩放系统（`NewGUI.Scale`）

| API | 说明 |
| --- | --- |
| `Scale.axis()` | 基准轴像素长度 = `min(视口宽, 视口高)` |
| `Scale.px(percent)` | 基准轴百分比 → 像素 |
| `Scale.u(percent)` | 基准轴百分比 → `UDim` |
| `Scale.size(w%, h%)` | → `UDim2`（Offset，基准轴百分比） |
| `Scale.bind(instance, fn)` | 绑定像素属性，屏幕变化时自动重算；返回"立即重算"函数 |
| `Scale.bindSize(instance, w%, h%)` | 绑定尺寸 |
| `Scale.viewportPosition(x%, y%)` | 视口百分比 → `UDim2` 位置 |
| `Scale.widthFraction(w%)` / `Scale.heightFraction(h%)` | 基准轴百分比 → 视口占比（算 Dock/边界用） |
| `Scale.font(percent, min?, max?)` | 百分比字号（默认钳制 9~34px） |
| `Scale.clamp(n, min, max)` / `Scale.round` / `Scale.lerp` | 数值工具 |
| `Scale.Changed` | 视口/相机变化信号 |
| `Scale.onChange(fn)` | 注册重算回调，返回断开函数 |
| `Scale.viewport` | 当前视口 `Vector2` |

---

## 3. 主题（`NewGUI.Theme`）

```lua
-- 圆角令牌(百分比, 像素风小数值)
Theme.radius = { window = 1.30, panel = 1.00, control = 0.92, small = 0.70, orb = 0.85, pill = 50 }

-- 尺寸令牌
Theme.metrics = { rowHeight = 5.0, controlHeight = 4.4, tabHeight = 4.6, gap = 1.0,
                  fontTitle = 3.0, fontBody = 2.45, fontSmall = 2.1, fontTiny = 1.85, iconSize = 2.6, ... }

-- 配色
Theme.palette.accent = Color3.fromRGB(150, 110, 255)
Theme.refresh()   -- 改完半径/尺寸后调用, 让所有绑定重算一次
```

`Theme.setPalette(tbl)` / `Theme.setRadius(tbl)` 可批量覆盖；

新增控件时用这些辅助函数，它们都会自动跟随屏幕百分比：

| API | 说明 |
| --- | --- |
| `Theme.corner(instance, "control")` | 加自适应圆角（令牌名或直接数字） |
| `Theme.stroke(parent, color?, widthPercent?)` | 加自适应描边 |
| `Theme.fontSize(label, percent, font?)` | 设置百分比字号 |
| `Theme.padding(frame, percent)` | 四边百分比内边距 |

> 注意：`Theme.refresh()` 只重算"像素级绑定"（圆角/字号/描边/间距）。
> 换主题色这类改动需要重建界面（内置「界面」页就是这么做的）。

---

## 4. 窗口与页面

```lua
local window = handle.GetWindow()

window:AddPage({ name = "首页", icon = "grid", build = function(scroll, window, ctx) ... end })
window:BuildNavigation()      -- 重建侧边栏(AddPage 会自动调用)
window:SelectPage(2)
window:SetStatus("左侧信息", "右侧信息")
window:SetSubtitle("新副标题")
```

页面 `build(scroll, window, ctx)` 收到的三个参数：

- `scroll`：页面滚动容器，控件都往它里面加
- `window`：窗口对象（要用 `window.overlay` 给下拉菜单当浮层）
- `ctx`：`{ notify(cfg), reload(), unload(), orb }`

```lua
window:AddPage({
    name = "设置",
    icon = "settings",
    build = function(scroll, window, ctx)
        NewGUI.Widgets.dropdown(scroll, {
            text = "服务器", options = { "东京", "新加坡" }, default = "东京",
            overlay = window.overlay,       -- 菜单浮层, 必填
            changed = function(value) print(value) end,
        })
    end,
})
```

---

## 5. 控件（`NewGUI.Widgets`）

所有控件第一个参数是父容器，第二个参数是配置表，返回值都带 `:Get()` / `:Set()`：

| 控件 | 关键参数 |
| --- | --- |
| `label(parent, text, opts)` | `font = title/body/small/tiny`、`color`、`align`、`wrapped`、`heightPercent`、`order` |
| `button(parent, text, opts)` | `icon`、`variant = primary/danger/ghost`、`callback`、`order` |
| `iconButton(parent, iconName, opts)` | `transparent`、`hoverColor`、`callback` |
| `toggle(parent, opts)` | `text`、`icon`、`default`、`changed(value)` |
| `slider(parent, opts)` | `text`、`min`、`max`、`step`、`default`、`suffix`、`changed(value)` |
| `dropdown(parent, opts)` | `text`、`icon`、`options`、`default`、`overlay`、`changed(value)` |
| `input(parent, opts)` | `placeholder`、`default`、`icon`、`changed`、`submitted` |
| `keybind(parent, opts)` | `text`、`default = Enum.KeyCode.RightControl`、`changed(key)` |
| `tabs(parent, opts)` | `items = {{name, icon}, ...}`、`default`、`changed(index, name)` |
| `badge(parent, text, opts)` | `color`、`textColor`、`:SetText(text)` |
| `section(parent, title, opts)` | 分组小标题 |
| `separator(parent, opts)` | 分隔线，`thickness` |
| `list(parent, opts)` | 纵向容器：`gap`（基准轴百分比）、`padding` |
| `scroll(parent, opts)` | 滚动容器：`gap`、`padding` |

控件内部统一使用 `order`（LayoutOrder）排序，配合 `list`/`scroll` 自动布局。

---

## 6. 执行器适配（`NewGUI.Compat`）

```lua
local info = Compat.Detect()
-- info = { name, isExecutor, isStudio, hasHttpGet, hasFile, hasCustomAsset, hasGethui, canUseAssets }

local parent, kind = Compat.GuiParent()   -- gethui → CoreGui → PlayerGui
Compat.Protect(screenGui)                 -- protect_gui / syn.protect_gui
Compat.Elevate()                          -- setthreadidentity(8)

Compat.HttpGet(url)                       -- request → http_request → httpget → game:HttpGet → HttpService
Compat.WriteFile(path, data) / Compat.ReadFile(path)
Compat.IsFile(path) / Compat.IsFolder(path) / Compat.MakeFolder(path)
Compat.GetCustomAsset(path)               -- → rbxasset 路径
Compat.Spawn(fn, ...) / Compat.Wait(t) / Compat.Delay(t, fn, ...)
Compat.Global("name")                     -- 安全读执行器全局
```

---

## 7. 资产（`NewGUI.Assets`）

```lua
Assets.usable()                    -- 是否支持 writefile + getcustomasset
Assets.load(name, function(asset) end)   -- 异步; asset 为 nil 时请回退矢量图标
Assets.loadSync(name, timeout)     -- 同步(会阻塞), 少量关键图标才用
Assets.preload({ "sparkle", ... }, callback)
Assets.path(name)                  -- 已就绪的资产路径(没有则 nil)
Assets.stats()                     -- { downloaded, cached, failed, fetched }
Assets.clearCache()                -- 删除本地缓存文件, 下次重新下载
```

图标名 → 文件名的映射在 `Config.assets.icons`；仓库地址在 `Config.assets.remote.base`。

---

## 8. 其它

```lua
-- 事件
local conn = someSignal:Connect(fn); conn:Disconnect()
someSignal:Once(fn); someSignal:Fire(...)

-- 持久化
NewGUI.Storage.set("key", value)   -- 写 NewGUI/settings.json(节流)
NewGUI.Storage.get("key", default)
NewGUI.Storage.clear()

-- 矢量图标
NewGUI.Glyph.draw(frame, "bolt", { color = Color3.new(1,1,1), stroke = 2, padding = 8 })
NewGUI.Glyph.icons / Glyph.aliases / Glyph.list() / Glyph.resolve(name)

-- 轻提示
NewGUI.Notify.send(screenGui, { title = "完成", text = "详情", kind = "success", duration = 3 })
```

---

## 9. 常见坑

1. **基准轴百分比 ≠ 视口百分比**：`UDim2` 的 `Scale` 永远相对父容器/视口；
   想用"基准轴百分比"就必须换算成 `Offset`（`Scale.px`）。
2. `Theme.refresh()` 只刷新像素绑定；换配色请重建界面（`handle:Rebuild()`）。
3. 下拉菜单必须传 `overlay = window.overlay`，否则菜单会被内容区裁掉。
4. 有 `UIListLayout` 的容器里不要再手动设子控件的 `Position`，会互相打架。
5. 执行器没有 `writefile` 时，资产会走矢量回退，这是正常路径而不是错误。
