//
//  文件职责：声明 VideoConversion 界面结构、交互入口与展示状态。
//  所属模块：ImageFormatConversionKit。
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@MainActor
/// 定义 `VideoConversionView` 的值语义数据与相关行为。
struct VideoConversionView: View {
    @Environment(\.conversionTheme) private var theme
    @State private var viewModel: VideoConversionViewModel
    @State private var importSession: ConversionImportSession
    @State private var importerPresented = false
    @State private var selectedVideoItems: [PhotosPickerItem] = []
    @State private var isClearAllConfirmationPresented = false
    @State private var isAdvancedExpanded = false

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    init(
        viewModel: VideoConversionViewModel = VideoConversionViewModel(),
        importSession: ConversionImportSession = ConversionImportSession()
    ) {
        _viewModel = State(initialValue: viewModel)
        _importSession = State(initialValue: importSession)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 14) {
                if shouldShowImportCard { importCard } else { selectedFilesCard }
                if let notice = viewModel.notice { NoticeView(message: notice) }
                settingsCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .converterSoftScrollEdge()
        .safeAreaInset(edge: .bottom) {
            if !shouldShowImportCard {
                bottomActionBar
            }
        }
        .fileImporter(
            isPresented: $importerPresented,
            allowedContentTypes: supportedVideoImportTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                Task { await importFiles(urls) }
            case let .failure(error): viewModel.reportImportFailure(error.localizedDescription)
            }
        }
        .onChange(of: selectedVideoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importVideos(items) }
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

    private var supportedVideoImportTypes: [UTType] {
        var types: [UTType] = [.quickTimeMovie, .mpeg4Movie]
        if let m4v = UTType(filenameExtension: "m4v") {
            types.append(m4v)
        }
        return types
    }

