//
//  ConvertHomeVariants.swift
//  「转换」主页的 5 种设计变体 —— 用于横向对比选型
//
//  ⚠️ 依赖说明：本文件需与 ConvertHome.swift 加入同一 Target（复用其中的
//     MediaKind / ConvertTheme / PressableCardStyle / convertCard() /
//     ImageConvertView / ComingSoonView / SupportedFormatsSheet）。
//
//  变体总览：
//     1. RichCardHomeView      富信息大卡版（原版升级：格式胶囊 + 最近使用）
//     2. HeroGridHomeView      主推 Hero + 双小卡（图片做视觉焦点，层级分明）
//     3. RecentToolsHomeView   最近转换优先（先历史后工具，面向高频用户）
//     4. GridHomeView          双列网格（紧凑工具面板，预留「更多格式」格）
//     5. SettingsStyleHomeView 原生设置风（List 分组，维护成本最低）
//
//  每个变体都是完整独立页面，Xcode Canvas 可切换 5 个 #Preview 对比。
//

import SwiftUI

// MARK: - 0. 公共扩展与小组件（5 个变体共用）
//
//  ConvertHome.swift
//  「转换」模块：主页（三张媒体卡片）+ 图片/视频/音频 次级转换页
//
//  环境要求：iOS 17+ / Xcode 15+（#Preview 宏）
//  用法：新建一个 SwiftUI 文件，粘贴全部代码，打开 Canvas 即可切换多个预览。
//  接入现有 App：把「转换」Tab 的内容替换为 ConvertHomeView() 即可。
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - 1. 主题色板（想换肤只改这一个 enum）

enum ConvertTheme {
    /// 页面底色：暖米色（对应截图背景）
    static let background    = Color(red: 0.961, green: 0.941, blue: 0.910)   // ≈ #F5F0E8
    /// 卡片底色：米白
    static let card          = Color(red: 1.000, green: 0.992, blue: 0.965)   // ≈ #FFFDF7
    /// 强调色：金棕（截图中的选中态颜色）
    static let accent        = Color(red: 0.620, green: 0.478, blue: 0.302)   // ≈ #9E7A4D
    /// 强调色浅底：图标容器、选中态背景
    static let accentSoft    = Color(red: 0.620, green: 0.478, blue: 0.302).opacity(0.13)
    /// 主文字：暖黑
    static let primaryText   = Color(red: 0.170, green: 0.150, blue: 0.125)   // ≈ #2B2620
    /// 次要文字：暖灰
    static let secondaryText = Color(red: 0.541, green: 0.502, blue: 0.451)   // ≈ #8A8073
    /// 按钮底色：比背景深一档的米色
    static let control       = Color(red: 0.925, green: 0.898, blue: 0.847)   // ≈ #ECE5D8
    /// 卡片阴影（极浅，保持柔和质感）
    static let cardShadow    = Color.black.opacity(0.05)
}

// MARK: - 2. 媒体类型（枚举驱动：以后加 PDF/字幕，只需加一个 case + 一个子页面）

enum MediaKind: String, CaseIterable, Identifiable, Hashable {
    case image, video, audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .image: return "图片转换"
        case .video: return "视频转换"
        case .audio: return "音频转换"
        }
    }

    var icon: String {
        switch self {
        case .image: return "photo.on.rectangle.angled"
        case .video: return "video.fill"
        case .audio: return "waveform"
        }
    }

    /// 占位页展示的「将支持格式」标签
    var plannedFormats: [String] {
        switch self {
        case .image: return ["HEIC", "JPEG", "PNG", "WebP"]
        case .video: return ["MP4", "MOV", "HEVC", "MKV"]
        case .audio: return ["MP3", "AAC", "WAV", "FLAC"]
        }
    }
}

// MARK: - 3. 通用组件：按压缩放反馈 + 大圆角卡片容器

/// iOS 标准触感：按下轻微缩小 + 变透明，松手 spring 回弹
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.75),
                       value: configuration.isPressed)
    }
}

/// 统一的大圆角卡片样式（截图同款：24 圆角 + 极浅阴影）
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(ConvertTheme.card)
                    .shadow(color: ConvertTheme.cardShadow, radius: 12, x: 0, y: 5)
            )
    }
}

