// Premium 订阅页：展示功能、商品价格、恢复购买与服务条款。
// 商品和权益由对应的状态对象提供，页面不自行推断价格或试用资格。
// 大字号或紧凑窗口使用可滚动操作区，避免底部控件遮挡内容。
import SwiftUI

/// Premium 独立的浅色和深色界面配色，不依赖另一种外观的半透明颜色。
private struct PremiumPalette {
    let background: Color
    let text: Color
    let secondaryText: Color
    let surface: Color
    let border: Color
    let controlSurface: Color

    static let light = PremiumPalette(
        background: Color(red: 0.96, green: 0.97, blue: 0.96),
        text: Color(red: 0.08, green: 0.12, blue: 0.11),
        secondaryText: Color(red: 0.30, green: 0.34, blue: 0.33),
        surface: .white,
        border: .black.opacity(0.14),
        controlSurface: .black.opacity(0.06)
    )
    static let dark = PremiumPalette(
        background: Color(red: 0.06, green: 0.07, blue: 0.07),
        text: .white,
        secondaryText: .white.opacity(0.7),
        surface: .white.opacity(0.06),
        border: .white.opacity(0.12),
        controlSurface: .white.opacity(0.07)
    )
}

/// 展示订阅方案并将购买、恢复和核验重试交给状态对象处理。
struct PremiumSubscriptionView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @EnvironmentObject private var entitlementStore: PremiumEntitlementStore
    @EnvironmentObject private var themeSettings: ThemeSettings
    @StateObject private var purchaseModel = PremiumPurchaseViewModel()

    // 与用户当前选中的强调色保持同步，包括自定义颜色。
    private var premiumMint: Color { theme.accentPrimary }
    private var purchaseTextColor: Color {
        AppThemeColor.resolved(from: theme.accentPrimary, fallback: .black).preferredForeground.color
    }
    // 明暗外观分别采用完整配色，强调色继续跟随用户的主题设置。
    private var resolvedScheme: ColorScheme { themeSettings.effectiveColorScheme ?? colorScheme }
    private var isLight: Bool { resolvedScheme == .light }
    private var palette: PremiumPalette { isLight ? .light : .dark }
    private var premiumBackground: Color { palette.background }
    private var premiumText: Color { palette.text }
    private var premiumSecondaryText: Color { palette.secondaryText }
    private var premiumSurface: Color { palette.surface }
    private var premiumBorder: Color { palette.border }
    private var readableAccent: Color {
        let accent = AppThemeColor.resolved(from: theme.accentPrimary, fallback: .black)
        let background = AppThemeColor.resolved(from: premiumBackground, fallback: isLight ? .white : .black)
        guard accent.contrastRatio(with: background) < 4.5 else { return accent.color }
        let target: AppThemeColor = isLight ? .black : .white
        for step in 1...100 {
            let candidate = accent.blended(toward: target, amount: Double(step) / 100)
            if candidate.contrastRatio(with: background) >= 4.5 { return candidate.color }
        }
        return target.color
    }

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
                VStack(spacing: 10) {
                    if let requiredFeature { featureNotice(requiredFeature) }
                    hero
                    features
                    if entitlementStore.accessState == .checking {
                        verificationNotice
                    }
                    plans
                    if usesInlinePurchaseControls { purchaseControls }
                    legalLinks
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(premiumBackdrop)
            .foregroundStyle(premiumText)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !usesInlinePurchaseControls { purchaseFooter }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                premiumHeader
            }
        }
        .onAppear { purchaseModel.loadProducts() }
        .onDisappear { purchaseModel.cancelProductLoading() }
        .onChange(of: entitlementStore.accessState) { _, state in
            if state == .entitled, allowsDismiss { dismiss() }
        }
        .presentationDetents([.large])
        .preferredColorScheme(resolvedScheme)
        .accessibilityIdentifier("premium.screen")
    }

    private var premiumHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(premiumMint)
                .frame(width: 42, height: 42)
                .background(Color(red: 0.96, green: 0.95, blue: 0.84), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            (Text("Filevra ").foregroundStyle(premiumText) + Text("Premium").foregroundStyle(readableAccent))
                .font(.system(.headline, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel("Filevra Premium")
            Spacer(minLength: 8)
            if allowsDismiss {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(premiumText)
                        .frame(width: 44, height: 44)
                        .background(isLight ? .black.opacity(0.07) : .white.opacity(0.1), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppL10n.string("premium.close"))
                .accessibilityIdentifier("premium.close")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(premiumBackground.opacity(0.94))
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
            .foregroundStyle(readableAccent)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("premium.requiredFeature")
    }

    private var verificationNotice: some View {
        VStack(spacing: 10) {
            Text(AppL10n.string("premium.entitlement.checking"))
                .appTypeface(.footnote, size: 14, relativeTo: .footnote)
                .foregroundStyle(premiumSecondaryText)
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

    /// 明确标示示例，避免把宣传数字误认为设备的实际扫描结果。
    private var hero: some View {
        VStack(spacing: 6) {
            Text(AppL10n.string("premium.hero.title"))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [premiumText, readableAccent], startPoint: .top, endPoint: .bottom))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(AppL10n.string("premium.hero.subtitle"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(premiumSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { proxy in
                let width = min(proxy.size.width * 0.76, 300)
                ZStack {
                    RoundedRectangle(cornerRadius: 27)
                        .fill(premiumMint.opacity(0.12))
                        .frame(width: width, height: 128)
                        .rotationEffect(.degrees(-9))
                        .offset(x: -15, y: 6)
                    RoundedRectangle(cornerRadius: 27)
                        .fill(LinearGradient(colors: [premiumMint.opacity(0.36), premiumMint.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay {
                            RoundedRectangle(cornerRadius: 27)
                                .stroke(premiumMint.opacity(0.6), lineWidth: 2)
                        }
                        .frame(width: width, height: 128)
                        .rotationEffect(.degrees(5))
                        .shadow(color: premiumMint.opacity(0.22), radius: 16, y: 8)
                    VStack(alignment: .leading, spacing: 5) {
                        Label(AppL10n.string("intro.demo"), systemImage: "externaldrive.fill")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(premiumSecondaryText)
                        Text("194 GB")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(premiumText)
                        HStack(spacing: 0) {
                            premiumMint
                            Color(red: 0.35, green: 0.61, blue: 0.9)
                            Color(red: 0.95, green: 0.67, blue: 0.34)
                            premiumText.opacity(0.25)
                        }
                        .frame(height: 13)
                        .clipShape(Capsule())
                    }
                    .frame(width: width * 0.72, alignment: .leading)
                    Image(systemName: "photo.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(premiumMint.opacity(0.8), in: RoundedRectangle(cornerRadius: 13))
                        .rotationEffect(.degrees(-12))
                        .offset(x: -width * 0.5, y: 28)
                    Image(systemName: "video.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 13))
                        .rotationEffect(.degrees(12))
                        .offset(x: width * 0.5, y: -27)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 150)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(AppL10n.string("intro.demo")): 194 GB")
        }
        .frame(maxWidth: .infinity)
    }

    private var premiumBackdrop: some View {
        ZStack {
            premiumBackground
            LinearGradient(
                colors: [premiumMint.opacity(isLight ? 0.14 : 0.35), premiumBackground, isLight ? .white : .black],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(colors: [premiumMint.opacity(isLight ? 0.08 : 0.22), .clear], center: .topLeading, startRadius: 0, endRadius: 360)
        }
        .ignoresSafeArea()
    }

    /// 三列固定布局避免长文案触发整列纵向回退；文字可换行。
    private var features: some View {
        HStack(alignment: .top, spacing: 0) {
            feature(title: AppL10n.string("premium.feature.videoCompression"), symbol: "video")
            feature(title: AppL10n.string("premium.storage.title"), symbol: "folder")
            feature(title: AppL10n.string("premium.feature.compression.title"), symbol: "arrow.triangle.2.circlepath")
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("premium.features")
    }

    private func feature(title: String, symbol: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(readableAccent)
                .frame(height: 24)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(premiumText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var plans: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppL10n.string("premium.plans.title"))
                .appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            ForEach(PremiumPlan.allCases) { plan in planCard(plan) }
            catalogueStatus
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 展示方案选择和 StoreKit 价格；所选方案的试用说明保留在购买按钮。
    private func planCard(_ plan: PremiumPlan) -> some View {
        let selected = purchaseModel.selectedPlan == plan
        return Button { purchaseModel.selectedPlan = plan } label: {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Text(purchaseModel.priceDescription(for: plan) ?? AppL10n.string("premium.price.unavailable"))
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(premiumSecondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? readableAccent : premiumSecondaryText.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(selected ? premiumMint.opacity(isLight ? 0.12 : 0.16) : premiumSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected ? readableAccent : premiumBorder, lineWidth: selected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
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
            .foregroundStyle(premiumSecondaryText)
        } else if PremiumPlan.allCases.contains(where: { purchaseModel.products[$0] == nil }) {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppL10n.string("premium.pricing.unavailable"))
                    .appTypeface(.footnote, size: 14, relativeTo: .footnote)
                    .foregroundStyle(premiumSecondaryText)
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
        .tint(premiumSecondaryText)
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
            .padding(.top, 8)
            .padding(.bottom, 6)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .background { premiumBackground.ignoresSafeArea(edges: .bottom) }
    }

    private var purchaseControls: some View {
        VStack(spacing: 6) {
            if entitlementStore.accessState == .entitled {
                Label(AppL10n.string("premium.active"), systemImage: "checkmark.seal.fill")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(readableAccent)
                if allowsDismiss {
                    Button { dismiss() } label: {
                        Text(AppL10n.string("Done"))
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(purchaseTextColor)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(premiumMint, in: RoundedRectangle(cornerRadius: 24))
                            .contentShape(RoundedRectangle(cornerRadius: 24))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                if let feedback = purchaseModel.feedback {
                    Text(feedback)
                        .appTypeface(.footnote, size: 14, relativeTo: .footnote)
                        .foregroundStyle(premiumSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("premium.purchase.feedback")
                }
                purchaseButton
                restoreButton
                if allowsDismiss {
                    Button { dismiss() } label: {
                        Text(AppL10n.string("premium.continue.free"))
                            .appTypeface(.subheadline.weight(.medium), size: 16, relativeTo: .subheadline, weight: .medium)
                            .foregroundStyle(premiumSecondaryText)
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
                        ProgressView().tint(purchaseTextColor)
                    }
                    Text(AppL10n.string("premium.purchase.continue"))
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                }
                if let price = purchaseModel.priceDescription(for: purchaseModel.selectedPlan) {
                    Text(purchaseModel.offerDescription(for: purchaseModel.selectedPlan) ?? price)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                }
            }
            .foregroundStyle(purchaseTextColor)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(premiumMint, in: RoundedRectangle(cornerRadius: 28))
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
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(premiumText)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(palette.controlSurface, in: RoundedRectangle(cornerRadius: 28))
            .contentShape(RoundedRectangle(cornerRadius: 28))
        }
        .buttonStyle(.plain)
        .disabled(purchaseModel.isBusy)
        .accessibilityIdentifier("premium.restore")
    }
}
