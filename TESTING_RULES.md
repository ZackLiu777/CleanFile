# TESTING_RULES.md

## 1. 文档目的

本文档定义本项目的测试策略、测试分类、CI 阻塞规则、测试框架选择、GitHub Actions 执行原则以及 Codex 编写测试时必须遵守的工程规范。

本项目不追求：

> 所有测试都必须零失败。

而是追求：

> **确定性的正确性必须得到严格保证；非确定性测试用于发现风险，但不能因为环境抖动阻塞正常开发。**

测试体系因此分为两个主要层级：

```text
Required / Deterministic
        ↓
必须通过
        ↓
阻塞 Pull Request / main


Non-Blocking / Non-Deterministic
        ↓
允许失败
        ↓
用于观察风险与回归
```

开发过程中同时遵守：

- `AGENTS.md`
- `PROJECT_START.md`
- `SWIFTUI_RULES.md`
- `PITFALLS.md`

如果规则冲突：

> `AGENTS.md` 优先级最高。

---

# 2. 测试核心原则

本项目长期遵循：

> **Deterministic Tests Must Pass**

> **Non-Deterministic Tests May Fail**

> **Build Failure Always Fails**

> **CI Is The Test Environment**

> **Local Build, CI Test**

> **Tests Verify Contracts, Not Implementations**

---

# 3. 本地测试规则

未经用户主动明确允许：

> Codex 不得在本地执行任何测试。

禁止执行：

```bash
xcodebuild test
```

```bash
xcodebuild test-without-building
```

```bash
swift test
```

以及任何实际运行：

- Unit Test
- UI Test
- Integration Test
- Performance Test

的命令。

---

# 4. 本地允许做什么

默认本地只允许：

> Build / Compile。

例如：

```bash
xcodebuild build
```

或者：

```bash
xcodebuild build-for-testing
```

前提是：

> `build-for-testing` 只编译测试 Target，不实际运行测试。

本地允许验证：

- Swift 编译。
- Test Target 编译。
- Linker。
- Actor Isolation。
- API Availability。
- Package。
- Localization。
- SwiftUI 类型问题。
- XCTest / Swift Testing 测试代码是否可编译。

---

# 5. 正式测试执行环境

所有正式测试默认通过：

> GitHub Actions

运行。

正常触发条件：

```yaml
on:
  pull_request:
    branches:
      - main

  push:
    branches:
      - main
```

即：

```text
Pull Request → main
        +
Push → main
```

---

# 6. CI 基本结构

CI 建议保持三阶段：

```text
Checkout
    ↓
Build for Testing
    ↓
Required Tests
    ↓
Non-Blocking Tests
```

UI Test 可以作为独立 Job：

```text
Unit Tests
    ↓
UI Tests
```

---

# 7. Build 永远属于 Required

无论测试属于哪一类：

> Build 必须成功。

如果：

```text
Build for Testing
```

失败，

整个 CI 必须失败。

禁止：

```bash
xcodebuild build-for-testing ... || true
```

Build Failure 不属于：

> Flaky Failure。

它表示当前代码无法正确编译。

---

# 8. 测试分类

本项目测试分为：

## A. Required Tests

确定性测试。

必须通过。

失败：

> CI Failure。

---

## B. Non-Blocking Tests

存在：

- 随机性。
- 时序。
- Simulator 抖动。
- UI 自动化不稳定。
- 系统 Framework timing。
- File Provider timing。
- 并发 timing。

等非确定性因素。

允许失败。

失败：

> 不阻塞 CI。

但必须保留结果用于诊断。

---

# 9. 什么叫确定性测试

如果同样输入：

```text
Input X
```

无论什么时候运行都应该得到：

```text
Output Y
```

那么属于：

> Deterministic。

例如：

```text
file type
→ category
```

```text
bytes
→ formatted size
```

```text
files
→ storage summary
```

```text
same size group
→ duplicate candidate group
```

```text
conversion request
→ selected conversion engine
```

这些测试：

> 必须通过。

---

# 10. 当前项目适合 Required 的测试

包括但不限于：

### Model

- File Model。
- File Category。
- Storage Summary。
- Conversion Request。
- Conversion Result。
- Error Model。

### File Classification

例如：

```text
JPEG → Image
MP4 → Video
PDF → PDF / Document
ZIP → Archive
```

### Storage Calculation

例如：

```text
Video 10 GB
Image 5 GB

Total = 15 GB
Video Percentage = 2/3
```

### Duplicate Candidate Logic

例如：