extension View {
    func convertCard() -> some View { modifier(CardBackground()) }
}

// MARK: - 4. 转换主页（只有三张媒体卡片）

struct ConvertHomeView: View {
    /// 控制三张卡片的入场动画
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                ConvertTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(Array(MediaKind.allCases.enumerated()),
                                    id: \.element) { index, kind in
                                NavigationLink(value: kind) {
                                    ConvertCard(kind: kind)
                                }
                                .buttonStyle(PressableCardStyle())
                                // 入场：错峰渐现 + 上浮
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 22)
                                .animation(
                                    .spring(response: 0.5, dampingFraction: 0.85)
                                        .delay(Double(index) * 0.07 + 0.05),
                                    value: appeared
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize)

                    privacyFooter
                }
            }
            // 主页自带大标题，隐藏系统导航栏；次级页仍保留返回按钮
            .toolbar(.hidden, for: .navigationBar)
            // 类型安全路由：由 MediaKind 决定推入哪个次级页
            .navigationDestination(for: MediaKind.self) { kind in
                switch kind {
                case .image: ImageConvertView()
                case .video: ComingSoonView(kind: .video)
                case .audio: ComingSoonView(kind: .audio)
                }
            }
        }
        .task { appeared = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("转换")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(ConvertTheme.primaryText)
            Text("选择要转换的媒体类型")
                .font(.subheadline)
                .foregroundStyle(ConvertTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    /// 隐私脚注常驻：本地处理是这类工具的核心卖点，值得在入口页反复强调
    private var privacyFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.footnote.weight(.medium))
            Text("文件只在此设备上处理，不会上传")
                .font(.footnote)
        }
        .foregroundStyle(ConvertTheme.secondaryText)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }
}

// MARK: - 5. 主页卡片（极简：图标 + 标题 + 箭头）

struct ConvertCard: View {
    let kind: MediaKind

    var body: some View {
        HStack(spacing: 16) {
            // 图标容器：浅金棕底 squircle + 强调色 SF Symbol
            Image(systemName: kind.icon)
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(ConvertTheme.accent)
                .frame(width: 56, height: 56)
                .background(
                    ConvertTheme.accentSoft,
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )

            Text(kind.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ConvertTheme.primaryText)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(ConvertTheme.secondaryText.opacity(0.6))
        }
        .convertCard()
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - 6. 图片转换页（完整还原截图：文件来源 + 转换设置）

/// 输出格式
enum OutputFormat: String, CaseIterable, Identifiable, Hashable {
    case jpeg = "JPEG"
    case png  = "PNG"
    case heic = "HEIC"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .jpeg: return ".jpg"
        case .png:  return ".png"
        case .heic: return ".heic"
        }
    }

    var note: String {
        switch self {
        case .jpeg: return "体积较小且兼容性广，但不支持透明背景。"
        case .png:  return "无损质量，支持透明背景，体积较大。"
        case .heic: return "高压缩率与高质量，适合 Apple 生态。"
        }
    }
}

/// 透明区域填充色（转 JPEG 等不支持透明的格式时生效）
enum TransparentFill: String, CaseIterable, Identifiable, Hashable {
    case white = "白色"
    case black = "黑色"

    var id: String { rawValue }
}

struct ImageConvertView: View {
    // MARK: 转换设置状态（真实工程可抽成 ObservableObject / @Observable）
    @State private var outputFormat: OutputFormat = .jpeg
    @State private var removeGPS = true
    @State private var keepOriginalSize = true
    @State private var quality: Double = 85
    @State private var transparentFill: TransparentFill = .white
    @State private var outputFolder = "Converted Images"

