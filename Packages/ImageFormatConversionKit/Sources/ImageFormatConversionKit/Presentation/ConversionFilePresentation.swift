//
//  集中实现转换文件状态、大小、缩略图、列表卡片和批量操作的共享展示。
//  不同媒体状态映射为统一展示阶段；缩略图按文件路径缓存并提供占位。
//  批量清理通过用户确认触发，iOS 分享界面先关闭再展示确认。
//  图片、音频和视频页面复用此处的列表、状态与操作面板，保持展示语义一致。
//  缩略图和分享面板仅服务界面；清理目标与实际执行由调用方提供。
//

import AVFoundation
import ImageIO
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// 供缩略图和占位符区分图片、视频和音频。
enum ConversionFileKind: Sendable {
    case image
    case video
    case audio
}

/// 统一显示转换界面中的小号辅助标题。
struct ConversionMicroText: View {
    let text: String

    /// 保存分区标题文本，显示时使用统一的标题样式。
    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary.opacity(0.72))
    }
}

/// 将各媒体的详细状态归并为展示所需阶段。
enum ConversionFilePhase {
    case pending
    case working
    case completed
    case failed
}

/// 隔离业务状态枚举与 UI 展示所需数据，避免 View 重复理解每一种状态。
struct ConversionStatusPresentation {
    let phase: ConversionFilePhase
    let label: String
    let outputURL: URL?
}

/// 将媒体专属状态转换为统一的阶段、文案和可选输出路径。
protocol ConversionStatusPresentable {
    var conversionPresentation: ConversionStatusPresentation { get }
}

/// 将图片转换状态适配为文件列表可显示的阶段。
extension ImageConversionItemStatus: ConversionStatusPresentable {
    var conversionPresentation: ConversionStatusPresentation {
        switch self {
        case .inspecting:
            ConversionStatusPresentation(phase: .pending, label: L10n.string("status.inspecting"), outputURL: nil)
        case .ready:
            ConversionStatusPresentation(phase: .pending, label: L10n.string("status.ready"), outputURL: nil)
        case .converting:
            ConversionStatusPresentation(phase: .working, label: L10n.string("status.converting"), outputURL: nil)
        case let .completed(outputURL):
            ConversionStatusPresentation(phase: .completed, label: L10n.string("status.completed"), outputURL: outputURL)
        case let .failed(message):
            ConversionStatusPresentation(phase: .failed, label: message, outputURL: nil)
        case .cancelled:
            ConversionStatusPresentation(phase: .pending, label: L10n.string("status.cancelled"), outputURL: nil)
        }
    }
}

/// 将音频转换状态适配为文件列表可显示的阶段。
extension AudioConversionStatus: ConversionStatusPresentable {
    var conversionPresentation: ConversionStatusPresentation {
        switch self {
        case .ready:
            ConversionStatusPresentation(phase: .pending, label: L10n.string("status.ready"), outputURL: nil)
        case .converting:
            ConversionStatusPresentation(phase: .working, label: L10n.string("status.converting"), outputURL: nil)
        case let .completed(outputURL):
            ConversionStatusPresentation(phase: .completed, label: L10n.string("status.completed"), outputURL: outputURL)
        case let .failed(message):
            ConversionStatusPresentation(phase: .failed, label: message, outputURL: nil)
        case .cancelled:
            ConversionStatusPresentation(phase: .pending, label: L10n.string("status.cancelled"), outputURL: nil)
        }
    }
}

/// 将视频转换状态适配为文件列表可显示的阶段。
extension VideoConversionStatus: ConversionStatusPresentable {
    var conversionPresentation: ConversionStatusPresentation {
        switch self {
        case .ready:
            ConversionStatusPresentation(phase: .pending, label: L10n.string("status.ready"), outputURL: nil)
        case .converting:
            ConversionStatusPresentation(phase: .working, label: L10n.string("status.converting"), outputURL: nil)
        case let .completed(outputURL):
            ConversionStatusPresentation(phase: .completed, label: L10n.string("status.completed"), outputURL: outputURL)
        case let .failed(message):
            ConversionStatusPresentation(phase: .failed, label: message, outputURL: nil)
        case .cancelled:
            ConversionStatusPresentation(phase: .pending, label: L10n.string("status.cancelled"), outputURL: nil)
        }
    }
}

