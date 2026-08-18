# PITFALLS.md

## 1. 文档目的

本文档记录本项目开发过程中需要重点防范的工程风险、SwiftUI 常见陷阱、文件系统风险、并发问题、性能问题、构建问题以及从此前大型 iOS 项目中已经验证过的经验。

本文件的目标不是：

> 罗列所有理论上的错误。

而是：

> **避免重复踩已经发生过、或者在当前项目中高度可能发生的坑。**

开发过程中同时遵守：

- `AGENTS.md`
- `PROJECT_START.md`
- `SWIFTUI_RULES.md`

优先级：

```text
AGENTS.md
    ↓
PROJECT_START.md
    ↓
SWIFTUI_RULES.md
    ↓
PITFALLS.md
```

如果发生规则冲突：

> 以更高优先级文档为准。

---

# 2. 总体原则

遇到 Bug 时，不要立即假设：

> 当前看到的代码就是根因。

很多 iOS 问题可能来自：

- SwiftUI 生命周期。
- Environment。
- MainActor。
- File Provider。
- Security Scoped Resource。
- iCloud。
- 文件系统状态。
- Xcode Build Cache。
- Simulator。
- 新系统 API。
- Framework Beta 行为。
- 本地化资源。
- 数据模型状态。
- 增量缓存。

因此调试优先顺序应是：

```text
确认现象
↓
确认输入
↓
确认状态
↓
确认平台能力
↓
确认数据流
↓
确认线程 / Actor
↓
确认缓存
↓
最后修改代码
```

不要：

```text
看到异常
↓
猜一个原因
↓
直接大改
```

---

# 3. 平台能力误判

这是本项目最需要防止的错误之一。

## 3.1 不存在“扫描整个 iPhone 文件系统”

不得假设：

```text
FileManager
```

可以扫描：

- WhatsApp 数据。
- 微信缓存。
- Instagram 缓存。
- Safari 私有缓存。
- 其他 App Documents。
- 系统内部文件。
- iOS System Cache。

如果某个功能需要这些能力：

> 首先确认 Apple 是否提供公开 API。

如果没有：

> 功能本身不可实现。

不要通过代码技巧尝试绕过 Sandbox。

---

## 3.2 UI 不得领先于真实能力

禁止先设计：

```text
Clean Instagram Cache
Clean System Cache
Free RAM
Boost iPhone
```

然后再寻找实现方式。

正确顺序：

```text
Apple Public API Capability
        ↓
确认真的可实现
        ↓
定义业务
        ↓
设计 UI
```

不是：

```text
营销功能
↓
UI
↓
试图绕过平台
```

---

# 4. Security-Scoped URL

Security-Scoped Resource 是本项目的重要风险点。

## 4.1 URL 不代表永久权限

用户通过文件选择器获得：

```swift
URL
```

不代表：

> 永远可以访问这个 URL。

可能出现：

- 权限失效。
- File Provider 状态变化。
- 用户移动文件。
- 用户删除文件。
- iCloud 文件尚未下载。
- Provider 暂时离线。

因此：

```swift
FileManager.default.fileExists(atPath:)
```

不能证明：

> 文件一定能够成功读取。

---

## 4.2 startAccessing 必须配对

如果调用：

```swift
url.startAccessingSecurityScopedResource()
```

必须保证：

```swift
url.stopAccessingSecurityScopedResource()
```

在所有退出路径都执行。

优先：

```swift
guard url.startAccessingSecurityScopedResource() else {
    ...
}

defer {
    url.stopAccessingSecurityScopedResource()
}
```

避免权限生命周期泄漏。

---

## 4.3 不要每个子文件重复申请目录权限

如果用户授权的是一个目录：

> 应围绕授权目录管理访问生命周期。

不要扫描 10,000 个文件时：

```text
startAccessing(file1)
stopAccessing(file1)

startAccessing(file2)
stopAccessing(file2)

...
```

进行无意义的高频权限切换。

---

## 4.4 Security Bookmark 不是普通字符串

如果未来持久化 Security-Scoped Bookmark：

不得：

- 当普通 URL 字符串保存。
- 发送到 Analytics。
- 输出完整内容到日志。
- 假设永远不会 stale。

必须处理：

> stale bookmark。

---

# 5. File Provider 不是本地磁盘

用户选择的文件可能来自：

- iCloud Drive。
- Google Drive。
- Dropbox。
- OneDrive。
- NAS Provider。
- 其他 File Provider。

不要假设：

```text
URL = 本地 NAND 文件
```

某个 metadata 请求可能触发：

> 网络下载。

某个文件可能：

> 只有 placeholder。

因此文件访问必须对远程 Provider 保持容错。

---

# 6. 文件在操作过程中可能消失

经典错误：

```text
扫描时存在
↓
用户删除 / Provider 更新
↓
App 之后继续使用旧 URL
```

所以：

```text
scan result
```

只是：

> 某一时刻的快照。

后续删除、转换、读取时仍然必须重新处理错误。

