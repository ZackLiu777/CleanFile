# Sunburst / Folder Map 迭代方案

## 1. 本轮目标

当前 Folder Map 已经能够：

- 扫描用户授权目录。
- 获取文件 Metadata。
- 构建 `FileNode`。
- 通过 `Canvas` 绘制扇区。
- 根据文件大小分配角度。
- 支持点击与 Drill Down。
- 支持动态 Root。
- 支持基本颜色分支。

但当前视觉仍然表现为：

> **一个大饼图 + 若干扇区**

而不是目标 Disk Graph 风格的：

> **目录树径向投影 / Hierarchical Sunburst**

本轮迭代的核心不是继续调整颜色、Canvas、描边或动画，而是先修正：

```text
Scanner
    ↓
ScannedFile Path Information
    ↓
FileTreeBuilder
    ↓
真实 Hierarchical File Tree
    ↓
Sunburst Layout
```

只有底层树真正存在多层，UI 才能自然出现：

```text
Depth 1
Depth 2
Depth 3
Depth 4
...
```

---

# 2. 当前问题判断

当前 `SunburstLayoutEngine` 已经具备：

- `depth`
- `innerRadiusRatio`
- `outerRadiusRatio`
- Parent → Child 递归
- Child Angle 限制在 Parent Angle 内

也就是说 Layout Engine 已经具备真正 Sunburst 的基础结构。

并且当前递归代码已经会：

```text
parent
    ↓
child
    ↓
depth + 1
    ↓
child.children
```

继续生成下一圈。

因此：

> **如果最终仍然只有一圈，首先应该怀疑 File Tree，而不是 Canvas。**

---

# 3. 本轮开发优先级

按照以下顺序执行：

```text
P0  修复 Scanner → Tree 的目录层级信息
 ↓
P1  验证 FileNode 真正存在多级 children
 ↓
P2  修正 Ring Width 策略
 ↓
P3  修正 Small Node 聚合
 ↓
P4  调整视觉 Gap / Color
 ↓
P5  Drill Down / Hit Test
 ↓
P6  最后再做动画与视觉 polish
```

禁止倒序开发。

---

# 4. P0：给 ScannedFile 保存相对路径

## 当前问题

目前 `ScannedFile` 保存：

```text
absolute URL
name
category
size
dates
```

但是没有保存：

> **这个文件相对于用户选择根目录的位置。**

因此 `FileTreeBuilder` 只能事后通过：

```text
file.url
+
rootURL
```

重新推导目录关系。

当前实现一旦：

```swift
fileComponents.starts(with: rootComponents)
```

失败，就退化成：

```text
[file.name]
```

等价于：

```text
真实：

CloudDocs
└── Documents
    └── Work
        └── report.pdf


退化后：

CloudDocs
└── report.pdf
```

整个 hierarchy 会被静默拍平。

---

# 5. ScannedFile 新增字段

增加：

```swift
let relativePathComponents: [String]
```

语义必须明确：

假设用户选择：

```text
CloudDocs
```

文件实际位于：

```text
CloudDocs/Documents/Projects/App/report.pdf
```

则必须保存：

```swift
[
    "Documents",
    "Projects",
    "App",
    "report.pdf"
]
```

而不是只保存：

```swift
["report.pdf"]
```

---

# 6. Scanner 负责产生 Relative Path

目录关系应该：

> **在 Scanner 枚举文件的时候确定。**

而不是在 TreeBuilder 中重新猜。

最终职责变成：

```text
MetadataFileScanner
    │
    ├── absolute URL
    ├── metadata
    ├── size
    ├── category
    └── relativePathComponents
                ↓
           ScannedFile
```

可以利用 `DirectoryEnumerator` 当前层级信息，或者使用一个经过验证的 relative-path helper。

核心原则：

> Scanner 必须输出真实 Relative Path。

不允许：

```text
relative path 算不出来
↓
直接 fallback 到 filename
```

如果无法建立可信路径：

> 应明确跳过或记录 Failure。

不能悄悄拍平目录树。

---

# 7. Scanner 保持递归

当前使用：

```swift
FileManager.default.enumerator(...)
```

方向正确。

本轮不得将其改成：

```swift
contentsOfDirectory(...)
```

因为后者如果只处理第一层，会直接失去 Sunburst 所需的 hierarchy。

目标扫描结果：