/// 文件大小的读取与格式化集中在展示边界，业务 View 不依赖文件属性细节。
enum ConversionFileSizePresentation {
    /// 格式化源大小；有输出时附加当前读取到的输出大小。
    static func description(sourceBytes: Int64, outputURL: URL?) -> String {
        let source = ByteCountFormatter.string(fromByteCount: sourceBytes, countStyle: .file)
        guard let outputURL else { return source }

        let outputBytes = Int64(
            (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        )
        let output = ByteCountFormatter.string(fromByteCount: outputBytes, countStyle: .file)
        return "\(source) → \(output)"
    }
}

/// 转换设置中通用的标题/值行，保持各媒体页面布局一致。
struct ConversionSettingRow<Content: View>: View {
    let title: String
    let content: Content

    /// 保存设置项标题与由调用方构造的内容。
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            content
        }
    }
}

/// 展示原大小、预估范围和可能变化；估算尚在计算时显示进度。
struct ConversionSizeEstimateView: View {
    let estimate: ConversionSizeEstimate?
    var isLoading = false

    var body: some View {
        if let estimate {
            VStack(alignment: .leading, spacing: 9) {
                Divider()
                ConversionMicroText(L10n.string("estimate.title"))
                valueRow(L10n.string("estimate.original"), bytes(estimate.originalBytes))
                valueRow(
                    L10n.string("estimate.output"),
                    L10n.format(
                        "estimate.range",
                        bytes(estimate.lowerBoundBytes),
                        bytes(estimate.upperBoundBytes)
                    )
                )
                valueRow(changeTitle(estimate), changeValue(estimate))
            }
            .accessibilityIdentifier("conversion.sizeEstimate")
        } else if isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.string("estimate.calculating"))
                    .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("conversion.sizeEstimate.loading")
        }
    }

    /// 以统一布局展示估算标题和数值。
    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .medium)
    }

    /// 根据可能输出大小选择节省或增加的标题。
    private func changeTitle(_ estimate: ConversionSizeEstimate) -> String {
        estimate.likelyBytes <= estimate.originalBytes
            ? L10n.string("estimate.savings")
            : L10n.string("estimate.increase")
    }

    /// 仅展示估算变化百分比；源大小为零时无法计算比例。
    private func changeValue(_ estimate: ConversionSizeEstimate) -> String {
        guard estimate.originalBytes > 0 else { return "—" }
        let difference = abs(estimate.originalBytes - estimate.likelyBytes)
        let percentage = (Double(difference) / Double(estimate.originalBytes) * 100).rounded()
        return L10n.format("estimate.change", percentage)
    }

    /// 使用系统文件大小格式化规则显示字节数。
    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

/// 包装缩略图以跨隔离边界传递；图像由加载器生成后只用于展示。
private struct SendableThumbnail: @unchecked Sendable {
#if os(iOS)
    let image: UIImage
#endif
}

/// 串行生成并缓存缩略图，缓存按标准化文件路径索引。
private actor ConversionThumbnailLoader {
    static let shared = ConversionThumbnailLoader()

#if os(iOS)
    private let cache = NSCache<NSString, UIImage>()

    /// 创建缩略图缓存并限制缓存项数量。
    init() {
        cache.countLimit = 120
    }

    /// 优先返回缓存；图片和视频按类型生成缩略图，音频使用占位符。
    func thumbnail(for url: URL, kind: ConversionFileKind) -> SendableThumbnail? {
        let key = url.standardizedFileURL.path as NSString
        if let cached = cache.object(forKey: key) {
            return SendableThumbnail(image: cached)
        }

        let image: UIImage?
        switch kind {
        case .image:
            image = imageThumbnail(for: url)
        case .video:
            image = videoThumbnail(for: url)
        case .audio:
            image = nil
        }
        guard let image else { return nil }
        cache.setObject(image, forKey: key)
        return SendableThumbnail(image: image)
    }

    /// 使用 Image I/O 生成最长边不超过 300 像素的方向校正缩略图。
    private func imageThumbnail(for url: URL) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 300,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
              ) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    /// 读取视频起点画面并应用轨道方向，无法生成时返回 nil。
    private func videoThumbnail(for url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 300, height: 300)
        guard let image = try? generator.copyCGImage(at: .zero, actualTime: nil) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
