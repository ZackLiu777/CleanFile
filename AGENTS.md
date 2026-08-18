# AGENTS.md

## 1. 文档目的

本文件用于定义 Codex 在本项目中的基本行为边界、开发原则与协作规则。

Codex 的职责是：

* 理解现有代码与项目目标。
* 在明确需求范围内完成代码实现、修改、重构、测试代码编写与修复。
* 优先保持现有架构、设计语言与代码风格一致。
* 在修改前理解上下文，而不是基于猜测直接生成代码。
* 尽可能提交最小、清晰、可验证的改动。
* 主动发现与当前任务直接相关的问题。
* 对无法确定的事实保持谨慎，不伪造 API、框架行为、Build 结果或测试结果。

本文件只规定项目级开发原则，不定义具体目录结构。

除非任务明确要求，否则 Codex 不得擅自重新组织项目结构。

---

# 2. 核心开发原则

## 2.1 先理解，再修改

在修改代码之前，应优先理解：

* 当前实现的目的。
* 数据流。
* 状态管理方式。
* 调用关系。
* 已存在的抽象。
* 当前使用的系统 API。
* 与修改相关的测试代码。
* 修改可能产生的副作用。

不得仅根据文件名、函数名或局部代码猜测整个系统行为。

对于现有实现，应优先回答：

> 为什么当前代码这样设计？

而不是直接假设：

> 应该重新写一个更好的版本。

---

## 2.2 最小改动原则

默认采用最小可行修改。

如果一个问题可以通过修改少量代码解决，不应：

* 无理由重构整个模块。
* 大规模重命名。
* 重写已经正常工作的代码。
* 修改与当前任务无关的接口。
* 顺带调整大量格式。
* 顺带改变 UI。
* 顺带升级依赖。
* 顺带改变架构。

一次任务应尽量只解决一个明确的问题。

---

## 2.3 不破坏现有行为

除非需求明确要求改变行为，否则：

* 不删除已有功能。
* 不改变已有业务语义。
* 不修改现有用户流程。
* 不修改公开接口行为。
* 不改变持久化数据语义。
* 不改变错误处理语义。
* 不改变现有默认配置。

如果修改可能造成兼容性变化，必须明确指出。

---

# 3. 架构原则

项目采用 MVVM 思想组织 UI 与业务逻辑。

Codex 应遵守以下职责边界。

## View

主要负责：

* UI 声明。
* 页面布局。
* 用户交互入口。
* 展示状态。

View 不应承载复杂业务逻辑。

## ViewModel

主要负责：

* UI 状态。
* 用户操作对应的业务协调。
* 将底层数据转换为 UI 可消费的状态。
* 错误状态。
* Loading / Progress / Empty State 等展示状态。

ViewModel 不应演变成：

* 文件系统实现层。
* 媒体编解码实现层。
* 数据库实现层。
* 巨型工具类。

## Repository / Service / Engine

复杂能力应通过明确的抽象提供给上层。

例如：

* 文件访问。
* 文件扫描。
* 文件分析。
* 删除。
* Hash。
* 媒体转换。
* 图片处理。
* PDF 处理。
* 数据持久化。

UI 层不应直接依赖具体底层实现细节。

---

# 4. Swift 与并发规则

优先使用现代 Swift 能力，包括但不限于：

* async / await
* Task
* TaskGroup
* actor
* @MainActor
* AsyncSequence
* Observation

不得为了并发而随意创建大量线程或无边界任务。

## 4.1 MainActor

主线程主要负责：

* SwiftUI 状态。
* UI 更新。
* 与界面直接相关的状态同步。

以下工作原则上不应长期运行在 MainActor：

* 大规模文件枚举。
* 文件 Hash。
* 图片分析。
* 编解码。
* 大量数据库操作。
* CPU 密集计算。
* 大量同步 I/O。

`async` 本身不代表代码自动离开 MainActor。

必须明确区分：

> 异步

和：

> 后台执行。

## 4.2 并发策略

默认采用：

> 有界并发，而不是无限并发。

禁止类似：

```swift
for item in items {
    Task {
        await process(item)
    }
}
```

用于处理数千或数万个对象。

应避免：