```text
不同 size
→ 不进入 Hash Candidate
```

```text
相同 size
→ Candidate Group
```

### Hash Helper

使用固定字节输入时：

```text
Input
→ SHA256
```

结果必须完全确定。

### Formatter

- Bytes。
- File Count。
- Percentage。
- Date formatting logic。

### State Machine

例如：

```text
Idle
→ Scanning
→ Success
```

### Conversion Routing

例如：

```text
MOV → MP4
→ Native Converter
```

```text
Unsupported Native Format
→ FFmpeg Fallback
```

如果未来启用 FFmpeg。

### Incremental Update

例如：

```text
删除一个 2 GB Video
→ total -= 2 GB
→ video -= 2 GB
→ count -= 1
```

### Error Mapping

例如：

```text
Permission Error
→ FileAccessError.permissionDenied
```

---

# 11. “使用随机数”不自动等于随机测试

这是本项目必须明确的一条规则。

如果测试使用：

```swift
var rng = SeededGenerator(seed: 42)
```

那么它已经具有：

> 可重复性。

例如：

```text
seed = 42
↓
永远生成同一输入
↓
永远得到同一输出
```

这种测试属于：

> Required。

不能因为代码中出现 Random：

> 就自动放入 allowed-to-fail。

---

# 12. Seeded Random Test

固定 Seed 的随机测试应优先设计成：

> Deterministic Randomized Test。

例如：

```swift
@Test
func randomizedClassificationIsStable() {
    var rng = SeededGenerator(seed: 42)

    ...
}
```

如果：

```text
Seed 相同
→ Input 相同
→ Result 相同
```

它必须：

> Must Pass。

---

# 13. 什么属于真正的 Non-Deterministic

如果测试结果可能受到下面因素影响：

- 真随机数。
- 系统调度。
- Task 执行顺序。
- Simulator timing。
- Animation timing。
- UI transition timing。
- File Provider timing。
- iCloud timing。
- Real filesystem latency。
- OS scheduling。
- Hardware performance。

则可能属于：

> Non-Blocking。

---

# 14. 非确定性测试的目的

Non-Blocking Test 不是：

> 可以随便写坏的测试。

而是：

> 提供额外的回归信号。

例如一次 CI：

```text
Required
48 / 48 Passed

Non-Blocking
17 / 18 Passed
```

总体可以通过。

但是那一个失败：

> 仍然值得检查。

---

# 15. Non-Blocking 不是垃圾桶

禁止因为一个测试失败：

> 就把它从 Required 移到 Non-Blocking。

只有测试本质确实存在无法消除的非确定性时，才能进入该组。

禁止：

```text
测试失败
↓
不想修
↓
移到 flaky
```

---

# 16. 优先消除随机性

如果一个 Non-Deterministic Test 可以通过：

- Fixed Seed。
- Dependency Injection。
- Mock Clock。
- Mock FileSystem。
- Controlled Scheduler。
- Stable Fixture。

变成确定性测试，

应该：

> 优先改造成 Required。

长期目标是：

> Required Tests 越来越多。

而不是：

> Flaky Tests 越来越多。

---

# 17. Randomized / Statistical Test

部分算法可能需要：

> 多次随机输入。

例如未来测试：

- Hash Pipeline。
- Large Dataset。
- Sampling。
- Similarity。
- Statistical Heuristic。

如果使用真正随机输入：

> 可以放在 Non-Blocking。

但如果能够固定 Seed：

> 应优先固定 Seed。

---

# 18. Monte Carlo 类测试

如果未来存在概率算法：

例如：

```text
运行 1000 次
要求 95% 情况满足条件
```

这种测试天然可能因为采样波动失败。

可以作为：

> Non-Blocking Statistical Test。

但必须明确：

- Sample Size。
- Expected Range。
- Tolerance。
- Failure Probability。

不能写：

```text
运行随机算法
↓
大概应该没问题
```

这种没有统计定义的测试。

---

# 19. 概率测试必须避免极窄阈值

如果理论上：

```text
expected ≈ 0.50
```

不要测试：

```text
0.499 < result < 0.501
```

除非样本量足够支持。

应该根据：

- 方差。
- Sample Size。
- Statistical Error。

设置合理 tolerance。

---

# 20. Unit Test 框架

本项目所有新的 Unit Test：

> 必须使用 Swift Testing。

使用：

```swift
import Testing
```

```swift
@Test
```

```swift
#expect(...)
```

例如：