不要写：

```swift
if fileExists {
    // 后面一定存在
}
```

这种 TOCTOU 假设。

---

# 7. Metadata First

扫描文件时，不要第一步读取完整文件内容。

错误：

```swift
let data = try Data(contentsOf: url)
```

只是为了知道：

- 大小。
- 类型。
- 修改时间。

正确：

```text
URLResourceValues
UTType
FileManager Metadata
```

先完成 Metadata Scan。

---

# 8. Data(contentsOf:) 大文件风险

禁止默认使用：

```swift
Data(contentsOf: largeFileURL)
```

处理任意用户文件。

用户文件可能：

```text
50 MB
500 MB
5 GB
20 GB
```

一次加载进内存可能造成：

- Memory Warning。
- App 被 Jetsam。
- 页面卡死。
- Swift allocator 压力。
- 峰值内存爆炸。

大文件必须优先：

> Streaming / Chunking。

---

# 9. 不要对所有文件立即 Hash

这是非常容易制造性能问题的实现。

错误：

```text
Scan
↓
SHA256 every file
```

如果用户文件总量：

```text
80 GB
```

等于额外读取：

```text
80 GB
```

甚至更多。

正确流程：

```text
Size Group
↓
Candidate
↓
Partial Hash
↓
Full Hash
```

Full Hash 是：

> 最后一层确认。

不是：

> 基础 Metadata。

---

# 10. Hash 也不能一次读取完整文件

即使已经需要计算 SHA256：

不要：

```swift
SHA256.hash(
    data: Data(contentsOf: url)
)
```

对于大文件必须：

```text
FileHandle
↓
Chunk
↓
Incremental SHA256
```

否则 Duplicate Detection 本身就可能把 App 内存打爆。

---

# 11. 相同文件大小不代表 Duplicate

不能：

```text
size == size
→ duplicate
```

文件大小只适合作为：

> Candidate Filter。

最终 Duplicate 必须基于：

> 内容一致性。

---

# 12. 文件名不代表 Duplicate

不能通过：

```text
IMG_001.jpg
IMG_001 copy.jpg
```

直接判断内容相同。

同样：

```text
report.pdf
report.pdf
```

也不能证明内容相同。

文件名只能用于：

> UI。

不能作为 Duplicate Identity。

---

# 13. Similar 与 Duplicate 不得混淆

Duplicate：

> 内容完全一致。

Similar：

> 内容相似。

例如：

```text
原图
压缩图
裁剪图
截图
```

可能视觉相似，但 Hash 完全不同。

UI 必须明确区分：

```text
Exact Duplicates
Similar Photos
```

不能统一叫：

> Duplicates。

---

# 14. 不要过早生成 Thumbnail

一个常见性能灾难：

```text
扫描文件
↓
同时生成所有图片 Thumbnail
↓
同时生成所有视频 Thumbnail
```

如果有：

```text
10,000 photos
```

会直接造成：

- I/O 激增。
- Image Decode 激增。
- GPU / CPU 激增。
- 内存缓存暴涨。
- Scroll 掉帧。

Thumbnail 必须：

- Lazy。
- On-screen。
- Cached。
- 可取消。

---

# 15. Thumbnail 必须 Downsample

不要为了显示：

```text
60 × 60
```

缩略图，而完整 decode：

```text
4032 × 3024
```

图片。

应该使用 Downsampling。

UI 需要多大：

> 解码多大。

---

# 16. 视频 Thumbnail 是高成本操作

AVAsset / AVAssetImageGenerator 等操作可能：

- 访问媒体 metadata。
- 解码帧。
- 访问远程文件。

因此不要在 `body` 中创建。

必须交给：

> 后台 Service / Thumbnail Pipeline。

---

# 17. View body 必须是纯描述

此前项目已经踩过：

> body 内修改 @Observable 状态导致刷新循环和掉帧。

因此禁止：

```swift
var body: some View {
    viewModel.value = calculate()
    ...
}
```

也不要：

```text
body
↓
文件扫描
↓
数据库写入
↓
Hash
```

`body` 应尽可能是：

> Pure Function of State。

---

# 18. Computed Property 也可能是性能陷阱

例如：

```swift
var sortedFiles: [File] {
    files.sorted { ... }
}
```

如果：

```text
50,000 files
```

而 View 每次刷新都执行：

> 50,000 项排序。

性能会非常差。

昂贵的：

- Sort。
- Filter。
- Group。
- Aggregate。

应在 ViewModel / Service 中提前计算。

---

# 19. LazyVStack 不等于一切都自动高性能

虽然：

```swift
LazyVStack
```

避免一次创建全部 View，

但如果：

```text
每个 Row 的 Model 本身有巨大数据
每个 Row 都同步 decode 图片
每个 Row 都重新计算 Metadata
```

仍然会卡。

Lazy 只解决：

> View 创建。

不会自动解决：

> 数据处理。

---

# 20. Stable Identity

避免：

```swift
ForEach(files.indices, id: \.self)
```

