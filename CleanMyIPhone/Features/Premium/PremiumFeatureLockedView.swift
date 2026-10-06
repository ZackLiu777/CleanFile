import SwiftUI

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

