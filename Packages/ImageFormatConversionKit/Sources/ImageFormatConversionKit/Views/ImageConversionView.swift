//
//  文件职责：声明 ImageConversion 界面结构、交互入口与展示状态。
//  所属模块：ImageFormatConversionKit。
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
/// 定义 `ImageConversionView` 的值语义数据与相关行为。
public struct ImageConversionView: View {
    private let theme: ConversionTheme
    @AppStorage("conversion.selectedMode") private var mode: ConversionMode = .image
    @State private var isFormatSheetPresented = false
    @State private var transitionDirection: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
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

/// 定义 `ConversionMode` 使用的有限状态或选项集合。
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

/// 定义 `SupportedFormatsSheet` 的值语义数据与相关行为。
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

    /// 生成 `formatName` 使用的展示文本，保持格式与本地化规则一致。
    private func formatName(_ format: ImageOutputFormat) -> String {
        format.rawValue.uppercased()
    }
}

/// 定义 `FormatChipSection` 的值语义数据与相关行为。
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

@MainActor
/// 定义 `ImageConversionContentView` 的值语义数据与相关行为。
struct ImageConversionContentView: View {
    @State private var viewModel: ImageConversionViewModel
    @State private var importSession: ConversionImportSession
    @State private var isImporterPresented = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isClearAllConfirmationPresented = false

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    init(
        viewModel: ImageConversionViewModel = ImageConversionViewModel(),
        importSession: ConversionImportSession = ConversionImportSession()
    ) {
        _viewModel = State(initialValue: viewModel)
        _importSession = State(initialValue: importSession)
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 16) {
                if shouldShowImportCard {
                    importCard
                } else {
                    selectedFilesCard
                }

                if let notice = viewModel.notice {
                    NoticeView(message: notice)
                }

                ImageConversionSettingsCard(viewModel: viewModel)
                conversionAction
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        .converterSoftScrollEdge()
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
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .appTypeface(.system(size: 34, weight: .semibold), size: 34, relativeTo: .body, weight: .semibold)
                .foregroundStyle(.tint)

            VStack(spacing: 4) {
                Text(L10n.string("import.title"))
                    .appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)
            }

            Button {
                isImporterPresented = true
            } label: {
                Label(L10n.string("action.choose_files"), systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isConverting || viewModel.importProgress != nil)

            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: 100,
                matching: .images
            ) {
                Label(L10n.string("action.choose_photos"), systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isConverting || viewModel.importProgress != nil)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .converterCard()
    }