* Task 爆炸。
* 文件句柄爆炸。
* 内存无上限增长。
* 过度随机 I/O。
* 无意义的线程竞争。

并发度应根据任务类型设计，而不是单纯追求线程数量。

---

# 5. 文件系统规则

文件相关代码必须优先考虑：

* iOS Sandbox。
* Security-Scoped Resource。
* 文件访问权限。
* 文件可能来自第三方 File Provider。
* 文件可能位于 iCloud。
* 文件可能尚未完全下载。
* 文件可能在处理过程中消失。
* 文件可能被其他进程修改。

不得假设：

> URL 存在就一定可以永久访问。

## 5.1 文件扫描

文件扫描优先采用：

> Metadata First。

第一次扫描原则上只读取必要元数据，例如：

* 类型。
* 大小。
* 修改时间。
* 创建时间。
* 是否为目录。

不得为了分类文件而默认读取整个文件内容。

## 5.2 Hash

不得默认对所有文件计算完整 Hash。

重复文件检测应优先采用分层策略，例如：

1. 文件大小。
2. 候选分组。
3. Partial Hash。
4. Full Hash。

只有真正需要确认内容一致时才进行完整读取。

## 5.3 删除

删除属于高风险操作。

任何删除能力都应：

* 明确作用目标。
* 处理失败情况。
* 支持部分成功。
* 正确更新应用状态。
* 不因为单个文件失败而破坏整体状态。

禁止：

* 隐式删除。
* 未经用户操作删除文件。
* 将“扫描”与“删除”绑定成不可分割操作。
* 因分析结果直接自动删除用户文件。

除非产品需求明确规定，否则删除必须由用户主动触发。

---

# 6. 性能原则

优化优先级：

1. 减少不必要 I/O。
2. 避免重复计算。
3. 使用增量处理。
4. 使用缓存或索引。
5. 使用批处理。
6. 最后才考虑提高并发度。

不要将：

> 更多线程

等同于：

> 更高性能。

## 6.1 禁止无意义重复扫描

如果数据已经存在，并且能够判断文件没有发生变化，应尽可能复用已有结果。

高成本分析结果应该允许缓存，例如：

* Hash。
* 文件类型分析。
* 重复文件分析。
* 文件统计结果。

## 6.2 流式处理

对于大量文件，应优先考虑：

```text
发现
→ 分析
→ 记录
→ 更新进度
```

而不是：

```text
全部加载到内存
→ 全部处理
→ 最后统一显示
```

应避免无必要地将大量文件对象长期保存在内存中。

---

# 7. 文件转换原则

文件转换遵循：

> Native First。

如果 Apple 原生框架能够稳定完成任务，应优先使用系统能力。

只有在原生能力不足时，才考虑第三方转换引擎。

## 7.1 FFmpeg

FFmpeg 应视为独立底层能力，而不是业务层 API。

禁止：

* 在 View 中直接调用 FFmpeg。
* 在多个业务模块散落 FFmpeg 命令。
* 将 FFmpeg 具体实现泄漏到 UI 层。
* 随意替换整个原生媒体处理链路。

FFmpeg 应通过统一抽象进行封装。

---

# 8. 开源依赖规则

引入新的第三方依赖前必须考虑：

* 是否真的有必要。
* Apple 原生 API 是否已经可以实现。
* 项目维护状态。
* Binary Size。
* 性能。
* 安全。
* License。
* 商业使用限制。
* App Store 分发影响。

## 8.1 License 优先级

原则上优先：

* MIT
* BSD
* Apache-2.0
* 其他商业友好的宽松许可证

LGPL 依赖需要单独评估。

GPL 依赖不得在没有明确决策的情况下引入。

Non-free 或禁止重新分发的组件不得引入正式版本。

## 8.2 FFmpeg 特殊规则

不得擅自：

* 开启 GPL 组件。
* 开启 `--enable-gpl`。
* 开启 `--enable-nonfree`。
* 加入未经审核的 codec library。
* 使用来源不明确的 FFmpeg 预编译包。

任何 FFmpeg 构建配置变化都应被视为可能影响许可证合规性的改动。

---

# 9. Apple 原生框架

对于 Apple 官方系统 Framework：

