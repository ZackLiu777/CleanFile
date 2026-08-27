import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@MainActor
struct VideoConversionView: View {
    @State private var viewModel = VideoConversionViewModel()
    @State private var importerPresented = false
    @State private var selectedVideoItems: [PhotosPickerItem] = []
    @State private var isClearAllConfirmationPresented = false
    @State private var libraryImportProgress: ConversionImportProgress?
    @State private var libraryImportSessionID: UUID?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 16) {
                importCard
                if let progress = libraryImportProgress ?? viewModel.importProgress {
                    ConversionImportProgressView(progress: progress)
                }
                if let notice = viewModel.notice { NoticeView(message: notice) }
                if !viewModel.items.isEmpty { filesSection }
                settingsCard
                action
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 20)
        }
        .converterSoftScrollEdge()
        .fileImporter(
            isPresented: $importerPresented,
            allowedContentTypes: supportedVideoImportTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                Task { await viewModel.addFiles(urls) }
            case let .failure(error): viewModel.reportImportFailure(error.localizedDescription)
            }
        }
        .onChange(of: selectedVideoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importVideos(items) }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { importerPresented = true } label: {
                    Label(L10n.string("video.action.add"), systemImage: "video.badge.plus")
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

    private var supportedVideoImportTypes: [UTType] {
        var types: [UTType] = [.quickTimeMovie, .mpeg4Movie]
        if let m4v = UTType(filenameExtension: "m4v") {
            types.append(m4v)
        }
        return types
    }

    private var importCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack").font(.system(size: 34)).foregroundStyle(.tint)
            Text(L10n.string("video.import.title")).font(.headline)
            Button { importerPresented = true } label: {
                Label(L10n.string("action.choose_files"), systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isConverting || viewModel.importProgress != nil)

            PhotosPicker(
                selection: $selectedVideoItems,
                maxSelectionCount: 50,
                matching: .videos
            ) {
                Label(L10n.string("video.action.choose_library"), systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isConverting || viewModel.importProgress != nil)
        }
        .padding(20)
        .converterCard()
    }

    private func importVideos(_ selections: [PhotosPickerItem]) async {
        let sessionID = UUID()
        libraryImportSessionID = sessionID
        defer {
            selectedVideoItems = []
            if libraryImportSessionID == sessionID {
                libraryImportSessionID = nil
                libraryImportProgress = nil
            }
        }
        var urls: [URL] = []
        for (index, selection) in selections.enumerated() {
            libraryImportProgress = ConversionImportProgress(
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
                            guard libraryImportSessionID == sessionID else { return }
                            libraryImportProgress = ConversionImportProgress(
                                completed: index,
                                total: selections.count,
                                currentFileName: nil,
                                currentFileFraction: fraction
                            ).mapped(to: 0 ... 0.95)
                        }
                    }
                ) {
                    urls.append(imported.url)
                }
            } catch {
                viewModel.reportImportFailure(error.localizedDescription)
            }
            libraryImportProgress = ConversionImportProgress(
                completed: index + 1,
                total: selections.count,
                currentFileName: nil
            ).mapped(to: 0 ... 0.95)
        }
        // The workspace copy has byte-accurate progress. Stop masking it with
        // the PhotoKit acquisition phase once all source URLs are available.
        // Invalidate the session first so queued PhotoKit callbacks cannot put
        // the completed 95% acquisition state back on screen.
        libraryImportSessionID = nil
        libraryImportProgress = nil
        await viewModel.addFiles(urls, progressRange: 0.95 ... 1)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ConversionMicroText(L10n.string("settings.title"))

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("settings.format"))
                ConversionSettingsWheelPicker(
                    summary: videoSettingsSummary,
                    detail: L10n.dynamicString("format.video.\(viewModel.container.rawValue).detail")
                ) {
                    HStack(spacing: 0) {
                        ConversionWheelColumn(
                            title: L10n.string("settings.format"),
                            selection: Binding(
                                get: { viewModel.container },
                                set: { viewModel.container = $0 }
                            )
                        ) {
                            ForEach(viewModel.availableContainers) { container in
                                Text(container.rawValue.uppercased()).tag(container)
                            }
                        }
                        ConversionWheelColumn(
                            title: L10n.string("video.settings.codec"),
                            selection: Binding(
                                get: { viewModel.codec },
                                set: { viewModel.codec = $0 }
                            )
                        ) {
                            Text("H.264").tag(VideoCodec.h264)
                            Text("HEVC").tag(VideoCodec.hevc)
                            Text("ProRes 422").tag(VideoCodec.proRes422)
                            Text("ProRes 4444").tag(VideoCodec.proRes4444)
                        }
                        ConversionWheelColumn(
                            title: L10n.string("video.settings.resolution"),
                            selection: Binding(
                                get: { viewModel.resolution },
                                set: { viewModel.resolution = $0 }
                            )
                        ) {
                            ForEach(viewModel.availableResolutions) { preset in
                                Text(resolutionTitle(preset)).tag(preset)
                            }
                        }
                    }
                }
            }
            setting(L10n.string("settings.output")) {
                Text(viewModel.outputDirectory.lastPathComponent)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
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

    private var videoSettingsSummary: String {
        [
            viewModel.container.rawValue.uppercased(),
            codecTitle(viewModel.codec),
            resolutionTitle(viewModel.resolution)
        ].joined(separator: " · ")
    }

    private func codecTitle(_ codec: VideoCodec) -> String {
        switch codec {
        case .h264: "H.264"
        case .hevc: "HEVC"
        case .proRes422: "ProRes 422"
        case .proRes4444: "ProRes 4444"
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.format("files.videos.title", viewModel.items.count)).font(.headline)
                Spacer()
                Button(L10n.string("action.clear_all"), role: .destructive) {
                    isClearAllConfirmationPresented = true
                }
                    .disabled(viewModel.isConverting)
            }
            ForEach(viewModel.items) { item in
                HStack(spacing: 12) {
                    ConversionFileThumbnail(url: item.sourceURL, kind: .video)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.sourceURL.lastPathComponent)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 6) {
                            ConversionStatusDot(
                                phase: phase(item.status),
                                accessibilityLabel: statusText(item.status)
                            )
                            Text(sizeDescription(item))
                        }
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        if case let .failed(message) = item.status {
                            Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
                        }
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
                        Button { viewModel.remove(item.id) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                        }
                    }
                }
                Divider()
            }
        }
        .padding(16)
        .converterCard()
    }

    @ViewBuilder private var action: some View {
        if viewModel.isConverting {
            VStack(spacing: 10) {
                ProgressView(value: (Double(viewModel.completed) + viewModel.currentProgress) / Double(max(viewModel.total, 1)))
                HStack {
                    Text("\(viewModel.completed) / \(viewModel.total)").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.string("action.cancel"), role: .cancel) { viewModel.cancel() }
                }
            }.padding(16).converterCard()
        } else {
            PrimaryConversionButton(
                title: L10n.string("action.convert"),
                isEnabled: viewModel.canConvert,
                action: viewModel.start
            )
        }
    }

    private func setting<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack { Text(title); Spacer(); content() }
    }

    private func resolutionTitle(_ preset: VideoResolutionPreset) -> String {
        switch preset {
        case .original: L10n.string("resize.original")
        case .ultraHD: "4K"
        case .fullHD: "1080p"
        case .hd: "720p"
        case .sd: "480p"
        }
    }

    private func phase(_ status: VideoConversionStatus) -> ConversionFilePhase {
        switch status {
        case .ready, .cancelled: .pending
        case .converting: .working
        case .completed: .completed
        case .failed: .failed
        }
    }

    private func statusText(_ status: VideoConversionStatus) -> String {
        switch status {
        case .ready: L10n.string("status.ready")
        case .converting: L10n.string("status.converting")
        case .completed: L10n.string("status.completed")
        case let .failed(message): message
        case .cancelled: L10n.string("status.cancelled")
        }
    }

    private func sizeDescription(_ item: VideoConversionItem) -> String {
        let source = ByteCountFormatter.string(fromByteCount: item.sourceBytes, countStyle: .file)
        guard case let .completed(url) = item.status else { return source }
        let outputBytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let output = ByteCountFormatter.string(fromByteCount: outputBytes, countStyle: .file)
        return "\(source) → \(output)"
    }
}
