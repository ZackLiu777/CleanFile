## 颜色系统补充：品牌主色

本项目 UI 的主要品牌色确定为：

```swift
let instaBrightPink = Color(
    red: 0xE8 / 255.0,
    green: 0xA3 / 255.0,
    blue: 0x9C / 255.0
)
```

对应颜色：

```text
#E8A39C
```

该颜色作为当前产品的主要视觉识别色。

在正式 Theme / Design Token 中，不应长期直接使用变量名：

```text
instaBrightPink
```

业务 View 应通过语义 Token 使用：

```text
accentPrimary
```

例如：

```swift
let accentPrimary = Color(
    red: 0xE8 / 255.0,
    green: 0xA3 / 255.0,
    blue: 0x9C / 255.0
)
```

`instaBrightPink` 可以作为颜色来源或设计参考，但 View 层应优先写：

```swift
theme.accentPrimary
```

而不是：

```swift
instaBrightPink
```

这样未来即使品牌颜色发生变化，也不需要修改业务 UI。

---

## 品牌色使用原则

`#E8A39C` 属于柔和、偏暖的粉色，应主要用于：

- Tab 当前选中状态。
- Primary Button。
- Selection。
- Progress 强调。
- Donut Chart 的主要视觉类别。
- Slider / Toggle Tint。
- Interactive Icon。
- Link / Navigation Accent。
- Selected File。
- Conversion Primary Action。
- 少量 Hero 数据强调。

不要将品牌色大面积覆盖：

- 所有 Card。
- 所有背景。
- 所有文字。
- 所有文件分类。

品牌色属于：

> Accent。

而不是：

> Background。

---

## 品牌色与渐变

本项目允许围绕 `#E8A39C` 构建非常轻量的背景渐变。

原则：

```text
品牌色
↓
降低 Saturation / Opacity
↓
作为 Background Atmosphere
```

不得直接使用高饱和 `#E8A39C` 大面积铺满整个页面。

浅色模式可以考虑：

```text
柔和粉
→ 极浅粉
→ System Background
```

深色模式则应：

```text
Dark System Background
+
极弱暖粉 Tint
```

而不是：

```text
Bright Pink
→ Purple
→ Red
```

形成过度鲜艳的渐变。

本项目视觉目标仍然是：

> 工具感 + 苹果原生感 + 少量品牌识别。

---

# TabView 视觉规则

顶层导航优先使用系统：

```swift
TabView
```

而不是自定义 TabBar。

为了让页面背景与渐变延伸至 TabBar 后方，项目默认采用：

```swift
.toolbarBackground(.hidden, for: .tabBar)
```

例如：

```swift
TabView(selection: $selectedTab) {
    // Tabs
}
.toolbarBackground(.hidden, for: .tabBar)
```

设计目的：

> 隐藏额外的 TabBar Background，让页面渐变、Material 或背景 Surface 可以自然延伸到 TabBar 后方。

不要再额外绘制：

- 黑色 TabBar Background。
- 白色 TabBar Background。
- 自定义 Rectangle。
- 重复 Blur Layer。

除非实际可读性证明系统效果不足。

---

## TabBar 与背景关系

当使用：

```swift
.toolbarBackground(.hidden, for: .tabBar)
```

必须检查：

- Light Mode。
- Dark Mode。
- ScrollView。
- List。
- 长内容。
- 页面底部高对比内容。
- Liquid Glass。
- Accessibility Contrast。

不能仅仅因为：

> 背景透出来更漂亮

就忽略 TabBar Item 的可读性。

如果某个页面背景导致 TabBar 可读性明显下降，应优先调整：

- 页面背景。
- Gradient 强度。
- Bottom Safe Area。
- Scroll Edge Effect。

而不是立即重新制作自定义 TabBar。

---

# TabView Sensory Feedback

Tab 切换默认加入轻量 Selection Feedback：

```swift
.sensoryFeedback(
    .selection,
    trigger: selectedTab
)
```

完整形式例如：

```swift
TabView(selection: $selectedTab) {
    // Tabs
}
.toolbarBackground(.hidden, for: .tabBar)
.sensoryFeedback(.selection, trigger: selectedTab)
```

目的：

> 用户切换主要导航时获得轻微、明确但不过度的触觉确认。

---

## Tab Feedback 使用边界

Tab 切换可以使用：

```swift
.selection
```

但不要额外叠加：

- 手动 UIImpactFeedbackGenerator。
- 第二次 sensoryFeedback。
- 音效。
- 强震动。

同一个操作原则上：

> 只产生一次反馈。

不要出现：

```text
用户切 Tab
↓
SwiftUI sensoryFeedback
↓
UIKit Haptic
↓
再次触发 Haptic
```

这种重复反馈。

---

# Haptic 总体规则补充

优先使用 SwiftUI：