```swift
import Testing

struct FileCategoryTests {

    @Test
    func mp4IsVideo() {
        let result = FileClassifier.classify(...)
        #expect(result == .video)
    }
}
```

---

# 21. Unit Test 不使用 XCTestCase

除非存在平台级必要性，

新的 Unit Test 禁止默认：

```swift
import XCTest
```

以及：

```swift
final class SomeTests: XCTestCase
```

Unit Test：

> Swift Testing。

---

# 22. UI Test 框架

UI Test 必须使用：

> XCTest / XCUITest。

例如：

```swift
import XCTest

final class DashboardUITests: XCTestCase {

    func testDashboardLaunches() {
        let app = XCUIApplication()
        app.launch()
    }
}
```

UI 自动化不能用 Swift Testing 代替 XCUITest。

---

# 23. UI Tests 默认属于 Non-Blocking

UI Test 通常依赖：

- Simulator。
- Animation。
- Rendering。
- Accessibility Tree。
- Timing。
- App Launch。
- System Sheet。

因此项目初始阶段：

> UI Test 默认允许失败。

即：

```text
UI Tests
→ Non-Blocking
```

---

# 24. UI Test 未来可以升级为 Required

如果某个 UI Test 长期：

- 稳定。
- 无 Timing Dependency。
- 多次 CI 无 Flake。
- 属于核心用户路径。

可以考虑提升为：

> Required UI Test。

但必须是明确决策。

Codex 不得自行改变测试级别。

---

# 25. 当前适合 UI Test 的核心流程

例如：

```text
App Launch
```

```text
Dashboard 基础元素存在
```

```text
Tab 切换
```

```text
进入 Files 页面
```

```text
打开 Converter
```

```text
打开 Settings
```

后续可以增加：

```text
Selection Mode
```

```text
Delete Confirmation
```

但不要依赖真实删除用户数据。

---

# 26. UI Test 不操作真实用户文件

UI Test 必须使用：

- Test Fixture。
- Mock。
- 临时目录。
- Test-only environment。

禁止：

> UI Test 访问或删除真实用户文件。

尤其不能让 CI 测试：

> 依赖宿主机真实 Documents。

---

# 27. File System Unit Test

文件系统测试应尽量使用：

> Temporary Directory。

例如：

```text
tmp/
├── image.jpg
├── video.mp4
└── document.pdf
```

测试结束后：

> 清理 Fixture。

不要依赖：

```text
~/Downloads
```

这类环境目录。

---

# 28. File System 测试要保持隔离

每个 Test 应拥有：

> 自己的临时测试目录。

不要多个并行 Test 共用：

```text
/tmp/files
```

否则容易出现：

- Race Condition。
- 删除冲突。
- 状态污染。

应使用：

> Unique Temporary Directory。

---

# 29. Shared Database Test

如果未来使用数据库，

多个测试共用一个 DB 时容易：

- Race。
- Order Dependency。
- Dirty State。

这类测试如果暂时无法完全隔离：

> 可以进入 Non-Blocking。

但更好的长期方案仍然是：

> 每个测试独立 Database。

---

# 30. Test 必须彼此独立

禁止依赖：

```text
Test A
先创建数据
↓
Test B
读取 Test A 数据
```

每个测试必须可以：

> 单独运行。

测试顺序不能成为正确性的前提。

---

# 31. 不依赖测试执行顺序

不得假设：

```text
testCreate
↓
testUpdate
↓
testDelete
```

一定按照这个顺序执行。

Testing Framework 可以：

> 改变执行顺序或并行执行。

---

# 32. 不使用真实时间作为确定性输入

例如：

```swift
Date.now
```

容易使 Test 结果随时间变化。

对于 Required Test：

优先使用：

```text
2026-01-01 00:00:00
```

这种固定时间。

或者注入：

> Clock。

---

# 33. 不使用 sleep() 证明异步正确

避免：

```swift
try await Task.sleep(...)
#expect(...)
```

作为核心 Unit Test 策略。

这类测试容易受：

- CI Load。
- Scheduler。
- Simulator。

影响。

如果确实依赖 Timing：

> 应归类为 Non-Blocking。

---

# 34. Concurrency Test

如果测试的是：

- Actor Safety。
- Cancellation。
- AsyncSequence。
- Bounded Concurrency。

优先测试：

> 最终 Contract。

例如：

```text
Cancel
→ State = cancelled
```

而不是：

```text
Task 2 必须比 Task 3 先运行
```

除非顺序本身就是 Contract。

---

# 35. Cancellation Test

