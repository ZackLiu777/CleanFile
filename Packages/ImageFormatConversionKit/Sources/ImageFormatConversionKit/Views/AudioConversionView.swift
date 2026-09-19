//
//  文件职责：声明 AudioConversion 界面结构、交互入口与展示状态。
//  所属模块：ImageFormatConversionKit。
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@MainActor
/// 定义 `AudioConversionView` 的值语义数据与相关行为。
struct AudioConversionView: View {
    @State private var viewModel: AudioConversionViewModel
    @State private var importSession: ConversionImportSession
    @State private var mediaImporterPresented = false
    @State private var selectedVideoItems: [PhotosPickerItem] = []
    @State private var isClearAllConfirmationPresented = false

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    init(
        viewModel: AudioConversionViewModel = AudioConversionViewModel(),
        importSession: ConversionImportSession = ConversionImportSession()
    ) {
        _viewModel = State(initialValue: viewModel)
        _importSession = State(initialValue: importSession)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 16) {
                if shouldShowImportCard { importCard } else { selectedFilesCard }
                if let notice = viewModel.notice { NoticeView(message: notice) }
                settingsCard
                conversionAction
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .converterSoftScrollEdge()
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
        VStack(spacing: 12) {
            Image(systemName: "waveform").font(.system(size: 34)).foregroundStyle(.tint)
            Text(L10n.string("audio.import.title")).appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)
            Button { mediaImporterPresented = true } label: {
                Label(L10n.string("action.choose_files"), systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isConverting || activeImportProgress != nil)

            PhotosPicker(
                selection: $selectedVideoItems,
                maxSelectionCount: 50,
                matching: .videos
            ) {
                Label(L10n.string("action.choose_photos"), systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isConverting || activeImportProgress != nil)
        }
        .padding(20)
        .converterCard()
    }

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
        await viewModel.addFiles(urls, sourceKind: .video, progressRange: 0.95 ... 1)
    }

    /// 处理 `importMediaFiles` 导入流程，并将用户选择安全地交给后续处理。
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

    /// 处理 `importFiles` 导入流程，并将用户选择安全地交给后续处理。
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
            ConversionMicroText(L10n.string("settings.title"))

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("settings.format"))
                ConversionSettingsWheelPicker(
                    summary: audioSettingsSummary,
                    detail: L10n.dynamicString("format.audio.\(viewModel.outputFormat.rawValue).detail")
                ) {
                    HStack(spacing: 0) {
                        ConversionWheelColumn(
                            title: L10n.string("settings.format"),
                            selection: Binding(
                                get: { viewModel.outputFormat },
                                set: { format in
                                    viewModel.outputFormat = format
                                    if !format.isLossless,
                                       !format.availableBitRates.contains(viewModel.bitRate) {
                                        viewModel.bitRate = .veryHigh
                                    }
                                }
                            ),
                            options: AudioOutputFormat.allCases,
                            optionTitle: audioFormatTitle
                        )
                        if !viewModel.outputFormat.isLossless {
                            ConversionWheelColumn(
                                title: L10n.string("audio.settings.quality"),
                                selection: Binding(
                                    get: { viewModel.bitRate },
                                    set: { viewModel.bitRate = $0 }
                                ),
                                options: viewModel.outputFormat.availableBitRates,
                                optionTitle: { "\($0.rawValue / 1_000) kbps" }
                            )
                        }
                    }
                }
            }
            if viewModel.outputFormat.isLossless {
                Label(L10n.string("audio.lossless"), systemImage: "waveform.badge.checkmark")
                    .appTypeface(.caption, size: 12, relativeTo: .caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ConversionSettingRow(L10n.string("settings.output")) {
                Text(L10n.string("settings.output.audio"))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ConversionSizeEstimateView(estimate: viewModel.sizeEstimate)
        }
        .padding(16)
        .converterCard()
        .disabled(viewModel.isConverting)
    }

    private var audioSettingsSummary: String {
        guard !viewModel.outputFormat.isLossless else {
            return audioFormatTitle(viewModel.outputFormat)
        }

        return [
            audioFormatTitle(viewModel.outputFormat),
            "\(viewModel.bitRate.rawValue / 1_000) kbps"
        ].joined(separator: " · ")
    }

    /// 封装 `audioFormatTitle` 对应的局部行为，供当前类型在统一入口下复用。
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
            onClear: { isClearAllConfirmationPresented = true }
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

    @ViewBuilder private var conversionAction: some View {
        if viewModel.isConverting {
            VStack(spacing: 10) {
                ProgressView(value: (Double(viewModel.completed) + viewModel.itemProgress) / Double(max(viewModel.total, 1)))
                HStack {
                    Text("\(viewModel.completed) / \(viewModel.total)").appTypeface(.footnote, size: 13, relativeTo: .footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.string("action.cancel"), role: .cancel) { viewModel.cancel() }
                }
            }.padding(16).converterCard()
        } else {
            PrimaryConversionButton(title: L10n.string("action.convert"), isEnabled: viewModel.canConvert, action: viewModel.start)
        }
    }

    /// 封装 `sourceDescription` 对应的局部行为，供当前类型在统一入口下复用。
    private func audioSubtitle(_ item: AudioConversionItem, outputURL: URL?) -> String {
        let sizes = ConversionFileSizePresentation.description(
            sourceBytes: item.sourceBytes,
            outputURL: outputURL
        )
        // Keep the size transition first so compact tiles never truncate the
        // most important result behind source and duration metadata.
        return "\(sizes) · \(sourceDescription(item))"
    }

    private func sourceDescription(_ item: AudioConversionItem) -> String {
        let kind = item.sourceKind == .video
            ? L10n.string("audio.source.video")
            : L10n.string("audio.source.audio")
        guard let duration = item.duration else { return kind }
        let totalSeconds = max(Int(duration.rounded()), 0)
        return "\(kind) · \(String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60))"
    }

}
