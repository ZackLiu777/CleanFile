// 付费功能不可用时使用的统一入口。
// 页面区分权益正在核验与需要 Premium 两种提示，并提供订阅页面入口。
// 实际权限判定仍由 PremiumFeatureAccessStore 负责。
import SwiftUI

/// 展示指定功能的锁定状态和解锁操作。
struct PremiumFeatureLockedView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var accessStore: PremiumFeatureAccessStore
    @State private var showsPremium = false
    let feature: PremiumFeature

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .foregroundStyle(theme.accentPrimary)
                Text(AppL10n.string(feature.titleKey))
                    .appTypeface(.title2.bold(), size: 24, relativeTo: .title2, weight: .bold)
                Text(AppL10n.string(accessStore.accessState == .checking
                                    ? "premium.entitlement.checking" : "premium.feature.required"))
                    .foregroundStyle(theme.textSecondary)
                Button(AppL10n.string("premium.feature.unlock")) { showsPremium = true }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("premium.unlock." + feature.rawValue)
            }
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppBackground())
        }
        .sheet(isPresented: $showsPremium) { PremiumSubscriptionView(requiredFeature: feature) }
        .accessibilityIdentifier("premium.locked." + feature.rawValue)
    }
}