    // MARK: 弹层与选择器状态
    @State private var showOutputFormatSheet = false
    @State private var showSupportedFormatsSheet = false
    @State private var showFileImporter = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                privacyBar
                sourceCard
                settingsCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(ConvertTheme.background.ignoresSafeArea())
        .navigationTitle("图片转换")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ConvertTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(ConvertTheme.accent)
        .sheet(isPresented: $showOutputFormatSheet) {
            OutputFormatSheet(
                format: $outputFormat,
                removeGPS: $removeGPS,
                keepOriginalSize: $keepOriginalSize
            )
        }
        .sheet(isPresented: $showSupportedFormatsSheet) {
            SupportedFormatsSheet()
        }
        // 「从文件选择」：系统文件选择器
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                // TODO: 拿到 URL 后执行真正的转换
                print("已选择文件：\(urls.map(\.lastPathComponent))")
            case .failure(let error):
                print("选择失败：\(error.localizedDescription)")
            }
        }
        // 「从相册选择」：拿到 PhotosPickerItem 后读取数据
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            // TODO: item.loadDataRepresentation { ... } 拿到 Data 后执行转换
            print("已从相册选择 1 张图片")
            photoItem = nil
        }
    }

    // MARK: 隐私提示条（截图同款）

    private var privacyBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.footnote)
            Text("文件只在此设备上处理，不会上传。")
                .font(.footnote)
            Spacer(minLength: 8)
            Button {
                showSupportedFormatsSheet = true
            } label: {
                Text("查看格式")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ConvertTheme.accent)
                    .underline()
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(ConvertTheme.secondaryText)
    }

    // MARK: 文件选择卡片（截图同款：相机图标 + 两个来源按钮）

    private var sourceCard: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(ConvertTheme.accent)
                    .frame(width: 62, height: 62)
                    .background(
                        ConvertTheme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 19, style: .continuous)
                    )
                Text("在本地转换图片")
                    .font(.headline)
                    .foregroundStyle(ConvertTheme.primaryText)
            }

            HStack(spacing: 12) {
                Button {
                    showFileImporter = true
                } label: {
                    Label("从文件选择", systemImage: "folder")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ConvertTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            ConvertTheme.control,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
                .buttonStyle(PressableCardStyle())

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("从相册选择", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ConvertTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            ConvertTheme.control,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
                .buttonStyle(PressableCardStyle())
            }
        }
        .convertCard()
    }

    // MARK: 转换设置卡片（输出格式 / 压缩质量 / 透明区域 / 输出文件夹）

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("转换设置")
                .font(.headline)
                .foregroundStyle(ConvertTheme.primaryText)
                .padding(.bottom, 14)

            // ── 输出格式（点按弹出格式与选项设置） ──
            Button {
                showOutputFormatSheet = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("输出格式")
                            .font(.body)
                            .foregroundStyle(ConvertTheme.primaryText)
                        Spacer()
                        Text(formatSummary)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ConvertTheme.accent)
                            .lineLimit(1)
                    }
                    Text("\(outputFormat.fileExtension) · \(outputFormat.note)")
                        .font(.footnote)
                        .foregroundStyle(ConvertTheme.secondaryText)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            hairline

            // ── 压缩质量（滑块 + 三档说明） ──
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("压缩质量")
                        .foregroundStyle(ConvertTheme.primaryText)
                    Spacer()
                    Text("\(Int(quality))%")
                        .monospacedDigit()          // 滑动时数字不抖动
                        .foregroundStyle(ConvertTheme.accent)
                }
                .font(.body)

                Slider(value: $quality, in: 1...100, step: 1)
                    .tint(ConvertTheme.accent)

                HStack {
                    Text("体积更小")
                    Spacer()
                    Text("平衡")
                    Spacer()
                    Text("质量最佳")
                }
                .font(.caption2)
                .foregroundStyle(ConvertTheme.secondaryText)
            }
            .padding(.vertical, 14)

            hairline

            // ── 透明区域（白/黑 分段选择） ──
            HStack {
                Text("透明区域")
                    .font(.body)
                    .foregroundStyle(ConvertTheme.primaryText)
                Spacer()
                Picker("透明区域", selection: $transparentFill) {
                    ForEach(TransparentFill.allCases) { fill in
                        Text(fill.rawValue).tag(fill)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .tint(ConvertTheme.accent)
            }
            .padding(.vertical, 10)

            hairline

            // ── 输出文件夹 ──
            Button {
                // TODO: 接入你自己的文件夹选择器（如 UIDocumentPickerViewController）
            } label: {
                HStack {
                    Text("输出文件夹")
                        .font(.body)
                        .foregroundStyle(ConvertTheme.primaryText)
                    Spacer()
                    Text(outputFolder)
                        .font(.subheadline)
                        .foregroundStyle(ConvertTheme.secondaryText)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ConvertTheme.secondaryText.opacity(0.6))
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .convertCard()
    }

    /// 卡片内分隔线（比系统 Divider 更贴合暖色主题）
    private var hairline: some View {
        Rectangle()
            .fill(ConvertTheme.primaryText.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 6)
    }

    /// 汇总行文案，如「JPEG · 移除 GPS · 保持原始尺寸」（截图同款）
    private var formatSummary: String {
        var parts = [outputFormat.rawValue]
        if removeGPS { parts.append("移除 GPS") }
        if keepOriginalSize { parts.append("保持原始尺寸") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 7. 输出格式弹窗（格式选择 + 移除 GPS / 保持原始尺寸）

struct OutputFormatSheet: View {
    @Binding var format: OutputFormat
    @Binding var removeGPS: Bool
    @Binding var keepOriginalSize: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 格式列表
                    VStack(spacing: 0) {
                        ForEach(OutputFormat.allCases) { item in
                            Button {
                                format = item
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.rawValue)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(ConvertTheme.primaryText)
                                        Text("\(item.fileExtension) · \(item.note)")
                                            .font(.footnote)
                                            .foregroundStyle(ConvertTheme.secondaryText)
                                    }
                                    Spacer()
                                    Image(systemName: format == item
                                          ? "checkmark.circle.fill"
                                          : "circle")
                                        .font(.title3)
                                        .foregroundStyle(format == item
                                                         ? ConvertTheme.accent
                                                         : ConvertTheme.secondaryText.opacity(0.4))
                                }
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if item != OutputFormat.allCases.last {
                                Rectangle()
                                    .fill(ConvertTheme.primaryText.opacity(0.08))
                                    .frame(height: 1)
                            }
                        }
                    }
                    .convertCard()

                    // 转换选项
                    VStack(spacing: 4) {
                        Toggle(isOn: $removeGPS) {
                            settingLabel("移除 GPS 位置信息",
                                         subtitle: "转换时清除照片的拍摄地点信息")
                        }
                        .tint(ConvertTheme.accent)
                        .padding(.vertical, 8)

                        Rectangle()
                            .fill(ConvertTheme.primaryText.opacity(0.08))
                            .frame(height: 1)

                        Toggle(isOn: $keepOriginalSize) {
                            settingLabel("保持原始尺寸",
                                         subtitle: "关闭后可在转换时缩放图片")
                        }
                        .tint(ConvertTheme.accent)
                        .padding(.vertical, 8)
                    }
                    .convertCard()
                }
                .padding(20)
            }
            .background(ConvertTheme.background.ignoresSafeArea())
            .navigationTitle("输出格式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ConvertTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(ConvertTheme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(ConvertTheme.background)
    }

    private func settingLabel(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body)
                .foregroundStyle(ConvertTheme.primaryText)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(ConvertTheme.secondaryText)
        }
    }
}