用于会：

- 删除。
- 插入。
- 排序。
- 更新。

的文件列表。

否则 SwiftUI 可能复用错误 Row。

文件必须拥有：

> Stable Identity。

---

# 21. `.id()` 是危险的重建工具

此前项目已经验证：

```swift
.id(...)
```

可能导致整个 View Tree 重建。

如果其中包含：

- @State。
- ViewModel。
- Task。
- Navigation State。

这些状态全部可能被销毁。

不要使用：

```swift
.id(UUID())
```

作为：

> 强制刷新 UI。

这是高风险反模式。

---

# 22. SwiftUI Environment 单一真源

不要让：

```text
AppState Theme
+
Environment Theme
+
Local State Theme
```

同时成为主题来源。

这会产生：

> 半刷新。

原则：

> Global UI State 必须 Single Source of Truth。

同样适用于：

- Selected Tab。
- Theme。
- Current Scan。
- Current Directory。
- Selection Mode。

---

# 23. Sheet / FullScreenCover 环境问题

此前项目已经遇到：

> Sheet 作为独立 Presentation Root，环境状态可能和主树不同步。

因此如果未来存在动态 Theme：

必须检查：

- Sheet。
- fullScreenCover。
- Popover。
- Confirmation UI。

是否正确继承：

- Theme。
- colorScheme。
- tint。

不要假设：

> 主树正常 = Sheet 一定正常。

---

# 24. Dynamic Color 不要错误缓存

如果自定义 Theme 存储依赖环境的：

```swift
.primary
.secondary
UIColor.label
```

要特别谨慎。

这些颜色可能：

> 根据 colorScheme 动态解析。

如果被错误缓存或跨 Environment 保存，可能出现：

> Theme 已变，颜色仍是旧环境版本。

如果建立自定义 Theme，优先使用明确语义 Token 并验证真实行为。

---

# 25. 系统背景是多层的

一个常见 SwiftUI 问题：

```swift
.background(...)
```

加了但看不到。

可能不是 Color 失效，而是：

```text
NavigationStack
List
Form
ScrollView
System Background
```

存在额外不透明层。

遇到背景问题优先检查：

> View Hierarchy / Container Background。

不要不断叠加 `.background()`。

---

# 26. 不要过度叠 Material

此前项目已经验证：

```text
Material
+
Material
+
Blur
+
Shadow
```

很容易：

- 性能下降。
- Liquid Glass 采样异常。
- 视觉浑浊。
- Toolbar 合成冲突。

系统 Glass / Material：

> 能少一层就少一层。

---

# 27. Toolbar Item 必须简单

Toolbar 内不要塞：

```text
Menu
+ Spacer
+ Material
+ Custom Background
+ sheet modifier
+ Complex Geometry
```

此前这种组合已经导致：

- 重叠。
- Dynamic Island 空间冲突。
- Sheet 异常。
- Material 合成问题。

Toolbar Item 优先：

> 单一 Button / Menu。

复杂 Presentation Modifier 挂在：

> 稳定的 View Tree 根部。

---

# 28. TabView 不要自己重复实现背景

本项目已经规定：

```swift
.toolbarBackground(.hidden, for: .tabBar)
```

让背景透出。

不要同时再：

```text
Custom Tab Background
+
System TabBar
```

除非经过实际 UI 验证确有必要。

---

# 29. Haptic 不要重复触发

已有：