* 优先使用公开 API。
* 不调用 Private API。
* 不绕过 Sandbox。
* 不尝试访问其他 App 私有容器。
* 不依赖未公开系统行为。
* 不以 App Store 审核漏洞作为实现方式。

不得通过 undocumented API 实现所谓：

> 全盘扫描 iPhone。

如果 iOS 平台能力本身无法实现，应明确指出平台限制，而不是伪造解决方案。

---

# 10. 错误处理

不要大量使用：

```swift
try!
```

或：

```swift
fatalError()
```

处理正常运行过程中可能出现的问题。

对于以下情况必须视为正常错误场景：

* 文件不存在。
* 文件权限失效。
* 文件无法读取。
* iCloud 文件未下载。
* 文件转换失败。
* 磁盘空间不足。
* 输出文件已存在。
* 用户取消操作。
* Task 被取消。
* Security-Scoped Resource 获取失败。
* 部分文件删除失败。

错误应该尽可能转换为明确、可处理的业务状态。

---

# 11. 取消任务

耗时任务应考虑 Cancellation。

例如：

* 文件扫描。
* Duplicate 分析。
* Hash。
* 文件转换。
* 批量删除。

应在适当位置检查：

```swift
try Task.checkCancellation()
```

用户离开页面、取消任务或开始新的操作后，不应继续执行已经没有意义的大量工作。

---

# 12. 内存规则

处理大型文件时，应优先采用：

* Streaming。
* Chunk。
* Incremental Processing。

禁止默认：

```swift
Data(contentsOf:)
```

读取任意大型文件到内存。

尤其禁止一次性加载：

* 大型视频。
* 大型 ZIP。
* 数 GB 文件。
* 大量图片。
* 整个文件目录内容。

文件大小必须被视为不可信输入。

---

# 13. UI 状态原则

UI 应明确区分：

* Idle
* Scanning
* Processing
* Success
* Empty
* Cancelled
* Partial Failure
* Failure

不要仅使用：

```swift
var isLoading: Bool
```

承载所有复杂状态。

当业务状态复杂时，应优先使用明确状态模型。

---

# 14. UI 修改边界

除非任务明确要求 UI 改动，否则 Codex 不应：

* 修改整体视觉语言。
* 修改主题。
* 修改字体体系。
* 修改已有颜色。
* 修改导航结构。
* 修改动画。
* 重新设计页面。
* 替换现有组件。

修复逻辑问题时，不应顺带重新设计 UI。

---

# 15. 重构规则

重构必须有明确收益，例如：

* 消除真实重复。
* 修复职责混乱。
* 解决并发安全问题。
* 提高可测试性。
* 降低明显复杂度。
* 解决已经存在的维护问题。

禁止为了：

> 看起来更优雅

而进行大规模重构。

如果当前任务不需要重构，应优先保留现有结构。

---

# 16. 不要过度抽象

不得因为未来“可能”需要某功能，就提前构建复杂系统。

避免：

* 无实际使用者的 protocol。
* 只有一个实现却没有明确替换需求的多层 abstraction。
* 巨型 Factory。
* 复杂依赖容器。
* 没有实际需求的泛型系统。
* 没有实际业务价值的设计模式堆叠。

抽象应该由真实需求推动。

---

# 17. 测试与验证规则

## 17.1 本地测试禁止规则

除非用户主动、明确允许，否则 Codex **不得在本地执行任何测试**。

禁止执行包括但不限于：

```bash
swift test
```

```bash
xcodebuild test
```

```bash
xcodebuild test-without-building
```

以及任何会实际运行：

* Unit Test
* UI Test
* Integration Test
* Performance Test
* Snapshot Test

的本地命令。

即使 Codex：

* 新增了测试。
* 修改了测试。
* 修复了测试失败。
* 认为测试非常有必要。
* 希望验证某个行为。

也不得因此自行运行本地测试。

只有用户主动明确授权：

> 可以在本地运行测试。

之后，Codex 才可以执行本地测试。

授权仅针对用户明确允许的任务或范围，不应自动视为永久授权。

---

## 17.2 本地允许的验证方式

在没有额外授权的情况下，本地仅允许通过：

> Build / Compile

验证代码是否能够编译。

例如可以执行：

```bash
xcodebuild build
```

或者项目已有的、不运行测试的 Build 命令。

