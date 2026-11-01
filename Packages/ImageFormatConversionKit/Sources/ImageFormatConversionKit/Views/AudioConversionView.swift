// 音频转换与视频提取音轨的用户界面。
// 从文件或照片选择器接收用户选择，展示导入进度、格式设置、批次进度及输出。
// 文件暂存、检查和转换由音频状态对象协调；页面本身不直接处理编码。
// 页面使用转换主题与共享文件展示组件，并将用户操作转交音频状态对象。
// 音频格式和视频音轨来源通过模型表达，输出文件由底层流程管理。

import SwiftUI
import StoreKit
import PhotosUI
import UniformTypeIdentifiers

/// 展示音频转换设置、导入进度及结果，用户操作交由状态对象处理。
@MainActor
struct AudioConversionView: View {
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @State private var completedBeforeBatch: Set<UUID> = []
    @Environment(\.conversionUsagePolicy) private var usagePolicy
    @Environment(\.conversionTheme) private var theme
    @State private var viewModel: AudioConversionViewModel
    @State private var importSession: ConversionImportSession
    @State private var mediaImporterPresented = false
    @State private var selectedVideoItems: [PhotosPickerItem] = []
    @State private var isClearAllConfirmationPresented = false

    /// 注入音频转换状态与导入会话，由页面持有其展示生命周期。
    init(
        viewModel: AudioConversionViewModel = AudioConversionViewModel(),
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
        .sheet(isPresented: Binding(
            get: { viewModel.isPremiumRequiredPresented },
            set: { viewModel.isPremiumRequiredPresented = $0 }
        )) { usagePolicy.upgradeContent(.audio) }
        .safeAreaInset(edge: .bottom) {
            if !shouldShowImportCard {
                bottomActionBar
            }
        }
        .fileImporter(
            isPresented: $mediaImporterPresented,
            allowedContentTypes: mediaInputTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                Task { await importFiles(urls) }
            case let .failure(error): viewModel.reportImportFailure(error.localizedDescription)
            }
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

    private var shouldShowImportCard: Bool {
        viewModel.items.isEmpty
            && activeImportProgress == nil
            && importSession.pendingCount == 0
    }

    private var activeImportProgress: ConversionImportProgress? {
        importSession.libraryProgress ?? viewModel.importProgress
    }

    private var displayedFileCount: Int {
        max(
            viewModel.items.count,
            importSession.pendingCount,
            activeImportProgress?.total ?? 0
        )
    }

    private var audioInputTypes: [UTType] {
        AudioConversionEngine.supportedInputExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
    }

    private var videoInputTypes: [UTType] {
        var types: [UTType] = [.quickTimeMovie, .mpeg4Movie]
        if let m4v = UTType(filenameExtension: "m4v") { types.append(m4v) }
        return types
    }

    private var mediaInputTypes: [UTType] {
        Array(Set(audioInputTypes + videoInputTypes))
    }

    private var importCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform").font(.system(size: 34)).foregroundStyle(.tint)
            Text(L10n.string("audio.import.title")).appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)
            HStack(spacing: 10) {
                Button { mediaImporterPresented = true } label: {
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
                        title: L10n.string("action.choose_photos"),
                        systemImage: "photo.on.rectangle"
                    )
                }
                .buttonStyle(.bordered)
            }
            .disabled(viewModel.isConverting || activeImportProgress != nil)
        }
        .padding(20)
        .converterCard()
    }

    /// 从照片选择器逐项取得视频并记录资源标识；用会话标识忽略迟到的进度回调。
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

        importSession.librarySessionID = nil
        importSession.libraryProgress = nil
        await viewModel.addFiles(
            urls,
            sourceKind: .video,
            photoAssetIdentifiers: assetIdentifiers,
            progressRange: 0.95 ... 1
        )
    }

    /// 按扩展名区分视频与音频来源，再交由状态对象分别导入。
    private func importMediaFiles(_ urls: [URL]) async {
        let videoExtensions = Set(["mov", "mp4", "m4v"])
        let videoURLs = urls.filter {
            videoExtensions.contains($0.pathExtension.lowercased())
        }
        let audioURLs = urls.filter {
            !videoExtensions.contains($0.pathExtension.lowercased())
        }

        if !audioURLs.isEmpty {
            await viewModel.addFiles(audioURLs, sourceKind: .audioFile)
        }
        if !videoURLs.isEmpty {
            await viewModel.addFiles(videoURLs, sourceKind: .video)
        }
    }

    /// 在导入期间展示待处理文件，结束后清理临时预览状态。
    private func importFiles(_ urls: [URL]) async {
        importSession.pendingCount = urls.count
        importSession.previewURLs = urls
        defer {
            importSession.pendingCount = 0
            importSession.previewURLs = []
        }
        await importMediaFiles(urls)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                ConversionMicroText(L10n.string("settings.format"))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AudioOutputFormat.allCases, id: \.self) { format in
                            let isSelected = viewModel.outputFormat == format
                            Button {
                                viewModel.outputFormat = format
                                if !format.isLossless,
                                   !format.availableBitRates.contains(viewModel.bitRate) {
                                    viewModel.bitRate = .veryHigh
                                }
                            } label: {
                                Text(audioFormatTitle(format))
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

            if viewModel.outputFormat.isLossless {
                Label(L10n.string("audio.lossless"), systemImage: "waveform.badge.checkmark")
                    .appTypeface(.caption, size: 12, relativeTo: .caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ConversionMicroText(L10n.string("audio.settings.quality"))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.outputFormat.availableBitRates, id: \.self) { bitRate in
                                let isSelected = viewModel.bitRate == bitRate
                                Button {
                                    viewModel.bitRate = bitRate
                                } label: {
                                    Text("\(bitRate.rawValue / 1_000) kbps")
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
            }

            ConversionSettingRow(L10n.string("settings.output")) {
                Text(L10n.string("settings.output.audio"))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ConversionSizeEstimateView(estimate: viewModel.sizeEstimate)
        }
        .padding(14)
        .converterCard()
        .disabled(viewModel.isConverting)
    }

    /// 将音频输出格式映射为本地化设置名称。
    private func audioFormatTitle(_ format: AudioOutputFormat) -> String {
        switch format {
        case .mp3: L10n.string("audio.format.mp3")
        case .aac: L10n.string("audio.format.aac")
        case .aacFile: L10n.string("audio.format.aac_file")
        case .alac: L10n.string("audio.format.alac")
        case .wav: L10n.string("audio.format.wav")
        case .aiff: L10n.string("audio.format.aiff")
        case .cafPCM: L10n.string("audio.format.caf_pcm")
        case .cafALAC: L10n.string("audio.format.caf_alac")
        }
    }

    private var selectedFilesCard: some View {
        ConversionFileTray(
            title: activeImportProgress == nil
                ? L10n.format("files.audio.title", displayedFileCount)
                : "\(L10n.string("import.progress.title")) · \(L10n.format("files.audio.title", displayedFileCount))",
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
                    kind: presentation.outputURL == nil && item.sourceKind == .video ? .video : .audio,
                    title: presentationURL.lastPathComponent,
                    subtitle: audioSubtitle(item, outputURL: presentation.outputURL),
                    phase: presentation.phase,
                    statusLabel: presentation.label,
                    isLocked: viewModel.isConverting,
                    outputURL: presentation.outputURL,
                    onRemove: { viewModel.remove(item.id) }
                )
            }

            ForEach(Array(importSession.previewURLs.dropFirst(min(viewModel.items.count, importSession.previewURLs.count)).enumerated()), id: \.offset) { _, url in
                let kind: ConversionFileKind = ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased())
                    ? .video
                    : .audio
                ConversionFileTile(
                    url: url,
                    kind: kind,
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
                    ConversionPendingFileTile(index: index, kind: .audio)
                }
            }
        }
    }

    private var bottomActionBar: some View {
        ConversionNeoBrutalistActionBar(
            countTitle: L10n.format("files.audio.title", displayedFileCount),
            isWorking: viewModel.isConverting,
            progress: (Double(viewModel.completed) + viewModel.itemProgress)
                / Double(max(viewModel.total, 1)),
            progressTitle: "\(viewModel.completed) / \(viewModel.total)",
            isEnabled: viewModel.canConvert,
            onStart: { viewModel.start(usagePolicy: usagePolicy) },
            onCancel: viewModel.cancel
        )
    }

    /// 优先展示源与输出文件大小，再附上来源类型和可用时长。
    private func audioSubtitle(_ item: AudioConversionItem, outputURL: URL?) -> String {
        let sizes = ConversionFileSizePresentation.description(
            sourceBytes: item.sourceBytes,
            outputURL: outputURL
        )
        // Keep the size transition first so compact tiles never truncate the
        // most important result behind source and duration metadata.
        return "\(sizes) · \(sourceDescription(item))"
    }

    /// 为音频来源构造展示说明，帮助区分导入项目。
    private func sourceDescription(_ item: AudioConversionItem) -> String {
        let kind = item.sourceKind == .video
            ? L10n.string("audio.source.video")
            : L10n.string("audio.source.audio")
        guard let duration = item.duration else { return kind }
        let totalSeconds = max(Int(duration.rounded()), 0)
        return "\(kind) · \(String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60))"
    }

}