// MARK: - 8. 支持的输入格式弹窗（「查看格式」入口）

struct SupportedFormatsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let formats: [(name: String, note: String)] = [
        ("HEIC / HEIF", "iPhone 默认拍摄格式"),
        ("JPEG", "兼容性最广的通用格式"),
        ("PNG", "无损、支持透明背景"),
        ("WebP", "现代网页格式，体积小"),
        ("GIF", "动图（转换时取首帧）"),
        ("TIFF / BMP", "专业与旧式格式"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(formats, id: \.name) { item in
                        HStack {
                            Text(item.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(ConvertTheme.primaryText)
                            Spacer()
                            Text(item.note)
                                .font(.footnote)
                                .foregroundStyle(ConvertTheme.secondaryText)
                        }
                        .padding(.vertical, 12)

                        if item.name != formats.last?.name {
                            Rectangle()
                                .fill(ConvertTheme.primaryText.opacity(0.08))
                                .frame(height: 1)
                        }
                    }
                }
                .convertCard()
                .padding(20)

                Text("输出格式与压缩质量可在「转换设置」中调整。")
                    .font(.footnote)
                    .foregroundStyle(ConvertTheme.secondaryText)
                    .padding(.horizontal, 24)
            }
            .background(ConvertTheme.background.ignoresSafeArea())
            .navigationTitle("支持的格式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ConvertTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(ConvertTheme.accent)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(ConvertTheme.background)
    }
}