```swift
.sensoryFeedback(...)
```

而不是优先回退到 UIKit Haptic API。

适合 Feedback 的操作：

```text
Tab Selection
File Selection
Operation Success
Conversion Complete
Delete Confirmation
重要状态变化
```

不要用于：

```text
普通 Scroll
每个 Row Tap
每次 Progress 更新
Donut 动画
普通 Navigation
```

Haptic 应：

> 稀疏、可预测、有明确语义。

---

# Scroll Edge Effect

本项目采用现代 SwiftUI Scroll Edge Effect。

Apple 当前 SwiftUI API 使用：

```swift
.scrollEdgeEffectStyle(
    .soft,
    for: ...
)
```

而不是：

```swift
.scrollEdgeEffect(.softEdge)
```

不得根据旧代码、博客或模型记忆猜测 API 名称。

---

## Soft Scroll Edge

当滚动内容经过：

- Navigation Controls。
- Floating Controls。
- TabBar。
- Liquid Glass。
- Safe Area Bar。

后方时，可以使用 Soft Edge：

```swift
ScrollView {
    // Content
}
.scrollEdgeEffectStyle(
    .soft,
    for: .all
)
```

也可以根据实际界面只指定：

```swift
.scrollEdgeEffectStyle(
    .soft,
    for: .top
)
```

或：

```swift
.scrollEdgeEffectStyle(
    .soft,
    for: .bottom
)
```

不要机械地所有 ScrollView 都使用 `.all`。

---

## Scroll Edge Effect 默认策略

项目原则是：

> Automatic First, Soft When Appropriate。

SwiftUI 默认会根据平台和上下文应用 Automatic Scroll Edge Effect。

因此：

```text
第一选择
↓
System Automatic

如果设计明确需要更柔和过渡
↓
Soft
```

不要为了统一代码而无条件：

```swift
.scrollEdgeEffectStyle(.soft, for: .all)
```

加到整个 App。

---

## 什么时候使用 Soft

Soft Edge 特别适合本项目：

```text
渐变 Background
+
ScrollView Content
+
Floating / Glass Controls
```

例如：

```text
Dashboard
────────────────
Navigation

渐变 Background

↓ Scrolling Content ↓

Storage Card
Cleaner Cards
File Categories

────────────────
Transparent / Glass TabBar
```

Soft Edge 可以帮助滚动内容与固定控件之间形成柔和视觉分离。

---

## Scroll Edge Effect 不是装饰

不得为了：

> 看起来更高级

使用 Scroll Edge Effect。

它的职责是：

> 当滚动内容位于固定控件后方时，提高控件与内容之间的视觉分离和可读性。

如果页面：

- 没有 Floating Controls。
- 没有重叠 Toolbar。
- 没有边缘可读性问题。

则优先保持：

```text
Automatic
```

不要主动添加额外效果。

---

## 不叠加 Edge Effect

同一个视觉边界不要同时存在：

```text
Soft Edge
+
Gradient Mask
+
Material Blur
+
Shadow
+
Divider
```

这种多层视觉处理。

原则：

> 一个 Edge 使用一种主要分离手段。

避免：

- Blur 重叠。
- Material 重叠。
- Shadow 重叠。
- Scroll Edge Effect 重叠。

---

# TabBar + Scroll Edge + Gradient 组合规范

本项目 Dashboard 等主页面建议采用：

```swift
ZStack {
    // Background Gradient

    ScrollView {
        // Content
    }
    .scrollEdgeEffectStyle(.soft, for: .vertical)
}
```

外层：

```swift
TabView(selection: $selectedTab) {
    // Pages
}
.toolbarBackground(.hidden, for: .tabBar)
.sensoryFeedback(.selection, trigger: selectedTab)
```

总体视觉结构：

```text
Gradient
    ↓
Scroll Content
    ↓
Soft Edge Transition
    ↓
System TabView
    ↓
Transparent TabBar Background
```

目标是：

> 背景连续，但控件仍然清晰。

---

# Modern SwiftUI API 查询规则

SwiftUI API 更新速度很快。

Codex 不得假设模型训练数据中的：

- API 名称。
- Modifier。
- 参数。
- Availability。
- Deprecated 状态。
- 新 Design System。
- Liquid Glass 行为。
- TabView 行为。
- ScrollView 行为。

一定仍然正确。

---

## 出现不确定 API 时必须联网查询

如果 Codex 对某个 SwiftUI / UIKit / Apple Framework API：

- 不确定是否存在。
- 不确定 API 名称。
- 不确定参数。
- 不确定 Availability。
- 不确定是否 Deprecated。
- 不确定最新推荐实现。
- 怀疑 API 在新系统版本发生变化。
- 用户提到一个 Codex 不认识的新 API。

则：

> 必须先使用网络搜索查询 Apple 官方文档。