允许检查：

* Swift 编译错误。
* Linker 错误。
* 类型错误。
* Actor isolation 错误。
* API availability 错误。
* Build Warning。
* Package 编译问题。

但不得通过 Build 命令间接触发测试。

本地验证边界必须保持为：

```text
允许：
Build / Compile

禁止：
Test Execution
```

---

# 18. GitHub Actions 测试规则

项目的自动化测试统一交由：

> GitHub Actions

执行。

Codex 应将 CI 视为正式测试环境。

自动测试原则上只允许在以下 GitHub 事件触发：

```text
Pull Request
```

以及：

```text
Push → main
```

即：

```text
pull_request
push:
  branches:
    - main
```

---

## 18.1 Workflow 规则

测试 Workflow 应通过 GitHub Actions 的 `.yml` / `.yaml` 配置管理。

除非用户明确要求，否则不得改变：

* CI 的整体触发策略。
* main 分支测试策略。
* Pull Request 测试策略。
* Runner 类型。
* Xcode 版本。
* Deployment Target。
* Signing 配置。
* 测试范围。

尤其不得为了：

> 让测试更快

擅自关闭测试或减少测试覆盖。

---

## 18.2 测试执行原则

正式测试应由：

```text
Pull Request
        ↓
GitHub Actions
        ↓
Build
        ↓
Unit Tests
        ↓
UI Tests
```

或者：

```text
Push to main
        ↓
GitHub Actions
        ↓
Build
        ↓
Tests
```

完成。

Codex 本地只负责：

```text
代码修改
+
测试代码编写
+
Build 验证
```

而不负责未经授权的本地测试执行。

---

# 19. Unit Test 技术规则

项目的 Unit Test 统一使用：

> Swift Testing

即：

```swift
import Testing
```

以及：

```swift
@Test
```

等 Swift Testing API。

新增 Unit Test 时，Codex 应优先使用 Swift Testing，而不是 XCTest。

例如：

```swift
import Testing

struct FileClassifierTests {

    @Test
    func videoShouldBeClassifiedCorrectly() {
        // ...
    }
}
```

---

## 19.1 Unit Test 禁止事项

新增 Unit Test 时，不得默认使用：

```swift
import XCTest
```

不得新增：

```swift
final class SomeTests: XCTestCase
```

作为普通 Unit Test 的默认实现。

除非存在明确的平台限制、兼容性要求，或者用户主动要求，否则：

> Unit Test = Swift Testing

---

# 20. UI Test 技术规则

UI Test 必须使用：

> XCTest / XCUITest

UI 自动化属于 XCTest UI Testing 体系。

因此 UI Test 可以且应使用：

```swift
import XCTest
```

并基于：

```swift
XCTestCase
XCUIApplication
XCUIElement
```

实现。

例如：

```swift
import XCTest

final class CleanerUITests: XCTestCase {

    func testOpenCleaner() {
        let app = XCUIApplication()
        app.launch()

        // ...
    }
}
```

---

## 20.1 测试框架边界

测试框架必须保持清晰：

```text
Unit Test
    ↓
Swift Testing
    ↓
@Test


UI Test
    ↓
XCTest / XCUITest
    ↓
XCTestCase + XCUIApplication
```

不得因为 XCTest 可以编写 Unit Test，就继续为新 Unit Test 使用 XCTest。

同样，不得尝试使用 Swift Testing 替代 XCUITest 完成 UI 自动化。

---

# 21. 编写测试与运行测试是两个不同权限

Codex 必须区分：

```text
编写测试
```

和：

```text
运行测试
```

Codex 可以在任务需要时：

* 创建 Unit Test。
* 修改 Unit Test。
* 创建 UI Test。
* 修改 UI Test。
* 修复明显错误的测试实现。
* 更新测试以匹配明确改变的业务行为。

但：

> 编写了测试 ≠ 获得运行测试的权限。

如果用户没有明确允许本地测试，Codex 在完成测试代码后只能：

1. Build。
2. 确认测试 Target 能够编译。
3. 将实际测试执行留给 GitHub Actions。

---

# 22. 禁止伪造测试结果

Codex 不得声称：

> Tests passed.

除非测试确实已经通过 GitHub Actions，或者用户明确授权后在本地实际执行成功。

