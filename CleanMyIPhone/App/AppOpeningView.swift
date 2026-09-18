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
                    FileFlowOpeningArtwork(time: min(elapsed, 2), size: artworkSize)
                        .frame(width: artworkSize, height: artworkSize)
                }
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Keeps startup presentation separate from the application's navigation and business state.
struct AppOpeningContainer<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsOpening: Bool
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
        let arguments = ProcessInfo.processInfo.arguments
        _showsOpening = State(initialValue: !arguments.contains { $0.hasPrefix("--ui-test") })
    }

    var body: some View {
        ZStack {
            content
            if showsOpening {
                AppOpeningView(animationsEnabled: !reduceMotion)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task(id: showsOpening) {
            guard showsOpening else { return }
            let duration: Duration = reduceMotion ? .milliseconds(450) : .milliseconds(2050)
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.32)) {
                showsOpening = false
            }
        }
    }
}
