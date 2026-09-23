import StoreKit
import SwiftUI

struct PremiumSubscriptionView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var entitlementStore: PremiumEntitlementStore
    @State private var lifetimeProduct: Product?
    @State private var isLoadingLifetimeProduct = false
    @State private var isPurchasingLifetime = false
    @State private var isStorefrontReady = false
    @State private var isCheckingStorefront = true
    @State private var storefrontFailureIsNetwork = true

    let allowsDismiss: Bool

    init(allowsDismiss: Bool = true) {
        self.allowsDismiss = allowsDismiss
    }

    var body: some View {
        NavigationStack {
            Group {
                if PremiumConfiguration.purchasesEnabled,
                   let groupID = PremiumConfiguration.subscriptionGroupID {
                    if isStorefrontReady {
                        SubscriptionStoreView(groupID: groupID) {
                            introduction
                        }
                        .subscriptionStoreControlStyle(.prominentPicker)
                        .subscriptionStoreControlBackground(theme.cardSurface)
                        .subscriptionStoreButtonLabel(.multiline)
                        .subscriptionStorePolicyDestination(
                            url: PremiumConfiguration.privacyPolicyURL,
                            for: .privacyPolicy
                        )
                        .subscriptionStorePolicyDestination(
                            url: PremiumConfiguration.termsOfServiceURL,
                            for: .termsOfService
                        )
                        .subscriptionStorePolicyForegroundStyle(theme.textSecondary)
                        .storeButton(.visible, for: .restorePurchases)
                        .onInAppPurchaseCompletion { _, result in
                            guard case .success(let purchaseResult) = result else {
                                if case .failure(let error) = result {
                                    entitlementStore.recordPurchaseError(error)
                                }
                                await entitlementStore.refresh()
                                return
                            }
                            let didUnlock = await entitlementStore.handlePurchaseResult(purchaseResult)
                            if didUnlock, allowsDismiss {
                                dismiss()
                            }
                        }
                        .containerBackground(for: .subscriptionStoreFullHeight) {
                            AppBackground()
                        }
                    } else {
                        offlineStorefront
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
                if allowsDismiss {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("premium.close", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("premium.close")
                    }
                }
            }
        }
        .task {
            await loadStorefront()
        }
        .onChange(of: entitlementStore.accessState) { _, state in
            if state == .entitled, allowsDismiss {
                dismiss()
            }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("premium.screen")
    }

    private var offlineStorefront: some View {
        ScrollView {
            VStack(spacing: 24) {
                introduction

                if isCheckingStorefront {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: 140)
                        .accessibilityLabel("premium.entitlement.checking")
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: storefrontFailureIsNetwork ? "wifi.exclamationmark" : "info.circle")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(theme.accentPrimary)
                            .accessibilityHidden(true)
                        Text(storefrontFailureIsNetwork ? "premium.connection.title" : "premium.plans.title")
                            .appTypeface(.title3.bold(), size: 20, relativeTo: .title3, weight: .bold)
                        Text(storefrontFailureIsNetwork ? "premium.connection.message" : "premium.plans.retryLater")
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("premium.retry") {
                            Task { await loadStorefront() }
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("premium.connection.retry")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .appContentCard()
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 640)
                }
            }
            .padding(.bottom, 24)
        }
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

            lifetimePurchaseCard
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    private var lifetimePurchaseCard: some View {
        Group {
            if let lifetimeProduct {
                Button {
                    Task { await purchaseLifetime(lifetimeProduct) }
                } label: {
                    lifetimeOptionLabel(price: lifetimeProduct.displayPrice)
                }
                .buttonStyle(.plain)
                .disabled(isPurchasingLifetime)
                .accessibilityIdentifier("premium.lifetime.purchase")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        lifetimeDescription
                        Spacer(minLength: 12)
                        Image(systemName: "infinity")
                            .foregroundStyle(theme.accentPrimary)
                            .accessibilityHidden(true)
                    }

                    if isLoadingLifetimeProduct {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("premium.lifetime.loading")
                    } else {
                        Text("premium.lifetime.unavailable")
                            .font(.footnote)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .padding(20)
                .appContentCard()
            }
        }
        .accessibilityIdentifier("premium.lifetime.card")
    }

    private func lifetimeOptionLabel(price: String) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("premium.lifetime.title")
                    .appTypeface(.title2.bold(), size: 22, relativeTo: .title2, weight: .bold)

                HStack(spacing: 6) {
                    Text(price)
                    Text("premium.lifetime.once")
                        .foregroundStyle(theme.textSecondary)
                }
                .font(.subheadline)

                Text("premium.lifetime.detail")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isPurchasingLifetime {
                ProgressView()
                    .controlSize(.large)
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 112)
        .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(theme.divider, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var lifetimeDescription: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("premium.lifetime.title")
                .appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)
            Text("premium.lifetime.detail")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
        }
    }

    private func loadStorefront() async {
        guard PremiumConfiguration.purchasesEnabled else { return }
        isCheckingStorefront = true
        isLoadingLifetimeProduct = true
        defer {
            isCheckingStorefront = false
            isLoadingLifetimeProduct = false
        }

        if entitlementStore.startupConnectivity != .available {
            // This request triggers the system cellular-data choice. A failure here
            // can be stale for a moment after the user grants access, so StoreKit is
            // the final authority for whether the purchase page can be shown.
            _ = await entitlementStore.refreshStartupConnectivity()
        }

        do {
            var products = try await Product.products(for: PremiumConfiguration.productIDs)
            if !products.contains(where: {
                PremiumConfiguration.subscriptionProductIDs.contains($0.id)
            }) {
                try await Task.sleep(for: .milliseconds(650))
                products = try await Product.products(for: PremiumConfiguration.productIDs)
            }
            guard products.contains(where: {
                PremiumConfiguration.subscriptionProductIDs.contains($0.id)
            }) else {
                storefrontFailureIsNetwork = false
                isStorefrontReady = false
                return
            }
            lifetimeProduct = products.first { $0.id == PremiumConfiguration.lifetimeProductID }
            isStorefrontReady = true
        } catch {
            storefrontFailureIsNetwork = error is URLError
            isStorefrontReady = false
            entitlementStore.recordPurchaseError(error)
        }
    }

    private func purchaseLifetime(_ product: Product) async {
        guard !isPurchasingLifetime else { return }
        isPurchasingLifetime = true
        defer { isPurchasingLifetime = false }

        do {
            let result = try await product.purchase()
            let didUnlock = await entitlementStore.handlePurchaseResult(result)
            if didUnlock, allowsDismiss {
                dismiss()
            }
        } catch StoreKitError.userCancelled {
            return
        } catch {
            entitlementStore.recordPurchaseError(error)
        }
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