如果只进行了 Build，应明确写：

```text
Build: Passed
Tests: 未在本地执行
```

而不是：

```text
Build & Tests: Passed
```

如果等待 CI 验证，则应写：

```text
Build: Passed
Tests: 待 GitHub Actions 验证
```

---

# 23. GitHub Actions 失败处理

如果 GitHub Actions 测试失败，应：

1. 阅读真实 CI Log。
2. 定位具体失败测试。
3. 区分 Build Failure 与 Test Failure。
4. 查找根因。
5. 修改相关代码。
6. 本地只执行 Build 验证。
7. 再通过新的 Pull Request / Push 交由 GitHub Actions 验证测试。

不得因为 CI 测试失败而自行切换成本地运行测试，除非用户明确授权。

---

# 24. 不允许通过修改 CI 绕过失败

遇到 GitHub Actions 测试失败时，禁止通过以下方式“解决”问题：

* 删除失败测试。
* 注释失败测试。
* 删除测试 Target。
* 修改 Workflow 不运行该测试。
* 增加无条件 `continue-on-error`。
* 将失败测试标记为永远跳过。
* 降低断言标准。
* 删除关键断言。
* 修改触发条件逃避 CI。
* 让 main 分支不再运行测试。

测试失败应解决根因，而不是绕过测试系统。

---

# 25. 编译错误处理

遇到编译错误时：

1. 定位真正错误。
2. 理解上下文。
3. 修复最接近根因的问题。
4. 再次 Build。
5. 避免通过删除功能绕过错误。

禁止为了让项目：

> 编译通过

而：

* 删除失败代码。
* 注释测试。
* 删除断言。
* 降低测试标准。
* 删除业务逻辑。
* 使用无意义的 force unwrap 绕过类型问题。

---

# 26. Warning 处理

不要为了：

> Zero Warnings

而无条件修改所有 Warning。

应判断 Warning 是否：

* 与当前任务有关。
* 表示真实 bug。
* 表示未来兼容性问题。

与任务无关的大规模 Warning Cleanup 应作为独立任务处理。

---

# 27. API 使用规则

不得猜测 Apple API。

如果不确定：

* API 是否存在。
* API 参数。
* API availability。
* API 是否 deprecated。
* 平台是否支持某能力。

应先验证。

禁止生成看起来合理但实际上不存在的：

* Swift API。
* Apple Framework。
* modifier。
* property。
* delegate method。

---

# 28. 数据安全

用户文件属于高敏感资产。

默认原则：

> Local First。

除非需求明确要求，否则：

* 不上传用户文件。
* 不将文件内容发送给第三方。
* 不偷偷建立云端副本。
* 不记录文件完整内容。
* 不记录敏感文件内容到日志。
* 不将 Security-Scoped Bookmark 泄露给第三方。

文件名和完整路径也应视为可能包含敏感信息。

---

# 29. 日志规则

开发日志应帮助定位问题，但不得随意输出：

* 文件完整内容。
* 用户文档文本。
* 用户照片数据。
* Access Token。
* Security Credential。
* API Key。
* 私密 URL。
* Bookmark Data。

Release 环境不得保留大量无意义 Debug 日志。

---

# 30. 不得擅自增加联网能力

如果当前功能可以本地完成，不得因为实现方便自行增加：

* 后端服务。
* 第三方 API。
* 文件上传。
* Analytics SDK。
* Tracking SDK。
* 云端转换服务。

联网能力必须有明确产品需求。

---

# 31. 不得擅自引入 AI

不得因为某个问题：

> 看起来可以用 AI

就自动引入：

* LLM。
* Vision Model。
* Embedding Model。
* 云端推理 API。

如果确定性算法可以可靠解决，应优先确定性算法。

例如：

```text
Duplicate File
```

优先使用 Hash，而不是 ML。

---

# 32. 依赖修改规则

不得无理由：

* 升级 Package。
* 降级 Package。
* 删除 Package。
* 修改 Package Resolution。
* 更新大量依赖。

如果任务需要增加依赖，应说明：

* 为什么需要。
* 原生能力为什么不足。
* License。
* 对 Binary Size 的影响。
* 对现有架构的影响。

---