// MARK: - 9. 视频 / 音频占位页（结构与风格就绪，功能待填充）

struct ComingSoonView: View {
    let kind: MediaKind

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: kind.icon)
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(ConvertTheme.accent)
                .frame(width: 96, height: 96)
                .background(
                    ConvertTheme.accentSoft,
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                )

            VStack(spacing: 8) {
                Text(kind.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ConvertTheme.primaryText)
                Text("页面打磨中，将支持以下格式的本地转换。")
                    .font(.subheadline)
                    .foregroundStyle(ConvertTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            // 将支持格式的标签胶囊
            HStack(spacing: 8) {
                ForEach(kind.plannedFormats, id: \.self) { format in
                    Text(format)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ConvertTheme.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(ConvertTheme.control, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ConvertTheme.background.ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ConvertTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(ConvertTheme.accent)
    }
}

// MARK: - 10. 预览（Xcode Canvas 中可切换）

#Preview("转换主页") {
    ConvertHomeView()
}

#Preview("图片转换") {
    NavigationStack {
        ImageConvertView()
    }
}

#Preview("输出格式弹窗") {
    OutputFormatSheet(
        format: .constant(.jpeg),
        removeGPS: .constant(true),
        keepOriginalSize: .constant(true)
    )
}

#Preview("视频转换（占位）") {
    NavigationStack {
        ComingSoonView(kind: .video)
    }
}

#Preview("音频转换（占位）") {
    NavigationStack {
        ComingSoonView(kind: .audio)
    }
}




extension MediaKind {
    /// 一句话功能说明
    var tagline: String {
        switch self {
        case .image: return "HEIC 互转 · 压缩 · 去 GPS"
        case .video: return "MP4 / MOV · 压缩 · 提取音频"
        case .audio: return "MP3 / AAC / WAV 互转"
        }
    }

    /// 最近使用文案（nil = 从未用过；真实工程从数据库读取）
    var recentUsage: String? {
        switch self {
        case .image: return "2 小时前 · 转换过 3 个文件"
        case .video: return nil
        case .audio: return "昨天 · 转换过 1 个文件"
        }
    }

    /// 每种媒体一组暖色渐变（金棕 / 赤陶 / 鼠尾青），与米色底和谐但彼此可区分
    var warmColors: [Color] {
        switch self {
        case .image: return [Color(red: 0.80, green: 0.62, blue: 0.38),   // 金棕
                             Color(red: 0.62, green: 0.45, blue: 0.28)]
        case .video: return [Color(red: 0.77, green: 0.45, blue: 0.32),   // 赤陶
                             Color(red: 0.59, green: 0.32, blue: 0.22)]
        case .audio: return [Color(red: 0.42, green: 0.56, blue: 0.50),   // 鼠尾青
                             Color(red: 0.28, green: 0.41, blue: 0.36)]
        }
    }

    var warmGradient: LinearGradient {
        LinearGradient(colors: warmColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 图标投影色（带一点媒体自身色相，比纯黑阴影更精致）
    var warmShadow: Color { warmColors[1].opacity(0.32) }
}

/// 渐变图标徽章（各变体通用）
struct GradientIconBadge: View {
    let kind: MediaKind
    var size: CGFloat = 54
    var cornerRadius: CGFloat = 16

    var body: some View {
        Image(systemName: kind.icon)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(kind.warmGradient,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: kind.warmShadow, radius: 6, x: 0, y: 3)
    }
}

/// 入场动效：错峰渐现 + 上浮（每个条目自带状态，无需外部协调）
struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 22)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)
                    .delay(Double(index) * 0.07 + 0.05)) { shown = true }
            }
    }
}

extension View {
    func staggeredAppear(index: Int) -> some View { modifier(StaggeredAppear(index: index)) }

    /// 统一路由：MediaKind → 对应次级页（复用 ConvertHome.swift 中的页面）
    func convertRouting() -> some View {
        navigationDestination(for: MediaKind.self) { kind in
            switch kind {
            case .image: ImageConvertView()
            case .video: ComingSoonView(kind: .video)
            case .audio: ComingSoonView(kind: .audio)
            }
        }
    }
}