Cancellation 应尽可能做成确定性测试。

例如通过：

- Controlled Mock Service。
- AsyncStream。
- Test Hook。

使任务在明确位置挂起，

然后：

```text
cancel
```

再检查：

```text
state == .cancelled
```

不要依赖：

> 随机等 0.5 秒再取消。

---

# 36. Performance Test

Performance Test 通常受到：

- Runner 性能。
- Thermal。
- Simulator。
- GitHub Host。

影响。

因此：

> 默认 Non-Blocking。

不要在普通 CI 中写：

```text
扫描必须 < 0.241 秒
```

这种脆弱硬阈值。

---

# 37. 性能测试更适合趋势观察

例如：

```text
10,000 fixture files
↓
scan duration
↓
record
```

用于观察：

> 是否突然慢一个数量级。

而不是：

> 100 ms 波动就失败。

---

# 38. Required Test 不应该依赖网络

Required Test 禁止访问：

- GitHub。
- Apple。
- Web API。
- Cloud Storage。
- File Provider Network。

网络属于：

> 外部非确定性输入。

核心业务必须使用：

> Mock / Fixture。

---

# 39. Required Test 不依赖真实 iCloud

iCloud：

- 状态变化。
- 网络变化。
- 登录状态。
- 同步 Timing。

不适合作为 Required Unit Test Dependency。

相关行为使用：

> 抽象 + Mock。

真实 iCloud 测试如果未来存在：

> Non-Blocking Integration Test。

---

# 40. Required Test 不依赖真实 FFmpeg Process Timing

如果未来集成 FFmpeg，

Router 等业务判断必须：

> Deterministic。

例如：

```text
request X
→ FFmpeg backend
```

必须通过。

但真实：

```text
转码一个大型视频
```

可能属于 Integration / Non-Blocking。

---

# 41. Test Double

建议优先使用简单 Test Double：

- Mock。
- Stub。
- Fake。

不要为了测试建立复杂 mocking framework。

如果 Protocol 很简单：

> 手写 Mock 更透明。

---

# 42. Mock 必须确定性

Mock 不应该：

```swift
Bool.random()
```

或者：

```swift
Int.random(in:)
```

决定响应。

默认 Mock：

> 固定结果。

如果需要多数据：

> Seeded> 固定结果。

如果需要多数据：

> Seeded。

---

# 43. Production 与 Mock Pipeline 隔离

测试 Mock 不允许：

> 泄漏进入 Release 运行路径。

尤其不要：

```text
真实扫描失败
↓
自动 fallback mock result
```

这种设计。

---

# 44. 测试命名

Test 名称应该表达：

> Given / Behavior / Result。

例如：

```text
deleteSuccessfulFileRemovesItFromSummary
```

好于：

```text
testDelete1
```

Swift Testing 可以采用自然函数名称表达 Contract。

---

# 45. 测试一个行为

一个测试最好验证：

> 一个核心业务行为。

不要写一个 300 行 Test 同时验证：

- Scan。
- Duplicate。
- Delete。
- Convert。
- Theme。

这样失败后难定位。

---

# 46. 不测试实现细节

例如：

如果 Contract 是：

```text
JPEG → Image
```

不要测试：

> FileClassifier 内部调用了哪个 private helper。

测试：

> 最终结果。

这样重构内部实现不会无意义破坏 Test。

---

# 47. 不使用脆弱 Count Assertion

例如：

```swift
#expect(FileCategory.allCases.count == 6)
```

如果枚举未来允许扩展，

这种测试价值低。

更合理：

```swift
#expect(FileCategory.allCases.contains(.video))
#expect(FileCategory.allCases.contains(.image))
```

测试真正 Contract。

---

# 48. Floating Point

浮点数不要：

```swift
#expect(actual == expected)
```

除非计算理论上完全精确。

使用：

> 合理 tolerance。

例如：

```text
|actual - expected| < ε
```

---

# 49. UI Color Test

不要依赖：

> Color 对象直接相等。

不同 OS / Dynamic Provider 可能行为不同。

如果真的需要测试颜色：

> 比较明确 RGBA Component。

但不要为了测试视觉 Token：

> 构建大量脆弱像素测试。

---

# 50. Snapshot Test

第一阶段不默认引入 Snapshot Test Framework。

原因：

- iOS Version。
- Font Rendering。
- Simulator。
- Scale。
- System UI。

容易制造大量不稳定失败。

如未来引入：

> 默认 Non-Blocking。

---

# 51. Localization Test

Localization Contract 属于：