```swift
.sensoryFeedback(. UI 验证确有必要。

---

# 29. Haptic 不要重复触发

已有：

```swift
.sensoryFeedback(.selection, trigger: selectedTab)
```

时不要又调用：

```text
UIImpactFeedbackGenerator
```

相同交互只允许一次 Feedback。

---

# 30. 不要根据模型记忆猜新 API

iOS / SwiftUI 更新快。

如果遇到：

- 新 Scroll API。
- Liquid Glass。
- TabView 新行为。
- Navigation 新 API。
- 新 Modifier。
- API Availability 不确定。

必须：

> 查 Apple 官方文档。

不要：

```text
猜一个 modifier
↓
Build
↓
再猜一个
```

---

# 31. Swift Charts Domain 静默裁剪

此前项目非常重要的经验：

> Swift Charts 数据落在 Domain 外时可能直接不显示，而且没有明显 Warning。

如果未来 Donut 之外增加：

- 时间图。
- Storage History。
- Cleanup Trend。

出现：

> 数据存在但图表没显示。

首先检查：

```text
Domain
Scale
Data Range
```

不要第一时间怀疑数据没加载。

---

# 32. Swift Charts 不要强行统一所有数据形态

不同图表数据：

```text
Storage Category
Time Series
File Size Distribution
```

没有必要共享全部配置。

此前已经证明：

> 为了代码统一而强行复用 Chart 配置，容易互相污染。

共享：

> 真正相同的视觉 Token。

不要共享：

> 本质不同的 Scale / Mark 配置。

---

# 33. Beta Framework 内部断言

如果使用较新的 iOS SDK / Beta SDK，

出现：

```text
ChartInternal
SwiftUI Internal Assertion
SIGTRAP
```

不要无限调整参数尝试绕过系统内部断言。

优先：

1. 查询 Apple 文档。
2. 确认 API Availability。
3. 最小复现。
4. 换稳定方案。
5. 必要时记录 Radar / Feedback。

系统 Framework bug：

> 不应通过大规模业务代码重构解决。

---

# 34. 并发不是越多越快

禁止：

```swift
for file in files {
    Task {
        ...
    }
}
```

处理数万文件。

可能导致：

- Task 爆炸。
- File Handle 爆炸。
- 内存激增。
- I/O 抢占。
- 热量增加。

应使用：

> Bounded Concurrency。

---

# 35.炸。
- 内存激增。
- I/O 抢占。
- 热量增加。

应使用：

> Bounded Concurrency。

---

# 35.炸。
- 内存激增。
- I/O 抢占。
- 热量增加。

应使用：

> Bounded Concurrency。

---

# 35. async 不等于后台线程

如果：

```swift
@MainActor
func scan() async {
    expensiveSyncWork()
}
```

那么：

> expensiveSyncWork 仍可能阻塞 MainActor。

不要仅仅因为函数标记：

```swift
async
```

就认为性能问题已经解决。

---

# 36. Actor 不是性能魔法

`actor` 负责：

> Data Isolation。

不意味着：

> 自动并行。

如果把所有文件任务全部塞进同一个 actor 顺序执行：

> 可能完全串行。

Actor 的使用目的首先是：

> 正确性。

然后再设计并发。

---

# 37. 删除不要高并发

删除 10,000 个文件时，不要：

```text
10,000 concurrent removeItem
```

删除涉及：

- Filesystem Metadata。
- File Provider。
- Security Permission。
- Directory Update。

默认应采用：

> 串行或低并发。

性能需要 Benchmark 后再调整。

---

# 38. 删除不能“失败即全部失败”

批量删除：

```text
100 files
```

其中：

```text
98 success
2 failure
```

UI 不应该只显示：

> Delete Failed。

必须支持：

> Partial Success。

同时 Index 必须只移除：

> 实际成功删除的文件。

---

# 39. 删除后不要默认 Full Rescan

错误：

```text
Delete 1 file
↓
Rescan 50,000 files
```

正确：

```text
Delete Success
↓
Index Remove
↓
Rescan 50,000 files
```

正确：

```text
Delete Success
↓
Index Remove
↓
Storage Summary Incremental Update
```

只有数据一致性无法保证时才执行 Full Rescan。

---

# 40. 删除必须区分“已经不存在”

如果用户已经在 Files App 删除文件，

然后 App 再执行删除：

```text
file not found
```

不一定应该显示：

> 严重错误。

业务上可能应视为：

> 目标已经不存在。

具体语义应明确设计。

---

# 41. 转换不能覆盖义应明确设计。

---

# 41. 转换不能覆盖原文件

默认转换：

```text
A
↓
B
```

必须生成：

> 新文件。

禁止直接覆盖 Original。

除非用户明确选择：

> Replace Original。

---

# 42. 转换前必须检查剩余空间

例如：

```text
10 GB video
```

转换过程中可能同时存在：

```text
Original 10 GB
+
Temporary 10 GB
+
Output 8 GB
```

真实峰值空间可能远高于输出文件大小。

因此大型转换必须考虑：

> Available Capacity。

---

# 43. 临时文件必须有生命周期

转换失败时很容易留下：

```text
tmp-123.mp4
partial-output.mov
```

必须：

```text
Success
→ move final output