    /// 处理 `importPhotos` 导入流程，并将用户选择安全地交给后续处理。
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
        await viewModel.addFiles(urls, progressRange: 0.95 ... 1)
    }

    /// 处理 `importFiles` 导入流程，并将用户选择安全地交给后续处理。
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
            onClear: { isClearAllConfirmationPresented = true }
        ) {
            ForEach(viewModel.items) { item in
                let presentationURL = imageOutputURL(item.status) ?? item.sourceURL
                ConversionFileTile(
                    url: presentationURL,
                    kind: .image,
                    title: presentationURL.lastPathComponent,
                    subtitle: imageSubtitle(item),
                    phase: imagePhase(item.status),
                    statusLabel: imageStatusText(item.status),
                    isLocked: viewModel.isConverting,
                    outputURL: imageOutputURL(item.status),
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

    /// 封装 `imageSubtitle` 对应的局部行为，供当前类型在统一入口下复用。
    private func imageSubtitle(_ item: ImageConversionItem) -> String {
        guard let info = item.info else { return imageStatusText(item.status) }
        let size = ByteCountFormatter.string(fromByteCount: info.fileSizeBytes, countStyle: .file)
        return "\(info.pixelWidth)×\(info.pixelHeight) · \(size)"
    }

    /// 封装 `imagePhase` 对应的局部行为，供当前类型在统一入口下复用。
    private func imagePhase(_ status: ImageConversionItemStatus) -> ConversionFilePhase {
        switch status {
        case .inspecting, .ready, .cancelled: .pending
        case .converting: .working
        case .completed: .completed
        case .failed: .failed
        }
    }

    /// 封装 `imageStatusText` 对应的局部行为，供当前类型在统一入口下复用。
    private func imageStatusText(_ status: ImageConversionItemStatus) -> String {
        switch status {
        case .inspecting: L10n.string("status.inspecting")
        case .ready: L10n.string("status.ready")
        case .converting: L10n.string("status.converting")
        case .completed: L10n.string("status.completed")
        case let .failed(message): message
        case .cancelled: L10n.string("status.cancelled")
        }
    }

    /// 封装 `imageOutputURL` 对应的局部行为，供当前类型在统一入口下复用。
    private func imageOutputURL(_ status: ImageConversionItemStatus) -> URL? {
        guard case let .completed(url) = status else { return nil }
        return url
    }

    @ViewBuilder
    private var conversionAction: some View {
        if viewModel.isConverting {
            VStack(spacing: 12) {
                ProgressView(value: viewModel.progress.fractionCompleted)

                HStack {
                    Text(
                        L10n.format(
                            "progress.summary",
                            viewModel.progress.completed,
                            viewModel.progress.total
                        )
                    )
                    .appTypeface(.footnote, size: 13, relativeTo: .footnote, weight: .regular)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button(L10n.string("action.cancel"), role: .cancel) {
                        viewModel.cancelConversion()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .converterCard()
        } else {
            PrimaryConversionButton(
                title: L10n.string("action.convert"),
                isEnabled: viewModel.canStartConversion,
                action: viewModel.startConversion
            )
        }
    }

}

@MainActor
/// 定义 `ImageConversionSettingsCard` 的值语义数据与相关行为。
private struct ImageConversionSettingsCard: View {
    @Bindable var viewModel: ImageConversionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConversionMicroText(L10n.string("settings.title"))

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("settings.format"))
                ConversionSettingsWheelPicker(
                    summary: imageSettingsSummary,
                    detail: L10n.dynamicString("format.image.\(viewModel.outputFormat.rawValue).detail")
                ) {
                    HStack(spacing: 0) {
                        ConversionWheelColumn(
                            title: L10n.string("settings.format"),
                            selection: $viewModel.outputFormat
                        ) {
                            ForEach(viewModel.availableFormats) { format in
                                Text(format.rawValue.uppercased()).tag(format)
                            }
                        }
                        ConversionWheelColumn(
                            title: L10n.string("settings.metadata"),
                            selection: $viewModel.metadataPolicy
                        ) {
                            ForEach(ImageMetadataPolicy.allCases) { policy in
                                Text(metadataTitle(policy)).tag(policy)
                            }
                        }
                        ConversionWheelColumn(
                            title: L10n.string("settings.resize"),
                            selection: $viewModel.resizePreset
                        ) {
                            ForEach(ImageResizePreset.allCases) { preset in
                                Text(resizeTitle(preset)).tag(preset)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.string("settings.quality"))
                    Spacer()
                    if viewModel.outputFormat.supportsQuality {
                        Text(viewModel.quality, format: .percent.precision(.fractionLength(0)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text("—")
                            .foregroundStyle(.tertiary)
                    }
                }
                Slider(value: $viewModel.quality, in: 0.1 ... 1, step: 0.05)

                HStack {
                    Text(L10n.string("quality.smaller"))
                    Spacer()
                    Text(L10n.string("quality.balanced"))
                    Spacer()
                    Text(L10n.string("quality.best"))
                }
                .appTypeface(.caption2, size: 11, relativeTo: .caption2, weight: .regular)
                .foregroundStyle(.tertiary)
            }
            .disabled(!viewModel.outputFormat.supportsQuality)
            .opacity(viewModel.outputFormat.supportsQuality ? 1 : 0.42)
            .animation(.easeInOut(duration: 0.18), value: viewModel.outputFormat)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("settings.background"))
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
                Text(L10n.string("settings.background.detail"))
                    .appTypeface(.footnote, size: 13, relativeTo: .footnote, weight: .regular)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string("settings.output"))
                Spacer()
                Text(viewModel.outputDirectory.lastPathComponent)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .converterCard()
        .disabled(viewModel.isConverting)
    }

    private var imageSettingsSummary: String {
        [
            viewModel.outputFormat.rawValue.uppercased(),
            metadataTitle(viewModel.metadataPolicy),
            resizeSummaryTitle(viewModel.resizePreset)
        ].joined(separator: " · ")
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

    /// 封装 `settingRow` 对应的局部行为，供当前类型在统一入口下复用。
    private func settingRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            content()
        }
    }

    /// 封装 `metadataTitle` 对应的局部行为，供当前类型在统一入口下复用。
    private func metadataTitle(_ policy: ImageMetadataPolicy) -> String {
        switch policy {
        case .preserve: L10n.string("metadata.preserve")
        case .removeGPS: L10n.string("metadata.remove_gps")
        case .removeAll: L10n.string("metadata.remove_all")
        }
    }

    /// 封装 `resizeTitle` 对应的局部行为，供当前类型在统一入口下复用。
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

@MainActor
/// 定义 `ImageConversionFileRow` 的值语义数据与相关行为。
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
                        Text("\(info.pixelWidth)×\(info.pixelHeight)")
                        Text("·")
                        Text(ByteCountFormatter.string(
                            fromByteCount: info.fileSizeBytes,
                            countStyle: .file
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
        guard case let .completed(outputURL) = item.status else { return item.sourceURL }
        return outputURL
    }

    private var statusPhase: ConversionFilePhase {
        switch item.status {
        case .inspecting, .ready, .cancelled: .pending
        case .converting: .working
        case .completed: .completed
        case .failed: .failed
        }
    }

    private var statusText: String {
        switch item.status {
        case .inspecting: L10n.string("status.inspecting")
        case .ready: L10n.string("status.ready")
        case .converting: L10n.string("status.converting")
        case .completed: L10n.string("status.completed")
        case let .failed(message): message
        case .cancelled: L10n.string("status.cancelled")
        }
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

/// 定义 `NoticeView` 的值语义数据与相关行为。
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

@MainActor
/// 定义 `PrimaryConversionButton` 的值语义数据与相关行为。
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

/// 定义 `ConverterCardModifier` 的值语义数据与相关行为。
private struct ConverterCardModifier: ViewModifier {
    @Environment(\.conversionTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat

    /// 封装 `body` 对应的局部行为，供当前类型在统一入口下复用。
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

private struct ConverterAccentCardModifier: ViewModifier {
    @Environment(\.conversionTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat

    @ViewBuilder
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

/// 扩展 `View`，集中实现当前文件所需的附加能力。
extension View {
    /// 执行 `converterCard` 转换流程，并按当前配置生成输出结果。
    func converterCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(ConverterCardModifier(cornerRadius: cornerRadius))
    }

    func converterAccentCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(ConverterAccentCardModifier(cornerRadius: cornerRadius))
    }

    /// 执行 `converterSoftScrollEdge` 转换流程，并按当前配置生成输出结果。
    func converterSoftScrollEdge() -> some View {
        modifier(ConverterSoftScrollEdgeModifier())
    }
}

/// 定义 `ConverterSoftScrollEdgeModifier` 的值语义数据与相关行为。
private struct ConverterSoftScrollEdgeModifier: ViewModifier {
    @ViewBuilder
    /// 封装 `body` 对应的局部行为，供当前类型在统一入口下复用。
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .vertical)
        } else {
            content
        }
    }
}
