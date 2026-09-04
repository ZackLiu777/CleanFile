//
//  ContentView.swift
//  CleanMyIPhone
//
//  Created by Zane Liao on 8/18/26.
//
 
//
//  文件职责：声明 Content 界面结构、交互入口与展示状态。
//  所属模块：CleanMyIPhone。
//

import ImageFormatConversionKit
import Combine
import SwiftUI

/// 协调详情页面对自定义 Tab Bar 的可见性，避免未激活 Tab 的导航栈影响当前页面。
@MainActor
final class TabBarVisibilityCoordinator: ObservableObject {
    enum Scope: String {
        case media
        case storage
        case conversion
        case settings
    }

    @Published private(set) var isHidden = false
    private var activeScope: Scope = .media
    private var hiddenSources = Set<String>()

    func setActiveScope(_ scope: Scope) {
        activeScope = scope
        updateVisibility()
    }

    func setHidden(_ hidden: Bool, source: String, scope: Scope) {
        let key = "\(scope.rawValue):\(source)"
        if hidden {
            hiddenSources.insert(key)
        } else {
            hiddenSources.remove(key)
        }
        updateVisibility()
    }

    private func updateVisibility() {
        let scopePrefix = "\(activeScope.rawValue):"
        let shouldHide = hiddenSources.contains { $0.hasPrefix(scopePrefix) }
        guard shouldHide != isHidden else { return }
        isHidden = shouldHide
    }
}

/// 定义 `AppTab` 使用的有限状态或选项集合。
private enum AppTab: String, CaseIterable, Hashable {
    case photos
    case storage
    case conversion
    case settings

    var titleKey: LocalizedStringKey {
        switch self {
        case .photos:
            "Media"
        case .storage:
            "Storage"
        case .conversion:
            "Compress"
        case .settings:
            "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .photos:
            "photo.on.rectangle"
        case .storage:
            "externaldrive"
        case .conversion:
            "arrow.triangle.2.circlepath"
        case .settings:
            "gearshape"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .photos:
            "tab.media"
        case .storage:
            "tab.storage"
        case .conversion:
            "tab.convert"
        case .settings:
            "tab.settings"
        }
    }

    var tabBarScope: TabBarVisibilityCoordinator.Scope {
        switch self {
        case .photos: .media
        case .storage: .storage
        case .conversion: .conversion
        case .settings: .settings
        }
    }
}

private struct TabButtonFramesKey: PreferenceKey {
    static let defaultValue: [AppTab: CGRect] = [:]

