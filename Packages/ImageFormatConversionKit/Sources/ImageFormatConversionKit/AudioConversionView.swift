import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct AudioConversionView: View {
    @State private var viewModel = AudioConversionViewModel()
    @State private var mediaImporterPresented = false
    @State private var isClearAllConfirmationPresented = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 16) {
                importCard
                if let progress = viewModel.importProgress {
                    ConversionImportProgressView(progress: progress)
                }
                if let notice = viewModel.notice { NoticeView(message: notice) }
                if viewModel.items.isEmpty { emptyState } else { filesSection }
                settingsCard
                conversionAction
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 20)
        }
        .converterSoftScrollEdge()
        .fileImporter(
            isPresented: $mediaImporterPresented,
            allowedContentTypes: mediaInputTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                Task { await importMediaFiles(urls) }
            case let .failure(error): viewModel.reportImportFailure(error.localizedDescription)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { mediaImporterPresented = true } label: {
                    Label(L10n.string("audio.action.add_media"), systemImage: "plus")
                }
                .disabled(viewModel.isConverting || viewModel.importProgress != nil)
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
            Text(L10n.string("audio.import.title")).font(.headline)
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

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L10n.string("settings.title"), systemImage: "slider.horizontal.3")
                .font(.headline)

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
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            row(L10n.string("settings.output")) {
                Text(viewModel.outputDirectory.lastPathComponent)
                    .font(.footnote).foregroundStyle(.secondary)
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

    private var emptyState: some View {
        ContentUnavailableView(
            L10n.string("audio.empty.title"),
            systemImage: "waveform",
            description: Text(L10n.string("audio.empty.subtitle"))
        )
        .padding(.vertical, 28)
        .converterCard()
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.format("files.audio.title", viewModel.items.count)).font(.headline)
                Spacer()
                Button(L10n.string("action.clear_all"), role: .destructive) {
                    isClearAllConfirmationPresented = true
                }
                    .disabled(viewModel.isConverting)
            }
            ForEach(viewModel.items) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.sourceKind == .video ? "video" : "waveform")
                        .foregroundStyle(.tint)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.sourceURL.lastPathComponent).lineLimit(1)
                        Text(sourceDescription(item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(sizeDescription(item)).font(.caption).foregroundStyle(.secondary)
                        statusText(item.status).font(.caption)
                    }
                    Spacer()
                    if case let .completed(url) = item.status {
                        HStack {
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                            Button(role: .destructive) { viewModel.remove(item.id) } label: {
                                Image(systemName: "trash")
                            }
                        }
                    } else if case .converting = item.status {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(role: .destructive) { viewModel.remove(item.id) } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
                Divider()
            }
        }
        .padding(16)
        .converterCard()
    }

    @ViewBuilder private var conversionAction: some View {
        if viewModel.isConverting {
            VStack(spacing: 10) {
                ProgressView(value: (Double(viewModel.completed) + viewModel.itemProgress) / Double(max(viewModel.total, 1)))
                HStack {
                    Text("\(viewModel.completed) / \(viewModel.total)").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.string("action.cancel"), role: .cancel) { viewModel.cancel() }
                }
            }.padding(16).converterCard()
        } else {
            PrimaryConversionButton(title: L10n.string("action.convert"), isEnabled: viewModel.canConvert, action: viewModel.start)
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack { Text(title); Spacer(); content() }
    }

    private func sizeDescription(_ item: AudioConversionItem) -> String {
        let source = ByteCountFormatter.string(fromByteCount: item.sourceBytes, countStyle: .file)
        guard case let .completed(url) = item.status else { return source }
        let bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return "\(source) → \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }

    private func sourceDescription(_ item: AudioConversionItem) -> String {
        let kind = item.sourceKind == .video
            ? L10n.string("audio.source.video")
            : L10n.string("audio.source.audio")
        guard let duration = item.duration else { return kind }
        let totalSeconds = max(Int(duration.rounded()), 0)
        return "\(kind) · \(String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60))"
    }

    private func statusText(_ status: AudioConversionStatus) -> Text {
        switch status {
        case .ready: Text(L10n.string("status.ready"))
        case .converting: Text(L10n.string("status.converting"))
        case .completed: Text(L10n.string("status.completed"))
        case let .failed(message): Text(message)
        case .cancelled: Text(L10n.string("status.cancelled"))
        }
    }
}
