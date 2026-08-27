# CleanFile 项目说明与迭代复盘

> 最后更新：2026-08-26  
> 本文记录当前 App 的产品定位、真实能力、架构、关键数据流，以及迭代过程中出现过的问题与解决方案。实现状态以当前仓库代码为准；讨论过但尚未落地的能力不会被写成已完成。

## 1. App 介绍

CleanFile 是一款面向 iPhone 的本地媒体与文件管理工具，当前包含四个主要页面：

1. **媒体**：分析用户授权的照片图库，展示相似照片、视频、屏幕截图、Live Photos 和视频分类，并支持预览、播放、选择与删除。
2. **存储**：扫描用户通过系统文件选择器授权的文件夹，统计占用、按类型分类、展示文件夹层级，并支持选择与删除文件。
3. **转换**：在设备本地导入、暂存并转换图片、视频和音频，也支持从视频中提取音频。
4. **设置**：管理外观、主题、照片权限、隐私说明和版本信息。

产品遵循两个基本原则：

- **Local First**：分析和转换默认只在设备上进行，不上传用户文件。
- **Native First**：优先使用 PhotoKit、Vision、ImageIO、AVFoundation 等 Apple 公开框架；只有原生能力明确不足时，才评估第三方引擎。

### 1.1 iOS 平台边界

CleanFile 不是“扫描整个 iPhone”的工具。iOS Sandbox 不允许应用任意读取其他 App 的私有目录、系统缓存或完整文件系统。

当前能够处理的内容仅包括：

- 用户授权访问的照片图库内容。
- 用户通过系统文件选择器明确选择的文件或文件夹。
- App 自己容器内的导入文件、转换结果和状态文件。

## 2. 当前功能

### 2.1 媒体分析与清理

- 通过 PhotoKit 获取图片和视频资产。
- 识别屏幕截图与 Live Photos。
- 识别长视频、4K 视频、屏幕录制、慢动作和延时摄影。
- 使用时间序列、感知哈希和 Vision 特征距离识别相似照片。
- 详情页按拍摄日期分组展示媒体。
- 统一尺寸的相册式缩略图网格。
- 图片可查看大图，视频可播放，Live Photo 可播放。
- 支持多选、全选、显示已选空间及批量删除。
- 分析结果和稳定状态可持久化，切换 Tab 或重启 App 时尽量复用。
- iCloud 中尚未在本地可用的图片可能被跳过，并以部分失败状态呈现。

### 2.2 文件扫描与清理

- 通过 Security-Scoped URL 访问用户授权目录。
- Metadata First 扫描：优先读取类型、大小和日期，不默认读取完整文件。
- 按图片、视频、音频、文档、PDF、压缩包和其他类型统计。
- 文件按大小降序展示，便于优先定位大文件。
- 使用真实相对路径构建文件树与 Sunburst 文件夹地图。
- 支持文件多选、批量删除和部分失败处理。
- 保存目录 Bookmark、扫描结果和稳定状态，避免每次切换页面都重新扫描。

### 2.3 图片转换

当前输出模型定义了以下格式：

- JPEG
- PNG
- HEIC
- HEIF
- TIFF
- WebP
- 静态 GIF
- BMP

实际可用输出会根据当前系统中 ImageIO 报告的编码器动态过滤，避免承诺设备并不支持的格式。

图片转换还支持：

- 原尺寸或按最长边 4096、2048、1280 像素缩放。
- 可调质量（仅对有损或支持质量参数的编码器显示）。
- 保留元数据、仅移除 GPS 或移除全部元数据。
- EXIF 方向规范化。
- 对不支持透明度的格式使用白色或黑色背景铺平。
- 批量转换、取消、单文件失败隔离和文件名冲突处理。
- 临时文件写入后再提交，避免失败时留下不完整结果。

当前明确不把动画 GIF 当作普通静态图片悄悄取第一帧转换，因为这会造成不可见的数据损失。

### 2.4 视频转换

当前模型提供：

