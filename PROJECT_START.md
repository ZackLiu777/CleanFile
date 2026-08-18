# PROJECT_START.md

## 1. 项目启动说明

本文档用于定义项目的初始产品目标、技术方向、第一阶段开发范围与 Codex 的启动顺序。

本项目当前处于：

> **Initial Development / MVP Foundation**

阶段。

现阶段的目标不是一次性完成全部功能，而是先建立一个：

- 正确。
- 稳定。
- 可扩展。
- 可测试。
- 符合 iOS 平台限制。
- 不破坏用户文件安全。

的基础版本。

开发过程中必须同时遵守项目根目录中的：

> `AGENTS.md`

如果本文档与 `AGENTS.md` 存在冲突：

> **以 `AGENTS.md` 为最高优先级。**

---

# 2. 产品定义

本项目是一款面向 iPhone 的：

> **文件管理、存储分析、文件清理与常用格式转换工具。**

产品当前有两个核心方向：

## A. 文件分析与清理

用于：

- 用户授权文件区域的扫描。
- 文件分类。
- 文件大小统计。
- 大文件发现。
- 重复文件分析。
- 文件筛选。
- 用户主动删除文件。
- 存储占用可视化。

---

## B. 文件格式转换

用于：

- 图片格式转换。
- PDF 处理。
- 常见音视频格式转换。
- 文件压缩与解压。
- 后续扩展更多文件转换能力。

转换能力遵循：

> **Apple Native First**

原则。

只有 Apple 原生能力无法满足需求时，才考虑 FFmpeg 或其他经过许可证审核的开源组件。

---

# 3. 当前产品边界

必须首先理解：

> 本项目不是 Android 类型的“全盘清理器”。

iOS Sandbox 决定 App 不能随意扫描：

- 其他 App 的私有文件。
- 系统内部缓存。
- 其他 App 的 Documents。
- 系统不可公开访问的数据。

本项目只能处理：

- App 自己拥有权限的文件。
- 用户明确通过系统文件选择器授权访问的文件或目录。
- Apple API 明确允许访问的数据。

不得通过：

- Private API。
- 未公开系统机制。
- Sandbox 绕过。
- 权限漏洞。

实现所谓：

> Scan Entire iPhone

任何 UI、业务逻辑和产品文案都必须建立在真实的平台能力之上。

---

# 4. 核心技术方向

项目使用：

> **Swift + SwiftUI**

作为主要开发技术。

整体架构采用：

> **MVVM + Repository + Service / Engine**

原则。

主要技术方向包括：

- SwiftUI
- Swift Concurrency
- Observation
- FileManager
- UniformTypeIdentifiers
- CryptoKit
- AVFoundation
- ImageIO
- CoreGraphics
- PDFKit
- Compression

如果未来确实需要：

- MKV
- WebM
- FLAC
- OGG
- 其他 Apple 原生框架无法可靠处理的格式

再考虑集成：

> FFmpeg

FFmpeg 不属于第一阶段必须依赖。

---

# 5. 架构职责边界

项目必须保持明确的职责分离。

## View

只负责：

- UI 展示。
- 用户交互。
- 状态呈现。
- 导航入口。

不得承担复杂文件处理逻辑。

---

## ViewModel

负责：

- 页面状态。
- 用户操作协调。
- Progress。
- Loading。
- Error。
- Empty State。
- 数据向 UI 模型转换。

ViewModel 不直接承担：

- 大规模 FileManager 枚举。
- Hash。
- FFmpeg 处理。
- 编解码。
- 大量数据库操作。

---

## Repository

负责：

> 向上层提供统一的数据访问接口。

Repository 应隔离：

- 数据来源。
- 文件索引。
- 底层 Service。
- 后续持久化实现。

---

## Service / Engine

负责真正执行：

- 文件扫描。
- 文件元数据读取。
- 文件删除。
- Hash。
- Duplicate 分析。
- 图片转换。
- 音视频转换。
- PDF 处理。
- 压缩处理。

---

# 6. 第一阶段开发目标

第一阶段不追求功能数量。

目标是完成：

