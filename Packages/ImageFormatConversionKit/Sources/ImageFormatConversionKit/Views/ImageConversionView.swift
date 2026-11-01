// 图片转换入口、设置和文件列表界面。
// 协调照片及文件导入、输出选项、转换进度、结果操作和快捷压缩展示。
// 图片检测、转换和工作区文件管理由状态对象与底层引擎执行。
// 页面通过图片状态对象接收导入和转换结果，并复用共享文件列表和操作栏。
// 可显示专业设置或快捷压缩入口；取消、失败和结果清理仍由对应业务流程处理。

import SwiftUI
import StoreKit
import PhotosUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 图片转换入口，负责组装主题与内容页面。
@MainActor
public struct ImageConversionView: View {
    private let theme: ConversionTheme
    @AppStorage("conversion.selectedMode") private var mode: ConversionMode = .image
    @State private var isFormatSheetPresented = false
    @State private var transitionDirection: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 使用指定主题创建图片转换入口。
    public init(theme: ConversionTheme = .system) {
        self.theme = theme
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(L10n.string("converter.heading"))
                    .appTypeface(.largeTitle.bold(), size: 34, relativeTo: .largeTitle, weight: .bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, -12)
                    .padding(.bottom, 12)

                Picker(L10n.string("converter.mode"), selection: modeSelection) {
                    Text(L10n.string("converter.mode.image")).tag(ConversionMode.image)
                    Text(L10n.string("converter.mode.video")).tag(ConversionMode.video)
                    Text(L10n.string("converter.mode.audio")).tag(ConversionMode.audio)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 4)
                .padding(.top, 2)

                privacySummary
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                ZStack {
                    conversionContent
                        .id(mode)
                        .transition(modeTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .background(converterBackground)
#if os(iOS)
            .toolbar(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
        .environment(\.conversionTheme, theme)
        .tint(theme.accent)
        .foregroundStyle(theme.textPrimary)
        .sheet(isPresented: $isFormatSheetPresented) {
            SupportedFormatsSheet(mode: mode)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var modeSelection: Binding<ConversionMode> {
        Binding(
            get: { mode },
            set: { newMode in
                guard newMode != mode else { return }
                transitionDirection = newMode.position > mode.position ? 1 : -1
                withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.24)) {
                    mode = newMode
                }
            }
        )
    }

    @ViewBuilder
    private var conversionContent: some View {
        switch mode {
        case .image: ImageConversionContentView()
        case .video: VideoConversionView()
        case .audio: AudioConversionView()
        }
    }

    private var modeTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(x: 18 * transitionDirection).combined(with: .opacity),
            removal: .offset(x: -12 * transitionDirection).combined(with: .opacity)
        )
    }

    private var privacySummary: some View {
        HStack(spacing: 8) {
            Label(L10n.string("import.subtitle"), systemImage: "lock.shield")
                .appTypeface(.caption2, size: 11, relativeTo: .caption2, weight: .regular)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(L10n.string("formats.view_all")) {
                isFormatSheetPresented = true
            }
            .appTypeface(.caption2.weight(.medium), size: 11, relativeTo: .caption2, weight: .medium)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var converterBackground: some View {
        ConversionBackgroundView(background: theme.background)
            .ignoresSafeArea()
    }
}

/// 标识图片、视频和音频转换模式，并提供对应的显示位置。
private enum ConversionMode: String, Hashable {
    case image
    case video
    case audio

    var position: Int {
        switch self {
        case .image: 0
        case .video: 1
        case .audio: 2
        }
    }
}

/// 按转换模式展示支持的导入、导出格式和视频编码。
private struct SupportedFormatsSheet: View {
    let mode: ConversionMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    if mode == .image {
                        FormatChipSection(
                            title: L10n.string("formats.import"),
                            formats: imageInputFormats
                        )
                        FormatChipSection(
                            title: L10n.string("formats.export"),
                            formats: ImageConversionEngine.supportedOutputFormats.map(formatName)
                        )
                    } else if mode == .video {
                        FormatChipSection(
                            title: L10n.string("formats.import"),
                            formats: ["MOV", "MP4", "M4V"]
                        )
                        FormatChipSection(
                            title: L10n.string("formats.export"),
                            formats: ["MP4", "MOV", "M4V"]
                        )
                        FormatChipSection(
                            title: L10n.string("formats.codec"),
                            formats: ["H.264", "HEVC", "ProRes 422", "ProRes 4444"]
                        )
                    } else {
                        FormatChipSection(
                            title: L10n.string("formats.import"),
                            formats: ["M4A", "AAC", "MP3", "WAV", "AIFF", "CAF"]
                        )
                        FormatChipSection(
                            title: L10n.string("formats.video_to_audio_import"),
                            formats: ["MOV", "MP4", "M4V"]
                        )
                        FormatChipSection(
                            title: L10n.string("formats.export"),
                            formats: ["AAC · M4A", "ALAC · M4A", "WAV · PCM"]
                        )
                    }
                }
                .padding(20)
            }
            .converterSoftScrollEdge()
            .navigationTitle(formatTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("action.done")) { dismiss() }
                }
            }
        }
    }

    private var formatTitle: String {
        switch mode {
        case .image: L10n.string("formats.image.title")
        case .video: L10n.string("formats.video.title")
        case .audio: L10n.string("formats.audio.title")
        }
    }

    private var imageInputFormats: [String] {
        ImageConversionEngine.supportedInputFormatNames
    }

    /// 读取图片输出格式的显示名称，供格式列表展示。
    private func formatName(_ format: ImageOutputFormat) -> String {
        format.displayName
    }
}