#endif
}

/// 异步展示文件缩略图；无法生成时使用对应媒体类型的占位图。
struct ConversionFileThumbnail: View {
    let url: URL
    let kind: ConversionFileKind
    var width: CGFloat = 48
    var height: CGFloat = 48
    @State private var thumbnail: SendableThumbnail?

    var body: some View {
        ZStack {
#if os(iOS)
            if let thumbnail {
                Image(uiImage: thumbnail.image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
#else
            placeholder
#endif
        }
        .frame(width: width, height: height)
        .background(.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .task(id: url) {
            thumbnail = await ConversionThumbnailLoader.shared.thumbnail(for: url, kind: kind)
        }
    }

    private var placeholder: some View {
        Image(systemName: placeholderSymbol)
            .font(.system(size: 16, weight: .light))
            .foregroundStyle(.secondary)
    }

    private var placeholderSymbol: String {
        switch kind {
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        }
    }
}

/// 展示文件网格、导入进度和批量操作入口；有输出时提供分享及确认清理。
struct ConversionFileTray<Content: View>: View {
    @Environment(\.conversionTheme) private var theme

    let title: String
    let progress: ConversionImportProgress?
    let rowCount: Int
    let canClear: Bool
    let outputURLs: [URL]
    @State private var showsBatchActions = false
    let onClear: () -> Void
    let onConfirmedClear: @MainActor @Sendable () -> Void
    let content: Content

    /// 保存文件区块标题、导入进度、分享目标及清理回调，构造列表内容。
    init(
        title: String,
        progress: ConversionImportProgress?,
        rowCount: Int = 1,
        canClear: Bool,
        outputURLs: [URL],
        onClear: @escaping () -> Void,
        onConfirmedClear: @escaping @MainActor @Sendable () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.progress = progress
        self.rowCount = max(1, min(rowCount, 2))
        self.canClear = canClear
        self.outputURLs = outputURLs
        self.onClear = onClear
        self.onConfirmedClear = onConfirmedClear
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button(L10n.string(outputURLs.isEmpty ? "action.clear_all" : "action.batch_actions")) {
                    if outputURLs.isEmpty {
                        onClear()
                    } else {
                        showsBatchActions = true
                    }
                }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.plain)
                    .disabled(!canClear)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: Array(
                        repeating: GridItem(.fixed(132), spacing: 10, alignment: .top),
                        count: rowCount
                    ),
                    alignment: .top,
                    spacing: 10
                ) {
                    content
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)

            if let progress {
                VStack(spacing: 7) {
                    WaveProgressView(
                        progress: progress.fractionCompleted,
                        tint: theme.accent
                    )

                    HStack {
                        Text(L10n.string("import.progress.title"))
                        Spacer()
                        Text("\(progress.percentage)%")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .converterCard()
        #if os(iOS)
        .background {
            ConversionBatchPresenter(isPresented: $showsBatchActions, urls: outputURLs,
                                     onConfirmedClear: onConfirmedClear)
                .frame(width: 0, height: 0)
        }
        #else
        .sheet(isPresented: $showsBatchActions) {
            ConversionBatchActionsPanel(urls: outputURLs, onConfirmedClear: onConfirmedClear)
        }
        #endif
    }
}

/// 展示文件缩略图、名称和状态，并按状态提供分享、进度或移除入口。
struct ConversionFileTile: View {
    @Environment(\.conversionTheme) private var theme

    let url: URL
    let kind: ConversionFileKind
    let title: String
    let subtitle: String
    let phase: ConversionFilePhase
    let statusLabel: String
    let isLocked: Bool
    let outputURL: URL?
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ConversionFileThumbnail(
                    url: url,
                    kind: kind,
                    width: 112,
                    height: 96
                )

                statusBadge
                    .padding(7)
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Text(subtitle)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 112, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(statusLabel), \(subtitle)")
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let outputURL {
            ShareLink(item: outputURL) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("action.share"))
        } else if case .working = phase {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial, in: Circle())
                .accessibilityLabel(statusLabel)
        } else {
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isLocked)
            .accessibilityLabel(L10n.string("action.remove"))
        }
    }
}

