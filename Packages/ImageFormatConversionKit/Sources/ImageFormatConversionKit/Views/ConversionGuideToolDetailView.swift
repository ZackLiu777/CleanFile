//
//  ConversionGuideToolDetailView.swift
//
//  文件职责：逐项解释图片、视频与音频转换工具的真实能力与设置边界。
//  所属模块：ImageFormatConversionKit。
//

import SwiftUI

enum ConversionGuideTool: String, CaseIterable, Identifiable, Hashable {
    case image
    case video
    case audio

    var id: Self { self }

    var title: String {
        L10n.dynamicString("conversion.home.\(rawValue).title")
    }

    var overview: String {
        L10n.dynamicString("conversion.guide.\(rawValue).detail")
    }

    var purpose: String {
        L10n.dynamicString("conversion.guide.\(rawValue).purpose")
    }

    var importDetail: String {
        L10n.dynamicString("conversion.guide.\(rawValue).imports.detail")
    }

    var workflowDetail: String {
        L10n.dynamicString("conversion.guide.\(rawValue).workflow.detail")
    }

    var imageName: String {
        "conversion-guide-\(rawValue)"
    }

    var symbol: String {
        switch self {
        case .image: "photo.on.rectangle.angled"
        case .video: "film.stack"
        case .audio: "waveform"
        }
    }

    var importFormats: [String] {
        switch self {
        case .image:
            ImageConversionEngine.supportedInputFormatNames
        case .video:
            ["MOV", "MP4", "M4V"]
        case .audio:
            (AudioConversionEngine.supportedInputExtensions
                + AudioConversionEngine.supportedVideoInputExtensions)
                .map { $0.uppercased() }
        }
    }

    var outputFormats: [ConversionGuideFormat] {
        switch self {
        case .image:
            ImageConversionEngine.supportedOutputFormats.map { format in
                ConversionGuideFormat(
                    title: format.rawValue.uppercased(),
                    detail: L10n.dynamicString("format.image.\(format.rawValue).detail")
                )
            }
        case .video:
            VideoOutputContainer.allCases.map { container in
                ConversionGuideFormat(
                    title: container.rawValue.uppercased(),
                    detail: L10n.dynamicString("format.video.\(container.rawValue).detail")
                )
            }
        case .audio:
            AudioOutputFormat.allCases.map { format in
                ConversionGuideFormat(
                    title: Self.audioFormatTitle(format),
                    detail: L10n.dynamicString("format.audio.\(format.rawValue).detail")
                )
            }
        }
    }

    var settings: [ConversionGuideSetting] {
        switch self {
        case .image:
            [
                ConversionGuideSetting(
                    symbol: "slider.horizontal.3",
                    title: L10n.string("settings.quality"),
                    detail: L10n.string("conversion.guide.image.quality.detail")
                ),
                ConversionGuideSetting(
                    symbol: "arrow.down.right.and.arrow.up.left",
                    title: L10n.string("settings.resize"),
                    detail: L10n.string("conversion.guide.image.resize.detail")
                ),
                ConversionGuideSetting(
                    symbol: "location.slash",
                    title: L10n.string("settings.metadata"),
                    detail: L10n.string("conversion.guide.metadata.detail")
                ),
                ConversionGuideSetting(
                    symbol: "circle.lefthalf.filled",
                    title: L10n.string("settings.transparent_background"),
                    detail: L10n.string("conversion.guide.image.transparency.detail")
                ),
                ConversionGuideSetting(
                    symbol: "folder",
                    title: L10n.string("settings.output"),
                    detail: L10n.string("conversion.guide.output.detail")
                )
            ]
        case .video:
            [
                ConversionGuideSetting(
                    symbol: "rectangle.inset.filled",
                    title: L10n.string("video.settings.resolution"),
                    detail: L10n.string("conversion.guide.video.resolution.detail")
                ),
                ConversionGuideSetting(
                    symbol: "checkmark.circle",
                    title: L10n.string("conversion.guide.video.compatibility.title"),
                    detail: L10n.string("conversion.guide.video.compatibility.detail")
                ),
                ConversionGuideSetting(
                    symbol: "folder",
                    title: L10n.string("settings.output"),
                    detail: L10n.string("conversion.guide.output.detail")
                )
            ]
        case .audio:
            [
                ConversionGuideSetting(
                    symbol: "waveform.path.ecg",
                    title: L10n.string("audio.settings.quality"),
                    detail: L10n.string("conversion.guide.audio.quality.detail")
                ),
                ConversionGuideSetting(
                    symbol: "waveform.badge.checkmark",
                    title: L10n.string("conversion.guide.audio.lossless.title"),
                    detail: L10n.string("conversion.guide.audio.lossless.detail")
                ),
                ConversionGuideSetting(
                    symbol: "film.stack",
                    title: L10n.string("conversion.guide.audio.extract.title"),
                    detail: L10n.string("conversion.guide.audio.extract.detail")
                ),
                ConversionGuideSetting(
                    symbol: "folder",
                    title: L10n.string("settings.output"),
                    detail: L10n.string("conversion.guide.output.detail")
                )
            ]
        }
    }