```text
CloudDocs
│
├── Documents
│   └── Work
│       └── report.pdf
│
└── Downloads
    └── Video
        └── movie.mov
```

Scanner 应得到：

```text
report.pdf
relativePathComponents =
["Documents", "Work", "report.pdf"]

movie.mov
relativePathComponents =
["Downloads", "Video", "movie.mov"]
```

---

# 8. P1：FileTreeBuilder 不再推断 URL

完成 `relativePathComponents` 后，删除 TreeBuilder 中：

```text
rootURL.pathComponents
file.url.pathComponents
starts(with:)
dropFirst(...)
fallback filename
```

TreeBuilder 只消费：

```swift
file.relativePathComponents
```

职责彻底变成：

> Relative Paths → Hierarchical Tree

---

# 9. TreeBuilder 应生成的结构

输入：

```text
A:
["Documents", "Projects", "app.zip"]

B:
["Documents", "Projects", "README.md"]

C:
["Downloads", "Videos", "movie.mov"]

D:
["Downloads", "Images", "photo.heic"]
```

输出必须是：

```text
CloudDocs
│
├── Documents
│   └── Projects
│       ├── app.zip
│       └── README.md
│
└── Downloads
    ├── Videos
    │   └── movie.mov
    │
    └── Images
        └── photo.heic
```

而不是：

```text
CloudDocs
├── app.zip
├── README.md
├── movie.mov
└── photo.heic
```

---

# 10. Directory Size 聚合原则

目录自身大小：

> 等于所有 descendants 的已知文件大小之和。

例如：

```text
Documents        20 MB
└── Projects     20 MB
    ├── A         15 MB
    └── B          5 MB
```

因此：

```text
Documents.byteCount = 20
Projects.byteCount  = 20
A.byteCount         = 15
B.byteCount         = 5
```

不是重复统计。

这些值用于不同层级的角度分配。

---

# 11. 必须增加 Tree Diagnostics

本轮不要再通过截图猜 Tree 是否正确。

增加 Debug-only 辅助能力。

至少输出：

```text
Root children
Maximum depth
前几层 hierarchy
```

例如：

```text
com~apple~CloudDocs
children = 7

  Documents
  children = 4

    Projects
    children = 3

      CleanMyIPhone
      children = 22

  Downloads
  children = 5
```

关键指标：

```text
Tree Maximum Depth
```

如果：

```text
Maximum Depth = 1
```

Sunburst 一圈就是正常结果。

如果：

```text
Maximum Depth = 5
```

但只有一圈：

> 才继续调查 Layout Engine。

---

# 12. 本轮必须检查最大 Sector

当前截图中有一个接近 80% 的巨大红色 Sector。

需要明确它是什么。

检查：

```text
node.name
node.byteCount
node.isDirectory
node.children.count
```

如果：

```text
movie.mov
isDirectory = false
children = 0
```

那么：

> 大 Sector 完全正确。

它确实就是一个巨大文件。

如果：

```text
Documents
isDirectory = true
children = 0
```

则：

> Tree Builder 出错。

如果：

```text
Documents
isDirectory = true
children = 12
```

但 UI 没有第二圈：

> Layout Engine 出错。

通过这一项可以快速把问题切成：

```text
Data Layer
vs
Layout Layer
```

---

# 13. P2：Ring Width 不再无限扩张

上一轮使用：

```text
实际 Tree Depth
↓
平均分满所有剩余 Radius
```

解决了“图太小”的问题。

但又产生了新的问题：

```text
actualDepth = 1
↓
唯一 Ring 占满全部剩余 Radius
↓
巨大 Pie
```

因此本轮改成：

> **Actual Depth + Preferred Maximum Ring Width**

---

# 14. 新增 Ring Width 配置

增加：

```swift
preferredRingWidthRatio
```

建议初始：

```text
0.10 ~ 0.13
```

例如：

```swift
preferredRingWidthRatio = 0.115
```

Ring Width：

```text
availableRadius
        ↓
availableRadius / actualDepth
        ↓
与 preferredRingWidthRatio 比较
        ↓
取较小值
```

即：

```swift
ringWidth = min(
    preferredRingWidthRatio,
    maximumAllowedRingWidth
)
```

---

# 15. Ring Width 最终效果

### 如果只有一层

不要：

```text
██████████████████████
██████████████████████
████████ ○ ███████████
██████████████████████
```

而应该：

