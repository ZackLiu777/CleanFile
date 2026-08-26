import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@MainActor
struct AudioConversionView: View {
    @State private var viewModel = AudioConversionViewModel()
    @State private var audioImporterPresented = false
    @State private var videoImporterPresented = false
    @State private var selectedVideoItems: [PhotosPickerItem] = []
    @State private var isClearAllConfirmationPresented = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                importCard
                if let notice = viewModel.notice { NoticeView(message: notice) }
                if viewModel.items.isEmpty { emptyState } else { filesSection }
                settingsCard
                conversionAction
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .converterSoftScrollEdge()
        .fileImporter(
            isPresented: $audioImporterPresented,
            allowedContentTypes: audioInputTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls): viewModel.addFiles(urls, sourceKind: .audioFile)
            case let .failure(error): viewModel.reportImportFailure(error.localizedDescription)
            }
        }
        .fileImporter(
            isPresented: $videoImporterPresented,
            allowedContentTypes: videoInputTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls): viewModel.addFiles(urls, sourceKind: .video)
            case let .failure(error): viewModel.reportImportFailure(error.localizedDescription)
            }
        }
        .onChange(of: selectedVideoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importVideos(items) }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { audioImporterPresented = true } label: {
                        Label(L10n.string("audio.action.add_audio"), systemImage: "waveform.badge.plus")
                    }
                    Button { videoImporterPresented = true } label: {
                        Label(L10n.string("audio.action.add_video"), systemImage: "video.badge.plus")
                    }
                } label: {
                    Label(L10n.string("audio.action.add"), systemImage: "plus")
                }
                .disabled(viewModel.isConverting)
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

    private var importCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform").font(.system(size: 34)).foregroundStyle(.tint)
            Text(L10n.string("audio.import.title")).font(.headline)
            Button { audioImporterPresented = true } label: {
                Label(L10n.string("audio.action.add_audio"), systemImage: "waveform.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button { videoImporterPresented = true } label: {
                Label(L10n.string("audio.action.add_video_file"), systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            PhotosPicker(selection: $selectedVideoItems, maxSelectionCount: 50, matching: .videos) {
                Label(L10n.string("audio.action.choose_video_library"), systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .converterCard()
    }

    private func importVideos(_ selections: [PhotosPickerItem]) async {
        var urls: [URL] = []
        for selection in selections {
            do {
                if let imported = try await selection.loadTransferable(type: ImportedVideoFile.self) {
                    urls.append(imported.url)
                }
            } catch {
                viewModel.reportImportFailure(error.localizedDescription)
            }
        }
        selectedVideoItems = []
        viewModel.addFiles(urls, sourceKind: .video)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L10n.string("settings.title"), systemImage: "slider.horizontal.3")
                .font(.headline)

            row(L10n.string("settings.format")) {
                Picker("", selection: Binding(
                    get: { viewModel.outputFormat },
                    set: { viewModel.outputFormat = $0 }
                )) {
                    Text(L10n.string("audio.format.aac")).tag(AudioOutputFormat.aac)
                    Text(L10n.string("audio.format.aac_file")).tag(AudioOutputFormat.aacFile)
                    Text(L10n.string("audio.format.alac")).tag(AudioOutputFormat.alac)
                    Text(L10n.string("audio.format.wav")).tag(AudioOutputFormat.wav)
                    Text(L10n.string("audio.format.aiff")).tag(AudioOutputFormat.aiff)
                    Text(L10n.string("audio.format.caf_pcm")).tag(AudioOutputFormat.cafPCM)
                    Text(L10n.string("audio.format.caf_alac")).tag(AudioOutputFormat.cafALAC)
                }.labelsHidden().pickerStyle(.menu)
            }
            if !viewModel.outputFormat.isLossless {
                row(L10n.string("audio.settings.quality")) {
                    Picker("", selection: Binding(
                        get: { viewModel.bitRate },
                        set: { viewModel.bitRate = $0 }
                    )) {
                        ForEach(AudioBitRate.allCases) { bitRate in
                            Text("\(bitRate.rawValue / 1_000) kbps").tag(bitRate)
                        }
                    }.labelsHidden().pickerStyle(.menu)
                }
            } else {
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
                Text(L10n.format("files.title", viewModel.items.count)).font(.headline)
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