不得直接依赖模型记忆生成代码。

---

## Apple 官方资料优先级

涉及 Apple 技术时，资料优先级为：

```text
1. Apple Developer Documentation

2. Apple Human Interface Guidelines

3. Apple Design Documentation

4. Apple WWDC Sessions

5. Apple Developer Forums / 官方工程师回复

6. Swift Evolution / Swift 官方资料

7. 高质量第三方资料
```

如果 Apple 官方资料已经明确说明：

> 不应优先采用第三方博客作为依据。

---

# Apple Design 查询规则

涉及以下问题时，应优先查询 Apple Human Interface Guidelines：

- Navigation。
- TabView。
- ScrollView。
- Scroll Edge Effect。
- Liquid Glass。
- Color。
- Typography。
- Materials。
- Layout。
- Accessibility。
- Haptic。
- Icons。
- Search。
- Sheets。
- Toolbars。
- Menus。
- Selection。
- Destructive Actions。

不能仅仅通过：

> “以前 Follower 是这样设计的”

决定新项目 UI。

Follower 是：

> 工程经验参考。

Apple HIG 是：

> 平台设计基准。

---

# 新系统设计变化规则

如果新的 iOS / SwiftUI 版本引入：

- 新 TabView 行为。
- 新 Navigation 行为。
- Liquid Glass。
- Scroll Edge Effect。
- 新 Toolbar API。
- 新动画 API。
- 新 Container。
- 新 Material。
- 新 Accessibility API。

Codex 必须：

```text
发现新 API
↓
查询 Apple Documentation
↓
查询对应 HIG
↓
确认 Availability
↓
判断 Deployment Target
↓
再决定是否使用
```

不能：

```text
发现不认识
↓
猜一个 API
↓
Build Error
↓
不停试 modifier 名称
```

---

# API Availability

所有较新的 SwiftUI API 在加入项目之前必须确认：

```text
Deployment Target
```

是否支持。

如果 Deployment Target 与 API Availability 不一致：

应明确选择：

```text
提高 Deployment Target
```

或者：

```text
提供 #available fallback
```

不得在未确认的情况下直接加入 Production UI。

同时：

> Codex 不得擅自修改 Deployment Target。

如果新 API 必须提高 Deployment Target，应先明确报告这一事实。

---

# Apple 文档优先于模型记忆

本项目永久遵循：

> **Apple Documentation > Codex Memory**

如果 Codex 记忆认为 API 是：

```swift
.scrollEdgeEffect(.softEdge)
```

但当前 Apple Documentation 显示为：

```swift
.scrollEdgeEffectStyle(.soft, for: ...)
```

则必须：

> 使用 Apple 当前文档中的 API。

不得坚持模型训练时期的旧知识。

同样适用于：

- SwiftUI。
- Foundation。
- AVFoundation。
- FileManager。
- UniformTypeIdentifiers。
- PDFKit。
- ImageIO。
- Photos。
- UIKit。
- StoreKit。
- Swift Concurrency。

---

# SwiftUI API 搜索原则

查询 Apple API 时尽量搜索：

```text
Apple Documentation
+
Framework
+
Symbol
```

例如：

```text
SwiftUI ScrollEdgeEffectStyle
```

而不是：

```text
how to make blurry scroll top swift ios
```

如果需要了解设计原因，再进一步查询：

```text
Apple HIG Scroll Views
```

以及：

```text
WWDC Scroll Edge Effect
```

目标是同时得到：

```text
API 怎么写
+
Apple 为什么这样设计
```

---

# 当前视觉基准速查

本项目目前确定：

| 项目 | 当前选择 |
|---|---|
| 主品牌色 | `#E8A39C` |
| SwiftUI Token | `accentPrimary` |
| 顶层导航 | System `TabView` |
| TabBar Background | `.toolbarBackground(.hidden, for: .tabBar)` |
| Tab 切换反馈 | `.sensoryFeedback(.selection, trigger: selectedTab)` |
| Scroll Edge | Automatic First |
| 指定 Edge Style | `.scrollEdgeEffectStyle(.soft, for: ...)` |
| 背景 | 低强度渐变 / System Background |
| UI 风格 | Native + Soft Brand Identity |
| 新 API 来源 | Apple Developer Documentation |
| 设计规范来源 | Apple HIG / Apple Design / WWDC |
| 未知 API | 先联网查 Apple 官方资料，禁止猜测 |

---

# 最终补充原则

本项目的 SwiftUI 设计方向可以概括为：

> **Apple Native Structure + #E8A39C Brand Accent + Soft Gradient + Modern Scroll Behavior + Restrained Haptics**

对于新 SwiftUI API：

> **Search First, Implement Second.**

对于 Apple 平台设计：

> **HIG First, Personal Preference Second.**

对于视觉效果：

> **Readability First, Effect Second.**