// 首次启动介绍页与示意画面。
// 展示状态由持久化标记控制，示意内容使用样例而非用户文件。
// 容器根据首次介绍完成标记决定显示介绍还是应用内容，并支持从设置重新预览。
// 介绍页通过完成回调结束，示例卡片和图片不读取或修改用户相册。

import ImageFormatConversionKit
import SwiftUI

/// The introduction uses bundled sample data; it never reads or changes the user's files.
struct FirstLaunchIntroductionContainer<Content: View>: View {
    @AppStorage("hasCompletedFirstLaunchIntroduction") private var hasCompletedIntroduction = false
    private let content: Content

    /// 保存介绍完成后展示的内容。
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

/// 定义介绍页顺序及每页对应的文案和图标。
private enum IntroductionPage: Int, CaseIterable {
    case media, appearance, compress, files

    var title: LocalizedStringKey {
        switch self {
        case .media: "intro.media.title"
        case .files: "intro.convert.title"
        case .compress: "intro.compress.title"
        case .appearance: "intro.storage.title"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .media: "intro.media.detail"
        case .files: "intro.convert.detail"
        case .compress: "intro.compress.detail"
        case .appearance: "intro.storage.detail"
        }
    }

    var icon: String {
        switch self {
        case .media: "sparkles"
        case .files: "arrow.triangle.2.circlepath"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .appearance: "folder"
        }
    }
}

/// 介绍页使用同一组虚构数据，保证分类、总量和压缩结果彼此一致。
private enum IntroductionSample {
    static let similarPhotos: Int64 = 8_000_000_000
    static let screenshots: Int64 = 6_000_000_000
    static let videos: Int64 = 140_000_000_000
    static let livePhotos: Int64 = 10_000_000_000
    // 宣传图中的照片总量为 54 GB，其余 30 GB 归入其他照片。
    static let otherPhotos: Int64 = 30_000_000_000
    static let cleanupTotal = similarPhotos + screenshots + videos + livePhotos + otherPhotos
    static let compressionOriginal: Int64 = 23_700_000_000
    static let compressionResult: Int64 = 4_140_000_000
    static let compressionSaved = compressionOriginal - compressionResult
}

/// 展示可分页的首次使用介绍，并通过回调结束介绍。
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
                                Text(item.title)
                                    .appTypeface(.largeTitle.bold(), size: 31, relativeTo: .largeTitle, weight: .bold)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(item.detail)
                                    .appTypeface(.body, size: 17, relativeTo: .body)
                                    .foregroundStyle(theme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                IntroductionWalkthrough(page: item, isActive: page == item.rawValue)
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

/// 只使用内置样例重放操作；离开页面时停止，减少动态效果时保留静态步骤切换。
private struct IntroductionWalkthrough: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let page: IntroductionPage
    let isActive: Bool
    @State private var step = 0
    @State private var playbackRevision = 0
    @State private var isPressing = false
    @State private var hasPerformedTap = false
    @State private var hasCompletedDemo = false

    private var stepKeys: [String] {
        switch page {
        case .media: ["intro.walk.media.1", "intro.walk.media.2", "intro.walk.media.3"]
        case .appearance: ["intro.walk.storage.1", "intro.walk.storage.2", "intro.walk.storage.3"]
        case .compress: ["intro.walk.compress.1", "intro.walk.compress.2", "intro.walk.compress.3"]
        case .files: ["intro.walk.convert.1", "intro.walk.convert.2", "intro.walk.convert.3"]
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label("intro.demo", systemImage: page.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Text("\(step + 1) / 3")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.textSecondary)
            }
            demoContent
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<3) { index in
                    Button {
                        playbackRevision &+= 1
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step = index }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(index == step ? theme.textInverted : theme.textPrimary)
                                .frame(width: 26, height: 26)
                                .background(index == step ? theme.accentPrimary : theme.backgroundSecondary, in: Circle())
                            Text(LocalizedStringKey(stepKeys[index]))
                                .font(.subheadline.weight(index == step ? .semibold : .regular))
                                .foregroundStyle(theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(index == step ? [.isSelected] : [])
                    .accessibilityIdentifier("intro.step.\(index + 1)")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(theme.divider, lineWidth: 1))
        .task(id: AnimationState(active: isActive, reduced: reduceMotion, sceneActive: scenePhase == .active, revision: playbackRevision)) {
            guard isActive, scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { step = (step + 1) % 3 }
            }
        }
        .task(id: DemonstrationPhase(step: step, active: isActive, sceneActive: scenePhase == .active, reduced: reduceMotion, revision: playbackRevision)) {
            isPressing = false
            hasPerformedTap = false
            hasCompletedDemo = false
            guard isActive, scenePhase == .active else { return }
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { isPressing = true }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                isPressing = false
                hasPerformedTap = true
            }
            if step == 0 && (page == .appearance || page == .files) {
                do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { isPressing = true }
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { isPressing = false }
            }
            if step == 2 {
                do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { hasCompletedDemo = true }
            }
        }
    }

    @ViewBuilder private var demoContent: some View {
        if step == 0 {
            demoHome
        } else {
            activeDemo
        }
    }

    @ViewBuilder private var activeDemo: some View {
        switch page {
        case .media:
            VStack(spacing: 9) {
                demoHeader("Photos", symbol: "photo.stack")
                Text(ByteCountFormatter.string(fromByteCount: IntroductionSample.cleanupTotal, countStyle: .file))
                    .font(.title.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                demoRow("Similar Photos", symbol: "photo.stack", selected: step == 2 || hasPerformedTap, bytes: IntroductionSample.similarPhotos, showTap: step == 1)
                demoRow("Screenshots", symbol: "iphone", selected: step == 2 || hasPerformedTap, bytes: IntroductionSample.screenshots)
                demoAction("Delete", symbol: "trash", highlighted: step == 2)
                if step == 2 && hasPerformedTap { demoConfirmation("Delete selected media?") }
            }
        case .appearance:
            VStack(spacing: 9) {
                demoHeader("storage.heading", symbol: "folder")
                demoRow("Choose Folder", symbol: "folder.badge.plus", selected: step == 2 || hasPerformedTap, showTap: step == 1)
                if step == 1 {
                    ProgressView(value: 0.65).tint(theme.accentPrimary)
                } else {
                    demoRow("Videos", symbol: "film", selected: step >= 2)
                }
                demoRow("Review and Delete Files", symbol: "doc.text", selected: step >= 2)
                demoAction("Delete", symbol: "trash", highlighted: step == 2)
                if step == 2 && hasPerformedTap { demoConfirmation("Permanently delete selected files?") }
            }
        case .compress:
            VStack(spacing: 10) {
                demoHeader("compression.action.short", symbol: "arrow.down.right.and.arrow.up.left")
                HStack(spacing: 8) {
                    demoPhoto(selected: step == 2 || hasPerformedTap, keeper: false, showTap: step == 1)
                    demoPhoto(selected: step == 2 || hasPerformedTap, keeper: false)
                }
                .frame(height: 124)
                HStack {
                    Text(ByteCountFormatter.string(fromByteCount: IntroductionSample.compressionOriginal, countStyle: .file))
                    Image(systemName: "arrow.right")
                    Text(ByteCountFormatter.string(fromByteCount: IntroductionSample.compressionResult, countStyle: .file))
                }
                .font(.subheadline.weight(.semibold))
                demoAction("compression.action.short", symbol: "arrow.down.right.and.arrow.up.left", highlighted: step == 2)
                if step == 2 && hasPerformedTap { demoConfirmation("compression.confirm.title") }
            }
        case .files:
            VStack(spacing: 8) {
                demoHeader("intro.convert.title", symbol: "arrow.triangle.2.circlepath")
                HStack {
                    Text("MOV").foregroundStyle(theme.textSecondary)
                    Image(systemName: "arrow.right").foregroundStyle(theme.accentPrimary)
                    Text("MP4").foregroundStyle(theme.textPrimary)
                    Spacer()
                }
                .font(.headline)
                .padding(10)
                .background(theme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12))
                ConversionBitrateDemonstration(
                    value: step == 1 && !hasPerformedTap ? 1 : 0.5,
                    theme: theme.conversionTheme,
                    pausesAnimation: reduceMotion || !isActive || scenePhase != .active
                )
                .overlay(alignment: .bottom) {
                    if step == 1 { tapIndicator }
                }
                if step == 2 && hasPerformedTap {
                    WaveProgressView(progress: hasCompletedDemo ? 1 : 0.35, height: 12, tint: theme.accentPrimary)
                }
                demoAction("Convert", symbol: "arrow.triangle.2.circlepath", highlighted: step == 2)
                if hasCompletedDemo { demoConfirmation("Done") }
            }

        }
    }

    /// 首帧展示实际入口；后续画面展示进入后的选择与确认。
    private var demoHome: some View {
        VStack(spacing: 9) {
            HStack {
                Text("Filevra").font(.headline)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .padding(10)
                    .background(theme.backgroundSecondary, in: Circle())
                    .overlay(alignment: .bottomTrailing) {
                        if (page == .appearance || page == .files) && !hasPerformedTap { tapIndicator }
                    }
            }
            if page == .media {
                demoHomeTile("Similar Photos", symbol: "photo.stack")
                demoHomeTile("Screenshots", symbol: "iphone")
            } else if page == .compress {
                demoHomeTile("compression.action.short", symbol: "arrow.down.right.and.arrow.up.left")
                demoHomeTile("Videos", symbol: "video.fill")
            } else if hasPerformedTap {
                demoHomeTile("Quick Cleanup", symbol: "sparkles")
                demoHomeTile("Storage", symbol: "externaldrive")
                demoHomeTile("Convert", symbol: "arrow.triangle.2.circlepath")
            }
        }
    }

    private func demoHomeTile(_ title: LocalizedStringKey, symbol: String) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(theme.accentPrimary).frame(width: 28)
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Image(systemName: "chevron.right").font(.caption)
        }
        .padding(14)
        .background(theme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .trailing) {
            if (page == .media && symbol == "photo.stack")
                || (page == .compress && symbol == "arrow.down.right.and.arrow.up.left")
                || (page == .appearance && symbol == "externaldrive")
                || (page == .files && symbol == "arrow.triangle.2.circlepath") {
                tapIndicator.padding(.trailing, 10)
            }
        }
    }

    private var tapIndicator: some View {
        Image(systemName: "hand.tap.fill")
            .font(.title3)
            .foregroundStyle(theme.accentPrimary)
            .scaleEffect(reduceMotion ? 1 : (isPressing ? 0.78 : 1.12))
            .opacity(isPressing ? 0.7 : 1)
            .accessibilityHidden(true)
    }

    private func demoHeader(_ title: LocalizedStringKey, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func demoRow(_ title: LocalizedStringKey, symbol: String, selected: Bool, bytes: Int64? = nil, showTap: Bool = false) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(theme.accentPrimary).frame(width: 28)
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            if let bytes {
                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? theme.accentPrimary : theme.textSecondary)
            if showTap { tapIndicator }
        }
        .padding(12)
        .background(theme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func demoPhoto(selected: Bool, keeper: Bool, showTap: Bool = false) -> some View {
        GeometryReader { proxy in
            Image("IntroductionSamplePhoto")
                .resizable().scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    Image(systemName: keeper ? "checkmark.shield.fill" : selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(theme.accentPrimary, in: Circle())
                        .padding(5)
                }
                .overlay(alignment: .bottomTrailing) {
                    if showTap {
                        Image(systemName: "hand.tap.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .scaleEffect(reduceMotion ? 1 : (isPressing ? 0.78 : 1.12))
                            .shadow(color: .black.opacity(0.7), radius: 3)
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func demoConfirmation(_ title: LocalizedStringKey) -> some View {
        Label(title, systemImage: "checkmark.shield")
            .font(.caption.weight(.medium))
            .foregroundStyle(theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func demoAction(_ title: LocalizedStringKey, symbol: String, highlighted: Bool) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            if highlighted { tapIndicator }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(highlighted ? theme.textInverted : theme.textPrimary)
        .padding(12)
        .background(highlighted ? theme.accentPrimary : theme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private struct AnimationState: Hashable {
        let active: Bool
        let reduced: Bool
        let sceneActive: Bool
        let revision: Int
    }

    private struct DemonstrationPhase: Hashable {
        let step: Int
        let active: Bool
        let sceneActive: Bool
        let reduced: Bool
        let revision: Int
    }
}