/// 隐私脚注（通用）
struct PrivacyFootnote: View {
    var body: some View {
        Label("文件只在此设备上处理，不会上传", systemImage: "lock.shield")
            .font(.footnote)
            .foregroundStyle(ConvertTheme.secondaryText)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - 1. 变体一：富信息大卡版
//
// 设计意图：保持纵向大卡片的布局惯性，在「信息密度」上做增量——
// 每张卡从 1 行扩成 3 层：图标+标题副标题 / 格式胶囊 / 最近使用脚注。
// 用户点进次级页之前就能判断「能不能转我的格式」「上次是什么时候用的」。

struct RichCardHomeView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                ConvertTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(Array(MediaKind.allCases.enumerated()),
                                id: \.element) { index, kind in
                            NavigationLink(value: kind) {
                                RichMediaCard(kind: kind)
                            }
                            .buttonStyle(PressableCardStyle())
                            .staggeredAppear(index: index)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
            }
            .navigationTitle("转换")
            .toolbarBackground(ConvertTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(ConvertTheme.accent)
            .convertRouting()
        }
    }
}

/// 富信息卡片：渐变图标 + 标题副标题 + 格式胶囊 + 最近使用脚注
struct RichMediaCard: View {
    let kind: MediaKind

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 第一层：图标 + 标题 + 一句话说明 + 箭头
            HStack(spacing: 14) {
                GradientIconBadge(kind: kind)

                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ConvertTheme.primaryText)
                    Text(kind.tagline)
                        .font(.footnote)
                        .foregroundStyle(ConvertTheme.secondaryText)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ConvertTheme.secondaryText.opacity(0.6))
            }

            // 第二层：支持格式胶囊
            HStack(spacing: 6) {
                ForEach(kind.plannedFormats, id: \.self) { format in
                    Text(format)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ConvertTheme.secondaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(ConvertTheme.control, in: Capsule())
                }
            }

            // 第三层：最近使用（有记录才显示，让卡片呈现「活」的状态）
            if let recent = kind.recentUsage {
                VStack(alignment: .leading, spacing: 10) {
                    Rectangle()
                        .fill(ConvertTheme.primaryText.opacity(0.08))
                        .frame(height: 1)
                    Label(recent, systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(ConvertTheme.secondaryText)
                }
            }
        }
        .convertCard()
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - 2. 变体二：主推 Hero + 双小卡
//
// 设计意图：用「视觉权重」表达优先级——图片转换是最高频功能，
// 给它一张深金棕渐变 Hero 大卡（带装饰圆 + 「最常用」徽标）；
// 视频/音频降为半宽小卡。层级一眼分明，页面也更像「被设计过」。