/// 将一组格式名称以自适应网格展示。
private struct FormatChipSection: View {
    let title: String
    let formats: [String]
    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ConversionMicroText(title)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(formats, id: \.self) { format in
                    Text(format)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Color.primary.opacity(0.055),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        }
                }
            }
        }
    }
}

/// 协调图片导入、输出设置、文件列表、转换进度和确认交互。
@MainActor
struct ImageConversionContentView: View {
    let isQuickCompression: Bool
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @State private var completedBeforeBatch: Set<UUID> = []
    @Environment(\.conversionUsagePolicy) private var usagePolicy
    @State private var viewModel: ImageConversionViewModel
    @State private var importSession: ConversionImportSession
    @State private var isImporterPresented = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isClearAllConfirmationPresented = false

    /// 注入图片转换状态与导入会话，并记录是否从快捷压缩入口进入。
    init(
        viewModel: ImageConversionViewModel = ImageConversionViewModel(),
        importSession: ConversionImportSession = ConversionImportSession(),
        isQuickCompression: Bool = false
    ) {
        self.isQuickCompression = isQuickCompression
        _viewModel = State(initialValue: viewModel)
        _importSession = State(initialValue: importSession)
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 14) {
                if shouldShowImportCard {
                    importCard
                } else {
                    selectedFilesCard
                }

                if let notice = viewModel.notice {
                    NoticeView(message: notice)
                }

                if isQuickCompression {
                    QuickCompressionSummary(kind: .images)
                } else {
                    ImageConversionSettingsCard(viewModel: viewModel)
                        .accessibilityIdentifier("conversion.settings")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .converterSoftScrollEdge()
        .sheet(isPresented: Binding(
            get: { viewModel.isPremiumRequiredPresented },
            set: { viewModel.isPremiumRequiredPresented = $0 }
        )) { usagePolicy.upgradeContent(.images) }
        .safeAreaInset(edge: .bottom) {
            if !shouldShowImportCard {
                bottomActionBar
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: ImageConversionEngine.supportedInputContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                Task { @MainActor in
                    await importFiles(urls)
                }
            case let .failure(error):
                let message = error.localizedDescription
                Task { @MainActor in
                    viewModel.reportImportFailure(message)
                }
            }
        }
        .alert(
            L10n.string("conversion.delete_all.title"),
            isPresented: $isClearAllConfirmationPresented
        ) {
            Button(L10n.string("action.cancel"), role: .cancel) {}
            Button(L10n.string("conversion.delete.action"), role: .destructive) {
                viewModel.removeAll()
            }
        } message: {
            Text(L10n.string("conversion.delete_all.message"))
        }
        .onChange(of: viewModel.isConverting) { _, converting in
            let completedIDs = Set(viewModel.items.compactMap { item -> UUID? in
                if case .completed = item.status { return item.id }
                return nil
            })
            if converting {
                completedBeforeBatch = completedIDs
            } else if scenePhase == .active,
                      !completedIDs.subtracting(completedBeforeBatch).isEmpty {
                requestReview()
            }
        }
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
    }

    private var activeImportProgress: ConversionImportProgress? {
        importSession.libraryProgress ?? viewModel.importProgress
    }

    private var shouldShowImportCard: Bool {
        viewModel.items.isEmpty && activeImportProgress == nil && importSession.pendingCount == 0
    }

    private var displayedFileCount: Int {
        max(
            viewModel.items.count,
            importSession.pendingCount,
            activeImportProgress?.total ?? 0
        )
    }

    private var importCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .appTypeface(.system(size: 34, weight: .semibold), size: 34, relativeTo: .body, weight: .semibold)
                .foregroundStyle(.tint)

            VStack(spacing: 4) {
                Text(L10n.string(isQuickCompression ? "quick.image" : "import.title"))
                    .appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)
            }