> **文件扫描 → 分类 → 展示 → 文件操作**

这一条最基础的完整链路。

第一阶段必须优先保证：

1. 文件访问正确。
2. 文件扫描不会阻塞 UI。
3. 分类结果正确。
4. 用户可以看到扫描进度。
5. 用户可以查看分类后的文件。
6. 用户可以主动选择文件。
7. 删除行为安全。
8. 删除后状态可以正确更新。
9. 大量文件不会导致明显内存问题。
10. 架构允许后续增加 Duplicate 与 Converter。

---

# 7. 第一阶段暂不追求的内容

初始阶段不要立即实现：

- 全部文件转换格式。
- FFmpeg 全功能支持。
- AI 文件分析。
- 云端文件转换。
- 后端服务器。
- 用户账户系统。
- 大规模 Analytics。
- 文件云同步系统。
- 自动清理。
- 后台自动删除。
- 复杂智能推荐。
- 大规模文件预览系统。
- 完整 Office 转换。
- DOCX → PDF 高保真转换。
- PPTX → PDF 高保真转换。
- XLSX → PDF 高保真转换。

这些功能只有在核心文件系统稳定后才能评估。

---

# 8. 第一条核心数据链

Codex 首先应围绕下面的数据流进行开发：

```text
用户选择文件区域

        ↓

获得系统授权

        ↓

扫描文件

        ↓

读取 Metadata

        ↓

文件分类

        ↓

统计大小

        ↓

生成 Storage Summary

        ↓

ViewModel

        ↓

SwiftUI
```

第一阶段不要在这个流程中加入：

- Full Hash。
- AI。
- FFmpeg。
- 文件内容解析。
- 大规模缩略图生成。

---

# 9. 文件扫描原则

扫描必须采用：

> **Metadata First**

基础扫描只获取业务真正需要的信息。

例如：

- 文件名称。
- URL。
- 文件类型。
- 文件大小。
- 创建时间。
- 修改时间。
- 是否目录。
- 必要的系统 metadata。

不得为了判断：

> 这是一个视频文件。

就读取整个视频内容。

---

# 10. 文件分类

初始分类可以围绕高层文件类型展开。

例如：

- Video
- Image
- Audio
- Document
- PDF
- Archive
- Other

文件类型判断优先使用：

> UniformTypeIdentifiers / UTType

而不是只根据字符串扩展名进行硬编码。

扩展名可以作为辅助信息，但不应该成为唯一依据。

---

# 11. Storage Summary

扫描结果需要生成面向 UI 的 Storage Summary。

核心信息至少应能够表达：

- 已分析总文件数量。
- 已分析总容量。
- 各文件类别容量。
- 各文件类别文件数量。
- 各类别占比。
- 当前扫描状态。

注意：

> 已分析文件容量不能伪装成整个 iPhone 的真实存储占用。

如果用户只授权一个目录，UI 表达的必须是：

> Analyzed Files

或者具有同等真实语义的内容。

不得误导用户这是完整的：

> iPhone Storage

---

# 12. 首页 Storage UI

首页核心存储可视化方向采用：

> **Donut Chart + Category List**

Donut Chart 主要负责表达：

> 各类别在已分析文件中的占比。

列表负责提供准确数据。

建议展示：

```text
Storage

       Donut

Videos        XX GB
Images        XX GB
Documents     XX GB
Archives      XX GB
Other         XX GB
```

环形图不应承担全部精确数据表达。

如果文件类别过多：

> 合并低占比类别为 Other。

不要生成大量难以辨认的小扇区。

---

# 13. 文件详情

用户点击某一分类后，应能够查看：

- 文件名称。
- 文件大小。
- 文件类型。
- 必要日期信息。

第一阶段应优先支持：

- 按大小排序。
- 文件选择。
- 多选。
- 删除入口。

不要在初始阶段构建过于复杂的文件管理器功能。

---

# 14. 删除原则

删除是整个项目最高风险的操作之一。

必须遵循：

> **用户主动选择 → 明确确认 → 执行删除 → 更新状态**

不得：

```text
扫描
↓
判断“不重要”
↓
自动删除
```

