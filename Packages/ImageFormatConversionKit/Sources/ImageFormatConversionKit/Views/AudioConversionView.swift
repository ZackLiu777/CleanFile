//
//  文件职责：声明 AudioConversion 界面结构、交互入口与展示状态。
//  所属模块：ImageFormatConversionKit。
//

import SwiftUI
import UniformTypeIdentifiers

@MainActor
/// 定义 `AudioConversionView` 的值语义数据与相关行为。
struct AudioConversionView: View {
    @State private var viewModel: AudioConversionViewModel
    @State private var importSession: ConversionImportSession
    @State private var mediaImporterPresented = false
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
            && viewModel.importProgress == nil
            && importSession.pendingCount == 0
    }

    private var displayedFileCount: Int {
        max(
            viewModel.items.count,
            importSession.pendingCount,
            viewModel.importProgress?.total ?? 0
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
                Label(L10n.string("audio.action.add_media"), systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isConverting || viewModel.importProgress != nil)
        }
        .padding(20)
        .converterCard()
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
                                set: { viewModel.outputFormat = $0 }
                            )
                        ) {
                            ForEach(AudioOutputFormat.allCases) { format in
                                Text(audioFormatTitle(format)).tag(format)
                            }
                        }
                        ConversionWheelColumn(
                            title: L10n.string("audio.settings.quality"),
                            selection: Binding(
                                get: { viewModel.bitRate },
                                set: { viewModel.bitRate = $0 }
                            )
                        ) {
                            ForEach(AudioBitRate.allCases) { bitRate in
                                Text("\(bitRate.rawValue / 1_000) kbps").tag(bitRate)
                            }
                        }
                    }
                }
            }
            if viewModel.outputFormat.isLossless {
                Label(L10n.string("audio.lossless"), systemImage: "waveform.badge.checkmark")
                    .appTypeface(.caption, size: 12, relativeTo: .caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            row(L10n.string("settings.output")) {
                Text(viewModel.outputDirectory.lastPathComponent)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .converterCard()
        .disabled(viewModel.isConverting)
    }

    private var audioSettingsSummary: String {
        let quality = viewModel.outputFormat.isLossless
            ? L10n.string("audio.lossless")
            : "\(viewModel.bitRate.rawValue / 1_000) kbps"
        return [audioFormatTitle(viewModel.outputFormat), quality]
            .joined(separator: " · ")
    }

    /// 封装 `audioFormatTitle` 对应的局部行为，供当前类型在统一入口下复用。
    private func audioFormatTitle(_ format: AudioOutputFormat) -> String {
        switch format {
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
            title: viewModel.importProgress == nil
                ? L10n.format("files.audio.title", displayedFileCount)
                : "\(L10n.string("import.progress.title")) · \(L10n.format("files.audio.title", displayedFileCount))",
            progress: viewModel.importProgress,
            rowCount: displayedFileCount > 3 ? 2 : 1,
            canClear: !viewModel.isConverting && viewModel.importProgress == nil,
            onClear: { isClearAllConfirmationPresented = true }
        ) {
            ForEach(viewModel.items) { item in
                let presentationURL = outputURL(item.status) ?? item.sourceURL
                ConversionFileTile(
                    url: presentationURL,
                    kind: outputURL(item.status) == nil && item.sourceKind == .video ? .video : .audio,
                    title: presentationURL.lastPathComponent,
                    subtitle: "\(sourceDescription(item)) · \(sizeDescription(item))",
                    phase: phase(item.status),
                    statusLabel: statusString(item.status),
                    isLocked: viewModel.isConverting,
                    outputURL: outputURL(item.status),
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

    /// 封装 `row` 对应的局部行为，供当前类型在统一入口下复用。
    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack { Text(title); Spacer(); content() }
    }

    /// 封装 `sizeDescription` 对应的局部行为，供当前类型在统一入口下复用。
    private func sizeDescription(_ item: AudioConversionItem) -> String {
        let source = ByteCountFormatter.string(fromByteCount: item.sourceBytes, countStyle: .file)
        guard case let .completed(url) = item.status else { return source }
        let bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return "\(source) → \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }

    /// 封装 `outputURL` 对应的局部行为，供当前类型在统一入口下复用。
    private func outputURL(_ status: AudioConversionStatus) -> URL? {
        guard case let .completed(url) = status else { return nil }
        return url
    }

    /// 封装 `sourceDescription` 对应的局部行为，供当前类型在统一入口下复用。
    private func sourceDescription(_ item: AudioConversionItem) -> String {
        let kind = item.sourceKind == .video
            ? L10n.string("audio.source.video")
            : L10n.string("audio.source.audio")
        guard let duration = item.duration else { return kind }
        let totalSeconds = max(Int(duration.rounded()), 0)
        return "\(kind) · \(String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60))"
    }

    /// 封装 `phase` 对应的局部行为，供当前类型在统一入口下复用。
    private func phase(_ status: AudioConversionStatus) -> ConversionFilePhase {
        switch status {
        case .ready, .cancelled: .pending
        case .converting: .working
        case .completed: .completed
        case .failed: .failed
        }
    }

    /// 封装 `statusString` 对应的局部行为，供当前类型在统一入口下复用。
    private func statusString(_ status: AudioConversionStatus) -> String {
        switch status {
        case .ready: L10n.string("status.ready")
        case .converting: L10n.string("status.converting")
        case .completed: L10n.string("status.completed")
        case let .failed(message): message
        case .cancelled: L10n.string("status.cancelled")
        }
    }
}