Failure / Cancel
→ cleanup temp
```

不要让转换器不断污染 App 沙盒。

---

# 44. Conversion Cancellation

用户取消转换后：

- 停止处理。
- 清理 Partial Output。
- 不删除 Original。
- UI 切到 Cancelled。
- 不错误显示 Success。

取消：

> 不是 Error。

---

# 45. AVFoundation 不代表所有 MP4 都能转换

文件扩展名：

```text
.mp4
```

只是 Container。

内部可能是：

- H.264。
- HEVC。
- AV1。
- 其他 Codec。

不要：

```text
extension == mp4
→ AVFoundation 一定支持
```

应检查真实 Capability。

---

# 46. Container 与 Codec 不得混淆

例如：

```text
MP4
MOV
MKV
```

是 Container。

而：

```text
H.264
HEVC
AAC
AV1
```

是 Codec。

UI 可以对普通用户隐藏复杂性，

但底层 Engine 不能把两者混为一谈。

---

# 47. FFmpeg 不要使用来历不明的 Binary

禁止直接集成：

```text
random GitHub ffmpeg-ios-full.zip
```

因为可能：

- GPL。
- nonfree。
- 开启 x264。
- 开启 x265。
- 构建配置不透明。
- Binary 被修改。

FFmpeg 必须：

> 来源明确 + Build Config 可审计。

---

# 48. FFmpeg License 与 Codec Patent 是两件事

不能：

```text
LGPL compliant
=
所有法律问题解决
```

许可证与 Codec Patent 是：

> 不同问题。

如果未来加入新 Encoder：

必须单独评估。

---

# 49. FFmpeg 不应泄漏到 UI

禁止：

```swift
Button("Convert") {
    FFmpeg.execute(...)
}
```

FFmpeg 必须在：

> Conversion Engine Boundary

之后。

这样即使未来移除 FFmpeg，

UI 和 ViewModel 不需要重写。

---

# 50. Native First 不代表强行 Native

如果 Apple Framework 明确不能可靠处理某格式，

不要为了：

> Native First

硬写脆弱 workaround。

Native First 的意思是：

> 能稳定完成时优先 Native。

不是：

> 禁止合理 OSS。

---

# 51. 数据口径必须明确

首页显示：

```text
28 GB
```

必须知道它是什么：

- 已扫描文件总量？
- 用户授权目录总量？
- 当前分类总量？
- 可清理空间？
- iPhone 总容量？

不同概念不能混用。

变量名也不能含糊：

```text
totalStorage
```

应尽可能明确：

```text
analyzedBytes
reclaimableBytes
selectedBytes
```

---

# 52. 已扫描容量不能冒充系统容量

如果 App 只扫描用户授权目录：

禁止 UI：

```text
iPhone Storage
28 GB used
```

应该：

```text
Analyzed Files
28 GB
```

这是数据真实性问题，不只是文案问题。

---

# 53. Reclaimable 不得等于“建议删除”

例如：

```text
Duplicate 2 GB
```

也不能直接说：

```text
You can safely delete 2 GB
```

因为 Duplicate Group 至少需要保留一份。

真正可回收：

```text
groupTotal - keepOne
```

而且最终仍由用户决定。

---

# 54. Mock 数据不得进入真实 Pipeline

Preview 数据必须：

> 独立。

禁止：

```text
Production Service
↓
if no data
↓
random mock
```

否则很容易在 Release 显示假文件统计。

Preview 可以使用：

> 静态、确定性的 Mock。

---

# 55. Preview 不要使用随机数

此前项目已经证明 Random Mock 会导致：

- Screenshot 不稳定。
- UI 每次不同。
- 测试难断言。
- Bug 难复现。

Preview 使用：

> Fixed Seed 或固定常量。

---

# 56. 状态字段不能互相打架

避免：

```swift
isLoading
hasData
hasError
isEmpty
```

同时存在且可以组合成非法状态。

例如：

```text
isLoading = true
hasError = true
hasData = true
```

复杂页面优先：

```swift
enum State
```

确保状态互斥。

---

# 57. Selection 与数据源必须同步

批量选择文件后：

如果扫描刷新、文件删除或排序：

> Selection Set 可能包含已经不存在的 ID。

必须在数据变化时：

> 校验 Selection。

否则可能出现：

```text
UI 显> 校验 Selection。

否则可能出现：

```text
UI 显示 selected = 5
实际只有 3 个文件
```

---

# 58. 全局 Current Directory 不能悬空

如果当前授权目录：

- 权限失效。
- Bookmark stale。
- 用户删除目录。

Global State 不应继续认为：

> 当前目录有效。

所有 Current ID / URL / Selection 都应该与实际数据源定期对齐。

---

# 59. 不要依赖 View 生命周期触发重要业务同步

`.task` 适合页面加载，

但不能把核心一致

`.task` 适合页面加载，

但不能把核心一致性依赖于：

> View 必须重新创建。

ViewModel 可能一直存在。

重要状态变化应该通过：

- 明确 State。
- Observable。
- AsyncSequence。
- Event。

驱动。

---

# 60. 数据库 Schema 是长期契约

如果未来使用 GRDB：

Migration Identifier 不要随便改名。

已经发布：

```text
v1_create_files
```

之后即使内部文件重构，

也不能随便改成：

```text
createFiles
```

否则旧数据库可能再次执行迁移。

---

# 61. 唯一索引不能只靠假设

如果 Upsert 的正确性依赖：

> UNIQUE INDEX。

必须确认 Schema 真正存在。

不能：

```text
代码看起来是 upsert
↓
所以一定幂等
```

数据库实际状态才是真相。

---

# 62. 批量数据库写入不要逐条 SELECT

错误：

```text
for each file
    SELECT exists
    INSERT / UPDATE
```

面对 50,000 文件会非常慢。

优先：

- Batch。
- Transaction。
- Proper Upsert。
- Delete + Insert。
- Prepared Statement。

具体根据 Schema 选择。

---

# 63. 数据库写入必须批处理

不要：

```text
发现一个文件
↓
commit

发现一个文件
↓
commit
```

应：

```text
积累合理 Batch
↓
Single Transaction
```

减少 fsync 和事务开销。

---

# 64. 缓存必须按数据作用域隔离

例如未来允许扫描多个目录：

不能一个：

```text
filesCache
```

混合所有目录。