```text
      ███████████
    ███         ███
   ██      ○      ██
    ███         ███
      ███████████
```

剩余 Radius：

> 保持空白。

---

### 如果有五层

自然生长：

```text
Depth 5          ██
Depth 4        ████
Depth 3      ██████
Depth 2    ████████
Depth 1  ██████████
             ○
```

没有 children 的 Branch：

> 停止。

不会自动延伸到最外圈。

---

# 16. Disk Graph 最重要的视觉规则

必须永久保持：

> **Leaf 到哪里结束，Branch 就在哪里结束。**

不要：

```text
leaf
↓
自动 extend to maximumRadius
```

因为目标图漂亮的核心之一正是：

> 外轮廓不规则。

例如：

```text
           ██

        █████

      ███████

██████████

      ███

          █████
```

这些外层空白不是 Bug。

它们就是：

> Directory Tree Structure。

---

# 17. P3：Small Node Aggregation

当前已经有：

```text
minimumAngularSpan
Other
```

方向正确。

但本轮调整语义：

> Aggregate Node 是 Visual Node，不是普通目录。

如果：

```text
427 个很小文件
```

总角度太小，不应该生成：

```text
427 根 <1px 扇区
```

应该：

```text
Smaller Objects
```

一个节点表示。

---

# 18. Aggregate Node 不默认展开

当前逻辑已经阻止：

```text
isAggregate
```

继续递归。

建议进一步统一模型语义：

```text
Aggregate Node
=
Layout generated visual group
```

它不应该看起来像一个普通物理文件夹。

如果未来要支持：

```text
Tap Smaller Objects
↓
继续 Drill Down
```

单独设计 Aggregate Drill Down。

不要和正常 Folder Navigation 混在一起。

---

# 19. P4：Angular Gap

目标 Disk Graph 与普通 Donut 最大视觉差异之一：

> Branch 之间存在清晰的裂缝。

Gap 分两级。

### Root Major Gap

一级目录之间：

```text
Documents   |    Downloads
            ↑
       明显 branch gap
```

建议：

```text
约 1.5°～3°
```

实际值根据屏幕调整。

---

### Sibling Gap

普通 children：

```text
A|B|C|D
```

只需要：

```text
很细的 gap
```

不能每个小文件之间都留非常宽的白缝。

---

# 20. Gap 不允许吃掉 Parent

必须保持：

```text
totalGap
<<
parentAngularSpan
```

小 Branch 中如果 Children 太多：

> 动态压缩 Gap。

不要出现：

```text
Parent = 5°

10 children
Gap total = 4°
```

最终节点全变成白线。

---

# 21. P5：颜色继承

目标不是：

```text
每个文件 = 彩虹一个新颜色
```

也不是：

```text
所有节点 = 红色
```

应该：

```text
Root Branch
↓
决定 Base Hue

Child
↓
继承 Base Hue
+
轻微偏移

Grandchild
↓
继续轻微变化
```

例如：

```text
Documents
cyan

↓

Projects
cyan-blue

↓

App
blue-cyan
```

另一个 Root：

```text
Downloads
pink

↓

Videos
coral-pink

↓

Movie
red-pink
```

最终形成：

> 一个 Branch 内颜色相近，不同 Branch 明显区分。

---

# 22. 文件 Category 不用于 Sunburst 主颜色逻辑

Storage Summary 可以：

```text
Video = Red
Image = Pink
Document = Blue
```

但是 Folder Map 展示的是：

> Filesystem Hierarchy

不是：

> File Category。

所以 Sunburst 主颜色应该表达：

> Branch Identity。

而不是简单：

```text
所有 Video 都红
所有 PDF 都蓝
```

否则同一个 Folder Branch 内会变得非常杂乱。

---

# 23. P6：Canvas 暂时保持

当前：

```text
Canvas
+
Path
```

路线正确。

本轮不要改成：

```text
ForEach
+
数千个 Shape
```

原因：

> 文件图可能存在数百到上千 Sector。

Canvas 更适合这种大量轻量几何绘制。

---

# 24. Stroke 降低存在感

Sector 主要通过：

> Gap

形成分离。

Stroke 只作为极弱辅助。

保持：

```text
lineWidth ≈ 0.3 ~ 0.5
```

Opacity：

```text
约 0.1 ~ 0.2
```

不要通过粗黑边模拟目录分割。

---

# 25. P7：Drill Down 保留