- 容器：MP4、MOV、M4V。
- 编码：H.264、HEVC、ProRes 422、ProRes 4444。
- 分辨率：原始、4K、1080p、720p、SD。

最终组合仍受设备、系统版本、源文件轨道及 AVFoundation 导出能力限制；不支持的组合会返回明确错误，不应在 UI 中过度承诺。

### 2.5 音频转换与视频转音频

当前输出格式包括：

- M4A（AAC）
- AAC 文件
- M4A（ALAC）
- WAV
- AIFF
- CAF（PCM）
- CAF（ALAC）

有损 AAC 提供 96、128、192、256 kbps 等码率选项。视频也可以作为音频来源；系统会检查音轨、受保护内容和源文件可用性。

### 2.6 导入工作区

转换页中的文件不是只保存在临时 UI 状态中。导入后会进入 App 的 Application Support 工作区，并保存对应 Manifest：

```text
Application Support
└── Media Conversion Workspace
    ├── Imports
    │   ├── image
    │   ├── video
    │   └── audio
    └── Manifests
```

因此 App 退出后可以恢复尚未处理或已处理的转换项目。用户执行“清除”时，系统只删除工作区内受控的导入副本和属于转换输出目录的结果，不会根据任意外部 URL 删除文件。

## 3. 架构

项目整体采用 **SwiftUI + MVVM + Service/Engine**。转换模块作为本地 Swift Package 集成。

```text
CleanMyIPhoneApp
│
├── ThemeSettings / Theme Environment
│
└── ContentView (TabView)
    ├── PhotosView
    │   └── PhotoLibraryViewModel
    │       ├── PhotoKit / PHCachingImageManager
    │       ├── MediaClassificationService
    │       └── AppStateStore
    │
    ├── StorageView
    │   └── FileScannerViewModel
    │       ├── MetadataFileScanner
    │       ├── FileTreeBuilder
    │       ├── FileDeletionService
    │       └── AppStateStore
    │
    ├── ImageConversionView
    │   └── ImageFormatConversionKit
    │       ├── Image / Video / Audio ViewModel
    │       ├── ConversionWorkspace
    │       ├── ConversionImportScheduler
    │       ├── ImageIO Engines
    │       └── AVFoundation Engines
    │
    └── SettingsView
        └── ThemeSettings / System Settings
```

### 3.1 View

View 负责布局、导航、选择、进度、空状态、错误状态和用户交互入口，不直接实现文件扫描、特征分析或编解码。

### 3.2 ViewModel

ViewModel 位于 `@MainActor`，维护页面可消费的状态并协调 Service/Engine：

- `PhotoLibraryViewModel`：授权、资产索引、缩略图、分析、预览、删除和媒体状态恢复。
- `FileScannerViewModel`：目录选择后的扫描事件、统计、文件树、删除和文件状态恢复。
- 转换 ViewModel：导入、工作区恢复、转换队列、进度、取消、清理和错误呈现。

### 3.3 Service / Engine

- `MediaClassificationService`：媒体分类和相似照片分析。
- `MetadataFileScanner`：流式目录枚举和元数据读取。
- `FileDeletionService`：在授权根目录范围内执行文件删除。
- `ImageConversionEngine`：ImageIO 解码、缩放、元数据处理和编码。
- `VideoConversionEngine`：AVFoundation 视频导出。
- `AudioConversionEngine`：音频转码。
- `VideoAudioExtractionEngine`：从视频音轨产生音频文件。
- `ConversionWorkspace`：导入副本、Manifest 和安全清理。
- `ConversionImportScheduler`：跨图片、视频、音频页面控制重型导入并发。

### 3.4 状态模型

媒体分析、文件扫描和删除使用明确的枚举状态，而不是一个 `isLoading` 覆盖所有情况：

```text
Idle
→ Scanning / Analyzing / Deleting
→ Success / Empty / Partial Failure / Failure / Cancelled
```

稳定结果由 `AppStateStore` 以 JSON 原子写入 Application Support。当前 Tab 使用 `@AppStorage` 保存，主题和外观使用 `UserDefaults` 保存。