    var codecs: [ConversionGuideFormat] {
        guard self == .video else { return [] }
        return [
            ConversionGuideFormat(
                title: "H.264",
                detail: L10n.string("conversion.guide.video.codec.h264.detail")
            ),
            ConversionGuideFormat(
                title: "HEVC",
                detail: L10n.string("conversion.guide.video.codec.hevc.detail")
            ),
            ConversionGuideFormat(
                title: "ProRes 422",
                detail: L10n.string("conversion.guide.video.codec.prores422.detail")
            ),
            ConversionGuideFormat(
                title: "ProRes 4444",
                detail: L10n.string("conversion.guide.video.codec.prores4444.detail")
            )
        ]
    }

    static var initialDebugPath: [ConversionGuideTool] {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--conversion-guide-screenshot") else {
            return []
        }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return [] }
        let value = arguments[valueIndex]
        guard value.hasPrefix("guide-") else { return [] }
        let rawValue = String(value.dropFirst("guide-".count))
        return ConversionGuideTool(rawValue: rawValue).map { [$0] } ?? []
#else
        return []
#endif
    }

    private static func audioFormatTitle(_ format: AudioOutputFormat) -> String {
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
}

struct ConversionGuideToolDetailView: View {
    @Environment(\.conversionTheme) private var theme
    let tool: ConversionGuideTool

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 28) {
                screenshotHero

                detailSection(L10n.string("conversion.guide.detail.purpose.title")) {
                    ConversionGuideCallout(
                        symbol: tool.symbol,
                        detail: tool.purpose
                    )
                }

                detailSection(L10n.string("formats.import")) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(tool.importDetail)
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        ConversionGuideTagGrid(values: tool.importFormats)
                    }
                    .padding(16)
                    .converterCard()
                }

                detailSection(L10n.string("formats.export")) {
                    ConversionGuideFormatList(formats: tool.outputFormats)
                }

                if !tool.codecs.isEmpty {
                    detailSection(L10n.string("formats.codec")) {
                        ConversionGuideFormatList(formats: tool.codecs)
                    }
                }

                detailSection(L10n.string("settings.title")) {
                    ConversionGuideSettingList(settings: tool.settings)
                }

                detailSection(L10n.string("conversion.guide.detail.workflow.title")) {
                    ConversionGuideCallout(
                        symbol: "checkmark.circle.fill",
                        detail: tool.workflowDetail
                    )
                }

                ConversionGuideDetailPrivacyCard()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .converterSoftScrollEdge()
        .background(converterBackground)
        .navigationTitle(tool.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private var screenshotHero: some View {
        ZStack(alignment: .bottomLeading) {
            ConversionGuideLocalizedPreview(imageName: tool.imageName)
                .frame(maxWidth: .infinity)
                .frame(height: 250, alignment: .top)
                .clipped()
                .accessibilityHidden(true)

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )

            HStack(spacing: 12) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.title)
                        .font(.title2.bold())
                    Text(tool.overview)
                        .font(.subheadline)
                        .lineLimit(2)
                }
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.divider.opacity(0.5), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
    }

    @ViewBuilder
    private var converterBackground: some View {
        ConversionBackgroundView(background: theme.background)
            .ignoresSafeArea()
    }
}

struct ConversionGuideFormat: Identifiable {
    let title: String
    let detail: String

    var id: String { title }
}

struct ConversionGuideSetting: Identifiable {
    let symbol: String
    let title: String
    let detail: String

    var id: String { title }
}

private struct ConversionGuideTagGrid: View {
    @Environment(\.conversionTheme) private var theme
    let values: [String]
    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(theme.cardElevated, in: Capsule())
            }
        }
    }
}

private struct ConversionGuideFormatList: View {
    @Environment(\.conversionTheme) private var theme
    let formats: [ConversionGuideFormat]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(formats.enumerated()), id: \.element.id) { index, format in
                VStack(alignment: .leading, spacing: 5) {
                    Text(format.title)
                        .font(.headline)
                    Text(format.detail)
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)

                if index < formats.count - 1 {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 16)
        .converterCard()
    }
}

private struct ConversionGuideSettingList: View {
    @Environment(\.conversionTheme) private var theme
    let settings: [ConversionGuideSetting]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(settings.enumerated()), id: \.element.id) { index, setting in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: setting.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 34, height: 34)
                        .background(theme.accent.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(setting.title)
                            .font(.headline)
                        Text(setting.detail)
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 14)

                if index < settings.count - 1 {
                    Divider()
                        .padding(.leading, 46)
                }
            }
        }
        .padding(.horizontal, 16)
        .converterCard()
    }
}

private struct ConversionGuideCallout: View {
    @Environment(\.conversionTheme) private var theme
    let symbol: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 42, height: 42)
                .background(theme.accent.opacity(0.12), in: Circle())

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .converterCard()
    }
}

private struct ConversionGuideDetailPrivacyCard: View {
    @Environment(\.conversionTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 44, height: 44)
                .background(theme.accent.opacity(0.13), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.string("conversion.guide.privacy.title"))
                    .font(.headline)
                Text(L10n.string("conversion.guide.privacy.detail"))
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .converterAccentCard()
    }
}