当前点击行为：

```text
Folder
↓
currentRoot = Folder
↓
重新 Layout 360°
```

这个方向正确。

不要做：

> 在原图上无限 Scale Zoom。

重新 Root 的方式：

- 简单。
- 稳定。
- 容易 Hit Test。
- 非常适合 iPhone。

---

# 26. Drill Down 行为

点击 Directory：

```text
CloudDocs
↓
Documents
↓
Projects
```

Breadcrumb：

```text
CloudDocs > Documents > Projects
```

点击 File：

> 选中文件。

不重新 Root。

---

# 27. Root 更新问题

当前 `SunburstView` 使用：

```text
StateObject
```

因此外部 Scanner 更新 `root` 时，需要：

```text
replaceRoot()
```

当前方向正确。

保持：

```text
.onChange(of: root)
```

不要使用：

```swift
.id(UUID())
```

强制重建整个 View。

---

# 28. Storage 页面本轮暂不重构

当前页面：

```text
Analyzed Folder
Status
Folder Map
Storage Summary
Largest Files
```

本轮不进行大规模 UI 重构。

优先把：

> Folder Map 数据与 Layout 做正确。

等 Sunburst 达到目标后再调整页面结构。

---

# 29. 后续 UI 优化

Sunburst 正确后，再考虑：

### 减少 Folder Map 卡片空白

目标：

```text
Folder Map

      Sunburst
```

占用更紧凑。

---

### Breadcrumb 更接近工具 UI

例如：

```text
CloudDocs › Documents › Projects
```

---

### Center Label

中心只显示：

```text
当前 Root
容量
```

例如：

```text
Projects
12.8 GB
```

不要放过多信息。

---

# 30. 中心洞

建议：

```text
centerRadiusRatio
≈ 0.14 ~ 0.17
```

不要过大。

Disk Graph 的中心只是：

> Root 信息入口。

不是主要视觉主体。

---

# 31. 本轮不要做动画

在 hierarchy 没正确之前：

禁止浪费时间做：

- Sector Transition。
- Spring。
- Zoom Animation。
- Color Animation。
- Rotation。
- Selection Glow。

开发顺序必须：

```text
Correct Tree
↓
Correct Layout
↓
Correct Hit Test
↓
Performance
↓
Animation
```

---

# 32. 当前完整目标 Pipeline

本轮完成后应该变成：

```text
UIDocumentPicker / fileImporter
        ↓
用户授权 Root
        ↓
MetadataFileScanner
        │
        ├── metadata
        ├── file size
        ├── category
        └── relativePathComponents
        ↓
ScannedFile[]
        ↓
FileTreeBuilder
        ↓
真实 FileNode Hierarchy
        ↓
Tree Diagnostics
        ↓
SunburstLayoutEngine
        │
        ├── size → angular span
        ├── depth → radius
        ├── parent → child angle inheritance
        ├── leaf → stop
        └── tiny nodes → aggregate
        ↓
SunburstSector[]
        ↓
Canvas
        ↓
Hit Testing
        ↓
Drill Down
```

---

# 33. 本轮第一阶段验收

完成 Scanner / TreeBuilder 修改后，必须能观察到：

```text
File:
report.pdf

relative:
["Documents", "Work", "report.pdf"]
```

而不是：

```text
["report.pdf"]
```

---

# 34. Tree 验收

如果真实目录是：

```text
CloudDocs
└── A
    └── B
        └── file.pdf
```

Tree 必须：

```text
Depth = 3+
```

而不是：

```text
Depth = 1
```

---

# 35. Layout 验收

如果 Tree：

```text
Root
├── A
│   └── B
│       └── C
└── file
```

Sunburst 必须：

```text
Ring 1:
A
file

Ring 2:
B

Ring 3:
C
```

`file` 对应 branch：

> Ring 1 后停止。

不能延伸到 Ring 2/3。

---

# 36. Single-Level 验收

如果真实目录确实只有：

```text
Root
├── a
├── b
└── c
```

那么：

> 图就应该只有一层。

但是该 Ring：

> 不应该因为只有一层就填满整个 Radius。

这是 `preferredRingWidthRatio` 需要解决的问题。

---

# 37. Large File 验收

如果：

```text
movie.mov = 80%
```

那么它：

> 就应该占约 80% 的角度。

不要为了美观人为缩小。

Sunburst 必须保持：