## 4. 相似照片算法

当前实现不是“完全重复文件 Hash”，也没有引入云端机器学习模型，而是使用 Apple Vision 加确定性候选筛选：

1. 排除屏幕截图，并要求资产具有拍摄时间。
2. 按拍摄时间排序，把相邻时间不超过 12 秒的照片组成候选序列。
3. 请求 256×256 快速缩略图，不主动下载 iCloud 原图。
4. 计算 64 位差异哈希，汉明距离大于 16 的图片提前排除。
5. 对剩余候选使用 `VNGenerateImageFeaturePrintRequest`，接受距离不大于 0.55 的配对。
6. 每张图片只与同一序列中后续最多 10 张图片比较，避免全图库 O(n²) 比较。
7. 保守聚类，避免仅凭 A≈B、B≈C 就错误推断 A≈C。
8. 优先建议保留像素数更高的照片；分辨率相同时优先较早拍摄的照片。

这是一套工程阈值，不是适用于所有图库的数学真理。阈值需要继续使用真实图库样本校准，并重点控制误删风险。分析只产生建议，绝不自动删除。

## 5. 迭代问题与解决方案

### 5.1 切换 Tab 后反复分析

**现象**：每次离开媒体或存储页面再返回，都会重新扫描，造成等待、耗电和状态跳变。

**根因**：页面生命周期与高成本任务绑定，稳定分析结果没有独立持久化。

**解决方案**：

- 在根 `ContentView` 持有媒体与文件 ViewModel，避免 Tab 切换销毁状态。
- `loadIfNeeded` 与 `hasLoadedLibrary` 防止无意义重复加载。
- `AppStateStore` 保存媒体分析结果、目录 Bookmark、文件元数据和跳过数量。
- 只有用户主动刷新时才清理快照并重新分析。

### 5.2 App 重启后状态丢失

**现象**：关闭 App 后，媒体分析、文件扫描或转换导入列表需要重新开始。

**解决方案**：

- 媒体和文件稳定状态保存到 Application Support。
- 文件目录通过 Bookmark 恢复，并处理 Bookmark 过期后的更新。
- 转换导入文件进入持久工作区，并为三种媒体保存 Manifest。
- 主题、外观和当前 Tab 使用轻量设置持久化。

### 5.3 缩略图尺寸不一致

**现象**：横图、竖图和视频按原始宽高比参与布局，网格单元尺寸错乱。

**根因**：把图片固有尺寸当成网格布局尺寸，或只设置一侧 frame。

**解决方案**：统一网格列宽和固定单元高度，缩略图使用 `aspectFill` 并裁剪到统一容器。大图预览继续使用 `aspectFit`，避免为了网格一致性裁掉预览内容。

### 5.4 详情页日期条遮挡内容

**现象**：日期分组使用粘性 Header 后，在上下滚动时长期停留并遮挡图片。

**解决方案**：日期只作为普通分组标题参与滚动，不将所有日期标题做成持续悬浮层；导航区与内容区保持独立安全距离。

### 5.5 媒体分类信息不完整

**现象**：分类卡片只显示缩略图或标题，没有项目数、估算大小和标签；另一版本又把缩略图改成了信息列表，偏离原设计。

**解决方案**：保留四宫格缩略图卡片，在图片底部加入标题、项目数和估算空间；详细分类使用图标、数量和大小补充，但不替代主要缩略图入口。

### 5.6 删除能力缺失或删除后状态不同步

**现象**：只能看到清理建议，不能多选删除；或者删除后旧项目仍留在分析结果中。

**解决方案**：

- 媒体删除使用 `PHPhotoLibrary.performChanges`，由系统提供最终确认与权限控制。
- 文件删除只允许已扫描、且位于授权根目录中的已知 URL。
- 支持部分成功，单个失败不破坏整个批次。
- 成功删除后同步更新资产索引、分类结果、统计、文件树和持久化快照。
- 删除按钮旁显示已选项目的估算空间，并使用系统化的透明按钮表达危险操作。

