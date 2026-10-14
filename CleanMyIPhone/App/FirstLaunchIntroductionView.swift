import ImageFormatConversionKit
import SwiftUI

/// The introduction uses bundled sample data; it never reads or changes the user's files.
struct FirstLaunchIntroductionContainer<Content: View>: View {
    @AppStorage("hasCompletedFirstLaunchIntroduction") private var hasCompletedIntroduction = false
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var shouldShowIntroduction: Bool {
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-test") }) { return false }
        return !hasCompletedIntroduction
    }

    var body: some View {
        Group {
            if shouldShowIntroduction {
                FirstLaunchIntroductionView {
                    hasCompletedIntroduction = true
                }
            } else {
                content
            }
        }
    }
}

private enum IntroductionPage: Int, CaseIterable {
    case media, appearance, compress, files

    var title: LocalizedStringKey {
        switch self {
        case .media: "intro.media.title"
        case .files: "intro.files.title"
        case .compress: "intro.compress.title"
        case .appearance: "intro.appearance.title"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .media: "intro.media.detail"
        case .files: "intro.files.detail"
        case .compress: "intro.compress.detail"
        case .appearance: "intro.appearance.detail"
        }
    }

    var icon: String {
        switch self {
        case .media: "sparkles"
        case .files: "iphone"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .appearance: "photo.stack"
        }
    }
}

struct FirstLaunchIntroductionView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    var showsCloseButton = false
    let onComplete: () -> Void

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Text("Filevra")
                        .appTypeface(.headline.bold(), size: 17, relativeTo: .headline, weight: .bold)
                    Spacer()
                    Text("\(page + 1) / 4")
                        .appTypeface(.subheadline, size: 15, relativeTo: .subheadline)
                        .foregroundStyle(theme.textSecondary)
                    if showsCloseButton {
                        Button(action: onComplete) {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(Text("settings.intro.close"))
                        .accessibilityIdentifier("intro.close")
                    }
                }
                .padding(.top, 18)

                TabView(selection: $page) {
                    ForEach(IntroductionPage.allCases, id: \.rawValue) { item in
                        ScrollView {
                            VStack(spacing: 20) {
                                IntroductionArtwork(page: item)
                                    .frame(minHeight: min(geometry.size.height * 0.48, 370))
                                    .accessibilityHidden(true)
                                Text(item.title)
                                    .appTypeface(.largeTitle.bold(), size: 31, relativeTo: .largeTitle, weight: .bold)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(item.detail)
                                    .appTypeface(.body, size: 17, relativeTo: .body)
                                    .foregroundStyle(theme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 20)
                        }
                        .tag(item.rawValue)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 9) {
                    ForEach(0..<4) { index in
                        Capsule()
                            .fill(index == page ? theme.accentPrimary : theme.textTertiary.opacity(0.45))
                            .frame(width: index == page ? 25 : 8, height: 8)
                    }
                }
                .accessibilityLabel("\(page + 1) of 4")
                .padding(.bottom, 24)

                Button {
                    if page == 3 {
                        onComplete()
                    } else {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { page += 1 }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(page == 3 ? "intro.start" : "intro.next")
                        Image(systemName: page == 3 ? "checkmark" : "arrow.right")
                    }
                    .appTypeface(.headline.bold(), size: 17, relativeTo: .headline, weight: .bold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .foregroundStyle(theme.textInverted)
                    .background(theme.buttonPrimaryBackground, in: RoundedRectangle(cornerRadius: 18))
                }
                .accessibilityIdentifier("intro.continue")
                .padding(.bottom, 18)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                AppBackground()
                    .ignoresSafeArea()
            }
        }
    }
}