> Data Honesty。

---

# 38. Performance 验收

第一阶段目标：

```text
<= 1,500 visible sectors
```

通过：

- minimumAngularSpan
- aggregation
- maximumSectorCount

控制。

不要试图把：

```text
50,000 files
```

全部单独画出来。

---

# 39. Testing 策略

遵循项目规则：

> 本地不执行 Test。

本地仅：

```text
Build
```

正式 Tests：

> GitHub Actions。

---

# 40. Required Unit Tests

以下属于确定性逻辑，应进入 Must Pass：

### Relative Path

输入固定 hierarchy：

```text
Root/A/B/file.pdf
```

应得到：

```text
["A", "B", "file.pdf"]
```

---

### Tree Builder

输入：

```text
A/B/1
A/C/2
```

必须得到：

```text
Root
└── A
    ├── B
    │   └── 1
    └── C
        └── 2
```

---

### Directory Size

```text
A
├── 10 MB
└── 20 MB
```

必须：

```text
A = 30 MB
```

---

### Tree Depth

固定 Tree：

```text
Root → A → B → C
```

必须得到正确 Depth。

---

### Sunburst Layout

验证：

```text
child.start >= parent.start

child.end <= parent.end
```

---

### Radius

必须：

```text
depth + 1
→
更大的 innerRadius
```

---

### Leaf

Leaf 不允许：

> 自动延伸到 maximum radius。

---

### Angular Proportion

```text
A = 75
B = 25
```

必须近似：

```text
A = 270°
B = 90°
```

扣除 Gap 后按相同比例计算。

---

# 41. 本轮不要写脆弱 UI Test

本轮核心问题是：

> 数据结构 + Layout Math。

因此重点：

```text
Swift Testing
```

而不是 Screenshot / Pixel Test。

UI 自动化可以继续保持 Non-Blocking。

---

# 42. 本轮具体实施顺序

## Iteration 1 — ScannedFile

新增：

```text
relativePathComponents
```

更新 initializer。

---

## Iteration 2 — MetadataFileScanner

枚举文件时直接产生：

```text
relativePathComponents
```

不得 silent flatten。

---

## Iteration 3 — FileTreeBuilder

删除绝对 URL prefix 推断。

直接使用：

```text
relativePathComponents
```

---

## Iteration 4 — Diagnostics

开发模式确认：

```text
Root children
Tree depth
前 3～4 层 hierarchy
```

---

## Iteration 5 — Layout Width

增加：

```text
preferredRingWidthRatio
```

避免单层扩大成巨大 Pie。

---

## Iteration 6 — Aggregate

统一 `Smaller Objects` 语义。

限制 visible sector 数量。

---

## Iteration 7 — Visual Tuning

最后调整：

```text
major gap
sibling gap
color inheritance
stroke
center radius
```

---

## Iteration 8 — Interaction

验证：

```text
Hit Test
Drill Down
Breadcrumb
Root Replacement
```

---

# 43. 本轮明确不做

不要：

- 重写 `StorageView`。
- 替换 Canvas。
- 改成 Swift Charts。
- 加第三方 Sunburst Library。
- 做复杂动画。
- 做 3D。
- 做 Zoom Gesture。
- 为视觉效果造假层级。
- 根据文件 Category 人工增加 Depth。
- 让 leaf 延伸到 Outer Radius。
- 为了“更像 Disk Graph”伪造目录。

---

# 44. 最终目标

最终图不是：

> 一个漂亮的多层饼图。

而应该是：

> **真实文件目录树的径向可视化。**

其数学语义保持：

```text
File Size
→ Angle

Directory Depth
→ Radius

Parent
→ Angular Boundary

Children
→ Split Parent Angle

Leaf
→ Stop Growing

Small Nodes
→ Aggregate

Folder
→ Drill Down
```

最终我们想得到的视觉：

```text
                     ▌
                  ███▌
               ██████
             ███████
        █████████
      ███████████

              ███
           ███████

    █████████
       █████

          ○
```

而不是：

```text
      ███████████████
    ███████████████████
   █████████████████████
         ○
```

本轮最重要的一句话：

> **不要继续修 Canvas，先让 Scanner → ScannedFile → FileTreeBuilder 真正保留 filesystem hierarchy。**

当 Tree 正确之后，当前 Sunburst 的绘制框架已经足够承载目标 Disk Graph 效果。