### 5.7 媒体扫描性能下降

**现象**：加入相似图片分析后，扫描时间明显增长；无边界并发实验反而更慢。

**根因**：高成本主要来自缩略图请求、特征生成和候选配对，而不是视频元数据分类。过多任务会增加 PhotoKit 排队、内存、线程切换和热压力。

**解决方案**：

- 先按 12 秒拍摄序列缩小候选范围。
- 使用 256×256 快速缩略图和差异哈希预筛选。
- 只比较局部邻居，而不是全部两两比较。
- 缓存特征结果，并按资产修改时间和尺寸判断缓存是否有效。
- 特征请求采用有界并发 2；比较按 128 对批处理。
- 进度最多按约 1% 更新，避免每张图片都触发 SwiftUI 重绘。

结论是：并发不是第一优化手段。应先减少工作量、重复 I/O 和比较规模，再谨慎提高并发度。

### 5.8 存储 Sunburst 只有一圈或背景突兀

**现象**：文件夹地图看起来像普通饼图；图表还带有与主题不一致的深色矩形背景。

**根因**：扫描结果没有可靠保存相对于授权根目录的路径，文件树被拍平；Canvas 又自行绘制了不需要的背景。

**解决方案**：

- Scanner 直接保存 `relativePathComponents`。
- `FileTreeBuilder` 根据真实相对路径构建多级目录树。
- Sunburst 只负责层级布局，不猜目录关系。
- 移除图表内部固定背景，使页面主题背景自然透出。

### 5.9 转换页不知道支持哪些格式

**现象**：把所有格式写成长段说明过于冗余，不写又让用户无法判断能力；早期文案还可能把理论格式误写成真实支持。

**解决方案**：

- 只展示当前原生实现真正支持的格式。
- 输出格式使用滚轮选择器。
- 选中格式后展示简短说明、扩展名、编码或无损/有损特征。
- 图片输出再根据当前设备 ImageIO 编码器动态过滤。
- 不展示“暂不支持格式”清单，避免制造视觉噪声。

### 5.10 质量参数含义不清

**现象**：单独显示数值或滑块，用户不知道质量提高意味着什么。

**解决方案**：在质量控件附近说明质量越高通常保留更多细节、文件更大，质量越低通常文件更小、压缩痕迹更明显；无损格式不展示无意义的有损质量控制。

### 5.11 从相册导入入口缺失

**现象**：系统文件选择器只能显示“文件”位置，用户找不到照片图库里的本地照片和视频。

**解决方案**：图片和视频分别增加 PhotosPicker 入口；文件选择器继续用于 Files、iCloud Drive 和第三方 File Provider。两种来源最终都进入统一转换工作区。

### 5.12 大文件导入没有反馈、进度长期为 0%

**现象**：用户选择大文件后不知道是否已开始；早期 UI 只显示 0%，随后瞬间完成，进度与真实复制不同步。

**根因**：

- 进度只按“完成文件数”计算，没有文件内部字节进度。
- 一次性复制 API 无法持续反馈已写入字节。
- PhotosPicker 的提供者进度、App 暂存复制和最终队列进度没有映射到同一模型。
- 状态更新可能没有在主 Actor 上驱动 UI。

**解决方案**：

- 使用 `ConversionImportProgress` 同时表示已完成文件数和当前文件的分数。
- 工作区通过 `FileHandle` 分块流式复制，并按已复制字节报告进度。
- 块大小以约 1% 为目标，同时限制在 16 KiB 到 1 MiB，兼顾细粒度和 I/O 开销。
- 进度条、百分比和当前文件名使用同一状态来源。
- 对已经位于 App 支持目录中的 PhotosPicker 文件优先原子移动，避免再复制一遍。

### 5.13 多文件同时导入导致卡顿和发热

**现象**：同时导入大量图片、视频和音频时，滚动明显掉帧，设备背板发热。

