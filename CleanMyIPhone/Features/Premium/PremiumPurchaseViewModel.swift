// Premium 商品目录、购买与恢复操作的界面状态。
// 价格和试用资格来自 StoreKit；目录不可用时不伪造商品信息。
// 加载任务使用代次与取消机制，防止过期请求覆盖较新的商品结果。
import Combine
import Foundation
import StoreKit

/// 可展示的订阅或终身方案，以及对应的 StoreKit 商品身份和类型。
enum PremiumPlan: String, CaseIterable, Identifiable {
    case annual, monthly, lifetime

    var id: Self { self }

    var productID: String {
        switch self {
        case .annual: PremiumConfiguration.annualProductID
        case .monthly: PremiumConfiguration.monthlyProductID
        case .lifetime: PremiumConfiguration.lifetimeProductID
        }
    }

    var title: String {
        switch self {
        case .annual: AppL10n.string("premium.plan.annual")
        case .monthly: AppL10n.string("premium.plan.monthly")
        case .lifetime: AppL10n.string("premium.lifetime.title")
        }
    }

    var productType: Product.ProductType {
        self == .lifetime ? .nonConsumable : .autoRenewable
    }
}

@MainActor
/// 管理方案选择、商品加载和互斥的购买/恢复交互。
final class PremiumPurchaseViewModel: ObservableObject {
    /// 商品目录的加载状态，与购买操作状态分开维护。
    enum CatalogueState: Equatable { case idle, loading, available, unavailable }
    /// 正在执行的商店操作；购买和恢复不会同时提交。
    enum Activity: Equatable { case idle, purchasing, restoring }

    @Published var selectedPlan: PremiumPlan = .annual
    @Published private(set) var catalogueState: CatalogueState = .idle
    @Published private(set) var activity: Activity = .idle
    @Published private(set) var products: [PremiumPlan: Product] = [:]
    @Published private(set) var eligibleIntroOffers: Set<PremiumPlan> = []
    @Published private(set) var feedback: String?

    private let productLookup: @MainActor () async throws -> [Product]
    private let introEligibility: @MainActor (Product) async -> Bool
    private var loadTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var loadGeneration = 0

    /// 注入商品和试用资格查询；默认实现使用 StoreKit。
    init(
        productLookup: @escaping @MainActor () async throws -> [Product] = {
            guard PremiumConfiguration.purchasesEnabled,
                  !PremiumConfiguration.usesFreeTierForUITesting else { return [] }
            return try await Product.products(for: PremiumConfiguration.productIDs.sorted())
        },
        introEligibility: @escaping @MainActor (Product) async -> Bool = {
            await $0.subscription?.isEligibleForIntroOffer ?? false
        }
    ) {
        self.productLookup = productLookup
        self.introEligibility = introEligibility
    }

    deinit {
        loadTask?.cancel()
        timeoutTask?.cancel()
    }

    var selectedProduct: Product? { products[selectedPlan] }
    var isBusy: Bool { activity != .idle }

