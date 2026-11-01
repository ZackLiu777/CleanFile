// Premium 订阅页：展示功能、商品价格、恢复购买与服务条款。
// 商品和权益由对应的状态对象提供，页面不自行推断价格或试用资格。
// 大字号或紧凑窗口使用可滚动操作区，避免底部控件遮挡内容。
import SwiftUI

/// 展示订阅方案并将购买、恢复和核验重试交给状态对象处理。
struct PremiumSubscriptionView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @EnvironmentObject private var entitlementStore: PremiumEntitlementStore
    @StateObject private var purchaseModel = PremiumPurchaseViewModel()

    let allowsDismiss: Bool
    let requiredFeature: PremiumFeature?

    /// 配置关闭入口，以及从具体功能进入时需要显示的功能提示。
    init(allowsDismiss: Bool = true, requiredFeature: PremiumFeature? = nil) {
        self.allowsDismiss = allowsDismiss
        self.requiredFeature = requiredFeature
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let requiredFeature { featureNotice(requiredFeature) }
                    introduction
                    features
                    if entitlementStore.accessState == .checking {
                        verificationNotice
                    }
                    plans
                    if usesInlinePurchaseControls { purchaseControls }
                    legalLinks
                }
                .padding(24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(AppBackground())
            .foregroundStyle(theme.textPrimary)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !usesInlinePurchaseControls { purchaseFooter }
            }
            .navigationTitle("Filevra Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if allowsDismiss {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .tint(theme.accentPrimary)
                        .accessibilityLabel(AppL10n.string("premium.close"))
                        .accessibilityIdentifier("premium.close")
                    }
                }
            }
        }
        .onAppear { purchaseModel.loadProducts() }
        .onDisappear { purchaseModel.cancelProductLoading() }
        .onChange(of: entitlementStore.accessState) { _, state in
            if state == .entitled, allowsDismiss { dismiss() }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("premium.screen")
    }

    // Large text and short windows need a scrollable action area instead of a footer
    // that can consume all the space available for plans and subscription terms.
    private var usesInlinePurchaseControls: Bool {
        dynamicTypeSize.isAccessibilitySize || verticalSizeClass == .compact
    }

    private var isPurchaseDisabled: Bool {
        purchaseModel.isBusy || entitlementStore.accessState != .notEntitled ||
        purchaseModel.priceDescription(for: purchaseModel.selectedPlan) == nil
    }

    /// 标识触发本次升级页面的功能。
    private func featureNotice(_ feature: PremiumFeature) -> some View {
        Label(AppL10n.string(feature.titleKey), systemImage: "lock.fill")
            .font(.headline)
            .foregroundStyle(theme.accentPrimary)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("premium.requiredFeature")
    }

    private var verificationNotice: some View {
        VStack(spacing: 10) {
            Text(AppL10n.string("premium.entitlement.checking"))
                .appTypeface(.footnote, size: 14, relativeTo: .footnote)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if entitlementStore.verificationUnavailable {
                Button(AppL10n.string("premium.retry")) {
                    Task { await entitlementStore.refresh() }
                }
                .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var introduction: some View {
        VStack(spacing: 14) {
            Image(systemName: "crown.fill")
                .font(.largeTitle)
                .foregroundStyle(theme.accentPrimary)
                .accessibilityHidden(true)
            Text(AppL10n.string("premium.title"))
                .appTypeface(.title.bold(), size: 30, relativeTo: .title, weight: .bold)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(AppL10n.string("premium.value.summary"))
                .appTypeface(.body, size: 17, relativeTo: .body)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("premium.introduction")
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 20) {
            feature(title: AppL10n.string("Quick Cleanup"), detail: AppL10n.string("premium.quickClean.detail"), symbol: "sparkles")
            feature(title: AppL10n.string("premium.storage.title"), detail: AppL10n.string("premium.storage.detail"), symbol: "folder")
            feature(title: AppL10n.string("premium.feature.compression.title"), detail: AppL10n.string("premium.feature.compression.detail"), symbol: "arrow.triangle.2.circlepath")
            feature(title: AppL10n.string("premium.feature.appearance.title"), detail: AppL10n.string("premium.feature.appearance.detail"), symbol: "paintpalette")
            Divider()
            Text(AppL10n.string("premium.free.summary"))
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .appContentCard(cornerRadius: 24)
        .accessibilityIdentifier("premium.features")
    }

    /// 组合一项 Premium 功能说明，图标不重复进入无障碍朗读。
    private func feature(title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(theme.accentPrimary)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .appTypeface(.title3.bold(), size: 20, relativeTo: .title3, weight: .bold)
                Text(detail)
                    .appTypeface(.subheadline, size: 15, relativeTo: .subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(3)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var plans: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppL10n.string("premium.plans.title"))
                .appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            ForEach(PremiumPlan.allCases) { plan in planCard(plan) }
            catalogueStatus
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 展示方案选择、StoreKit 价格和当前用户可用的试用说明。
    private func planCard(_ plan: PremiumPlan) -> some View {
        let selected = purchaseModel.selectedPlan == plan
        return Button { purchaseModel.selectedPlan = plan } label: {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(plan.title)
                        .appTypeface(.title3.bold(), size: 20, relativeTo: .title3, weight: .bold)
                    Text(purchaseModel.priceDescription(for: plan) ?? AppL10n.string("premium.price.unavailable"))
                        .appTypeface(.body.weight(.semibold), size: 17, relativeTo: .body, weight: .semibold)
                        .foregroundStyle(theme.textPrimary)
                    if let offer = purchaseModel.offerDescription(for: plan) {
                        Text(offer)
                            .appTypeface(.footnote, size: 14, relativeTo: .footnote)
                            .foregroundStyle(theme.textSecondary)
                    } else if plan == .lifetime {
                        Text(AppL10n.string("premium.lifetime.detail"))
                            .appTypeface(.footnote, size: 14, relativeTo: .footnote)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? theme.accentPrimary : theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .appContentCard(cornerRadius: 24)
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(selected ? theme.accentPrimary : .clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .disabled(purchaseModel.isBusy)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("premium.plan." + plan.rawValue)
    }

    @ViewBuilder
    private var catalogueStatus: some View {
        if purchaseModel.catalogueState == .loading {
            HStack(spacing: 10) {
                ProgressView()
                Text(AppL10n.string("premium.pricing.loading"))
                    .appTypeface(.footnote, size: 14, relativeTo: .footnote)
            }
            .foregroundStyle(theme.textSecondary)
        } else if PremiumPlan.allCases.contains(where: { purchaseModel.products[$0] == nil }) {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppL10n.string("premium.pricing.unavailable"))
                    .appTypeface(.footnote, size: 14, relativeTo: .footnote)
                    .foregroundStyle(theme.textSecondary)
                Button(AppL10n.string("premium.retry")) { purchaseModel.retryProducts() }
                    .disabled(purchaseModel.isBusy)
                    .accessibilityIdentifier("premium.connection.retry")
            }
        }
    }

    private var legalLinks: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) { policyLinks }
            VStack(spacing: 4) { policyLinks }
        }
        .appTypeface(.footnote, size: 14, relativeTo: .footnote)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .tint(theme.textSecondary)
    }

    @ViewBuilder
    private var policyLinks: some View {
        Link(AppL10n.string("premium.terms"), destination: PremiumConfiguration.termsOfServiceURL)
            .frame(minHeight: 44)
            .accessibilityIdentifier("premium.termsLink")
        Link(AppL10n.string("premium.privacy.link"), destination: PremiumConfiguration.privacyPolicyURL)
            .frame(minHeight: 44)
            .accessibilityIdentifier("premium.privacyLink")
    }

    private var purchaseFooter: some View {
        purchaseControls
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .background { AppBackground().ignoresSafeArea(edges: .bottom) }
    }

    private var purchaseControls: some View {
        VStack(spacing: 12) {
            if entitlementStore.accessState == .entitled {
                Label(AppL10n.string("premium.active"), systemImage: "checkmark.seal.fill")
                    .appTypeface(.headline, size: 18, relativeTo: .headline, weight: .semibold)
                    .foregroundStyle(theme.accentPrimary)
                if allowsDismiss {
                    Button(AppL10n.string("Done")) { dismiss() }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .appGlassButtonStyle()
                }
            } else {
                if let feedback = purchaseModel.feedback {
                    Text(feedback)
                        .appTypeface(.footnote, size: 14, relativeTo: .footnote)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("premium.purchase.feedback")
                }
                purchaseButton
                restoreButton
                if allowsDismiss {
                    Button { dismiss() } label: {
                        Text(AppL10n.string("premium.continue.free"))
                            .appTypeface(.subheadline.weight(.medium), size: 16, relativeTo: .subheadline, weight: .medium)
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("premium.continueFree")
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var purchaseButton: some View {
        Button {
            Task {
                if await purchaseModel.purchase(using: entitlementStore), allowsDismiss { dismiss() }
            }
        } label: {
            VStack(spacing: 5) {
                HStack(spacing: 10) {
                    if purchaseModel.activity == .purchasing {
                        ProgressView().tint(theme.textInverted)
                    }
                    Text(AppL10n.string("premium.purchase.continue"))
                        .appTypeface(.headline, size: 18, relativeTo: .headline, weight: .semibold)
                }
                if let price = purchaseModel.priceDescription(for: purchaseModel.selectedPlan) {
                    Text(purchaseModel.offerDescription(for: purchaseModel.selectedPlan) ?? price)
                        .appTypeface(.subheadline.weight(.semibold), size: 15, relativeTo: .subheadline, weight: .semibold)
                }
            }
            .foregroundStyle(theme.textInverted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(theme.buttonPrimaryBackground, in: RoundedRectangle(cornerRadius: 28))
            .contentShape(RoundedRectangle(cornerRadius: 28))
            .opacity(isPurchaseDisabled ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isPurchaseDisabled)
        .accessibilityIdentifier("premium.purchase")
    }

    private var restoreButton: some View {
        Button {
            Task {
                if await purchaseModel.restore(using: entitlementStore), allowsDismiss { dismiss() }
            }
        } label: {
            HStack(spacing: 10) {
                if purchaseModel.activity == .restoring { ProgressView().tint(theme.accentPrimary) }
                Text(AppL10n.string("premium.restore"))
                    .appTypeface(.headline, size: 18, relativeTo: .headline, weight: .semibold)
                    .foregroundStyle(theme.textPrimary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .appContentCard(cornerRadius: 28)
            .contentShape(RoundedRectangle(cornerRadius: 28))
        }
        .buttonStyle(.plain)
        .disabled(purchaseModel.isBusy)
        .accessibilityIdentifier("premium.restore")
    }
}