**根因**：多个 Tab 的导入任务彼此独立，可能同时触发文件提供者读取、磁盘复制、元数据解析和 UI 高频更新。

**解决方案**：

- 使用全局 `ConversionImportScheduler` 跨媒体类型限制重型导入。
- 正常与轻度热状态最多允许 2 个活动操作。
- 严重或临界热状态降为 1 个操作。
- 使用流式复制，避免用 `Data(contentsOf:)` 把大文件整体载入内存。
- 原子移动已位于同卷 App 目录中的临时导入文件，减少重复 I/O。

这里不存在对所有 iPhone 都固定成立的“文件数临界值”。真正限制来自文件大小、格式、File Provider、可用内存、设备代际和热状态，因此运行时有界调度比按文件数量硬编码阈值更可靠。

### 5.14 转换列表全部显示为“图片”

**现象**：视频页显示“5 张图片”，音频页显示“1 张图片”。

**根因**：三个列表共用了图片专用的 `files.title` 本地化键。

**解决方案**：保留图片键，并为视频与音频分别使用 `files.videos.title` 和 `files.audio.title`；同步补齐七种语言资源。

### 5.15 UI 风格不统一、主题扩展后视觉廉价

**现象**：不同页面分别硬编码颜色、渐变、卡片和按钮；增加主题后浅色卡片与背景冲突，Liquid Glass 使用也不一致。

**解决方案**：

- 用独立 `Theme` 结构管理语义颜色，而不是在业务 View 中写固定颜色。
- 当前主题为 System、Cream、Porcelain、Sage、Graphite。
- 浅色纯色主题让背景与卡片使用同一基础颜色，通过细边框和层级排版区分，而不是堆叠廉价阴影或高饱和渐变。
- 系统主题可以启用 Liquid Glass；不适合玻璃效果的主题使用纯色表面。
- 转换 Package 通过 `ConversionTheme` 接收宿主主题，避免反向依赖 App。
- iOS 26 以上使用 `.scrollEdgeEffectStyle(.soft, for: .vertical)` 恢复滚动边缘的 soft 效果，旧系统保持兼容。

### 5.16 导航标题与内容顶部距离过大

**现象**：四个 Tab 顶部留白过多，标题距离状态栏和灵动岛很远。

**解决方案**：减少自定义顶部占位和不必要的大标题间距；后来根据产品要求进一步移除顶层页面标题，让内容直接进入主操作区。应依赖 Safe Area，而不是硬编码灵动岛坐标。

### 5.17 本地化键直接显示在 UI

**现象**：格式说明处出现 `format.video.mp4.detail` 等键名。

**根因**：资源缺少对应翻译、资源 Bundle 查找错误，或新增键未同步所有语言。

**解决原则**：新增 UI 文案时必须同时更新 Package 的七套资源，并确认 `L10n` 从 `Bundle.module` 读取；格式能力与计数文案采用语义明确且不跨媒体复用的键。

## 6. 主题与 UI 设计原则

- 品牌强调色为 `#E8A39C`，用于选中状态、主要按钮、进度和少量数据强调，不作为大面积页面背景。
- 优先使用系统 TabView、Sheet、Picker、PhotosPicker、文件选择器和删除确认流程。
- 卡片用于组织信息，不应让每层内容都套一层高对比背景。
- 图片网格必须统一单元尺寸；预览页则尊重媒体原始比例。
- Liquid Glass 是交互材质，不是覆盖所有区域的装饰。
- 深色与浅色主题都必须验证文本、TabBar、滚动边缘和危险按钮的可读性。

## 7. 数据安全与删除边界

- 扫描永远不自动触发删除。
- 所有删除必须由用户主动选择并确认。
- 媒体删除交由 PhotoKit 变更事务。
- 文件删除只能处理当前授权根目录中的扫描结果。
- 转换清理只能删除 App 工作区和已知输出根目录内的文件。
- 批量删除必须允许部分失败，并向 UI 报告成功与失败数量。
- Security-Scoped Resource 的开始和结束访问必须配对。
- 不记录用户文件内容、完整敏感路径、Bookmark 数据或媒体二进制内容。