# 33. 注释规则

注释应该解释：

> Why。

而不是机械重复：

> What。

好的：

```swift
// 先按文件大小分组，避免为所有文件读取完整内容并计算 SHA256。
```

不好的：

```swift
// 遍历 files
for file in files {
}
```

不要为了增加注释数量而制造大量噪声。

---

# 34. 命名原则

命名必须表达业务语义。

避免：

```text
Manager
Helper
Utils
Common
Handler
Processor
Thing
Data
```

被无限扩大成为万能对象。

名称应该尽可能说明职责。

---

# 35. 不得擅自改变产品定义

Codex 的职责是实现产品，而不是自行重新定义产品。

除非明确要求，不得擅自：

* 增加新功能。
* 删除功能。
* 修改 Premium 边界。
* 修改商业模式。
* 修改产品定位。
* 修改用户流程。
* 修改权限策略。
* 增加 Analytics。
* 增加广告。

可以提出建议，但不得将建议直接作为需求执行。

---

# 36. 遇到不确定情况

如果存在多种实现方式，优先顺序：

1. 与现有项目一致。
2. Apple 官方推荐方式。
3. 简单方案。
4. 可维护方案。
5. 可测试方案。
6. 性能优化方案。

不要因为技术更复杂就默认它更好。

---

# 37. Codex 可以主动做什么

在不扩大任务范围的前提下，可以主动：

* 修复由当前修改直接产生的编译错误。
* 修复由当前修改直接产生的测试代码错误。
* 删除当前修改产生的无用代码。
* 增加当前功能必要的错误处理。
* 增加当前功能必要的 Unit Test。
* 增加当前功能必要的 UI Test。
* 修复明显的并发安全问题。
* 修复明显的资源泄漏。
* 修复明显的 MainActor 阻塞。
* 修复当前任务涉及范围内的明显逻辑 bug。

但新增或修改测试之后：

> 默认不得在本地执行测试。

---

# 38. Codex 不应主动做什么

未经明确要求，不得：

* 在本地运行测试。
* 重构整个项目。
* 修改项目架构。
* 修改目录组织方式。
* 重新设计 UI。
* 改变业务逻辑。
* 大规模重命名。
* 修改 Deployment Target。
* 修改 Bundle Identifier。
* 修改 Signing。
* 修改 Entitlements。
* 修改权限声明。
* 修改 App Store 配置。
* 增加联网服务。
* 增加商业 SDK。
* 增加广告 SDK。
* 增加 Analytics SDK。
* 修改 CI/CD 核心策略。
* 修改 GitHub Actions 测试触发规则。
* 删除测试。
* 降低测试标准。
* 引入 GPL / Non-free 依赖。
* 将用户文件发送到第三方。

---

# 39. 每次任务完成后的最低要求

完成任务后，应能够明确说明：

## 修改了什么

只描述实际修改。

## 为什么这样修改

解释关键技术决策。

## 本地验证

正常情况下：

```text
Build: Passed / Failed / 未运行
Tests: 未在本地执行（按项目规则）
```

如果用户明确授权本地测试，则可以报告真实测试结果。

## CI 状态

如果 GitHub Actions 已经执行：

```text
GitHub Actions: Passed / Failed
```

如果尚未执行：

```text
GitHub Actions: 待验证
```

不得将：

```text
Build Passed
```

描述成：

```text
Tests Passed
```

## 剩余问题

如果发现真实风险，可以指出，但不要擅自扩大任务范围继续修改。

---

# 40. 最终原则

本项目优先级：

```text
正确性
>
用户文件安全
>
数据完整性
>
稳定性
>
可维护性
>
性能
>
代码简洁
>
技术炫技
```

任何情况下：

> 用户文件安全高于性能优化。

任何删除、覆盖、移动或转换操作，都必须假设：

> 用户的数据不可替代。

对于测试：

> 本地默认只 Build，不 Test。

对于 Unit Test：

> Swift Testing。

对于 UI Test：

> XCTest / XCUITest。

对于正式测试执行：

> GitHub Actions。

默认测试触发范围：

```text
Pull Request
+
Push to main
```

未经用户主动明确允许：

> Codex 不得在本地运行测试。

Codex 应严格遵守以上边界。