任何扫描、分析算法只能生成：

> Candidate

而不能自动决定删除。

---

# 15. 删除后的数据更新

删除完成后：

> 不应默认重新进行完整文件扫描。

优先采用增量更新：

```text
文件删除成功

        ↓

移除对应记录

        ↓

更新分类容量

        ↓

更新总容量

        ↓

更新文件数量

        ↓

刷新 UI
```

只有无法保证当前 Index 正确时，才考虑重新扫描。

---

# 16. 性能方向

项目性能优化的第一原则：

> **减少不必要 I/O，而不是增加更多线程。**

优化优先级：

1. Metadata First。
2. 避免重复扫描。
3. Lazy Processing。
4. Incremental Update。
5. Batch Processing。
6. Streaming。
7. Bounded Concurrency。
8. 最后才考虑增加并发度。

---

# 17. Swift Concurrency

iOS 与 Swift Runtime 负责底层线程和 CPU 调度。

项目负责：

> 定义合理的并发结构。

不要：

- 手工绑定 CPU Core。
- 自行实现复杂 Thread Pool。
- 为每个文件创建独立无边界 Task。
- 认为 Task 越多性能越好。

文件扫描、大型 Hash、转换等工作必须避免长期占用 MainActor。

---

# 18. 大文件原则

任何文件都可能非常大。

代码不得假设：

> 文件只有几十 MB。

处理文件时必须考虑：

- 500 MB。
- 2 GB。
- 10 GB。
- 更大的用户文件。

因此不得默认使用：

```swift
Data(contentsOf: url)
```

读取任意文件全部内容。

大文件处理优先：

- Streaming。
- Chunking。
- Incremental Processing。

---

# 19. Duplicate Detection

Duplicate Detection 属于后续核心能力，但不属于最基础扫描链必须完成的内容。

实现时遵循：

```text
File Size
    ↓
Candidate Group
    ↓
Partial Hash
    ↓
Full Hash
    ↓
Confirmed Duplicate
```

禁止：

> 第一次扫描时对所有文件计算完整 SHA256。

Hash 应为：

> Lazy / On Demand。

---

# 20. Converter 方向

Converter 与 Cleaner 是两个相对独立的业务能力。

但最终可以通过文件详情自然连接：

```text
File

├── Delete
├── Compress
└── Convert
```

转换能力必须通过统一 Conversion Engine 暴露。

UI 不允许直接调用：

- AVFoundation。
- FFmpeg。
- ImageIO。

---

# 21. Native First

文件转换技术选择优先级：

```text
Apple Native Framework

        ↓

经过审核的宽松许可证 OSS

        ↓

LGPL OSS

        ↓

其他方案
```

对于媒体处理：

```text
AVFoundation
        ↓
FFmpeg Fallback
```

不是：

```text
Everything
        ↓
FFmpeg
```

---

# 22. 第一阶段 Converter 范围

初始 Converter 可以优先考虑 Apple 原生能力覆盖较好的格式。

图片方向：

- HEIC
- JPEG
- PNG

PDF：

- Image → PDF
- PDF → Image
- Merge
- Split

媒体：

- MOV
- MP4
- M4A
- WAV

压缩：

- ZIP

具体格式支持必须根据实际 API 能力实现。

不得为了完成产品列表：

> 声称支持实际无法稳定转换的格式。

---

# 23. FFmpeg

FFmpeg 为后续可选能力。

在真正需要之前：

> 不要提前集成。

如果未来集成：

- 必须独立封装。
- 不允许泄漏 FFmpeg API 到 ViewModel。
- 必须审核 License。
- 默认 LGPL-only。
- 禁止未经批准启用 GPL。
- 禁止 `--enable-nonfree`。
- 禁止来源不明确的预编译 Binary。

---

# 24. Local First

产品默认：

> **Local First / On-device Processing**

能够本地完成的功能应优先在设备本地完成。

未经明确产品决策：

- 不上传用户文件。
- 不建立云端文件副本。
- 不发送文件到第三方转换服务器。
- 不将文件内容用于 Analytics。
- 不发送完整文件路径。