## 8. 并发与性能策略

项目的优化顺序是：

```text
减少工作量
→ 避免重复扫描与重复复制
→ 缓存稳定结果
→ 流式与增量处理
→ 批处理 UI 更新
→ 最后使用有界并发
```

禁止为每个文件无限创建 Task。主 Actor 只维护 SwiftUI 状态和协调业务；大规模 I/O、Hash、特征计算和编解码不应长期阻塞主线程。

## 9. 测试与 CI

- Unit Test 使用 Swift Testing。
- UI Test 使用 XCTest / XCUITest。
- 图片转换引擎测试位于 `ImageConversionEngineTests.swift`。
- 导入进度具有 Debug 专用测试 Harness，用于验证百分比和进度条 UI。
- GitHub Actions 在 Pull Request 和 Push 到 `main` 时执行 Build、Unit Tests 和 UI Tests。
- 按项目规则，本地默认只允许 Build/Compile；未经用户针对当前任务明确授权，不运行本地测试。

## 10. 当前限制与待继续验证事项

1. 相似照片阈值仍需使用更大规模真实图库验证误报率和漏报率。
2. iCloud 原件未下载时，分析和导入取决于 PhotoKit/File Provider 的可用性；当前媒体相似度分析不会强制下载原图。
3. 视频和音频格式组合由 AVFoundation 和当前设备能力决定，不代表任意源格式都能转换为任意目标格式。
4. 动画图片的完整逐帧转换尚未实现。
5. 当前没有 FFmpeg，因此 MKV、WebM、OGG、FLAC 等非原生链路不能被笼统承诺为完整支持。
6. 导入并发上限 2 是当前面向流畅度和温度的保守策略，后续应通过 Instruments、不同设备和真实大文件基准继续校准。
7. 当前编译仍存在一个与 Swift 6 Actor 隔离相关的 warning：`FeatureCacheKey` 的 `Equatable` 隔离语义需要后续独立处理；它不应与无关 UI 任务混在一起修改。

## 11. 关键文件索引

```text
CleanMyIPhone/
├── CleanMyIPhoneApp.swift          App 入口与主题注入
├── ContentView.swift               四个顶层 Tab
├── AppTheme.swift                  主题 Token、主题持久化与 soft 边缘
├── AppStateStore.swift             媒体/文件稳定状态持久化
├── PhotoLibraryViewModel.swift     PhotoKit、媒体状态、预览与删除
├── MediaClassificationService.swift 相似图片与视频分类
├── MetadataFileScanner.swift       文件元数据扫描
├── FileScannerViewModel.swift      文件扫描页面状态与恢复
├── FileDeletionService.swift       安全文件删除
├── FileTree.swift                  真实目录树
└── View.swift                      Sunburst 文件夹地图

Packages/ImageFormatConversionKit/
├── ImageConversionEngine.swift
├── VideoConversionEngine.swift
├── AudioConversionEngine.swift
├── VideoAudioExtractionEngine.swift
├── ConversionWorkspace.swift
├── ConversionImportScheduler.swift
├── ConversionImportProgress.swift
├── Image/Video/AudioConversionViewModel.swift
├── Image/Video/AudioConversionView.swift
└── Resources/*.lproj/Localizable.strings
```

## 12. 后续迭代准则

每次继续开发时，应先确认：

1. 需求是否符合 iOS 公开能力与 Sandbox。
2. 当前代码是否已经有可复用状态、缓存或服务。
3. 问题根因是数据、状态、并发、I/O、布局还是本地化。
4. 能否通过最小修改解决，而不重写正常模块。
5. 是否会影响用户文件安全、删除边界或持久化兼容性。
6. UI 展示的能力是否与底层真实支持严格一致。
7. Build 与 Test 的验证结果是否被准确区分。

本项目的最终优先级始终是：

```text
正确性
> 用户文件安全
> 数据完整性
> 稳定性
> 可维护性
> 性能
> 视觉效果
```