    static func reduce(value: inout [AppTab: CGRect], nextValue: () -> [AppTab: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TabBarDragState {
    // Keep hit regions fixed while the selected label changes the bar's layout.
    let frames: [AppTab: CGRect]
    var target: AppTab
}

/// 定义 `ContentView` 的值语义数据与相关行为。
struct ContentView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var themeSettings: ThemeSettings
    @StateObject private var tabBarVisibility = TabBarVisibilityCoordinator()
    @StateObject private var mediaViewModel = PhotoLibraryViewModel()
    @StateObject private var fileViewModel = FileScannerViewModel()
    @AppStorage("selectedAppTab") private var selectedTab: AppTab = .photos
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabNamespace
    @State private var displayedTab: AppTab
    @State private var transitionFrom: AppTab?
    @State private var transitionTo: AppTab?
    @State private var outgoingPageOpacity = 1.0
    @State private var incomingPageOpacity = 0.0
    @State private var incomingPageOffset: CGFloat = 12
    @State private var transitionGeneration = 0
    @State private var tabButtonFrames: [AppTab: CGRect] = [:]
    @GestureState private var tabBarDragState: TabBarDragState?

    init() {
        let storedTab = UserDefaults.standard.string(forKey: "selectedAppTab")
        _displayedTab = State(initialValue: AppTab(rawValue: storedTab ?? "") ?? .photos)
    }

    var body: some View {
        Group {
            if themeSettings.liquidGlassTabEnabled {
                nativeTabView
            } else {
                customTabView
            }
        }
        .environmentObject(tabBarVisibility)
        .onChange(of: selectedTab) { _, newTab in
            // Native TabView changes the persisted selection directly. Keep the
            // custom page layer ready if the Liquid Glass option is turned off.
            guard themeSettings.liquidGlassTabEnabled else { return }
            settleTransition(to: newTab)
        }
        .onChange(of: themeSettings.liquidGlassTabEnabled) { _, _ in
            // Switching implementations must never leave an in-flight custom
            // transition or a stale displayed tab behind.
            settleTransition(to: selectedTab)
        }
    }

    private var nativeTabView: some View {
        TabView(selection: $selectedTab) {
            PhotosView(
                viewModel: mediaViewModel,
                isTabActive: selectedTab == .photos
            )
                .tabItem {
                    Label("Media", systemImage: "photo.on.rectangle")
                        .accessibilityIdentifier("tab.media")
                }
                .tag(AppTab.photos)

            StorageView(
                viewModel: fileViewModel,
                isTabActive: selectedTab == .storage
            )
                .tabItem {
                    Label("Storage", systemImage: "externaldrive")
                        .accessibilityIdentifier("tab.storage")
                }
                .tag(AppTab.storage)

            ConversionHomeView(
                theme: theme.conversionTheme,
                isTabActive: selectedTab == .conversion,
                animationsEnabled: themeSettings.interfaceAnimationsEnabled
            )
                .tabItem {
                    Label("Compress", systemImage: "arrow.triangle.2.circlepath")
                        .accessibilityIdentifier("tab.convert")
                }
                .tag(AppTab.conversion)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                        .accessibilityIdentifier("tab.settings")
                }
                .tag(AppTab.settings)
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(theme.accentPrimary)
        .toolbarBackground(.hidden, for: .tabBar)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }

    private var customTabView: some View {
        ZStack {
            // Keep the app background mounted outside the page transition. The
            // individual pages fade out as a unit, so without this stable layer
            // the transparent interval would expose the window's white color.
            // The opaque representative color is an immediate fallback for
            // complex custom backgrounds while their full renderer is composited.
            theme.backgroundPrimary
                .ignoresSafeArea()
            ThemeBackgroundLayer(background: theme.background)
                .ignoresSafeArea()

            ForEach(AppTab.allCases, id: \.self) { tab in
                page(for: tab)
                    // Fade the completed page, including its background, as one
                    // group instead of applying opacity to overlapping surfaces.
                    .compositingGroup()
                    .opacity(pageOpacity(for: tab))
                    .offset(y: pageOffset(for: tab))
                    .allowsHitTesting(isInteractive(tab))
                    .accessibilityHidden(!isInteractive(tab))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !tabBarVisibility.isHidden {
                tabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .tint(theme.accentPrimary)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .animation(
            animationsEnabled ? .easeInOut(duration: 0.28) : nil,
            value: tabBarVisibility.isHidden
        )
        .onAppear {
            tabBarVisibility.setActiveScope(displayedTab.tabBarScope)
        }
        .onChange(of: displayedTab) { _, newTab in
            tabBarVisibility.setActiveScope(newTab.tabBarScope)
        }
    }

    @ViewBuilder
    private func page(for tab: AppTab) -> some View {
        switch tab {
        case .photos:
            PhotosView(
                viewModel: mediaViewModel,
                isTabActive: displayedTab == .photos
            )
        case .storage:
            StorageView(
                viewModel: fileViewModel,
                isTabActive: displayedTab == .storage
            )
        case .conversion:
            ConversionHomeView(
                theme: theme.conversionTheme,
                isTabActive: displayedTab == .conversion,
                animationsEnabled: themeSettings.interfaceAnimationsEnabled,
                onDetailVisibilityChanged: { isDetailVisible in
                    tabBarVisibility.setHidden(
                        isDetailVisible,
                        source: "conversion.tool",
                        scope: .conversion
                    )
                }
            )
        case .settings:
            SettingsView()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .padding(5)
        .background {
            // Use the same opaque theme token as the stable page background.
            // This prevents a material or gradient renderer from exposing the
            // system window's white backdrop during a tab transition.
            Capsule()
                .fill(theme.backgroundPrimary)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(theme.divider.opacity(0.5), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 8)
        }
        .coordinateSpace(name: "customTabBar")
        .contentShape(Capsule())
        .onPreferenceChange(TabButtonFramesKey.self) { tabButtonFrames = $0 }
        .highPriorityGesture(tabBarDragGesture)
        .animation(
            animationsEnabled ? .spring(response: 0.24, dampingFraction: 0.88) : nil,
            value: tabBarDragState?.target
        )
        // Match the native Liquid Glass tab bar's 16pt side inset.
        .padding(.horizontal, 16)
        .padding(.bottom, -10)
    }

    private func tabButton(for tab: AppTab) -> some View {
        let isHighlighted = (tabBarDragState?.target ?? selectedTab) == tab
        return Button {
            selectTab(tab)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.systemImage)

                if isHighlighted {
                    Text(tab.titleKey)
                }
            }
            .appTypeface(
                .caption.weight(.medium),
                size: 13,
                relativeTo: .caption,
                weight: .medium
            )
            .foregroundStyle(
                isHighlighted ? theme.textPrimary : theme.textSecondary
            )
            .frame(maxWidth: .infinity)
            .frame(height: 45)
            .padding(.horizontal, isHighlighted ? 10 : 7)
            .background {
                if isHighlighted {
                    Capsule()
                        .fill(theme.accentPrimary.opacity(0.14))
                        .matchedGeometryEffect(id: "selectedTab", in: tabNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.titleKey))
        .accessibilityIdentifier(tab.accessibilityIdentifier)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: TabButtonFramesKey.self,
                    value: [tab: geometry.frame(in: .named("customTabBar"))]
                )
            }
        }
    }

    private var tabBarDragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named("customTabBar"))
            .updating($tabBarDragState) { value, state, _ in
                if state == nil {
                    guard abs(value.translation.width) > abs(value.translation.height),
                          !tabButtonFrames.isEmpty else { return }
                    state = TabBarDragState(frames: tabButtonFrames, target: selectedTab)
                }
                if let frames = state?.frames,
                   let target = tab(at: value.location.x, in: frames) {
                    state?.target = target
                }
            }
            .onEnded { value in
                guard tabBarDragState != nil
                    || abs(value.translation.width) > abs(value.translation.height) else { return }
                let frames = tabBarDragState?.frames ?? tabButtonFrames
                if let target = tab(at: value.location.x, in: frames) {
                    selectTab(target)
                }
            }
    }

    private func tab(at x: CGFloat, in frames: [AppTab: CGRect]) -> AppTab? {
        // Nearest centers also cover button gaps and clamp drags past either end.
        frames.min { abs($0.value.midX - x) < abs($1.value.midX - x) }?.key
    }

    private func pageOpacity(for tab: AppTab) -> Double {
        guard let transitionFrom, let transitionTo else {
            return tab == displayedTab ? 1 : 0
        }

        if tab == transitionFrom {
            return outgoingPageOpacity
        }

        if tab == transitionTo {
            return incomingPageOpacity
        }

        return 0
    }

    private func pageOffset(for tab: AppTab) -> CGFloat {
        tab == transitionTo ? incomingPageOffset : 0
    }

    private func isInteractive(_ tab: AppTab) -> Bool {
        transitionTo == nil && tab == displayedTab
    }

    private var animationsEnabled: Bool {
        themeSettings.interfaceAnimationsEnabled && !reduceMotion
    }

    private func selectTab(_ newTab: AppTab) {
        guard newTab != selectedTab else { return }

        // Finish the previous transition before starting another one so a rapid
        // sequence of taps cannot leave the page layer in an inconsistent state.
        if transitionTo != nil {
            settleTransition(to: selectedTab)
        }

        let oldTab = displayedTab
        guard oldTab != newTab else { return }

        if !animationsEnabled {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedTab = newTab
                displayedTab = newTab
                transitionFrom = nil
                transitionTo = nil
                outgoingPageOpacity = 1
                incomingPageOpacity = 0
                incomingPageOffset = 12
            }
            return
        }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            selectedTab = newTab
        }