---

# 25. 权限原则

权限遵循：

> 最小权限原则。

只有真正需要某种系统权限时才能申请。

不得：

> 为未来可能使用的功能提前申请权限。

权限请求必须能够解释：

> 为什么当前功能需要它。

---

# 26. 错误是正常状态

文件系统并不可靠。

Codex 必须假设以下情况随时可能发生：

- 文件被删除。
- 文件被移动。
- Bookmark 失效。
- 用户撤销访问权限。
- iCloud 文件尚未下载。
- File Provider 不可用。
- 文件读取失败。
- 磁盘空间不足。
- 文件写入失败。
- 转换过程中用户取消。
- 文件在扫描过程中发生变化。

这些情况不能简单通过：

```swift
try!
```

处理。

---

# 27. 测试策略

严格遵守 `AGENTS.md`。

默认：

> 本地禁止运行 Test。

本地允许：

> Build / Compile。

正式测试执行位置：

> GitHub Actions。

触发：

```text
Pull Request
```

以及：

```text
Push → main
```

---

# 28. 测试框架

Unit Test：

> **Swift Testing**

使用：

```swift
import Testing
```

```swift
@Test
```

UI Test：

> **XCTest / XCUITest**

使用：

```swift
import XCTest
```

以及：

```swift
XCUIApplication
```

不得混淆两者职责。

---

# 29. 第一阶段需要重点测试的逻辑

在对应功能出现后，优先考虑：

- File Type Classification。
- File Size Statistics。
- Storage Percentage Calculation。
- Scan State。
- Error State。
- Cancellation。
- Delete Result。
- Incremental State Update。
- Duplicate Candidate Grouping。
- Conversion Routing。

测试应该关注：

> 业务逻辑正确性。

而不是为了覆盖率制造大量低价值测试。

---

# 30. Build 规则

Codex 完成修改后，可以在本地进行：

> Build。

用于检查：

- Swift 编译错误。
- Actor Isolation。
- 类型问题。
- API Availability。
- Linker。
- Package 编译。

如果 Build 失败：

> 应首先修复与当前修改有关的问题。

不得通过删除功能逃避编译失败。

---

# 31. 第一阶段开发顺序

Codex 默认按照以下顺序推进。

## Phase 0 — Foundation

确认：

- 项目可以 Build。
- 基本架构边界清晰。
- Swift Concurrency 使用原则正确。
- 基础 Domain Model 可支撑文件业务。

不要在此阶段增加大量功能。

---

## Phase 1 — File Access

实现：

- 用户选择文件区域。
- Security-Scoped Resource 访问。
- 文件访问生命周期。
- 基础权限错误处理。

目标：

> 能安全访问用户明确授权的文件。

---

## Phase 2 — Scanner

实现：

- 文件枚举。
- Metadata 获取。
- 文件类型判断。
- 文件大小统计。
- Cancellation。
- Progress。

目标：

> 能稳定扫描大量文件而不明显阻塞 UI。

---

## Phase 3 — Classification

实现：

- 文件类别。
- 分类统计。
- 分类容量。
- 文件数量。
- Storage Summary。

目标：

> Scanner 输出能够直接转化为可靠的分类数据。

---

## Phase 4 — Dashboard

实现：

- Storage Summary 展示。
- Donut Chart。
- Category List。
- Scan Progress。
- Empty State。
- Error State。

目标：

> 用户能够直观理解已经授权文件的存储结构。

---

## Phase 5 — File List

实现：

- 分类详情。
- 文件列表。
- 文件大小。
- 日期。
- 排序。
- 文件选择。

目标：

> 用户可以从 Storage Overview 进入具体文件。

---

## Phase 6 — Delete

实现：

- 单文件删除。
- 多文件删除。
- 删除确认。
- 部分失败处理。
- Cancellation。
- 删除后的 Incremental Update。

目标：

> 建立第一条完整 Cleaner 闭环。

---

## Phase 7 — Large Files

在已有 Index 基础上实现：

- 大文件查询。
- 排序。
- 筛选。
- 清理入口。

不得为了查询 Large Files：