> Required。

至少应该验证：

- Key 存在。
- 必要语言存在。
- Placeholder 一致。
- Production UI 不引用不存在 Key。

特别关注：

> 不引用不存在 Key。

特别关注：

> `%@` 参数数量和类型。

---

# 52. 本地化 Placeholder Test

如果字符串包含参数，

应检查所有语言：

```text
placeholder count
placeholder type
```

保持一致。

避免再次发生：

```text
%d
vs
%@
```

运行时崩溃。

---

# 53. Delete Logic Test

删除相关业务属于：

> Required。

至少应该覆盖：

```text
全部成功
```

```text
部分失败
```

```text
全部失败
```

```text
目标已经不存在
```

```text
用户取消
```

以及：

```text
成功删除后 Summary 正确更新
```

---

# 54. Delete Test 不真实删除重要文件

测试删除只能针对：

> Temporary Fixture。

永远不能：

```text
硬编码用户 Documents URL
↓
removeItem
```

---

# 55. Duplicate Test

Duplicate Pipeline 建议拆开测试：

```text
Size Grouping
```

```text
Partial Hash Candidate
```

```text
Full Hash Confirmation
```

不要只写：

```text
整个 Duplicate Engine 最终返回 3 组
```

而完全无法定位哪层出问题。

---

# 56. Hash Test

使用固定 Fixture：

```text
"hello"
```

结果应该：

> 固定。

Hash Test 属于 Required。

---

# 57. Storage Summary Test

这是本项目最核心的 Required Test 之一。

应验证：

- Total Bytes。
- Category Bytes。
- Count。
- Percentage。
- 删除后更新。
- 空数据。
- 单类别数据。
- Other 分类。

---

# 58. Percentage Edge Case

必须覆盖：

```text
total = 0
```

避免：

```text
NaN
Infinity
Division by zero
```

---

# 59. Large File Boundary

如果：

```text
Large File >= 500 MB
```

需要测试：

```text
499 MB
500 MB
501 MB
```

边界测试属于：

> Required。

---

# 60. Conversion Routing Test

如果 Conversion Engine 存在多个 Backend，

必须 Required 测试：

```text
Native Supported
→ Native
```

```text
Native Unsupported
→ Fallback
```

```text
No Backend
→ Unsupported Error
```

Router 逻辑不能靠 UI 手工验证。

---

# 61. Conversion Integration Test

真实图片 / 视频转换可能受到系统 Framework 影响。

可以根据稳定程度分为：

### 小型固定 Fixture

如果稳定：

> Required。

### 大媒体 / Codec / Timing

如果环境差异明显：

> Non-Blocking。

---

# 62. Test Fixture 大小

CI 不应该携带大量：

```text
几 GB
```

媒体 Fixture。

优先使用：

- 小图片。
- 极短视频。
- 小 PDF。
- 小 ZIP。

验证：

> 行为。

不是测试 Git LFS。

---

# 63. Test Fixture 必须合法

不要通过：

```text
创建一个空文件
命名 video.mp4
```

然后把它当真实 Media Conversion Fixture。

如果测试需要真实媒体：

> Fixture 必须是合法格式。

---

# 64. Required CI 失败规则

Required Test 命令：

> 不允许 `|| true`。

例如：

```bash
xcodebuild test-without-building \
  ... \
  -only-testing:...
```

如果失败：

> Job Failure。

---

# 65. Non-Blocking CI 失败规则

Non-Blocking Test 可以：

```bash
xcodebuild test-without-building \
  ... \
  -only-testing:... || true
```

这样失败不会阻塞 CI。

但必须：

> 保留测试日志。

---

# 66. 更推荐 continue-on-error

如果 Workflow 可读性允许，

也可以使用：

```yaml
continue-on-error: true
```

表达：

> 此步骤允许失败。

这通常比把：

```bash
|| true
```

隐藏在长命令尾部更清楚。

---

# 67. Non-Blocking Failure 必须显式命名

不要把步骤叫：

```text
Run Tests
```

然后 secretly：

```bash
|| true
```

应该明确：

```text
Run Non-Blocking Tests
```

或：

```text
Run Flaky / Statistical Tests
```

让维护者知道：

> 失败不会阻塞。

---

# 68. Required 与 Non-Blocking 分开运行

不要：

```text
所有测试一个 xcodebuild
↓
末尾 || true
```

这样会导致：

> Required Failure 也被吞掉。

必须：

```text
Required
独立命令
```

```text
Non-Blocking
独立命令
```

---