/// 导入尚未完成时显示媒体类型占位符和序号。
struct ConversionPendingFileTile: View {
    let index: Int
    let kind: ConversionFileKind

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.primary.opacity(0.055))

                Image(systemName: placeholderSymbol)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)

                ProgressView()
                    .controlSize(.mini)
                    .offset(x: 24, y: -22)
            }
            .frame(width: 112, height: 96)

            Text(L10n.string("import.progress.title"))
                .font(.caption.weight(.semibold))
            Text("#\(index + 1)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(width: 112, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var placeholderSymbol: String {
        switch kind {
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        }
    }
}

/// 以颜色及辅助功能标签呈现阶段，处理中使用脉冲反馈。
struct ConversionStatusDot: View {
    let phase: ConversionFilePhase
    let accessibilityLabel: String
    @State private var isPulsing = false

    private var color: Color {
        switch phase {
        case .pending: .secondary
        case .working: .accentColor
        case .completed: .green
        case .failed: .red
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(phase == .working && isPulsing ? 0.35 : 1)
            .animation(
                phase == .working
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear { isPulsing = phase == .working }
            .accessibilityLabel(accessibilityLabel)
    }
}

#if os(iOS)
/// 将 SwiftUI 的批量操作请求交给 iOS 分享控制器。
private struct ConversionBatchPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let urls: [URL]
    let onConfirmedClear: @MainActor @Sendable () -> Void

    /// 创建负责协调分享和清理确认的 UIKit 控制器。
    func makeUIViewController(context: Context) -> ConversionBatchPresentationController {
        ConversionBatchPresentationController()
    }

    /// 将 SwiftUI 请求和当前文件列表同步至控制器，并在流程结束时复位绑定。
    func updateUIViewController(_ controller: ConversionBatchPresentationController, context: Context) {
        controller.update(requested: isPresented, urls: urls, onConfirmedClear: onConfirmedClear,
                          onFinish: { isPresented = false })
    }
}

@MainActor
/// 管理分享界面、关闭和清理确认的顺序，避免同时展示两个控制器。
private final class ConversionBatchPresentationController: UIViewController {
    /// 记录分享、关闭分享和确认清理之间的互斥阶段。
    private enum State { case idle, sharing, dismissingForClear, confirming }
    private var state = State.idle
    private var requested = false
    private var urls: [URL] = []
    private var onConfirmedClear: @MainActor @Sendable () -> Void = {}
    private var onFinish: () -> Void = {}
    private var activityController: UIActivityViewController?
    private var clearActivity: ConversionClearActivity?

    /// 使用透明容器承载分享和确认界面，不展示额外内容。
    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
    }