    /// The catalogue only enriches an already-visible page. A slow StoreKit request
    /// must not gate navigation, free access, or the ability to dismiss the paywall.
    @discardableResult
    func loadProducts() -> Task<Void, Never> {
        if let loadTask { return loadTask }
        loadGeneration &+= 1
        let generation = loadGeneration
        catalogueState = .loading
        // Re-request price and eligibility together; never reuse an offer after an account/storefront change.
        products = [:]
        eligibleIntroOffers = []
        let lookup = productLookup
        let eligibility = introEligibility

        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self, self.loadGeneration == generation,
                  self.catalogueState == .loading else { return }
            self.catalogueState = .unavailable
        }
        let task = Task { [weak self] in
            defer { self?.finishLoading(generation: generation) }
            do {
                let fetched = try await lookup()
                guard !Task.isCancelled, self?.loadGeneration == generation else { return }
                self?.installProducts(fetched)
                for plan in PremiumPlan.allCases {
                    guard let product = self?.products[plan],
                          product.subscription?.introductoryOffer?.paymentMode == .freeTrial else { continue }
                    let isEligible = await eligibility(product)
                    guard !Task.isCancelled, self?.loadGeneration == generation else { return }
                    if isEligible { self?.eligibleIntroOffers.insert(plan) }
                }
            } catch {
                guard !Task.isCancelled, self?.loadGeneration == generation else { return }
                self?.catalogueState = .unavailable
            }
        }
        loadTask = task
        return task
    }

    /// 取消当前目录查询并推进代次，忽略可能迟到的旧结果。
    func cancelProductLoading() {
        loadGeneration &+= 1
        loadTask?.cancel()
        timeoutTask?.cancel()
        loadTask = nil
        timeoutTask = nil
        if catalogueState == .loading {
            catalogueState = products.isEmpty ? .idle : .available
        }
    }

    /// 结束旧查询后重新请求价格和试用资格。
    func retryProducts() {
        cancelProductLoading()
        loadProducts()
    }

    /// 根据真实商品价格与周期生成文案；商品或周期不可用时返回 nil。
    func priceDescription(for plan: PremiumPlan) -> String? {
        guard let product = products[plan] else { return nil }
        if plan == .lifetime {
            return product.displayPrice + " · " + AppL10n.string("premium.lifetime.once")
        }
        guard let subscription = product.subscription,
              let period = Self.periodDescription(subscription.subscriptionPeriod) else { return nil }
        return String(format: AppL10n.string("premium.price.recurring"), product.displayPrice, period)
    }

    /// 仅为已确认有资格的免费试用生成说明，并包含后续价格。
    func offerDescription(for plan: PremiumPlan) -> String? {
        guard eligibleIntroOffers.contains(plan),
              let offer = products[plan]?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial,
              let period = Self.periodDescription(offer.period, count: offer.periodCount),
              let price = priceDescription(for: plan) else { return nil }
        return String(format: AppL10n.string("premium.offer.free"), period, price)
    }

    /// 发起购买并交由权益对象处理交易；返回是否已有或成功获得访问权。
    func purchase(using entitlementStore: PremiumEntitlementStore) async -> Bool {
        guard !isBusy else { return false }
        if entitlementStore.accessState == .entitled { return true }
        // An unresolved entitlement check must not invite an existing subscriber to pay again.
        guard entitlementStore.accessState == .notEntitled,
              PremiumConfiguration.purchasesEnabled,
              let product = selectedProduct,
              priceDescription(for: selectedPlan) != nil else { return false }
        activity = .purchasing
        feedback = nil
        defer { activity = .idle }
        do {
            let result = try await product.purchase()
            switch result {
            case .pending: feedback = AppL10n.string("premium.purchase.pending")
            case .success(.unverified): feedback = AppL10n.string("premium.purchase.unverified")
            default: break
            }
            // Preserve the verified delivery/finish path used by the previous native paywall.
            return await entitlementStore.handlePurchaseResult(result)
        } catch {
            if !Self.isCancellation(error) {
                feedback = AppL10n.string("premium.lifetime.error.purchase")
                entitlementStore.recordPurchaseError(error)
            }
            return false
        }
    }

    /// 用户主动恢复时同步 App Store，再按核验结果更新反馈。
    func restore(using entitlementStore: PremiumEntitlementStore) async -> Bool {
        guard !isBusy else { return false }
        activity = .restoring
        feedback = nil
        defer { activity = .idle }
        do {
            // AppStore.sync may prompt for authentication; only this explicit user action calls it.
            try await AppStore.sync()
            await entitlementStore.refresh()
            switch entitlementStore.accessState {
            case .entitled: return true
            case .notEntitled: feedback = AppL10n.string("premium.restore.none")
            case .checking: feedback = AppL10n.string("premium.entitlement.checking")
            }
        } catch {
            if !Self.isCancellation(error) {
                feedback = AppL10n.string("premium.restore.failed")
                entitlementStore.recordPurchaseError(error)
            }
        }
        return false
    }

    /// 只接收 ID 与预期商品类型同时匹配的结果。
    private func installProducts(_ fetched: [Product]) {
        var catalogue: [PremiumPlan: Product] = [:]
        for plan in PremiumPlan.allCases {
            catalogue[plan] = fetched.first { $0.id == plan.productID && $0.type == plan.productType }
        }
        products = catalogue
        eligibleIntroOffers = []
        catalogueState = catalogue.isEmpty ? .unavailable : .available
    }

    /// 清理属于当前代次的加载任务，不影响已开始的新请求。
    private func finishLoading(generation: Int) {
        guard generation == loadGeneration else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        loadTask = nil
    }

    /// 按应用语言格式化订阅周期，并拒绝溢出或无法识别的周期。
    private static func periodDescription(_ period: Product.SubscriptionPeriod, count: Int = 1) -> String? {
        let (value, overflow) = period.value.multipliedReportingOverflow(by: count)
        guard !overflow, value > 0 else { return nil }
        var components = DateComponents()
        let formatter = DateComponentsFormatter()
        switch period.unit {
        case .day: components.day = value; formatter.allowedUnits = [.day]
        case .week: components.weekOfMonth = value; formatter.allowedUnits = [.weekOfMonth]
        case .month: components.month = value; formatter.allowedUnits = [.month]
        case .year: components.year = value; formatter.allowedUnits = [.year]
        default: return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        // Storefront currency comes from StoreKit, but duration wording follows the app language.
        calendar.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        return formatter.string(from: components)
    }

    /// 识别系统与网络取消，避免把用户取消显示为购买失败。
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let error = error as? StoreKitError, case .userCancelled = error { return true }
        if let error = error as? SKError, error.code == .paymentCancelled { return true }
        return (error as? URLError)?.code == .cancelled
    }
}