# 69. 建议 CI 结构

推荐：

```yaml
jobs:

  unit-tests:
    steps:

      - Build for Testing

      - Run Required Unit Tests

      - Run Non-Blocking Unit Tests

  ui-tests:
    needs: unit-tests

    steps:

      - Build for Testing

      - Run UI Tests
```

---

# 70. UI Job 是否等待 Required Unit Tests

默认：

```text
UI Tests
needs
Required Unit Tests
```

即：

> Required Unit Tests 已经失败时，没有必要继续消耗大量 CI 时间跑 UI。

---

# 71. Required Test List 应明确

CI 应明确列出：

> 哪些 Test Suite 属于 must-pass。

例如未来可能：

```text
FileModelTests
FileClassifierTests
StorageSummaryTests
FileSizeFormatterTests
DuplicateGroupingTests
HashTests
ConversionRoutingTests
DeletionStateTests
LocalizationTests
```

具体名称以实际项目为准。

---

# 72. 不要复制旧项目 Test Suite 名称

此前 Follower 的：

```text
PredictionServiceTests
LaplaceTests
GLM

此前 Follower 的：

```text
PredictionServiceTests
LaplaceTests
GLM

此前 Follower 的：

```text
PredictionServiceTests
LaplaceTests
GLMGradientTests
...
```

与当前项目无关。

当前 CI 只能根据：

> 当前项目真实测试模块

定义。

不要为了模仿旧 Workflow 制造不存在的 Test Suite。

---

# 73. 测试分类写入代码或文档

每个新增 Test Suite 必须清楚知道：

```text
Required
```

还是：

```text
Non-Blocking
```

不要长期存在：

> 没人知道这个 Test 是否应该阻塞 CI。

---

# 74. Codex 新增 Test 时必须分类

Codex 写一个新的 Test 后必须判断：

### 是否相同输入必然相同输出？

是：

> Required。

### 是否可以通过固定 Seed 消除随机性？

是：

> Required。

### 是否依赖 UI / Timing / Scheduler / Real Provider？

是：

> 优先尝试消除依赖。

无法消除：

> Non-Blocking。

---

# 75. Codex 不得擅自降低等级

如果 Required Test 失败，

Codex 不得：

```text
Required
↓
Non-Blocking
```

来让 CI 通过。

改变测试等级：

> 必须是明确工程决策。

---

# 76. Codex 不得删除失败测试

CI Failure 不允许通过：

- 删除 Test。
- Comment Test。
- Skip。
- `|| true`。
- 降级 Required。
- 修改 Workflow 排除 Test。

规避。

必须：

> 修根因。

---

# 77. Codex 不得为了通过测试修改正确业务逻辑

如果 Test 与当前业务契约冲突，

应先判断：

> Test 是否已经过期。

不是：

> 只要测试失败就改 Production。

测试与实现都可能有 Bug。

---

# 78. 算法重构必须重新检查断言语义

特别是修改：

- Percentage。
- Average。
- Threshold。
- Normalization。
- Grouping。
- Duplicate Rule。

后，

不能简单：

```text
运行结果是 0.37
↓
把 Test 改成 0.37
```

必须确认：

> 0.37 是否符合新的业务定义。

---

# 79. Flaky Test 连续失败需要治理

虽然 Non-Blocking 允许失败，

但如果：

```text
连续多次 CI 都失败
```

说明它已经不是偶发 Flake。

应该：

- 修复。
- 重写。
- 删除没有价值的测试。
- 或重新定义测试目的。

不能让 Non-Blocking 成为：

> 永久红灯区。

---

# 80. Random Test 应输出 Seed

如果真正使用随机 Seed，

失败日志必须尽量记录：

```text
Seed = ...
```

这样失败可以：

> 重现。

没有 Seed 的随机失败几乎没有调试价值。

---

# 81. Property-Based 思路

对于文件分类等纯逻辑，

未来可以考虑：

> Property-Based Testing。

例如：

```text
所有 size >= 0
→ Summary total >= 0
```

或者：

```text
category percentages
总和约等于 1
```

如果生成器使用固定 Seed：

> Required。

---

# 82. Test 必须可诊断

失败信息应该让人看得懂：

不好：

```text
Expected true
```

更好：

```text
Expected analyzedBytes = 1048576,
got 0
```

让 CI Log 可以直接帮助定位。

---

# 83. CI Simulator 要固定

不要长期依赖：

```text
OS=latest
```

优先固定：

- Runner。
- Xcode。
- Simulator Device。
- Simulator OS。

