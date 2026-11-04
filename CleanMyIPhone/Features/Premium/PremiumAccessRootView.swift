// Premium 根视图连接应用生命周期、权益状态和功能访问策略。
// 启动和返回前台时核验权益，不主动展示订阅页面。
// 页面重建与前后台切换分别由 SwiftUI 状态和 scenePhase 驱动。
import ImageFormatConversionKit
import SwiftUI

/// 将权益状态同步到功能访问和主题。
struct PremiumAccessRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var themeSettings: ThemeSettings
    @ObservedObject var entitlementStore: PremiumEntitlementStore
    @StateObject private var accessStore: PremiumFeatureAccessStore

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
            .task(id: scenePhase) {
                synchronizeAccess()
                guard scenePhase == .active,
                      !PremiumConfiguration.bypassesEntitlementForUITesting,
                      !PremiumConfiguration.usesFreeTierForUITesting else { return }
                await entitlementStore.start()
            }
            .onChange(of: entitlementStore.accessState) { _, _ in
                synchronizeAccess()
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
