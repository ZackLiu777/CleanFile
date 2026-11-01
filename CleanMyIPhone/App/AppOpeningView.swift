// 应用开屏画面及其容器。
// 容器根据启动状态切换内容，并通过环境值通知下游开屏是否完成；减少动态效果和场景状态影响画面动画。
// 开屏容器始终保留底层内容，遮罩存在时禁止底层点击和无障碍访问。
// 用户启用减少动态效果时缩短过渡；UI 测试启动参数可跳过开屏动画。

import SwiftUI

/// Hosts the opening artwork without mixing it into application navigation state.
struct AppOpeningView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var animationsEnabled = true
    @State private var startedAt = Date()

    private var animates: Bool {
        animationsEnabled && !reduceMotion && scenePhase == .active
    }

    var body: some View {
        GeometryReader { geometry in
            let artworkSize = min(geometry.size.width * 0.76, geometry.size.height * 0.43, 340)

            ZStack {
                theme.backgroundPrimary.ignoresSafeArea()
                AppBackground()
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animates)) { context in
                    let elapsed = animates ? context.date.timeIntervalSince(startedAt) : 2
                    RippleOpeningArtwork(time: min(elapsed, 2), size: artworkSize)
                }
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("正式开屏 · 涟漪收束") {
    AppOpeningView()
        .environment(\.appTheme, Theme.filevra)
}

#Preview("正式开屏 · 静态") {
    AppOpeningView(animationsEnabled: false)
        .environment(\.appTheme, Theme.filevra)
}
#endif

/// Keeps startup presentation separate from the application's navigation and business state.
private struct AppOpeningCompletedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var appOpeningCompleted: Bool {
        get { self[AppOpeningCompletedKey.self] }
        set { self[AppOpeningCompletedKey.self] = newValue }
    }
}

/// 协调开屏与目标内容的显示，并在遮罩存在时屏蔽底层交互和无障碍访问。
struct AppOpeningContainer<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var launchState: AppLaunchState
    @State private var openingCompleted = false
    private let destination: AppLaunchState.Destination
    private let content: Content

    /// 保存目标和内容；UI 测试启动参数会跳过开屏动画。
    init(destination: AppLaunchState.Destination, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.destination = destination
        let arguments = ProcessInfo.processInfo.arguments
        _launchState = State(initialValue: AppLaunchState(
            destination: destination,
            skipsAnimation: arguments.contains { $0.hasPrefix("--ui-test") }
        ))
    }

    var body: some View {
        ZStack {
            content
                .environment(\.appOpeningCompleted, openingCompleted)
                .allowsHitTesting(!launchState.showsOpening)
                .accessibilityHidden(launchState.showsOpening)
            if launchState.showsOpening {
                AppOpeningView(animationsEnabled: !reduceMotion)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onChange(of: destination) { _, value in
            withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.32)) {
                launchState.destinationChanged(to: value)
            } completion: {
                if !launchState.showsOpening { openingCompleted = true }
            }
        }
        .task {
            guard launchState.phase == .animating else {
                openingCompleted = !launchState.showsOpening
                return
            }
            let duration: Duration = reduceMotion ? .milliseconds(450) : .milliseconds(2050)
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.32)) {
                launchState.animationFinished()
            } completion: {
                if !launchState.showsOpening { openingCompleted = true }
            }
        }
    }
}