避免 CI Image 更新突然改变环境。

---

# 84. Xcode Version 要明确

如果项目依赖新 SwiftUI API，

CI 应明确：

> 使用支持该 API 的 Xcode。

不要：

```text
本地 Xcode 27
CI Xcode 26
```

然后把 API 不存在误认为代码 Bug。

---

# 85. CI 中不自动修改项目

测试 Workflow 不应：

- 修改源码。
- 自动 format 后 commit。
- 修改 Project Setting。
- 修改 Package Resolution。

CI 默认：

> Read + Build + Test。

---

# 86. CI 中测试 Release 与 Debug 的边界

Unit / UI Test 默认使用适合测试的 Build Configuration。

不要为了：

> Preview 或优化问题

随意把 Test Scheme 改成 Release。

如果未来需要 Release-specific Validation：

> 独立 Job。

---

# 87. Code Signing

Simulator CI 一般保持：

```text
CODE_SIGNING_ALLOWED=NO
```

避免不必要 Signing Dependency。

如果未来某个 Test 真正需要 Signing：

> 单独评估。

---

# 88. GitHub Actions Workflow 不应过度复杂

第一阶段不需要：

- 大型 Matrix。
- 多 Xcode 版本。
- 多 Simulator。
- 多语言 UI 全排列。
- 每个 Test 一个 Job。

先保证：

> 简单、稳定、可理解。

---

# 89. CI 失败优先判断类别

看到失败时先判断：

```text
Build Failure
```

还是：

```text
Required Test Failure
```

还是：

```text
Non-Blocking Failure
```

还是：

```text
Runner / Simulator Failure
```

四者处理方法完全不同。

---

# 90. Build Failure

意味着：

> 代码或环境无法构建。

必须解决。

不能忽略。

---

# 91. Required Failure

意味着：

> 项目确定性 Contract 被破坏。

必须解决。

阻塞合并。

---

# 92. Non-Blocking Failure

意味着：

> 发现潜在回归或环境波动。

不阻塞合并，

但需要观察。

---

# 93. Infrastructure Failure

例如：

```text
Simulator not found
Xcode missing
GitHub Runner issue
Dependency clone failed
```

不能把它误认为：

> Unit Test Failure。

应修 CI 环境。

---

# 94. Tests Passed 的报告规则

Codex 只有看到真实 CI 成功后，

才能说：

> Tests Passed。

如果只 Build：

```text
Build: Passed
Tests: 未在本地执行
```

如果 CI 尚未跑：

```text
GitHub Actions: 待验证
```

---

# 95. Non-Blocking 有失败时如何报告

例如：

```text
Required Tests: 42/42 Passed
Non-Blocking Tests: 8/9 Passed
UI Tests: 11/12 Passed
```

CI 总体：

> 可以视为通过。

但必须明确：

> 存在非阻塞失败。

不能说：

> All Tests Passed。

---

# 96. 建议的 CI 成功定义

项目整体 CI 可以认为成功，当且仅当：

```text
Build
=
Passed

Required Unit Tests
=
Passed
```

Non-Blocking：

```text
可以存在 Failure
```

UI：

```text
初始阶段可以存在 Failure
```

---

# 97. main 分支质量要求

任何进入 main 的代码必须至少满足：

```text
Build Pass
+
Required Tests Pass
```

这是最低质量门槛。

---

# 98. Pull Request 质量门槛

PR 合并前：

```text
Required CI
=
Green
```

如果 Required Test 红：

> 不应合并。

Non-Blocking 红：

> 可以合并，但需要判断失败是否代表真实问题。

---

# 99. 初始 CI 推荐分类

项目初期可以采用：

## Required

```text
Models
File Classification
Storage Summary
Formatter
State Machine
Duplicate Grouping
Hash
Conversion Router
Localization
Pure Services
```

## Non-Blocking

```text
Filesystem Integration
Shared Database
Concurrency Timing
Real Media Conversion
Performance
Random Statistical
MainActor Timing
```

## UI Non-Blocking

```text
Dashboard UI
Files UI
Cleaner UI
Converter UI
Settings UI
Navigation UI
```

具体 Test Suite 名称以后根据真实项目逐步填写。

---

# 100. 推荐 Workflow 基线

初始 Workflow 可以参考以下结构：

