// Premium 根视图连接应用生命周期、权益状态和功能访问策略。
// 开屏完成且启动核验结束后，符合条件时展示可关闭的订阅页面。
// 页面重建与前后台切换分别由 SwiftUI 状态和 scenePhase 驱动。
import ImageFormatConversionKit
import SwiftUI

/// 将权益同步到功能访问与主题，并协调入口订阅页的展示时机。
struct PremiumAccessRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appOpeningCompleted) private var openingCompleted
    @EnvironmentObject private var themeSettings: ThemeSettings
    @ObservedObject var entitlementStore: PremiumEntitlementStore
    @StateObject private var accessStore: PremiumFeatureAccessStore
    @State private var entryPresentation = PremiumEntryPresentation()
    @State private var showsEntryPremium = false
    @State private var entryVerified = false

    /// 从当前权益构造访问策略；UI 测试模式使用固定初始状态。
    init(entitlementStore: PremiumEntitlementStore) {
        self.entitlementStore = entitlementStore
        let state: PremiumEntitlementStore.AccessState = PremiumConfiguration.bypassesEntitlementForUITesting
            ? .entitled : PremiumConfiguration.usesFreeTierForUITesting ? .notEntitled : entitlementStore.accessState
        _accessStore = StateObject(wrappedValue: PremiumFeatureAccessStore(accessState: state))
    }

    var body: some View {
        ContentView(accessStore: accessStore)
            .environmentObject(accessStore)
            .environment(\.conversionUsagePolicy, accessStore.conversionPolicy)
            .sheet(isPresented: $showsEntryPremium) {
                PremiumSubscriptionView(allowsDismiss: true)
            }
            .task(id: scenePhase) {
                synchronizeAccess()
                guard scenePhase == .active, !skipsEntryPremium else { return }
                await entitlementStore.start()
                guard !Task.isCancelled, scenePhase == .active else { return }
                entryVerified = true
                presentEntryPremiumIfNeeded()
            }
            .onChange(of: openingCompleted) { _, _ in
                presentEntryPremiumIfNeeded()
            }
            .onChange(of: entitlementStore.accessState) { _, state in
                synchronizeAccess()
                if state == .entitled { showsEntryPremium = false }
                presentEntryPremiumIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    entryVerified = false
                }
            }
    }

    private var skipsEntryPremium: Bool {
        PremiumConfiguration.bypassesEntitlementForUITesting || PremiumConfiguration.usesFreeTierForUITesting
    }

    /// 只有场景活跃、已核验并完成开屏时才尝试消费入口展示机会。
    private func presentEntryPremiumIfNeeded() {
        guard !skipsEntryPremium, scenePhase == .active, entryVerified else { return }
        if entryPresentation.consumePresentation(for: entitlementStore.accessState, openingCompleted: openingCompleted) {
            showsEntryPremium = true
        }
    }

    /// 将权益更新同步到功能权限及付费外观的保留策略。
    private func synchronizeAccess() {
        if !PremiumConfiguration.bypassesEntitlementForUITesting,
           !PremiumConfiguration.usesFreeTierForUITesting {
            accessStore.update(entitlementStore.accessState)
        }
        themeSettings.setPremiumAppearanceAllowed(accessStore.preservesPremiumAppearance)
    }
}

/// The offer is consumed once for this root lifetime; foreground transitions do not reset it.
@MainActor
struct PremiumEntryPresentation {
    private var hasPresented = false

    /// 仅在已确认无权益且开屏完成时返回 true，同一实例只消费一次。
    mutating func consumePresentation(for state: PremiumEntitlementStore.AccessState, openingCompleted: Bool = true) -> Bool {
        guard openingCompleted, state == .notEntitled, !hasPresented else { return false }
        hasPresented = true
        return true
    }
}
