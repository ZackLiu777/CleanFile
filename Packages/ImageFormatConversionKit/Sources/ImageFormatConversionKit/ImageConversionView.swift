import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@MainActor
public struct ImageConversionView: View {
    @State private var mode: ConversionMode = .image
    @State private var isFormatSheetPresented = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.string("converter.mode"), selection: $mode) {
                Label(L10n.string("converter.mode.image"), systemImage: "photo").tag(ConversionMode.image)
                Label(L10n.string("converter.mode.video"), systemImage: "film").tag(ConversionMode.video)
                Label(L10n.string("converter.mode.audio"), systemImage: "waveform").tag(ConversionMode.audio)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 10)

            formatSummary
                .padding(.horizontal, 16)
                .padding(.top, 10)

            switch mode {
            case .image: ImageConversionContentView()
            case .video: VideoConversionView()
            case .audio: AudioConversionView()
            }
        }
        .background(converterBackground)
        .navigationTitle(L10n.string("converter.title"))
        .sheet(isPresented: $isFormatSheetPresented) {
            SupportedFormatsSheet(mode: mode)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var formatSummary: some View {
        HStack(spacing: 12) {
            Text(formatSummaryText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            formatDetailsButton
        }
    }

    private var formatSummaryText: String {
        switch mode {
        case .image: L10n.string("formats.image.summary")
        case .video: L10n.string("formats.video.summary")
        case .audio: L10n.string("formats.audio.summary")
        }
    }

    @ViewBuilder
    private var formatDetailsButton: some View {
        if #available(iOS 26.0, *) {
            Button(L10n.string("formats.view_all")) {
                isFormatSheetPresented = true
            }
            .buttonStyle(.glass)
        } else {
            Button(L10n.string("formats.view_all")) {
                isFormatSheetPresented = true
            }
            .buttonStyle(.bordered)
        }
    }

    private var converterBackground: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.14), Color.accentColor.opacity(0.04), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private enum ConversionMode: Hashable {
    case image
    case video
    case audio
}

private struct SupportedFormatsSheet: View {
    let mode: ConversionMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
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
                            title: L10n.string("formats.export"),
                            formats: ["AAC · M4A", "ALAC · M4A", "WAV · PCM"]
                        )
                    }
                }
                .padding(20)
            }
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

    private func formatName(_ format: ImageOutputFormat) -> String {
        format.rawValue.uppercased()
    }
}

private struct FormatChipSection: View {
    let title: String
    let formats: [String]
    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(formats, id: \.self) { format in
                    Text(format)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                }
            }
        }
    }
}