            HStack(spacing: 10) {
                Button {
                    isImporterPresented = true
                } label: {
                    ConversionImportButtonLabel(
                        title: L10n.string("action.choose_files"),
                        systemImage: "folder"
                    )
                }
                .buttonStyle(.bordered)

                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 100,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    ConversionImportButtonLabel(
                        title: L10n.string("action.choose_photos"),
                        systemImage: "photo.on.rectangle"
                    )
                }
                .buttonStyle(.bordered)
            }
            .disabled(viewModel.isConverting || viewModel.importProgress != nil)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .converterCard()
    }

    /// 从照片选择器逐项取得图片和资源标识；按会话过滤迟到的进度回调，再交由模型暂存。
    private func importPhotos(_ selections: [PhotosPickerItem]) async {
        let sessionID = UUID()
        importSession.librarySessionID = sessionID
        importSession.pendingCount = selections.count
        defer {
            selectedPhotoItems = []
            if importSession.librarySessionID == sessionID {
                importSession.librarySessionID = nil
                importSession.libraryProgress = nil
            }
            importSession.pendingCount = 0
            importSession.previewURLs = []
        }
        var urls: [URL] = []
        var assetIdentifiers: [URL: String] = [:]
        for (index, selection) in selections.enumerated() {
            importSession.libraryProgress = ConversionImportProgress(
                completed: index,
                total: selections.count,
                currentFileName: nil
            ).mapped(to: 0 ... 0.95)
            do {
                if let imported = try await PhotoLibraryImport.loadTransferable(
                    from: selection,
                    type: ImportedPhotoFile.self,
                    progress: { fraction in
                        Task { @MainActor in
                            guard importSession.librarySessionID == sessionID else { return }
                            importSession.libraryProgress = ConversionImportProgress(
                                completed: index,
                                total: selections.count,
                                currentFileName: nil,
                                currentFileFraction: fraction
                            ).mapped(to: 0 ... 0.95)
                        }
                    }
                ) {
                    urls.append(imported.url)
                    if let identifier = selection.itemIdentifier {
                        assetIdentifiers[imported.url.standardizedFileURL] = identifier
                    }
                    importSession.previewURLs.append(imported.url)
                }
            } catch {
                viewModel.reportImportFailure(error.localizedDescription)
            }
            importSession.libraryProgress = ConversionImportProgress(
                completed: index + 1,
                total: selections.count,
                currentFileName: nil
            ).mapped(to: 0 ... 0.95)
        }
        importSession.librarySessionID = nil
        importSession.libraryProgress = nil
        await viewModel.addFiles(
            urls,
            photoAssetIdentifiers: assetIdentifiers,
            progressRange: 0.95 ... 1
        )
    }

    /// 在文件导入期间维护待处理数量与临时预览，结束后清理这些展示状态。
    private func importFiles(_ urls: [URL]) async {
        importSession.pendingCount = urls.count
        importSession.previewURLs = urls
        defer {
            importSession.pendingCount = 0
            importSession.previewURLs = []
        }
        await viewModel.addFiles(urls)
    }

    private var selectedFilesCard: some View {
        ConversionFileTray(
            title: activeImportProgress == nil
                ? L10n.format("files.title", displayedFileCount)
                : "\(L10n.string("import.progress.title")) · \(L10n.format("files.title", displayedFileCount))",
            progress: activeImportProgress,
            rowCount: displayedFileCount > 3 ? 2 : 1,
            canClear: !viewModel.isConverting && activeImportProgress == nil,
            outputURLs: viewModel.items.compactMap { $0.status.conversionPresentation.outputURL },
            onClear: { isClearAllConfirmationPresented = true },
            onConfirmedClear: { viewModel.removeAll() }
        ) {
            ForEach(viewModel.items) { item in
                let presentation = item.status.conversionPresentation
                let presentationURL = presentation.outputURL ?? item.sourceURL
                ConversionFileTile(
                    url: presentationURL,
                    kind: .image,
                    title: presentationURL.lastPathComponent,
                    subtitle: imageSubtitle(item),
                    phase: presentation.phase,
                    statusLabel: presentation.label,
                    isLocked: viewModel.isConverting,
                    outputURL: presentation.outputURL,
                    onRemove: { viewModel.removeItem(id: item.id) }
                )
            }

            ForEach(Array(importSession.previewURLs.dropFirst(min(viewModel.items.count, importSession.previewURLs.count)).enumerated()), id: \.offset) { _, url in
                ConversionFileTile(
                    url: url,
                    kind: .image,
                    title: url.lastPathComponent,
                    subtitle: L10n.string("import.progress.title"),
                    phase: .working,
                    statusLabel: L10n.string("import.progress.title"),
                    isLocked: true,
                    outputURL: nil,
                    onRemove: {}
                )
            }

            let representedCount = max(viewModel.items.count, importSession.previewURLs.count)
            if displayedFileCount > representedCount {
                ForEach(representedCount ..< displayedFileCount, id: \.self) { index in
                    ConversionPendingFileTile(index: index, kind: .image)
                }
            }
        }
    }

    /// 检查信息可用时显示源文件与输出大小；否则显示当前状态。
    private func imageSubtitle(_ item: ImageConversionItem) -> String {
        guard let info = item.info else { return item.status.conversionPresentation.label }
        return ConversionFileSizePresentation.description(
            sourceBytes: info.fileSizeBytes,
            outputURL: item.status.conversionPresentation.outputURL
        )
    }

    private var bottomActionBar: some View {
        ConversionNeoBrutalistActionBar(
            countTitle: L10n.format("files.title", displayedFileCount),
            isWorking: viewModel.isConverting,
            progress: viewModel.progress.fractionCompleted,
            progressTitle: L10n.format(
                "progress.summary",
                viewModel.progress.completed,
                viewModel.progress.total
            ),
            isEnabled: viewModel.canStartConversion,
            onStart: {
                if isQuickCompression {
                    viewModel.startQuickCompression(usagePolicy: usagePolicy)
                } else {
                    viewModel.startConversion(usagePolicy: usagePolicy)
                }
            },
            onCancel: viewModel.cancelConversion,
            startTitle: isQuickCompression ? L10n.string("quick.action") : nil
        )
    }

}