> 每次重新遍历文件系统。

---

## Phase 8 — Duplicate Detection

实现：

- Size Grouping。
- Partial Hash。
- Full Hash。
- Duplicate Group。
- 用户确认删除。

必须避免无意义全文件 Hash。

---

## Phase 9 — Native Converter

在 Cleaner 核心稳定后，再开始：

- Image Conversion。
- PDF Operations。
- Native Media Conversion。
- Archive Operations。

---

## Phase 10 — Advanced Converter

只有产品需求证明存在价值时，再评估：

> FFmpeg。

---

# 32. Codex 每次开始任务前

Codex 应先确定：

1. 当前任务属于哪个 Phase。
2. 当前能力是否已经存在。
3. 是否存在可以复用的抽象。
4. 修改是否会跨越多个职责边界。
5. 是否涉及用户文件安全。
6. 是否涉及权限。
7. 是否涉及高成本 I/O。
8. 是否涉及新的 Dependency。
9. 是否涉及 License。
10. 是否超出了当前任务范围。

---

# 33. Codex 每次任务结束时

必须明确报告：

## 完成内容

只描述实际完成内容。

## 关键决策

解释必要的技术决策。

## Build

例如：

```text
Build: Passed
```

或者：

```text
Build: Failed
```

或者：

```text
Build: 未运行
```

## Tests

正常情况下：

```text
Tests: 未在本地执行（遵循项目规则）
```

如果等待 GitHub Actions：

```text
GitHub Actions: 待验证
```

不得伪造 CI 或测试结果。

---

# 34. 不允许一次性完成整个项目

Codex 不应收到：

> 开始开发

后就尝试一次完成：

- Cleaner。
- Duplicate。
- Converter。
- FFmpeg。
- 全部 UI。
- 全部测试。

正确方式是：

```text
Foundation
    ↓
File Access
    ↓
Scanner
    ↓
Classification
    ↓
Dashboard
    ↓
File Operations
    ↓
Cleaner
    ↓
Converter
```

每个阶段建立稳定基础后再继续。

---

# 35. 初始开发任务

如果当前代码库还没有建立上述能力，那么 Codex 的第一个开发目标是：

> **建立最小的文件扫描基础能力。**

第一轮只关注：

1. 确认现有项目可以 Build。
2. 理解现有 SwiftUI / MVVM 实现。
3. 建立最小必要的数据模型。
4. 建立文件访问抽象。
5. 建立 Metadata Scanner。
6. 建立基础文件分类。
7. 提供扫描结果与进度状态。
8. 完成 Build 验证。
9. 编写必要 Unit Test，但不在本地执行。
10. 将实际测试留给 GitHub Actions。

第一轮明确不做：

- Duplicate Hash。
- FFmpeg。
- AI。
- 云端。
- 自动删除。
- Office Conversion。
- 大规模 UI 重构。

---

# 36. 第一轮完成标准

第一轮完成后，系统至少应该能够做到：

```text
用户授权目录
        ↓
扫描
        ↓
获取 Metadata
        ↓
分类
        ↓
计算容量
        ↓
返回 Storage Summary
```

并满足：

- UI 不因扫描长期冻结。
- 支持 Cancellation。
- 单个文件失败不会导致整个扫描崩溃。
- 不读取无必要的大文件内容。
- 不计算全量 Hash。
- 不上传用户文件。
- Build 成功。
- 必要测试代码已经建立。
- 本地没有未经授权执行 Tests。

完成这一基础后，再进入下一阶段。

---

# 37. 项目核心原则

整个项目长期遵循：

> **Correctness First**

> **User Data Safety First**

> **Native First**

> **Local First**

> **Metadata First**

> **Incremental First**

> **Bounded Concurrency**

> **Minimal Change**

技术复杂度必须服务于真实需求。

不要为了：

> 看起来高级

而增加：

- 不必要抽象。
- 不必要并发。
- 不必要依赖。
- 不必要网络服务。
- 不必要 AI。

最终目标不是实现一个技术 Demo，而是构建一个：

> **可靠、安全、高性能、符合 iOS 平台规则的真实文件工具。**