        transitionFrom = oldTab
        transitionTo = newTab
        outgoingPageOpacity = 1
        incomingPageOpacity = 0
        incomingPageOffset = 12
        transitionGeneration += 1
        let generation = transitionGeneration

        withAnimation(.easeOut(duration: 0.18)) {
            outgoingPageOpacity = 0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard generation == transitionGeneration else { return }

            displayedTab = newTab

            withAnimation(.easeIn(duration: 0.38)) {
                incomingPageOpacity = 1
                incomingPageOffset = 0
            }

            try? await Task.sleep(for: .milliseconds(400))
            guard generation == transitionGeneration else { return }
            settleTransition(to: newTab)
        }
    }

    private func settleTransition(to tab: AppTab) {
        transitionGeneration += 1

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedTab = tab
            displayedTab = tab
            transitionFrom = nil
            transitionTo = nil
            outgoingPageOpacity = 1
            incomingPageOpacity = 0
            incomingPageOffset = 12
        }
    }
}

/// 扩展 `Theme`，集中实现当前文件所需的附加能力。
private extension Theme {
    var conversionTheme: ConversionTheme {
        ConversionTheme(
            background: conversionBackground,
            cardSurface: cardSurface,
            cardElevated: cardElevated,
            cardHighlight: backgroundSecondary,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            accent: accentPrimary,
            destructive: negativeRed,
            divider: divider,
            liquidGlassEnabled: liquidGlassEnabled,
            liquidGlassCardsEnabled: liquidGlassCardsEnabled
        )
    }

    var conversionBackground: ConversionBackground {
        switch background {
        case let .solid(color):
            .solid(color)
        case let .linearGradient(stops, startPoint, endPoint):
            .linearGradientStops(
                stops: stops.map {
                    ConversionGradientStop(color: $0.color.color, location: $0.location)
                },
                startPoint: startPoint,
                endPoint: endPoint
            )
        case let .meshGradient(colors):
            .meshGradient(colors: colors)
        }
    }
}

#if DEBUG
// Keep the canvas preview stateless. The live root owns file-scanning and
// PhotoKit state objects that should only be attached by the running app.
#Preview("App Theme") {
    VStack(spacing: 16) {
        Image(systemName: "photo.on.rectangle")
            .appTypeface(.largeTitle, size: 34, relativeTo: .largeTitle, weight: .regular)
            .foregroundStyle(Theme.system.accentPrimary)

        Text("CleanMyIPhone")
            .appTypeface(.title2.bold(), size: 22, relativeTo: .title2, weight: .bold)

        Text("Run the app to choose a folder or access the photo library.")
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
    }
    .padding()
}
#endif