private struct IntroductionArtwork: View {
    @Environment(\.appTheme) private var theme
    let page: IntroductionPage

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Image(systemName: page.icon)
                    .font(.title2)
                    .foregroundStyle(theme.accentPrimary)
                Spacer()
                Text("intro.demo")
                    .appTypeface(.caption, size: 12, relativeTo: .caption)
                    .foregroundStyle(theme.textSecondary)
            }
            switch page {
            case .media: mediaArtwork
            case .appearance: similarArtwork
            case .compress: compressArtwork
            case .files: filesArtwork
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(theme.divider, lineWidth: 1))
    }

    private var mediaArtwork: some View {
        VStack(spacing: 14) {
            Text(ByteCountFormatter.string(fromByteCount: 8_800_000_000, countStyle: .file))
                .appTypeface(.largeTitle.bold(), size: 48, relativeTo: .largeTitle, weight: .bold)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("intro.cleanup.total")
                .appTypeface(.subheadline, size: 15, relativeTo: .subheadline)
                .foregroundStyle(theme.textSecondary)
            sampleRow("Similar Photos", symbol: "photo.stack", bytes: 2_100_000_000)
            sampleRow("Screenshots", symbol: "iphone", bytes: 600_000_000)
            sampleRow("Videos", symbol: "video.fill", bytes: 5_700_000_000)
            sampleRow("Live Photos", symbol: "livephoto", bytes: 400_000_000)
        }
    }

    private func sampleRow(_ title: LocalizedStringKey, symbol: String, bytes: Int64) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(theme.accentPrimary)
                .frame(width: 28)
            Text(title)
                .appTypeface(.subheadline, size: 15, relativeTo: .subheadline, weight: .semibold)
            Spacer(minLength: 4)
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                .appTypeface(.subheadline, size: 15, relativeTo: .subheadline)
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme.accentPrimary)
        }
        .padding(12)
        .background(theme.backgroundSecondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    private var similarArtwork: some View {
        VStack(spacing: 12) {
            Text("Similar Photos")
                .appTypeface(.headline, size: 18, relativeTo: .headline, weight: .semibold)
            HStack(spacing: 10) {
                samplePhoto(keeper: true)
                    .frame(height: 210)
                VStack(spacing: 10) {
                    samplePhoto(keeper: false)
                    samplePhoto(keeper: false)
                }
                .frame(height: 210)
            }
        }
    }

    private func samplePhoto(keeper: Bool) -> some View {
        Color.clear
            .overlay {
                GeometryReader { proxy in
                    Image("IntroductionSamplePhoto")
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(keeper ? 1 : 1.12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: keeper ? .bottomLeading : .topTrailing) {
                if keeper {
                    Label("similar.keep", systemImage: "checkmark.shield.fill")
                        .appTypeface(.caption.bold(), size: 13, relativeTo: .caption, weight: .bold)
                        .padding(8)
                        .background(theme.cardSurface, in: Capsule())
                        .padding(8)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(theme.accentPrimary)
                        .padding(8)
                }
            }
    }

    private var filesArtwork: some View {
        VStack(spacing: 18) {
            Text("Screenshots")
                .appTypeface(.headline, size: 18, relativeTo: .headline, weight: .semibold)
            HStack(spacing: 10) {
                ForEach(0..<3) { index in
                    VStack(spacing: 12) {
                        Capsule().fill(theme.textPrimary.opacity(0.3)).frame(width: 24, height: 4)
                        Image(systemName: ["ticket", "calendar", "cart"][index])
                            .font(.title)
                            .foregroundStyle(theme.accentPrimary)
                        Text(["10:30", "12 / 24", "128.00"][index])
                            .appTypeface(.caption.bold(), size: 13, relativeTo: .caption, weight: .bold)
                        ForEach(0..<3) { _ in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.textSecondary.opacity(0.18))
                                .frame(height: 5)
                        }
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.accentPrimary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(theme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            sampleRow("Screenshots", symbol: "iphone", bytes: 600_000_000)
        }
    }

    private var compressArtwork: some View {
        VStack(spacing: 20) {
            Image("IntroductionSamplePhoto")
                .resizable()
                .scaledToFill()
                .frame(height: 145)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16))
            HStack(spacing: 12) {
                Text(ByteCountFormatter.string(fromByteCount: 2_000_000_000, countStyle: .file))
                Image(systemName: "arrow.right")
                    .foregroundStyle(theme.textSecondary)
                Text(ByteCountFormatter.string(fromByteCount: 1_100_000_000, countStyle: .file))
            }
            .appTypeface(.title2.bold(), size: 26, relativeTo: .title2, weight: .bold)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            VStack(spacing: 6) {
                Text("intro.compress.saved")
                    .appTypeface(.subheadline, size: 15, relativeTo: .subheadline)
                Text(ByteCountFormatter.string(fromByteCount: 900_000_000, countStyle: .file))
                    .appTypeface(.largeTitle.bold(), size: 36, relativeTo: .largeTitle, weight: .bold)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(theme.accentPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
        }
    }
}
