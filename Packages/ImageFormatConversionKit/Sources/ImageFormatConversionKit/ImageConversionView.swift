import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
public struct ImageConversionView: View {
    private let theme: ConversionTheme
    @AppStorage("conversion.selectedMode") private var mode: ConversionMode = .image
    @State private var isFormatSheetPresented = false

    public init(theme: ConversionTheme = .system) {
        self.theme = theme
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(L10n.string("converter.mode"), selection: $mode) {
                    Label(L10n.string("converter.mode.image"), systemImage: "photo").tag(ConversionMode.image)
                    Label(L10n.string("converter.mode.video"), systemImage: "film").tag(ConversionMode.video)
                    Label(L10n.string("converter.mode.audio"), systemImage: "waveform").tag(ConversionMode.audio)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 4)
                .padding(.top, 2)

                privacySummary
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                switch mode {
                case .image: ImageConversionContentView()
                case .video: VideoConversionView()
                case .audio: AudioConversionView()
                }
            }
            .background(converterBackground)
        }
        .environment(\.conversionTheme, theme)
        .tint(theme.accent)
        .foregroundStyle(theme.textPrimary)
        .sheet(isPresented: $isFormatSheetPresented) {
            SupportedFormatsSheet(mode: mode)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var privacySummary: some View {
        HStack(spacing: 12) {
            Label(L10n.string("import.subtitle"), systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            formatDetailsButton
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

    @ViewBuilder
    private var converterBackground: some View {
        switch theme.background {
        case let .solid(color):
            color.ignoresSafeArea()
        case let .linearGradient(colors, startPoint, endPoint):
            LinearGradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
                .ignoresSafeArea()
        }
    }
}

private enum ConversionMode: String, Hashable {
    case image
    case video
    case audio
}

private struct SupportedFormatsSheet: View {
    let mode: ConversionMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
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
                            title: L10n.string("formats.video_to_audio_import"),
                            formats: ["MOV", "MP4", "M4V"]
                        )
                        FormatChipSection(
                            title: L10n.string("formats.export"),
                            formats: ["AAC · M4A", "ALAC · M4A", "WAV · PCM"]
                        )
                    }
                }
                .padding(20)
            }
            .converterSoftScrollEdge()
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
    @State private var isClearAllConfirmationPresented = false
    @State private var libraryImportProgress: ConversionImportProgress?

    init(viewModel: ImageConversionViewModel = ImageConversionViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 16) {
                importCard

                if let progress = libraryImportProgress ?? viewModel.importProgress {
                    ConversionImportProgressView(progress: progress)
                }

                if let notice = viewModel.notice {
                    NoticeView(message: notice)
                }

                if viewModel.items.isEmpty {
                    emptyState
                } else {
                    filesSection
                }

                ImageConversionSettingsCard(viewModel: viewModel)
                conversionAction
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 20)
        }
        .converterSoftScrollEdge()
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
                .disabled(viewModel.isConverting || viewModel.importProgress != nil)
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
            }

            Button {
                isImporterPresented = true
            } label: {
                Label(L10n.string("action.choose_files"), systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isConverting || viewModel.importProgress != nil)

            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: 100,
                matching: .images
            ) {
                Label(L10n.string("action.choose_photos"), systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isConverting || viewModel.importProgress != nil)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .converterCard()
    }

    private func importPhotos(_ selections: [PhotosPickerItem]) async {
        defer {
            selectedPhotoItems = []
            libraryImportProgress = nil
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
                    type: ImportedPhotoFile.self,
                    progress: { fraction in
                        Task { @MainActor in
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
        libraryImportProgress = nil
        await viewModel.addFiles(urls, progressRange: 0.95 ... 1)
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

                Button(L10n.string("action.clear_all"), role: .destructive) {
                    isClearAllConfirmationPresented = true
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

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("settings.format"))
                ConversionSettingsWheelPicker(
                    summary: imageSettingsSummary,
                    detail: L10n.dynamicString("format.image.\(viewModel.outputFormat.rawValue).detail")
                ) {
                    HStack(spacing: 0) {
                        ConversionWheelColumn(
                            title: L10n.string("settings.format"),
                            selection: $viewModel.outputFormat
                        ) {
                            ForEach(viewModel.availableFormats) { format in
                                Text(format.rawValue.uppercased()).tag(format)
                            }
                        }
                        ConversionWheelColumn(
                            title: L10n.string("settings.metadata"),
                            selection: $viewModel.metadataPolicy
                        ) {
                            ForEach(ImageMetadataPolicy.allCases) { policy in
                                Text(metadataTitle(policy)).tag(policy)
                            }
                        }
                        ConversionWheelColumn(
                            title: L10n.string("settings.resize"),
                            selection: $viewModel.resizePreset
                        ) {
                            ForEach(ImageResizePreset.allCases) { preset in
                                Text(resizeTitle(preset)).tag(preset)
                            }
                        }
                    }
                }
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

    private var imageSettingsSummary: String {
        [
            viewModel.outputFormat.rawValue.uppercased(),
            metadataTitle(viewModel.metadataPolicy),
            resizeTitle(viewModel.resizePreset)
        ].joined(separator: " · ")
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
    @Environment(\.conversionTheme) private var theme

    let item: ImageConversionItem
    let isLocked: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ConversionFileThumbnail(url: item.sourceURL, kind: .image)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.sourceURL.lastPathComponent)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                if let info = item.info {
                    HStack(spacing: 6) {
                        ConversionStatusDot(
                            phase: statusPhase,
                            accessibilityLabel: statusText
                        )
                        Text("\(info.pixelWidth)×\(info.pixelHeight)")
                        Text("·")
                        Text(ByteCountFormatter.string(
                            fromByteCount: info.fileSizeBytes,
                            countStyle: .file
                        ))
                    }
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                }

                if item.info == nil {
                    HStack(spacing: 6) {
                        ConversionStatusDot(
                            phase: statusPhase,
                            accessibilityLabel: statusText
                        )
                        Text(statusText)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if case let .failed(message) = item.status {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(theme.destructive)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            trailingAction
        }
    }

    private var statusPhase: ConversionFilePhase {
        switch item.status {
        case .inspecting, .ready, .cancelled: .pending
        case .converting: .working
        case .completed: .completed
        case .failed: .failed
        }
    }

    private var statusText: String {
        switch item.status {
        case .inspecting: L10n.string("status.inspecting")
        case .ready: L10n.string("status.ready")
        case .converting: L10n.string("status.converting")
        case .completed: L10n.string("status.completed")
        case let .failed(message): message
        case .cancelled: L10n.string("status.cancelled")
        }
    }

    @ViewBuilder
    private var trailingAction: some View {
        switch item.status {
        case let .completed(outputURL):
            HStack(spacing: 4) {
                ShareLink(item: outputURL) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.string("action.share"))

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .disabled(isLocked)
                .accessibilityLabel(L10n.string("conversion.delete.action"))
            }
        case .converting, .inspecting:
            ProgressView()
                .controlSize(.small)
        case .ready, .failed, .cancelled:
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
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
    @Environment(\.conversionTheme) private var theme

    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Group {
#if os(iOS)
            if #available(iOS 26.0, *), theme.liquidGlassEnabled {
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
        .tint(theme.accent)
    }
}

private struct ConverterCardModifier: ViewModifier {
    @Environment(\.conversionTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(theme.divider.opacity(0.65), lineWidth: 0.5)
            }
    }
}

extension View {
    func converterCard() -> some View {
        modifier(ConverterCardModifier())
    }

    func converterSoftScrollEdge() -> some View {
        modifier(ConverterSoftScrollEdgeModifier())
    }
}

private struct ConverterSoftScrollEdgeModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .vertical)
        } else {
            content
        }
    }
}