@MainActor
private struct ImageConversionContentView: View {
    @State private var viewModel: ImageConversionViewModel
    @State private var isImporterPresented = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    init(viewModel: ImageConversionViewModel = ImageConversionViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                importCard
                ImageConversionSettingsCard(viewModel: viewModel)

                if let notice = viewModel.notice {
                    NoticeView(message: notice)
                }

                if viewModel.items.isEmpty {
                    emptyState
                } else {
                    filesSection
                }

                conversionAction
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isImporterPresented = true
                } label: {
                    Label(
                        L10n.string("action.add_images"),
                        systemImage: "photo.badge.plus"
                    )
                }
                .disabled(viewModel.isConverting)
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: ImageConversionEngine.supportedInputContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                Task { @MainActor in
                    await viewModel.addFiles(urls)
                }
            case let .failure(error):
                let message = error.localizedDescription
                Task { @MainActor in
                    viewModel.reportImportFailure(message)
                }
            }
        }
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
    }

    private var importCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.tint)

            VStack(spacing: 4) {
                Text(L10n.string("import.title"))
                    .font(.headline)
                Text(L10n.string("import.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                isImporterPresented = true
            } label: {
                Label(L10n.string("action.choose_files"), systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isConverting)

            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: 100,
                matching: .images
            ) {
                Label(L10n.string("action.choose_photos"), systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isConverting)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .converterCard()
    }

    private func importPhotos(_ selections: [PhotosPickerItem]) async {
        var urls: [URL] = []
        for selection in selections {
            do {
                if let imported = try await selection.loadTransferable(type: ImportedPhotoFile.self) {
                    urls.append(imported.url)
                }
            } catch {
                viewModel.reportImportFailure(error.localizedDescription)
            }
        }
        selectedPhotoItems = []
        await viewModel.addFiles(urls)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            L10n.string("empty.title"),
            systemImage: "photo.on.rectangle.angled",
            description: Text(L10n.string("empty.subtitle"))
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .converterCard()
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.format("files.title", viewModel.items.count))
                    .font(.headline)

                Spacer()

                Menu {
                    if viewModel.completedCount > 0 {
                        Button(L10n.string("action.clear_completed")) {
                            viewModel.clearCompleted()
                        }
                    }
                    Button(L10n.string("action.clear_all"), role: .destructive) {
                        viewModel.removeAll()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(viewModel.isConverting)
            }

            ForEach(viewModel.items) { item in
                ImageConversionFileRow(
                    item: item,
                    isLocked: viewModel.isConverting,
                    onRemove: { viewModel.removeItem(id: item.id) }
                )

                if item.id != viewModel.items.last?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .converterCard()
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
                    .font(.footnote)
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
private struct ImageConversionSettingsCard: View {
    @Bindable var viewModel: ImageConversionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L10n.string("settings.title"), systemImage: "slider.horizontal.3")
                .font(.headline)

            settingRow(title: L10n.string("settings.format")) {
                Picker(L10n.string("settings.format"), selection: $viewModel.outputFormat) {
                    ForEach(viewModel.availableFormats) { format in
                        Text(format.rawValue.uppercased()).tag(format)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            if viewModel.outputFormat.supportsQuality {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.string("settings.quality"))
                        Spacer()
                        Text(viewModel.quality, format: .percent.precision(.fractionLength(0)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $viewModel.quality, in: 0.1 ... 1, step: 0.05)

                    HStack {
                        Text(L10n.string("quality.smaller"))
                        Spacer()
                        Text(L10n.string("quality.balanced"))
                        Spacer()
                        Text(L10n.string("quality.best"))
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                    Label(qualityExplanation, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            settingRow(title: L10n.string("settings.metadata")) {
                Picker(L10n.string("settings.metadata"), selection: $viewModel.metadataPolicy) {
                    ForEach(ImageMetadataPolicy.allCases) { policy in
                        Text(metadataTitle(policy)).tag(policy)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            settingRow(title: L10n.string("settings.resize")) {
                Picker(L10n.string("settings.resize"), selection: $viewModel.resizePreset) {
                    ForEach(ImageResizePreset.allCases) { preset in
                        Text(resizeTitle(preset)).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            if viewModel.outputFormat.requiresOpaquePixels {
                settingRow(title: L10n.string("settings.transparent_background")) {
                    Picker(
                        L10n.string("settings.transparent_background"),
                        selection: $viewModel.flattenColor
                    ) {
                        Text(L10n.string("color.white")).tag(ImageFlattenColor.white)
                        Text(L10n.string("color.black")).tag(ImageFlattenColor.black)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string("settings.output"))
                Spacer()
                Text(viewModel.outputDirectory.lastPathComponent)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .converterCard()
        .disabled(viewModel.isConverting)
    }

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

    private func metadataTitle(_ policy: ImageMetadataPolicy) -> String {
        switch policy {
        case .preserve: L10n.string("metadata.preserve")
        case .removeGPS: L10n.string("metadata.remove_gps")
        case .removeAll: L10n.string("metadata.remove_all")
        }
    }

    private func resizeTitle(_ preset: ImageResizePreset) -> String {
        switch preset {
        case .original: L10n.string("resize.original")
        case .ultraHD: L10n.string("resize.4096")
        case .large: L10n.string("resize.2048")
        case .medium: L10n.string("resize.1280")
        }
    }

    private var qualityExplanation: String {
        switch viewModel.quality {
        case ..<0.5: L10n.string("quality.explanation.small")
        case ..<0.8: L10n.string("quality.explanation.balanced")
        default: L10n.string("quality.explanation.high")
        }
    }
}

@MainActor
private struct ImageConversionFileRow: View {
    let item: ImageConversionItem
    let isLocked: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.sourceURL.lastPathComponent)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                if let info = item.info {
                    Text(
                        "\(info.pixelWidth) × \(info.pixelHeight)  ·  "
                            + ByteCountFormatter.string(
                                fromByteCount: info.fileSizeBytes,
                                countStyle: .file
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }

                statusLabel
            }

            Spacer(minLength: 8)

            trailingAction
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch item.status {
        case .inspecting:
            Label(L10n.string("status.inspecting"), systemImage: "magnifyingglass")
                .foregroundStyle(.secondary)
        case .ready:
            Label(L10n.string("status.ready"), systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .converting:
            Label(L10n.string("status.converting"), systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.tint)
        case .completed:
            Label(L10n.string("status.completed"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(2)
        case .cancelled:
            Label(L10n.string("status.cancelled"), systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var trailingAction: some View {
        switch item.status {
        case let .completed(outputURL):
            ShareLink(item: outputURL) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.string("action.share"))
        case .converting, .inspecting:
            ProgressView()
                .controlSize(.small)
        case .ready, .failed, .cancelled:
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .disabled(isLocked)
            .accessibilityLabel(L10n.string("action.remove"))
        }
    }
}

struct NoticeView: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.tint)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .converterCard()
    }
}

@MainActor
struct PrimaryConversionButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Group {
#if os(iOS)
            if #available(iOS 26.0, *) {
                Button(action: action) {
                    Label(title, systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
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
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
    }
}

private struct ConverterCardModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
#if os(iOS)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 20))
        } else {
            fallback(content)
        }
#else
        fallback(content)
#endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            }
    }
}

extension View {
    func converterCard() -> some View {
        modifier(ConverterCardModifier())
    }
}