必须明确：

```text
Directory A
Directory B
```

的作用域。

切换 Source 后旧缓存必须正确失效或隔离。

---

# 65. 增量扫描必须防止 stale cache

使用：

```text
URL + size + modifiedDate
```

判断未变化时，要意识到：

> 这是一种优化策略，不是数学证明。

极端情况下文件内容可能变化但 metadata 看起来相同。

对于：

- Hash。
- Duplicate。

如果 correctness 要求更高，

必须设计更严格的 cache invalidation。

---

# 66. 文件路径不是稳定主键

文件可以：

```text
rename
move
```

所以：

```text
absolute path
```

不一定适合作为长期唯一 Identity。

Identity 策略必须根据实际访问模型设计。

不要未经思考直接：

```swift
id = url.path
```

作为永久 ID。

---

# 67. 本地化禁止硬编码 Production 文案

新增 SwiftUI：

禁止：

```swift
Text("Delete Files")
```

最终直接进入生产。

所有用户可见文案应进入本地化系统。

---

# 68. String(format:) 占位符必须统一

此前项目出现过：

> `%d` / `%@` 多语言不一致直接崩溃。

因此推荐：

```text
先格式化数据
↓
得到 String
↓
统一使用 %@
```

不要让不同语言翻译自行改变参数类型。

---

# 69. xcstrings 不要用脆弱文本拼接修改

如果程序化编辑 String Catalog：

> 使用 JSON 结构化读写。

不要：

```text
grep
sed
字符串拼接
```

大规模插入。

String Catalog 损坏往往直到 Build 才暴露。

---

# 70. 不要随便 git checkout 本地化文件

如果：

```text
Localizable.xcstrings
```

有大量未提交改动，

执行：

```bash
git checkout -- file
```

可能一次性丢掉所有新 Key。

恢复单个问题前：

> 先检查 diff。

---

# 71. 多 struct Swift 文件修改要检查括号

AI 自动编辑大型 Swift 文件时很容易：

```text
多一个 }
少一个 }
插错 struct
```

尤其：

```text
View
Preview
Helper View
Modifier
```

都在一个文件。

修改后至少：

- 阅读目标附近结构。
- 检查 Scope。
- Build。

---

# 72. 批量字符串替换后必须看 Diff

即使 Build 成功，也可能出现：

```swift
service: Service(),        repository: Repository()
```

这种格式损坏。

所有自动替换必须：

> Diff Review。

不要认为：

> 能编译 = 修改质量正确。

---

# 73. 不要在项目源码路径放备份 Swift 文件

禁止：

```text
Dashboard_backup.swift
OldCleanerView.swift
CleanerCopy.swift
```

Git 就是备份。

源码副本可能被 Xcode 自动编译，导致：

```text
Invalid redeclaration
Multiple commands produce
```

---

# 74. 删除任务必须先明确范围

删除代码是 AI Agent 特别容易误伤的任务。

例如用户说：

> 删除 Converter 的某个入口。

不能自动理解为：

> 删除整个 Conversion Engine。

执行删除前必须明确：

- Symbol。
- Feature Scope。
- Dependencies。
- Call Sites。

并确保：

> 不波及相邻能力。

---

# 75. 恢复误删代码优先 Git

如果已有历史版本：

优先：

```bash
git show <commit>:<path>
```

恢复。

不要凭记忆手工重写。

原因：

> 原版本已经被真实验证过。

恢复后再单独做新修改。

---

# 76. let 模型不要擅自改成 var

遇到：

```text
cannot assign to property
```

不要第一反应：

```text
let → var
```

模型不可变可能是有意设计。

优先：

> 创建新的 Value。

只有业务确实需要 Mutable Model 才修改定义。

---

# 77. 变量 Scope 要明确

AI 插入代码时非常容易：

```swift
if let files {
    ...
}

process(files)
```

然后出现：

```text
cannot find files in scope
```

修改复杂 Swift 代码后检查：

- if。
- guard。
- Task。
- closure。
- switch。

中的变量作用域。

---

# 78. 编译通过不代表测试通过

本项目规则：

> 本地只 Build，不 Test。

所以：

```text
Build Passed
```

只能说明：

> 代码可以编译 / 链接。

不能说明：

- Duplicate 算法正确。
- 删除逻辑正确。
- Unit Test 通过。
- UI Test 通过。

正式测试：

> GitHub Actions。

---

# 79. 未经允许禁止本地 Test

Codex 不得为了：

> 快速确认一下

自行运行：

```text
xcodebuild test
xcodebuild test-without-building
swift test
```

除非用户主动明确授权。

这条规则即使调试困难也不例外。

---

# 80. Unit Test 与 UI Test 框架不要混用

Unit Test：

> Swift Testing。

```swift
import Testing
@Test
#expect
```

UI Test：

> XCTest / XCUITest。

```swift
import XCTest
XCUIApplication
```

不要给新 Unit Test 使用旧 XCTestCase 模板。

---

# 81. 不要写脆弱 Count Test

