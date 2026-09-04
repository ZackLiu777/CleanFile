import StoreKit
import SwiftUI

struct PremiumSubscriptionView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if PremiumConfiguration.purchasesEnabled,
                   let groupID = PremiumConfiguration.subscriptionGroupID,
                   let privacyURL = PremiumConfiguration.privacyPolicyURL,
                   let termsURL = PremiumConfiguration.termsOfServiceURL {
                    SubscriptionStoreView(groupID: groupID) {
                        introduction
                    }
                    .subscriptionStoreControlStyle(.prominentPicker)
                    .subscriptionStoreControlBackground(theme.cardSurface)
                    .subscriptionStoreButtonLabel(.multiline)
                    .subscriptionStorePolicyDestination(url: privacyURL, for: .privacyPolicy)
                    .subscriptionStorePolicyDestination(url: termsURL, for: .termsOfService)
                    .storeButton(.visible, for: .restorePurchases)
                    .containerBackground(for: .subscriptionStoreFullHeight) {
                        AppBackground()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            introduction
                            unavailablePlans
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .background(AppBackground())
            .foregroundStyle(theme.textPrimary)
            .navigationTitle("CleanFile Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("premium.close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("premium.close")
                }
            }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("premium.screen")
    }

    private var introduction: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(theme.accentPrimary)
                    .accessibilityHidden(true)
                Text("premium.title")
                    .appTypeface(.largeTitle.bold(), size: 34, relativeTo: .largeTitle, weight: .bold)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("premium.subtitle")
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 20) {
                feature("premium.media.title", detail: "premium.media.detail", symbol: "photo.on.rectangle")
                feature("premium.storage.title", detail: "premium.storage.detail", symbol: "externaldrive")
                feature("premium.compression.title", detail: "premium.compression.detail", symbol: "arrow.down.right.and.arrow.up.left")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .appContentCard()

            Label("premium.privacy", systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    private func feature(_ title: LocalizedStringKey, detail: LocalizedStringKey, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(theme.accentPrimary)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var unavailablePlans: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("premium.plans.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Label("premium.plans.unavailable", systemImage: "info.circle")
            Text("premium.plans.retryLater")
                .foregroundStyle(theme.textSecondary)
            Text("premium.trial.note")
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .appContentCard()
        .padding(.horizontal, 24)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("premium.plans.unavailable")
    }
}
