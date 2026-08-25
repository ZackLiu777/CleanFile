import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct AudioConversionView: View {
    @State private var viewModel = AudioConversionViewModel()
    @State private var importerPresented = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                importCard
                settingsCard
                if let notice = viewModel.notice { NoticeView(message: notice) }
                if viewModel.items.isEmpty { emptyState } else { filesSection }
                conversionAction
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .fileImporter(
            isPresented: $importerPresented,
            allowedContentTypes: inputTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls): viewModel.addFiles(urls)
            case let .failure(error): viewModel.reportImportFailure(error.localizedDescription)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { importerPresented = true } label: {
                    Label(L10n.string("audio.action.add"), systemImage: "waveform.badge.plus")
                }
                .disabled(viewModel.isConverting)
            }
        }
    }

    private var inputTypes: [UTType] {
        AudioConversionEngine.supportedInputExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
    }

    private var importCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform").font(.system(size: 34)).foregroundStyle(.tint)
            Text(L10n.string("audio.import.title")).font(.headline)
            Text(L10n.string("import.subtitle"))
                .font(.subheadline).foregroundStyle(.secondary)
            Button { importerPresented = true } label: {
                Label(L10n.string("action.choose_files"), systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .converterCard()
    }

    private var settingsCard: some View {
        VStack(spacing: 14) {
            row(L10n.string("settings.format")) {
                Picker("", selection: Binding(
                    get: { viewModel.outputFormat },
                    set: { viewModel.outputFormat = $0 }
                )) {
                    Text("AAC · M4A").tag(AudioOutputFormat.aac)
                    Text("ALAC · M4A").tag(AudioOutputFormat.alac)
                    Text("WAV · PCM").tag(AudioOutputFormat.wav)
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
                Button(L10n.string("action.clear_all"), role: .destructive) { viewModel.removeAll() }
                    .disabled(viewModel.isConverting)
            }
            ForEach(viewModel.items) { item in
                HStack(spacing: 12) {
                    Image(systemName: "waveform").foregroundStyle(.tint).frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.sourceURL.lastPathComponent).lineLimit(1)
                        Text(sizeDescription(item)).font(.caption).foregroundStyle(.secondary)
                        statusText(item.status).font(.caption)
                    }
                    Spacer()
                    if case let .completed(url) = item.status {
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
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