struct HeroGridHomeView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                ConvertTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        heroCard
                            .staggeredAppear(index: 0)

                        HStack(spacing: 14) {
                            smallCard(.video)
                            smallCard(.audio)
                        }
                        .staggeredAppear(index: 1)

                        PrivacyFootnote()
                            .staggeredAppear(index: 2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
            }
            .navigationTitle("转换")
            .toolbarBackground(ConvertTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(ConvertTheme.accent)
            .convertRouting()
        }
    }

    /// Hero 卡：图片转换（深金棕渐变底 + 装饰圆 + 白色文字）
    private var heroCard: some View {
        NavigationLink(value: MediaKind.image) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    // 半透明徽标：在深色渐变上比再叠一层渐变更干净
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(.white.opacity(0.18),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Spacer()
                    Text("最常用")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.18), in: Capsule())
                }

                Text("图片转换")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)

                Text("HEIC / PNG / WebP 本地互转，可调压缩质量并移除 GPS。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))

                HStack(spacing: 6) {
                    ForEach(["HEIC", "PNG", "WebP"], id: \.self) { format in
                        Text(format)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.16), in: Capsule())
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.72, green: 0.53, blue: 0.30),
                                                  Color(red: 0.46, green: 0.31, blue: 0.18)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(.white.opacity(0.08))
                            .frame(width: 150, height: 150)
                            .offset(x: 45, y: -55)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Circle()
                            .fill(.white.opacity(0.05))
                            .frame(width: 100, height: 100)
                            .offset(x: -30, y: 40)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            )
            .shadow(color: MediaKind.image.warmShadow, radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PressableCardStyle())
    }

    /// 半宽小卡：视频 / 音频
    private func smallCard(_ kind: MediaKind) -> some View {
        NavigationLink(value: kind) {
            VStack(spacing: 10) {
                GradientIconBadge(kind: kind, size: 46, cornerRadius: 14)
                Text(kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ConvertTheme.primaryText)
                Text(kind.plannedFormats.prefix(3).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(ConvertTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .convertCard()
        }
        .buttonStyle(PressableCardStyle())
    }
}

// MARK: - 3. 变体三：最近转换优先
//
// 设计意图：面向「重复任务」——用户常转同类文件（如批量 HEIC→JPEG）。
// 顶部先给最近转换历史（点一行直接进对应工具），下方才是工具列表。
// 清空按钮带动画，空状态有占位文案，这套状态切换值得保留。

private struct RecentItem: Identifiable {
    let id = UUID()
    let fileName: String
    let from: String
    let to: String
    let time: String
    let kind: MediaKind
}

struct RecentToolsHomeView: View {
    @State private var recentItems: [RecentItem] = [
        RecentItem(fileName: "IMG_0412.HEIC", from: "HEIC", to: "JPEG", time: "2 小时前", kind: .image),
        RecentItem(fileName: "海边日落.MOV", from: "MOV", to: "MP4", time: "昨天", kind: .video),
        RecentItem(fileName: "录音_0513.M4A", from: "M4A", to: "MP3", time: "3 天前", kind: .audio),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                ConvertTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        recentSection
                            .staggeredAppear(index: 0)
                        toolsSection
                            .staggeredAppear(index: 1)
                        PrivacyFootnote()
                            .staggeredAppear(index: 2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
            }
            .navigationTitle("转换")
            .toolbarBackground(ConvertTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(ConvertTheme.accent)
            .convertRouting()
        }
    }

    // MARK: 最近转换（可清空，带动画）

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近转换")
                    .font(.headline)
                    .foregroundStyle(ConvertTheme.primaryText)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        recentItems.removeAll()
                    }
                } label: {
                    Text("清空")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(ConvertTheme.accent)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                if recentItems.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "tray")
                        Text("暂无转换记录，从下面的工具开始吧")
                    }
                    .font(.footnote)
                    .foregroundStyle(ConvertTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                } else {
                    ForEach(recentItems) { item in
                        NavigationLink(value: item.kind) {
                            RecentItemRow(item: item)
                        }
                        .buttonStyle(.plain)

                        if item.id != recentItems.last?.id {
                            Rectangle()
                                .fill(ConvertTheme.primaryText.opacity(0.08))
                                .frame(height: 1)
                                .padding(.leading, 54)   // 与图标列对齐
                        }
                    }
                }
            }
            .convertCard()
        }
    }

    // MARK: 转换工具（单行紧凑列表）

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("转换工具")
                .font(.headline)
                .foregroundStyle(ConvertTheme.primaryText)

            VStack(spacing: 0) {
                ForEach(MediaKind.allCases) { kind in
                    NavigationLink(value: kind) {
                        HStack(spacing: 12) {
                            GradientIconBadge(kind: kind, size: 42, cornerRadius: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(ConvertTheme.primaryText)
                                Text(kind.tagline)
                                    .font(.caption)
                                    .foregroundStyle(ConvertTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ConvertTheme.secondaryText.opacity(0.6))
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if kind != MediaKind.allCases.last {
                        Rectangle()
                            .fill(ConvertTheme.primaryText.opacity(0.08))
                            .frame(height: 1)
                            .padding(.leading, 54)
                    }
                }
            }
            .convertCard()
        }
    }
}

/// 历史行：文件图标 + 文件名 + 转换方向 + 时间
private struct RecentItemRow: View {
    let item: RecentItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(item.kind.warmGradient,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ConvertTheme.primaryText)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(item.from)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(item.to)
                    Text("· \(item.time)")
                }
                .font(.caption)
                .foregroundStyle(ConvertTheme.secondaryText)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ConvertTheme.secondaryText.opacity(0.6))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - 4. 变体四：双列网格
//
// 设计意图：紧凑「工具面板」气质，2×2 恰好 3 个工具 + 1 个预告位
// （虚线边框的「更多格式」幽灵格）。当未来加入 PDF / 字幕转换时，
// 只需把幽灵格替换成真实瓦片，再追加一行网格即可，扩展成本最低。