例如：

```swift
#expect(FileCategory.allCases.count == 6)
```

如果枚举很可能扩展，

这种 Test 会变成维护负担。

更合理：

```swift
#expect(FileCategory.allCases.contains(.video))
```

验证：

> 业务契约。

而不是：

> 当前实现数量。

---

# 82. 测试必须跟业务语义同步

如果算法从：

```text
Total
```

改成：

```text
Average
```

测试不能只修改成：

> 当前输出数字。

必须确认：

> 新断言代表的业务含义是正确的。

避免 Test 变成：

> 为了绿灯匹配实现。

---

# 83. CI Simulator 不要依赖 latest

此前项目已经发生：

> Simulator Version 与 Deployment Target 不匹配。

CI 应尽量固定：

- Xcode Version。
- Simulator Device。
- Simulator OS。

不要长期依赖：

```text
OS=latest
```

因为 CI Image 更新可能突然导致 Build/Test 失败。

---

# 84. Xcode DerivedData 缓存可能欺骗你

典型现象：

> 代码改了，运行还是旧版本。

先检查：

- Build Target。
- Scheme。
- DerivedData。
- Simulator 安装 App。
- Xcode Cache。

不要马上怀疑：

> SwiftUI 没更新。

---

# 85. Xcode 自定义缓存路径

如果出现：

```text
permission
/Volumes/...
CompilationCache
DerivedData
```

优先检查：

```text
IDECustomCompilationCacheLocation
IDECustomDerivedDataLocation
```

是否指向：

> 已经断开的外接盘。

这是环境问题，不是项目代码问题。

---

# 86. Preview 与 Release Build 配置

如果 Preview 报：

```text
needs an unoptimized build
```

首先检查：

```text
Scheme → Run → Debug
```

不要通过修改 Production Code 解决 Xcode Configuration 问题。

---

# 87. Preview 不等于真实设备

Preview 正常不能证明：

- Security Scoped URL 正常。
- File Provider 正常。
- 大文件性能正常。
- iCloud 正常。
- 删除正常。
- AVFoundation 正常。

Preview 只适合验证：

> UI State。

---

# 88. Simulator 不等于真实 iPhone Storage

文件系统、磁盘性能、File Provider、内存压力在 Simulator 上和真实 iPhone 不完全相同。

尤其：

- NAND I/O。
- Thermal。
- Memory Pressure。
- Video Hardware Codec。

最终性能判断不能只依赖 Simulator。

---

# 89. 不要优化 Benchmark 之前不存在的问题

例如：

```text
应该用 4 workers 还是 8 workers？
```

在没有真实 Benchmark 前，

不要把数字硬编码成架构原则。

先：

```text
Profile
↓
找到瓶颈
↓
Benchmark
↓
再调 Concurrency
```

---

# 90. Instruments 优先于猜性能

真正出现性能问题时：

优先使用：

- Time Profiler。
- Allocations。
- Memory Graph。
- File Activity。
- Energy Log。
- SwiftUI Instruments。

不要只凭：

> “感觉是 SwiftUI 慢。”

---

# 91. UI Progress 不要更新过于频繁

扫描 50,000 文件时：

不要：

```text
1 file
→ UI refresh
1 file
→ UI refresh
```

应：

> Batch / Throttle / Coalesce。

例如底层持续处理，

UI 每合理时间窗口更新一次。

---

# 92. Progress 不要造假

如果扫描总量未知：

> Indeterminate。

不要写：

```text
23%
48%
71%
```

只是根据 Timer 增长。

Fake Progress 会破坏用户信任。

---

# 93. Progress 与真正工作状态要一致

不要：

```text
Progress reaches 100%
↓
后台仍在 Hash 30 秒
```

如果存在多个阶段，

UI 应表达：

```text
Scanning
Analyzing duplicates
Finalizing
```

或者统一成为真正的总体 Progress。

---

# 94. MainActor ViewModel 依赖不要无限膨胀

此前项目曾出现：

```text
ViewModel 11 dependencies
```

这通常意味着职责可能过大。

如果 ViewModel 依赖不断增加，

先检查：

> 是否应该拆业务能力。

不要第一反应造一个：

> 巨型 ServiceContainer

把问题藏起来。

---

# 95. Manager / Helper 类不要无限膨胀

特别防止：

```text
FileManagerManager
FileHelper
FileUtils
CleanerManager
```

最终变成：

> 所有文件逻辑都在一个类。

职责必须明确：

```text
Scanning
Deletion
Hashing
Conversion
Thumbnail
Index
```

各自独立。

---

# 96. Service 也不要过度拆分

相反，也不要为了“Clean Architecture”制造：

```text
DeleteFileUseCase
DeleteFileInteractor
DeleteFileExecutor
DeleteFileCoordinator
DeleteFileService
DeleteFileRepository
```

一个简单行为穿六层。

本项目原则：

> 足够清晰即可。

不要技术炫技。

---

# 97. 新 Dependency 必须先问“为什么”

