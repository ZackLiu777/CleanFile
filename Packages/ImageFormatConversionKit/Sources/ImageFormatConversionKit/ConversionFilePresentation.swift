import AVFoundation
import ImageIO
import SwiftUI
#if os(iOS)
import UIKit
#endif

enum ConversionFileKind: Sendable {
    case image
    case video
    case audio
}

struct ConversionMicroText: View {
    let text: String

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

enum ConversionFilePhase {
    case pending
    case working
    case completed
    case failed
}

private struct SendableThumbnail: @unchecked Sendable {
#if os(iOS)
    let image: UIImage
#endif
}

private actor ConversionThumbnailLoader {
    static let shared = ConversionThumbnailLoader()

#if os(iOS)
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 240
    }

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

    private func imageThumbnail(for url: URL) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 144,
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

    private func videoThumbnail(for url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 144, height: 144)
        guard let image = try? generator.copyCGImage(at: .zero, actualTime: nil) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
#endif
}

struct ConversionFileThumbnail: View {
    let url: URL
    let kind: ConversionFileKind
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
        .frame(width: 48, height: 48)
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