    /// 界面进入窗口后检查待处理请求，避免在尚未显示时展示控制器。
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentIfNeeded()
    }

    /// 保存最新分享请求及回调，并尝试在允许的时机展示。
    func update(requested: Bool, urls: [URL],
                onConfirmedClear: @escaping @MainActor @Sendable () -> Void,
                onFinish: @escaping () -> Void) {
        self.requested = requested
        self.urls = urls
        self.onConfirmedClear = onConfirmedClear
        self.onFinish = onFinish
        presentIfNeeded()
    }

    /// 仅在视图已显示且空闲时展示分享界面，避免重复展示。
    private func presentIfNeeded() {
        guard requested, state == .idle, viewIfLoaded?.window != nil else { return }
        state = .sharing
        let activity = ConversionClearActivity { [weak self] in self?.requestClear() }
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: [activity])
        clearActivity = activity
        activityController = controller
        controller.popoverPresentationController?.sourceView = view
        controller.popoverPresentationController?.sourceRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        controller.completionWithItemsHandler = { [weak self] _, _, _, _ in
            Task { @MainActor in
                guard let self, self.state == .sharing else { return }
                self.finish()
            }
        }
        present(controller, animated: true)
    }

    /// 先关闭分享界面，待关闭完成后再展示清理确认。
    private func requestClear() {
        guard state == .sharing, let controller = activityController else { return }
        state = .dismissingForClear
        // UIKit's completion is the boundary: the share page is gone before confirmation.
        controller.dismiss(animated: true) { [weak self] in
            guard let self, self.state == .dismissingForClear else { return }
            self.clearActivity?.activityDidFinish(true)
            self.activityController = nil
            self.clearActivity = nil
            self.state = .confirming
            self.presentConfirmation()
        }
    }

    /// 由用户确认后调用清理回调；取消只结束当前流程。
    private func presentConfirmation() {
        let alert = UIAlertController(title: L10n.string("conversion.delete_all.title"),
                                      message: L10n.string("conversion.delete_all.message"),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.string("action.cancel"), style: .cancel) { [weak self] _ in
            self?.finish()
        })
        alert.addAction(UIAlertAction(title: L10n.string("conversion.delete.action"), style: .destructive) { [weak self] _ in
            guard let self, self.state == .confirming else { return }
            self.onConfirmedClear()
            self.finish()
        })
        present(alert, animated: true)
    }

    /// 重置展示状态并通知 SwiftUI 关闭请求。
    private func finish() {
        state = .idle
        requested = false
        activityController = nil
        clearActivity = nil
        onFinish()
    }
}

@MainActor
/// 分享界面中的清理入口；实际清理仍需后续确认。
private final class ConversionClearActivity: UIActivity {
    nonisolated private let onClear: @MainActor @Sendable () -> Void

    /// 保存清理入口的回调；回调仍需通过后续确认流程。
    init(onClear: @escaping @MainActor @Sendable () -> Void) {
        self.onClear = onClear
        super.init()
    }

    override var activityType: UIActivity.ActivityType? { UIActivity.ActivityType("filevra.conversion.clearAll") }
    override var activityTitle: String? { L10n.string("action.clear_all") }
    override var activityImage: UIImage? { UIImage(systemName: "trash") }
    /// 将自定义清理入口归入分享面板的操作类别。
    override class var activityCategory: UIActivity.Category { .action }
    /// 允许当前分享面板展示清理入口。
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool { true }
    /// 清理入口无需提前处理分享项目。
    override func prepare(withActivityItems activityItems: [Any]) {}
    /// 在主线程发起清理请求，具体删除仍由确认流程控制。
    override func perform() {
        let action = onClear
        MainActor.assumeIsolated { action() }
    }
}
#endif

/// 非 iOS 平台使用的分享与清理确认面板。
private struct ConversionBatchActionsPanel: View {
    @Environment(\.dismiss) private var dismiss
    let urls: [URL]
    let onConfirmedClear: @MainActor @Sendable () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(L10n.string("conversion.delete_all.title")).font(.headline)
            Text(L10n.string("conversion.delete_all.message"))
            HStack {
                Button(L10n.string("action.cancel")) { dismiss() }
                Button(L10n.string("conversion.delete.action"), role: .destructive) {
                    onConfirmedClear()
                    dismiss()
                }
            }
            if !urls.isEmpty {
                ShareLink(items: urls) { Text(L10n.string("action.share")) }
            }
        }
        .padding(24)
    }
}
