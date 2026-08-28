//
//  文件职责：集中定义 ConversionFilePresentation 相关的生产逻辑与共享能力。
//  所属模块：ImageFormatConversionKit。
//

import AVFoundation
import ImageIO
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// 定义 `ConversionFileKind` 使用的有限状态或选项集合。
enum ConversionFileKind: Sendable {
    case image
    case video
    case audio
}

/// 定义 `ConversionMicroText` 的值语义数据与相关行为。
struct ConversionMicroText: View {
    let text: String

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary.opacity(0.72))
    }
}

/// 定义 `ConversionFilePhase` 使用的有限状态或选项集合。
enum ConversionFilePhase {
    case pending
    case working
    case completed
    case failed
}

/// 定义 `SendableThumbnail` 的值语义数据与相关行为。
private struct SendableThumbnail: @unchecked Sendable {
#if os(iOS)
    let image: UIImage
#endif
}

/// 使用 Actor 隔离 `ConversionThumbnailLoader` 的可变状态，确保并发访问安全。
private actor ConversionThumbnailLoader {
    static let shared = ConversionThumbnailLoader()

#if os(iOS)
    private let cache = NSCache<NSString, UIImage>()

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    init() {
        cache.countLimit = 120
    }

    /// 封装 `thumbnail` 对应的局部行为，供当前类型在统一入口下复用。
    func thumbnail(for url: URL, kind: ConversionFileKind) -> SendableThumbnail? {
        let key = url.standardizedFileURL.path as NSString
        if let cached = cache.object(forKey: key) {
            return SendableThumbnail(image: cached)
        }

        let image: UIImage?
        switch kind {
        case .image:
            image = imageThumbnail(for: url)
        case .video:
            image = videoThumbnail(for: url)
        case .audio:
            image = nil
        }
        guard let image else { return nil }
        cache.setObject(image, forKey: key)
        return SendableThumbnail(image: image)
    }

    /// 封装 `imageThumbnail` 对应的局部行为，供当前类型在统一入口下复用。
    private func imageThumbnail(for url: URL) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 300,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
              ) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    /// 封装 `videoThumbnail` 对应的局部行为，供当前类型在统一入口下复用。
    private func videoThumbnail(for url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 300, height: 300)
        guard let image = try? generator.copyCGImage(at: .zero, actualTime: nil) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
#endif
}

/// 定义 `ConversionFileThumbnail` 的值语义数据与相关行为。
struct ConversionFileThumbnail: View {
    let url: URL
    let kind: ConversionFileKind
    var width: CGFloat = 48
    var height: CGFloat = 48
    @State private var thumbnail: SendableThumbnail?

    var body: some View {
        ZStack {
#if os(iOS)
            if let thumbnail {
                Image(uiImage: thumbnail.image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
#else
            placeholder
#endif
        }
        .frame(width: width, height: height)
        .background(.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .task(id: url) {
            thumbnail = await ConversionThumbnailLoader.shared.thumbnail(for: url, kind: kind)
        }
    }

    private var placeholder: some View {
        Image(systemName: placeholderSymbol)
            .font(.system(size: 16, weight: .light))
            .foregroundStyle(.secondary)
    }

    private var placeholderSymbol: String {
        switch kind {
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        }
    }
}

/// 定义 `ConversionFileTray` 的值语义数据与相关行为。
struct ConversionFileTray<Content: View>: View {
    @Environment(\.conversionTheme) private var theme

    let title: String
    let progress: ConversionImportProgress?
    let rowCount: Int
    let canClear: Bool
    let onClear: () -> Void
    let content: Content

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    init(
        title: String,
        progress: ConversionImportProgress?,
        rowCount: Int = 1,
        canClear: Bool,
        onClear: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.progress = progress
        self.rowCount = max(1, min(rowCount, 2))
        self.canClear = canClear
        self.onClear = onClear
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button(L10n.string("action.clear_all"), role: .destructive, action: onClear)
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.plain)
                    .disabled(!canClear)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: Array(
                        repeating: GridItem(.fixed(132), spacing: 10, alignment: .top),
                        count: rowCount
                    ),
                    alignment: .top,
                    spacing: 10
                ) {
                    content
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)

            if let progress {
                VStack(spacing: 7) {
                    ProgressView(value: progress.fractionCompleted)
                        .tint(theme.accent)
                        .animation(.linear(duration: 0.12), value: progress.fractionCompleted)

                    HStack {
                        Text(L10n.string("import.progress.title"))
                        Spacer()
                        Text("\(progress.percentage)%")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .converterCard()
    }
}

/// 定义 `ConversionFileTile` 的值语义数据与相关行为。
struct ConversionFileTile: View {
    @Environment(\.conversionTheme) private var theme

    let url: URL
    let kind: ConversionFileKind
    let title: String
    let subtitle: String
    let phase: ConversionFilePhase
    let statusLabel: String
    let isLocked: Bool
    let outputURL: URL?
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ConversionFileThumbnail(
                    url: url,
                    kind: kind,
                    width: 112,
                    height: 96
                )

                statusBadge
                    .padding(7)
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Text(subtitle)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 112, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(statusLabel), \(subtitle)")
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let outputURL {
            ShareLink(item: outputURL) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("action.share"))
        } else if case .working = phase {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial, in: Circle())
                .accessibilityLabel(statusLabel)
        } else {
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isLocked)
            .accessibilityLabel(L10n.string("action.remove"))
        }
    }
}

/// 定义 `ConversionPendingFileTile` 的值语义数据与相关行为。
struct ConversionPendingFileTile: View {
    let index: Int
    let kind: ConversionFileKind

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.primary.opacity(0.055))

                Image(systemName: placeholderSymbol)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)

                ProgressView()
                    .controlSize(.mini)
                    .offset(x: 24, y: -22)
            }
            .frame(width: 112, height: 96)

            Text(L10n.string("import.progress.title"))
                .font(.caption.weight(.semibold))
            Text("#\(index + 1)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(width: 112, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var placeholderSymbol: String {
        switch kind {
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        }
    }
}

/// 定义 `ConversionStatusDot` 的值语义数据与相关行为。
struct ConversionStatusDot: View {
    let phase: ConversionFilePhase
    let accessibilityLabel: String
    @State private var isPulsing = false

    private var color: Color {
        switch phase {
        case .pending: .secondary
        case .working: .accentColor
        case .completed: .green
        case .failed: .red
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(phase == .working && isPulsing ? 0.35 : 1)
            .animation(
                phase == .working
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear { isPulsing = phase == .working }
            .accessibilityLabel(accessibilityLabel)
    }
}