/// 集中展示导入、清理和转换等主要动作，并根据状态控制可用性。
@MainActor
struct ConversionNeoBrutalistActionBar: View {
    @Environment(\.conversionTheme) private var theme

    let countTitle: String
    let isWorking: Bool
    let progress: Double
    let progressTitle: String
    let isEnabled: Bool
    let onStart: () -> Void
    let onCancel: () -> Void
    var startTitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            if isWorking {
                VStack(alignment: .leading, spacing: 4) {
                    WaveProgressView(progress: progress, tint: theme.accent)
                        .frame(height: 6)

                    Text(progressTitle)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.textPrimary.opacity(0.65))
                }

                Spacer()
                actionButton(
                    title: L10n.string("action.cancel"),
                    systemImage: "xmark",
                    action: onCancel
                )
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(countTitle.uppercased())
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(theme.textPrimary)

                    Text(L10n.string("status.ready").uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.textPrimary.opacity(0.6))
                }

                Spacer()
                actionButton(
                    title: startTitle ?? L10n.string("action.convert"),
                    systemImage: "arrow.triangle.2.circlepath",
                    action: onStart
                )
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.48)
            }
        }
        // Keep the accessibility container on the content itself. Surface
        // modifiers and decorative overlays are not stable XCUI elements.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversion.actionBar")
        .accessibilityValue("solid")
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .modifier(ConversionActionBarSurfaceModifier())
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.textPrimary, lineWidth: 2.5)
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.textPrimary)
                .offset(x: 4, y: 4)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// 按传入的状态、标题和回调构造操作栏按钮。
    private func actionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        ConversionActionButton(
            title: title,
            systemImage: systemImage,
            accentColor: theme.accent,
            foregroundColor: theme.textPrimary,
            action: action
        )
        .accessibilityIdentifier("conversion.actionButton")
    }
}

