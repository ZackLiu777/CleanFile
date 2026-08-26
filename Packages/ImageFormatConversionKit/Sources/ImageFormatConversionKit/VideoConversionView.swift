import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@MainActor
struct VideoConversionView: View {
    @State private var viewModel = VideoConversionViewModel()
    @State private var importerPresented = false
    @State private var selectedVideoItems: [PhotosPickerItem] = []
    @State private var isClearAllConfirmationPresented = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                importCard
                if let notice = viewModel.notice { NoticeView(message: notice) }
                if viewModel.items.isEmpty { emptyState } else { filesSection }
                settingsCard
                action
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .converterSoftScrollEdge()
        .fileImporter(
            isPresented: $importerPresented,
            allowedContentTypes: supportedVideoImportTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls): viewModel.addFiles(urls)
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

            PhotosPicker(
                selection: $selectedVideoItems,
                maxSelectionCount: 50,
                matching: .videos
            ) {
                Label(L10n.string("video.action.choose_library"), systemImage: "photo.on.rectangle")
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
        viewModel.addFiles(urls)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L10n.string("settings.title"), systemImage: "slider.horizontal.3")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("settings.format"))
                ConversionFormatWheelPicker(
                    selection: Binding(
                        get: { viewModel.container },
                        set: { viewModel.container = $0 }
                    ),
                    options: viewModel.availableContainers.map { container in
                        ConversionFormatOption(
                            value: container,
                            title: container.rawValue.uppercased(),
                            detail: L10n.string("format.video.\(container.rawValue).detail")
                        )
                    }
                )
            }
            setting(L10n.string("video.settings.codec")) {
                Picker("", selection: Binding(
                    get: { viewModel.codec },
                    set: { viewModel.codec = $0 }
                )) {
                    Text("H.264").tag(VideoCodec.h264)
                    Text("HEVC").tag(VideoCodec.hevc)
                    Text("ProRes 422").tag(VideoCodec.proRes422)
                    Text("ProRes 4444").tag(VideoCodec.proRes4444)
                }.labelsHidden().pickerStyle(.menu)
            }
            setting(L10n.string("video.settings.resolution")) {
                Picker("", selection: Binding(
                    get: { viewModel.resolution },
                    set: { viewModel.resolution = $0 }
                )) {
                    ForEach(viewModel.availableResolutions) { preset in
                        Text(resolutionTitle(preset)).tag(preset)
                    }
                }.labelsHidden().pickerStyle(.menu)
            }
            setting(L10n.string("settings.output")) {
                Text(viewModel.outputDirectory.lastPathComponent)
                    .font(.footnote).foregroundStyle(.secondary)
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

    private var emptyState: some View {
        ContentUnavailableView(
            L10n.string("video.empty.title"),
            systemImage: "film",
            description: Text(L10n.string("video.empty.subtitle"))
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
                    Image(systemName: "film").foregroundStyle(.tint).frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.sourceURL.lastPathComponent).lineLimit(1)
                        Text(sizeDescription(item))
                            .font(.caption).foregroundStyle(.secondary)
                        status(item.status).font(.caption)
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

    private func status(_ status: VideoConversionStatus) -> Text {
        switch status {
        case .ready: Text(L10n.string("status.ready"))
        case .converting: Text(L10n.string("status.converting"))
        case .completed: Text(L10n.string("status.completed"))
        case let .failed(message): Text(message)
        case .cancelled: Text(L10n.string("status.cancelled"))
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