    private var importCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack").font(.system(size: 34)).foregroundStyle(.tint)
            Text(L10n.string("video.import.title")).appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)
            HStack(spacing: 10) {
                Button { importerPresented = true } label: {
                    ConversionImportButtonLabel(
                        title: L10n.string("action.choose_files"),
                        systemImage: "folder"
                    )
                }
                .buttonStyle(.bordered)

                PhotosPicker(
                    selection: $selectedVideoItems,
                    maxSelectionCount: 50,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    ConversionImportButtonLabel(
                        title: L10n.string("video.action.choose_library"),
                        systemImage: "photo.on.rectangle"
                    )
                }
                .buttonStyle(.bordered)
            }
            .disabled(viewModel.isConverting || viewModel.importProgress != nil)
        }
        .padding(20)
        .converterCard()
    }

    /// 处理 `importVideos` 导入流程，并将用户选择安全地交给后续处理。
    private func importVideos(_ selections: [PhotosPickerItem]) async {
        let sessionID = UUID()
        importSession.librarySessionID = sessionID
        importSession.pendingCount = selections.count
        defer {
            selectedVideoItems = []
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
                    type: ImportedVideoFile.self,
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
        // The workspace copy has byte-accurate progress. Stop masking it with
        // the PhotoKit acquisition phase once all source URLs are available.
        // Invalidate the session first so queued PhotoKit callbacks cannot put
        // the completed 95% acquisition state back on screen.
        importSession.librarySessionID = nil
        importSession.libraryProgress = nil
        await viewModel.addFiles(
            urls,
            photoAssetIdentifiers: assetIdentifiers,
            progressRange: 0.95 ... 1
        )
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

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                ConversionMicroText(L10n.string("settings.format"))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.availableContainers, id: \.self) { container in
                            let isSelected = viewModel.container == container
                            Button {
                                viewModel.container = container
                            } label: {
                                Text(container.rawValue.uppercased())
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

            if viewModel.codec == .h264 || viewModel.codec == .hevc {
                SegmentedStreamSlider(
                    value: Binding(
                        get: { viewModel.bitRateFraction },
                        set: { viewModel.bitRateFraction = $0 }
                    ),
                    title: L10n.string("video.settings.bitrate")
                )
                Text(L10n.string("video.settings.bitrate.help"))
                    .appTypeface(.caption2, size: 11, relativeTo: .caption2)
                    .foregroundStyle(.secondary)
            }

            Divider().opacity(0.4)

            DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                VStack(spacing: 12) {
                    compactPickerRow(
                        title: L10n.string("video.settings.codec"),
                        selection: Binding(
                            get: { viewModel.codec },
                            set: { viewModel.codec = $0 }
                        ),
                        options: VideoCodec.allCases,
                        optionTitle: videoCodecTitle
                    )

                    compactPickerRow(
                        title: L10n.string("video.settings.resolution"),
                        selection: Binding(
                            get: { viewModel.resolution },
                            set: { viewModel.resolution = $0 }
                        ),
                        options: viewModel.availableResolutions,
                        optionTitle: resolutionTitle
                    )

                    ConversionSettingRow(L10n.string("settings.output")) {
                        Text(L10n.string("settings.output.videos"))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 10)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(L10n.string("settings.title"))
                        .appTypeface(.subheadline, size: 15, relativeTo: .subheadline)
                    Spacer()
                    if !isAdvancedExpanded {
                        Text(videoAdvancedSummary)
                            .appTypeface(.caption, size: 12, relativeTo: .caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .tint(theme.textPrimary)

            ConversionSizeEstimateView(
                estimate: viewModel.sizeEstimate,
                isLoading: viewModel.isEstimatingSize
            )
        }
        .padding(14)
        .converterCard()
        .disabled(viewModel.isConverting)
        .onChange(of: viewModel.codec) { _, _ in
            if !viewModel.availableContainers.contains(viewModel.container) {
                viewModel.container = viewModel.availableContainers[0]
            }
            if !viewModel.availableResolutions.contains(viewModel.resolution) {
                viewModel.resolution = viewModel.availableResolutions[0]
            }
        }
    }

    private func videoCodecTitle(_ codec: VideoCodec) -> String {
        switch codec {
        case .h264: "H.264"
        case .hevc: "HEVC"
        case .proRes422: "ProRes 422"
        case .proRes4444: "ProRes 4444"
        }
    }

    private var videoAdvancedSummary: String {
        [
            videoCodecTitle(viewModel.codec),
            resolutionTitle(viewModel.resolution)
        ].joined(separator: " · ")
    }

    private func compactPickerRow<Option: Hashable>(
        title: String,
        selection: Binding<Option>,
        options: [Option],
        optionTitle: @escaping (Option) -> String
    ) -> some View {
        HStack {
            Text(title)
                .appTypeface(.subheadline, size: 15, relativeTo: .subheadline)
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

    private var selectedFilesCard: some View {
        ConversionFileTray(
            title: activeImportProgress == nil
                ? L10n.format("files.videos.title", displayedFileCount)
                : "\(L10n.string("import.progress.title")) · \(L10n.format("files.videos.title", displayedFileCount))",
            progress: activeImportProgress,
            rowCount: displayedFileCount > 3 ? 2 : 1,
            canClear: !viewModel.isConverting && activeImportProgress == nil,
            onClear: { isClearAllConfirmationPresented = true }
        ) {
            ForEach(viewModel.items) { item in
                let presentation = item.status.conversionPresentation
                let presentationURL = presentation.outputURL ?? item.sourceURL
                ConversionFileTile(
                    url: presentationURL,
                    kind: .video,
                    title: presentationURL.lastPathComponent,
                    subtitle: ConversionFileSizePresentation.description(sourceBytes: item.sourceBytes, outputURL: presentation.outputURL),
                    phase: presentation.phase,
                    statusLabel: presentation.label,
                    isLocked: viewModel.isConverting,
                    outputURL: presentation.outputURL,
                    onRemove: { viewModel.remove(item.id) }
                )
            }

            ForEach(Array(importSession.previewURLs.dropFirst(min(viewModel.items.count, importSession.previewURLs.count)).enumerated()), id: \.offset) { _, url in
                ConversionFileTile(
                    url: url,
                    kind: .video,
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
                    ConversionPendingFileTile(index: index, kind: .video)
                }
            }
        }
    }

    private var bottomActionBar: some View {
        ConversionNeoBrutalistActionBar(
            countTitle: L10n.format("files.videos.title", displayedFileCount),
            isWorking: viewModel.isConverting,
            progress: (Double(viewModel.completed) + viewModel.currentProgress)
                / Double(max(viewModel.total, 1)),
            progressTitle: "\(viewModel.completed) / \(viewModel.total)",
            isEnabled: viewModel.canConvert,
            onStart: viewModel.start,
            onCancel: viewModel.cancel
        )
    }

    /// 封装 `resolutionTitle` 对应的局部行为，供当前类型在统一入口下复用。
    private func resolutionTitle(_ preset: VideoResolutionPreset) -> String {
        switch preset {
        case .original: L10n.string("resize.original")
        case .ultraHD: "4K"
        case .fullHD: "1080p"
        case .hd: "720p"
        case .sd: "480p"
        }
    }

}