#if DEBUG
@MainActor
/// 为界面自动化单独展示转换操作栏。
public struct ConversionActionBarUITestHarness: View {
    private let theme: ConversionTheme

    /// 使用指定主题创建操作栏测试入口。
    public init(theme: ConversionTheme = .system) {
        self.theme = theme
    }

    public var body: some View {
        VStack {
            Spacer()
            ConversionNeoBrutalistActionBar(
                countTitle: "1 Image",
                isWorking: false,
                progress: 0,
                progressTitle: "",
                isEnabled: true,
                onStart: {},
                onCancel: {}
            )
        }
        .environment(\.conversionTheme, theme)
    }
}
#endif

/// 为转换操作栏提供统一的表面样式。
private struct ConversionActionBarSurfaceModifier: ViewModifier {
    @Environment(\.conversionTheme) private var theme
    /// 将对应卡片或按钮表面样式应用于内容。
    func body(content: Content) -> some View {
        content.background(
            theme.cardSurface,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

/// 定义转换操作按钮的按压外观。
struct ConversionPhysicalActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let faceColor: Color
    let edgeColor: Color

    /// 根据按压状态绘制按钮并提供视觉反馈。
    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed

        configuration.label
            .modifier(
                ConversionPhysicalButtonFaceModifier(
                    color: faceColor
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(edgeColor, lineWidth: 2.5)
            }
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(edgeColor)
                    .offset(x: isPressed ? 0 : 3, y: isPressed ? 0 : 4)
            }
            .offset(y: isPressed ? 4 : 0)
            .scaleEffect(isPressed ? 0.995 : 1)
            .animation(
                reduceMotion
                    ? .linear(duration: 0.01)
                    : .spring(response: 0.16, dampingFraction: 0.72),
                value: isPressed
            )
    }
}

/// 为按钮内容添加实体按钮表面效果。
private struct ConversionPhysicalButtonFaceModifier: ViewModifier {
    let color: Color
    /// 将对应卡片或按钮表面样式应用于内容。
    func body(content: Content) -> some View {
        content.background(
            color,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

/// 展示转换页面的导入按钮标签。
struct ConversionImportButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .appTypeface(
                .subheadline.weight(.medium),
                size: 15,
                relativeTo: .subheadline,
                weight: .medium
            )
            .frame(maxWidth: .infinity)
            .frame(height: 38)
    }
}

/// 组合图片格式、质量、尺寸与元数据设置控件。
@MainActor
private struct ImageConversionSettingsCard: View {
    @Environment(\.conversionTheme) private var theme
    @Bindable var viewModel: ImageConversionViewModel
    @State private var isAdvancedExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                ConversionMicroText(L10n.string("settings.format"))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.availableFormats, id: \.self) { format in
                            let isSelected = viewModel.outputFormat == format
                            Button {
                                viewModel.outputFormat = format
                            } label: {
                                Text(format.displayName)
                                    .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .foregroundStyle(isSelected ? Color.white : theme.textPrimary)
                                    .background(
                                        isSelected ? theme.accent : theme.textPrimary.opacity(0.06),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Divider().opacity(0.4)

            if viewModel.outputFormat.supportsQuality {
                SegmentedStreamSlider(value: $viewModel.quality)

                Divider().opacity(0.4)
            }

            DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                VStack(spacing: 12) {
                    compactPickerRow(
                        title: L10n.string("settings.metadata"),
                        selection: $viewModel.metadataPolicy,
                        options: ImageMetadataPolicy.allCases,
                        optionTitle: metadataTitle
                    )

                    compactPickerRow(
                        title: L10n.string("settings.resize"),
                        selection: $viewModel.resizePreset,
                        options: ImageResizePreset.allCases,
                        optionTitle: resizeTitle
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.string("settings.background"))
                            .appTypeface(.subheadline, size: 15, relativeTo: .subheadline, weight: .regular)

                        Picker(
                            L10n.string("settings.background"),
                            selection: $viewModel.background
                        ) {
                            Text(L10n.string("color.white")).tag(ImageBackground.white)
                            Text(L10n.string("color.black")).tag(ImageBackground.black)
                            Text(L10n.string("color.transparent")).tag(ImageBackground.transparent)
                                .disabled(!viewModel.outputFormat.supportsTransparentBackground)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("conversion.image.background")
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text(L10n.string("settings.output"))
                        Spacer()
                        Text(L10n.string("settings.output.images"))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.top, 10)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(L10n.string("settings.title"))
                        .appTypeface(.subheadline, size: 15, relativeTo: .subheadline, weight: .regular)
                    Spacer()
                    if !isAdvancedExpanded {
                        Text(advancedSummary)
                            .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .tint(theme.textPrimary)

            ConversionSizeEstimateView(estimate: viewModel.sizeEstimate)
        }
        .padding(14)
        .converterCard()
        .disabled(viewModel.isConverting)
    }

    private var advancedSummary: String {
        [
            metadataTitle(viewModel.metadataPolicy),
            resizeSummaryTitle(viewModel.resizePreset)
        ].joined(separator: " · ")
    }

    /// 为紧凑布局构造带绑定选项的选择行。
    private func compactPickerRow<Option: Hashable>(
        title: String,
        selection: Binding<Option>,
        options: [Option],
        optionTitle: @escaping (Option) -> String
    ) -> some View {
        HStack {
            Text(title)
                .appTypeface(.subheadline, size: 15, relativeTo: .subheadline, weight: .regular)
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(optionTitle(option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    /// 生成设置摘要使用的紧凑尺寸文本，仅省略“最长边不超过”的解释性前缀。
    private func resizeSummaryTitle(_ preset: ImageResizePreset) -> String {
        switch preset {
        case .original: L10n.string("resize.original")
        case .ultraHD: "4096 px"
        case .large: "2048 px"
        case .medium: "1280 px"
        case .square1024: L10n.string("resize.square1024")
        }
    }

    /// 将元数据保留策略映射为本地化设置名称。
    private func metadataTitle(_ policy: ImageMetadataPolicy) -> String {
        switch policy {
        case .preserve: L10n.string("metadata.preserve")
        case .removeGPS: L10n.string("metadata.remove_gps")
        case .removeAll: L10n.string("metadata.remove_all")
        }
    }

    /// 将图片缩放预设映射为完整的本地化设置名称。
    private func resizeTitle(_ preset: ImageResizePreset) -> String {
        switch preset {
        case .original: L10n.string("resize.original")
        case .ultraHD: L10n.string("resize.4096")
        case .large: L10n.string("resize.2048")
        case .medium: L10n.string("resize.1280")
        case .square1024: L10n.string("resize.square1024")
        }
    }

}

/// 根据单个图片项目的状态展示文件信息和可用操作。
@MainActor
private struct ImageConversionFileRow: View {
    @Environment(\.conversionTheme) private var theme

    let item: ImageConversionItem
    let isLocked: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ConversionFileThumbnail(url: presentationURL, kind: .image)

            VStack(alignment: .leading, spacing: 3) {
                Text(presentationURL.lastPathComponent)
                    .appTypeface(.subheadline.weight(.medium), size: 15, relativeTo: .subheadline, weight: .medium)
                    .lineLimit(1)

                if let info = item.info {
                    HStack(spacing: 6) {
                        ConversionStatusDot(
                            phase: statusPhase,
                            accessibilityLabel: statusText
                        )
                        Text(ConversionFileSizePresentation.description(
                            sourceBytes: info.fileSizeBytes,
                            outputURL: item.status.conversionPresentation.outputURL
                        ))
                    }
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                }

                if item.info == nil {
                    HStack(spacing: 6) {
                        ConversionStatusDot(
                            phase: statusPhase,
                            accessibilityLabel: statusText
                        )
                        Text(statusText)
                    }
                    .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                    .foregroundStyle(.secondary)
                }

                if case let .failed(message) = item.status {
                    Text(message)
                        .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                        .foregroundStyle(theme.destructive)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            trailingAction
        }
    }

    private var presentationURL: URL {
        item.status.conversionPresentation.outputURL ?? item.sourceURL
    }

    private var statusPhase: ConversionFilePhase {
        item.status.conversionPresentation.phase
    }

    private var statusText: String {
        item.status.conversionPresentation.label
    }

    @ViewBuilder
    private var trailingAction: some View {
        switch item.status {
        case let .completed(outputURL):
            HStack(spacing: 4) {
                ShareLink(item: outputURL) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.string("action.share"))

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .disabled(isLocked)
                .accessibilityLabel(L10n.string("conversion.delete.action"))
            }
        case .converting, .inspecting:
            ProgressView()
                .controlSize(.small)
        case .ready, .failed, .cancelled:
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .appTypeface(.system(size: 12, weight: .medium), size: 12, relativeTo: .body, weight: .medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .disabled(isLocked)
            .accessibilityLabel(L10n.string("action.remove"))
        }
    }
}

/// 以提示图标和文本展示转换页面中的说明信息。
struct NoticeView: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.tint)
            Text(message)
                .appTypeface(.footnote, size: 13, relativeTo: .footnote, weight: .regular)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .converterCard()
    }
}

/// 展示主转换操作按钮，根据可用状态控制交互并适配主题材质。
@MainActor
struct PrimaryConversionButton: View {
    @Environment(\.conversionTheme) private var theme

    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Group {
#if os(iOS)
            if #available(iOS 26.0, *), theme.liquidGlassEnabled {
                Button(action: action) {
                    Label(title, systemImage: "arrow.triangle.2.circlepath")
                        .appTypeface(.system(size: 17, weight: .semibold), size: 17, relativeTo: .body, weight: .semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.glassProminent)
            } else {
                fallbackButton
            }
#else
            fallbackButton
#endif
        }
        .disabled(!isEnabled)
    }

    private var fallbackButton: some View {
        Button(action: action) {
            Label(title, systemImage: "arrow.triangle.2.circlepath")
                .appTypeface(.system(size: 17, weight: .semibold), size: 17, relativeTo: .body, weight: .semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.accent)
    }
}

/// 按主题和系统能力选择玻璃材质或普通卡片背景。
private struct ConverterCardModifier: ViewModifier {
    @Environment(\.conversionTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat

    /// 根据系统版本、主题及减少透明度设置选择卡片外观。
    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *), theme.liquidGlassCardsEnabled, !reduceTransparency {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            fallbackCard(content)
        }
        #else
        fallbackCard(content)
        #endif
    }

    /// 在系统材质不可用的路径中绘制卡片背景。
    private func fallbackCard(_ content: Content) -> some View {
        content
            .background(
                theme.cardSurface,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(theme.divider.opacity(0.65), lineWidth: 0.5)
            }
    }
}

/// 提供转换界面强调卡片样式。
private struct ConverterAccentCardModifier: ViewModifier {
    @Environment(\.conversionTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat

    @ViewBuilder
    /// 将对应卡片或按钮表面样式应用于内容。
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *), theme.liquidGlassCardsEnabled, !reduceTransparency {
            content.glassEffect(
                .regular.tint(theme.accent.opacity(0.12)),
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            fallbackCard(content)
        }
        #else
        fallbackCard(content)
        #endif
    }

    /// 在系统材质不可用的路径中绘制卡片背景。
    private func fallbackCard(_ content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [theme.accent.opacity(0.14), theme.cardSurface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(theme.divider.opacity(0.55), lineWidth: 0.5)
            }
    }
}

/// 提供转换界面内凹卡片样式。
private struct ConverterInsetCardModifier: ViewModifier {
    @Environment(\.conversionTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat

    @ViewBuilder
    /// 将对应卡片或按钮表面样式应用于内容。
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *), theme.liquidGlassCardsEnabled, !reduceTransparency {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(theme.cardElevated, in: .rect(cornerRadius: cornerRadius))
        }
        #else
        content.background(theme.cardElevated, in: .rect(cornerRadius: cornerRadius))
        #endif
    }
}

/// 为转换页面提供统一的卡片和滚动边缘样式。
extension View {
    /// 将标准转换卡片样式应用于视图。
    func converterCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(ConverterCardModifier(cornerRadius: cornerRadius))
    }

    /// 将强调卡片样式应用于当前视图。
    func converterAccentCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(ConverterAccentCardModifier(cornerRadius: cornerRadius))
    }

    /// 将内凹卡片样式应用于当前视图。
    func converterInsetCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(ConverterInsetCardModifier(cornerRadius: cornerRadius))
    }

    /// 在系统支持时为垂直滚动内容应用柔和边缘效果。
    func converterSoftScrollEdge() -> some View {
        modifier(ConverterSoftScrollEdgeModifier())
    }
}

/// 为支持该能力的系统启用柔和滚动边缘，旧系统保留原视图。
private struct ConverterSoftScrollEdgeModifier: ViewModifier {
    /// 按系统版本选择滚动边缘效果。
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .vertical)
        } else {
            content
        }
    }
}