struct GridHomeView: View {
    private let columns = [GridItem(.flexible(), spacing: 14),
                           GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ZStack {
                ConvertTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(Array(MediaKind.allCases.enumerated()),
                                    id: \.element) { index, kind in
                                gridTile(kind)
                                    .staggeredAppear(index: index)
                            }
                            comingTile
                                .staggeredAppear(index: 3)
                        }
                        PrivacyFootnote()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
            }
            .navigationTitle("转换")
            .toolbarBackground(ConvertTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(ConvertTheme.accent)
            .convertRouting()
        }
    }

    /// 网格瓦片：居中图标 + 标题 + 说明，卡片底色带一丝媒体自身色相
    private func gridTile(_ kind: MediaKind) -> some View {
        NavigationLink(value: kind) {
            VStack(spacing: 10) {
                GradientIconBadge(kind: kind, size: 56, cornerRadius: 18)
                Text(kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ConvertTheme.primaryText)
                Text(kind.tagline)
                    .font(.caption2)
                    .foregroundStyle(ConvertTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(ConvertTheme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(kind.warmColors[0].opacity(0.05))
                    )
                    .shadow(color: ConvertTheme.cardShadow, radius: 12, x: 0, y: 5)
            )
        }
        .buttonStyle(PressableCardStyle())
    }

    /// 第 4 格：更多格式预告（虚线幽灵格，不可点击）
    private var comingTile: some View {
        VStack(spacing: 10) {
            Image(systemName: "ellipsis")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(ConvertTheme.secondaryText)
                .frame(width: 56, height: 56)
                .background(ConvertTheme.control.opacity(0.7),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("更多格式")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ConvertTheme.secondaryText)
            Text("PDF · 字幕 · 敬请期待")
                .font(.caption2)
                .foregroundStyle(ConvertTheme.secondaryText.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(ConvertTheme.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(ConvertTheme.primaryText.opacity(0.15),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                )
        )
    }
}

// MARK: - 5. 变体五：原生设置风
//
// 设计意图：完全交给系统组件（insetGrouped List）。
// 行高、分隔线、点击态、无障碍全是系统级质感，代码量和维护成本最低，
// 也最容易跟 App 其他设置页保持一致。代价是「个性」最弱。

struct SettingsStyleHomeView: View {
    @State private var showFormats = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(MediaKind.allCases) { kind in
                        NavigationLink(value: kind) {
                            HStack(spacing: 14) {
                                GradientIconBadge(kind: kind, size: 40, cornerRadius: 11)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kind.title)
                                        .foregroundStyle(ConvertTheme.primaryText)
                                    Text(kind.tagline)
                                        .font(.footnote)
                                        .foregroundStyle(ConvertTheme.secondaryText)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listRowBackground(ConvertTheme.card)
                } header: {
                    Text("转换工具")
                } footer: {
                    Text("所有转换在本设备完成，文件不会上传。")
                }

                Section {
                    Button {
                        showFormats = true
                    } label: {
                        HStack {
                            Text("支持的输入格式")
                                .foregroundStyle(ConvertTheme.primaryText)
                            Spacer()
                            Text("HEIC · JPEG · PNG · WebP")
                                .font(.footnote)
                                .foregroundStyle(ConvertTheme.secondaryText)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ConvertTheme.secondaryText.opacity(0.6))
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(ConvertTheme.card)
                } header: {
                    Text("通用")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(ConvertTheme.background.ignoresSafeArea())
            .navigationTitle("转换")
            .tint(ConvertTheme.accent)
            .toolbarBackground(ConvertTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .convertRouting()
            .sheet(isPresented: $showFormats) { SupportedFormatsSheet() }
        }
    }
}

// MARK: - 6. 预览（Canvas 中切换 5 个变体对比）

#Preview("变体 1 · 富信息大卡") {
    RichCardHomeView()
}

#Preview("变体 2 · Hero + 双小卡") {
    HeroGridHomeView()
}

#Preview("变体 3 · 最近转换优先") {
    RecentToolsHomeView()
}

#Preview("变体 4 · 双列网格") {
    GridHomeView()
}

#Preview("变体 5 · 原生设置风") {
    SettingsStyleHomeView()
}