加入任何 Package 前先回答：

1. Apple Native 做不到吗？
2. 自己实现真的更差吗？
3. Package 是否维护？
4. License？
5. Binary Size？
6. App Store 风险？
7. 是否有 transitive dependency？

不能：

```text
GitHub Stars 很多
→ 加入
```

---

# 98. README 示例代码不能当 Production Contract

第三方库 README 可能：

- 过期。
- 对旧版本。
- 省略 Error Handling。
- 没考虑 iOS Sandbox。

必须：

> 查看真实当前版本 API。

---

# 99. 新 Apple API 要确认 Availability

任何现代 SwiftUI API，

包括未来新：

- Scroll Edge。
- Glass。
- Navigation。
- Tab API。

必须确认：

```text
当前 Deployment Target
```

支持。

如果不支持：

> 不得擅自提高 Deployment Target。

---

# 100. 当前项目 Top 20 高频注意事项

开发时优先记住：

1. **不能扫描整个 iPhone。**
2. **Security-Scoped URL 不代表永久权限。**
3. **File Provider 可能是远程文件。**
4. **扫描只读 Metadata，不读完整内容。**
5. **禁止任意大文件 `Data(contentsOf:)`。**
6. **Duplicate 不要全量 Full Hash。**
7. **Thumbnail 必须 Lazy + Downsample。**
8. **View body 不做 I/O 和状态写入。**
9. **`.id()` 不作为强制刷新工具。**
10. **并发必须有界。**
11. **async 不等于自动后台运行。**
12. **删除必须用户主动确认。**
13. **删除后优先增量更新，不 Full Rescan。**
14. **转换默认保留原文件。**
15. **大型转换必须考虑临时空间。**
16. **FFmpeg Binary 必须可审计 License。**
17. **新 Apple API 不确定就查官方文档。**
18. **本地只 Build，不 Test。**
19. **Unit Test = Swift Testing，UI Test = XCTest/XCUITest。**
20. **所有自动修改完成后必须看 Diff + Build。**

---

# 101. Bug 排查速查

## 文件看得到但打不开

优先检查：

```text
Security Scoped Access
↓
File Provider
↓
iCloud Download State
↓
文件是否已移动
↓
权限是否 stale
```

---

## 扫描特别慢

优先检查：

```text
是否读取完整文件
↓
是否生成 Thumbnail
↓
是否计算全量 Hash
↓
是否每文件写一次数据库事务
↓
是否 UI 高频刷新
↓
最后才检查并发度
```

---

## Scroll 掉帧

优先检查：

```text
Thumbnail Decode
↓
Material / Blur
↓
body 昂贵计算
↓
状态频繁发布
↓
Stable ID
↓
Lazy Container
```

---

## 内存暴涨

优先检查：

```text
Data(contentsOf:)
↓
原图 Decode
↓
Thumbnail Cache
↓
数组保存巨大 Data
↓
Task 数量
↓
未释放临时资源
```

---

## 删除后容量不对

优先检查：

```text
哪些文件真正删除成功
↓
Partial Failure
↓
Index 是否只删除成功项
↓
Category Bytes 是否减正确
↓
Total Bytes 是否同步
```

---

## Duplicate 错误

优先检查：

```text
是否只看 filename
↓
是否只看 size
↓
Partial Hash collision / implementation
↓
Full Hash 是否真正执行
↓
Cache 是否 stale
```

---

## Converter 输出失败

优先检查：

```text
Container
↓
Codec
↓
AVFoundation Capability
↓
目标格式
↓
剩余磁盘空间
↓
Security Permission
↓
Temporary URL
↓
Cancellation
```

---

## UI 主题部分更新

优先检查：

```text
Single Source of Truth
↓
Environment
↓
colorScheme
↓
Sheet / Presentation Root
↓
Dynamic Color
```

---

## SwiftUI 新 API Build Error

优先：

```text
查询 Apple Documentation
↓
确认 API 名称
↓
确认 Availability
↓
确认 SDK Version
↓
再修改
```

不要靠猜。

---

# 102. 最终工程纪律

每次遇到问题时，优先选择：

> 找根因。

而不是：

> 找一个能让错误暂时消失的修改。

尤其禁止：

```text
测试失败
→ 删除测试

Build 失败
→ 删除功能

性能差
→ 无限并发

UI 不刷新
→ .id(UUID())

权限失败
→ 绕过 Sandbox

转换失败
→ 强行 FFmpeg

数据不对
→ 写死数字

Framework Bug
→ 大规模重构业务代码
```

本项目长期遵循：

> **平台限制不是 Bug。**

> **用户文件不是测试数据。**

> **编译通过不等于逻辑正确。**

> **并发不是性能本身。**

> **缓存不是事实来源。**

> **UI 不能夸大底层能力。**

> **删除与覆盖永远按高风险操作处理。**

> **如果 API 不确定，查 Apple 官方文档，不猜。**

> **如果修改范围不确定，宁可少改，不要扩大影响。**