```yaml
name: iOS CI

on:
  pull_request:
    branches:
      - main

  push:
    branches:
      - main

jobs:

  unit-tests:
    name: Unit Tests
    runs-on: macos-26

    steps:

      - name: Checkout
        uses: actions/checkout@v4

      - name: Select Xcode
        run: |
          sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

      - name: Build for Testing
        run: |
          xcodebuild build-for-testing \
            -project PROJECT_NAME.xcodeproj \
            -scheme SCHEME_NAME \
            -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
            -only-testing:UNIT_TEST_TARGET \
            -derivedDataPath /tmp/ProjectDD \
            CODE_SIGNING_ALLOWED=NO

      - name: Run Required Unit Tests
        run: |
          xcodebuild test-without-building \
            -project PROJECT_NAME.xcodeproj \
            -scheme SCHEME_NAME \
            -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
            -only-testing:UNIT_TEST_TARGET/RequiredTestSuite \
            -derivedDataPath /tmp/ProjectDD \
            CODE_SIGNING_ALLOWED=NO

      - name: Run Non-Blocking Unit Tests
        continue-on-error: true
        run: |
          xcodebuild test-without-building \
            -project PROJECT_NAME.xcodeproj \
            -scheme SCHEME_NAME \
            -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
            -only-testing:UNIT_TEST_TARGET/NonBlockingTestSuite \
            -derivedDataPath /tmp/ProjectDD \
            CODE_SIGNING_ALLOWED=NO

  ui-tests:
    name: UI Tests
    runs-on: macos-26
    needs: unit-tests

    steps:

      - name: Checkout
        uses: actions/checkout@v4

      - name: Select Xcode
        run: |
          sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

      - name: Build UI Tests
        run: |
          xcodebuild build-for-testing \
            -project PROJECT_NAME.xcodeproj \
            -scheme SCHEME_NAME \
            -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
            -only-testing:UI_TEST_TARGET \
            -derivedDataPath /tmp/ProjectUIDD \
            CODE_SIGNING_ALLOWED=NO

      - name: Run UI Tests
        continue-on-error: true
        run: |
          xcodebuild test-without-building \
            -project PROJECT_NAME.xcodeproj \
            -scheme SCHEME_NAME \
            -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
            -only-testing:UI_TEST_TARGET \
            -derivedDataPath /tmp/ProjectUIDD \
            CODE_SIGNING_ALLOWED=NO
```

该 Workflow 只是：

> 结构基线。

实际 Project Name、Scheme、Target、Simulator OS 等必须读取当前项目后再填写。

Codex 不得凭空猜测。

---

# 101. 不要现在硬编码未来测试名称

在项目尚未创建具体 Test Suite 时，

不要提前写几十个：

```text
FileScannerTests
DuplicateHashTests
...
```

进 `.yml`。

测试 Suite 出现后再：

> 加入明确分类。

避免 CI 长期引用不存在 Test。

---

# 102. 测试增长策略

测试体系应该随项目阶段演进：

```text
Foundation
↓
Models / Pure Logic


Scanner
↓
Classification / Summary


Cleaner
↓
Deletion / Duplicate


Converter
↓
Routing / Conversion


UI Stable
↓
UI Automation
```

不要在第一天试图完成全部 Test Infrastructure。

---

# 103. Required Test 的长期目标

随着项目成熟，

应尽可能把：

```text
Non-Blocking
```

中可以稳定化的测试迁移到：

```text
Required
```

例如：

```text
Flaky filesystem test
↓
改成 temp filesystem fake
↓
Required
```

这是测试体系成熟的重要指标。

---

# 104. Non-Blocking 的长期目标

Non-Blocking 应主要保留：

- UI timing。
- OS integration。
- Performance。
- Statistical。
- Real codec。
- External system behavior。

而不是：

> 普通业务逻辑。

---

# 105. 最终测试哲学

本项目不追求：

> 测试数量最多。

而追求：

> **确定性的核心行为永远不能悄悄坏掉。**

因此：

```text
Pure Logic
→ Required

Stable Business Contract
→ Required

Fixed Seed Random
→ Required

Random Statistical
→ Non-Blocking

System Timing
→ Non-Blocking

Performance
→ Non-Blocking

UI Automation
→ 初始 Non-Blocking
```

必须始终记住：

> **Flaky 不等于可以忽略。**

> **Random 不等于不可确定。**

> **Fixed Seed Random 本质上仍然是 Deterministic。**

> **Build Failure 永远不是允许失败。**

> **Required Test Failure 必须阻塞 main。**

> **Non-Blocking Test 的价值是提供额外信号，而不是隐藏错误。**

> **本地默认只 Build，真正的 Test 统一交给 GitHub Actions。**