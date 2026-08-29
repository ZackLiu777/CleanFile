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

# 外观、主题与调色盘设置规则

外观与主题属于影响整个 App、且通常不会频繁修改的全局设置。

因此，本项目应将它们放在：

```text
Settings
    ↓
Appearance / Theme 子页面
```

不要把全局主题切换长期放在：

- 首页工具栏。
- 每个功能页面。
- TabBar。
- 文件处理流程。
- 与当前任务无关的快捷菜单。

如果外观设置只有一个非常短的选项，可以直接放在 Settings 当前页面；当它包含外观模式、主题、强调色和预览等一组相关设置时，应使用标准 `NavigationLink` 进入独立子页面。

Apple 官方依据：

- [Human Interface Guidelines — Settings](https://developer.apple.com/design/human-interface-guidelines/settings)
- [SwiftUI — NavigationLink](https://developer.apple.com/documentation/swiftui/navigationlink)

---

## Settings 页面结构

设置页面优先使用系统结构：

```swift
NavigationStack {
    Form {
        Section {
            NavigationLink {
                AppearanceSettingsView()
            } label: {
                Label("Appearance", systemImage: "paintpalette")
            }
        }
    }
}
```

主题子页同样优先使用：

```text
Form
    ↓
Section
    ↓
Picker / ColorPicker / Preview
```

规则：

- 使用 `Form` 获得平台一致的设置布局与控件样式。
- 使用 `Section` 按“外观模式、主题、强调色、预览”分组。
- 使用标准 `NavigationLink` 表达层级，不手绘 chevron 或自定义整行点击语义。
- 使用 `Picker` 表达互斥选择，不用多个 Button 自行模拟单选控件。
- 选项很少时优先采用系统自动或 inline 呈现；只有选项较多、确实需要进入列表时，才考虑 navigation-link picker style。
- 不为简单的三个外观选项增加没有信息价值的额外导航层级。

Apple 官方依据：

- [SwiftUI — Form](https://developer.apple.com/documentation/swiftui/form)
- [SwiftUI — Section](https://developer.apple.com/documentation/swiftui/section)
- [SwiftUI — Picker](https://developer.apple.com/documentation/swiftui/picker)
- [SwiftUI — NavigationLinkPickerStyle](https://developer.apple.com/documentation/swiftui/pickerstyle/navigationlink)

---

## 默认跟随系统

外观模式至少应支持：

```text
System
Light
Dark
```

默认值必须是：

> System / 跟随系统。

SwiftUI 中应优先通过：

```swift
.preferredColorScheme(nil)    // System
.preferredColorScheme(.light)
.preferredColorScheme(.dark)
```

表达用户选择，而不是直接修改 `colorScheme` Environment。

不得在首次启动时强迫用户选择浅色或深色，也不得用 App 内设置重复实现系统已有的：

- Increase Contrast。
- Reduce Motion。
- Differentiate Without Color。
- Button Shapes。
- Bold Text。

App 应直接尊重这些系统设置。

Apple 官方依据：

- [SwiftUI — ColorScheme](https://developer.apple.com/documentation/swiftui/colorscheme)
- [Human Interface Guidelines — Settings](https://developer.apple.com/design/human-interface-guidelines/settings)

---

## 背景选择必须解析为完整语义 Theme

主题或背景选项不得只保存和传递一个裸 `Color`：

```swift
// 不推荐
let selectedBackground: Color
```

一个可选主题必须解析为完整的语义 Theme，例如至少能统一提供：

```text
Background Primary
Background Secondary / Grouped Background
Card / Elevated Surface
Text Primary
Text Secondary
Separator
Accent
Selection
Destructive / Warning / Success
Light / Dark 适配
Increased Contrast 适配
```

业务 View 应消费语义 Token：

```swift
theme.backgroundPrimary
theme.cardSurface
theme.textPrimary
theme.textSecondary
theme.separator
```

而不是根据一个背景色在 View 内临时推导文字颜色、透明度和卡片颜色。

原因：

- 单个 `Color` 无法保证整页层级。
- 单个 `Color` 无法保证 Light / Dark 一致性。
- 单个 `Color` 无法可靠满足 Increase Contrast。
- 每个 View 自行推导会产生不一致和不可验证的对比度。

系统结构色优先使用动态语义颜色；自定义 Theme 也必须提供相同的语义职责，而不是用固定 RGB 覆盖所有层级。

Apple 官方依据：

- [Human Interface Guidelines — Color](https://developer.apple.com/design/human-interface-guidelines/color)
- [SwiftUI — ShapeStyle](https://developer.apple.com/documentation/swiftui/shapestyle)
- [SwiftUI — ColorSchemeContrast](https://developer.apple.com/documentation/swiftui/colorschemecontrast)

---

## 强调色与语义色必须分离

强调色负责：

- Primary Action。
- Link。
- Selection 强调。
- Toggle / Slider Tint。
- 少量品牌识别。

语义色负责：

- Background。
- Surface。
- Primary / Secondary Text。
- Separator。
- Destructive。
- Warning。
- Success。

禁止：

- 用强调色替代页面背景。
- 用强调色替代所有正文文字。
- 根据强调色自动生成 Destructive / Warning / Success。
- 为了“主题统一”把所有控件和卡片染成同一种颜色。
- 改变强调色时同时破坏背景和文本的语义层级。

品牌色可以进入 Theme，但它必须作为 `accentPrimary` 等明确 Token 存在，不能吞并其他语义颜色。

---

## Picker 与调色盘选择状态

所有主题、外观或调色盘选择都必须同时提供非颜色状态标识。

可以使用：

- Checkmark。
- Selected border。
- 明确的选中文字。
- 不同的 SF Symbol variant。
- 系统 Picker 自带的 selection state。

不得只通过：

```text
粉色圆点
蓝色圆点
绿色圆点
```

让用户判断当前选择。

当系统开启 `Differentiate Without Color` 时，界面仍必须能够表达：

- 哪一个主题已选中。
- 哪一个颜色可点击。
- 哪一个状态表示成功、警告或失败。

自定义色块应具有清晰的可访问名称和当前值，例如：

```text
“暖粉色，已选择”
“海蓝色，未选择”
```

Apple 官方依据：

- [Human Interface Guidelines — Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [SwiftUI — accessibilityDifferentiateWithoutColor](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilitydifferentiatewithoutcolor)
- [SwiftUI — Accessibility modifiers](https://developer.apple.com/documentation/swiftui/view-accessibility)

---

## 任意颜色与 ColorPicker

只有当产品确实允许用户选择任意颜色时，才显示系统 `ColorPicker`。

主题强调色不支持透明度，因此必须使用：

```swift
ColorPicker(
    "Accent Color",
    selection: $accentColor,
    supportsOpacity: false
)
```

不得允许透明主题色进入正式 Theme，因为透明度会让最终颜色依赖未知背景，导致对比度不可预测。

任意颜色在保存或应用前必须进行对比度校验，至少检查它在以下环境中的真实前景/背景组合：

- Light Mode。
- Dark Mode。
- 普通对比度。
- Increase Contrast。
- 按钮文字或图标。
- 选中状态。
- Focus / Disabled 状态。

如果颜色不能满足可读性要求，应：

- 阻止把它用于需要承载文字的角色；或者
- 自动选择可读的前景色并重新验证；或者
- 明确提示用户并保留恢复默认颜色的入口。

不得因为 ColorPicker 是系统控件，就假设用户选择的任意颜色天然满足可访问性。

Apple HIG 给出的常用最低对比度参考：

```text
普通小号文字：4.5:1
大号文字或粗体文字：3:1
```

Apple 官方依据：

- [SwiftUI — ColorPicker](https://developer.apple.com/documentation/swiftui/colorpicker)
- [Human Interface Guidelines — Color wells](https://developer.apple.com/design/human-interface-guidelines/color-wells)
- [Human Interface Guidelines — Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

---

## 触控区域与 VoiceOver

主题色块、预览卡片和自定义选择控件在 iOS / iPadOS 上的默认可点击区域应达到：

```text
44 × 44 pt
```

视觉色块可以更小，但 `contentShape`、padding 或外层 Button 的命中区域必须足够。

标准 `Picker`、`ColorPicker`、`NavigationLink` 和 `Button` 应优先保留系统可访问性语义。自定义控件必须补充：

- `accessibilityLabel`：描述它是什么。
- `accessibilityValue`：描述当前颜色或选择状态。
- `accessibilityHint`：仅在操作结果不明显时说明行为。
- 合理的 VoiceOver 阅读和焦点顺序。

不要把一个主题卡片拆成多个重复播报的装饰元素；装饰性渐变、阴影和背景图形不应成为独立的 VoiceOver 焦点。

Apple 官方依据：

- [Human Interface Guidelines — Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [SwiftUI — Accessibility modifiers](https://developer.apple.com/documentation/swiftui/view-accessibility)

---

## Increase Contrast

主题必须在系统开启 Increase Contrast 时保持可读。

优先使用会自动响应系统设置的语义颜色。自定义 Theme 需要读取：

```swift
@Environment(\.colorSchemeContrast) private var colorSchemeContrast
```

并在 `.increased` 时提供足够清晰的：

- 前景与背景差异。
- Card 与页面背景边界。
- Separator。
- Selection border。
- Disabled 与 Enabled 状态差异。

不得只通过降低 opacity 表示次级内容，因为在复杂背景或自定义主题下可能失去可读性。

Apple 官方依据：

- [SwiftUI — ColorSchemeContrast](https://developer.apple.com/documentation/swiftui/colorschemecontrast)
- [Human Interface Guidelines — Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

---

## 主题切换动画与 Reduce Motion

主题切换反馈应：

- 短暂。
- 准确。
- 不阻塞交互。
- 不成为理解选中状态的唯一方式。

可以使用轻量淡入淡出或颜色过渡，但不要在每次选择时执行：

- 整页 Scale。
- 大范围位移。
- 3D 翻转。
- 强弹簧。
- Blur 进出。
- 无法取消的长动画。

必须读取：

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

Reduce Motion 开启时，应取消大范围运动，并改为淡入淡出或无动画。不要再创建一个 App 内“减少动态效果”开关来复制系统设置。

Apple 官方依据：

- [Human Interface Guidelines — Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- [SwiftUI — accessibilityReduceMotion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)

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
