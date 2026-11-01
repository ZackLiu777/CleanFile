//
//  高级购买目录状态
//
//  覆盖商品目录不可用、并发查询和过期请求结果的处理。
//  使用可控异步替身，验证权益未解析时不启动购买。
//  验证空目录、离线价格和试用资格不会被虚构，重试不能被旧结果覆盖。
//  查询替身可暂停并按指定顺序完成，不发起真实商店购买。
//

import Foundation
import StoreKit
import Testing
@testable import CleanMyIPhone

/// 验证购买目录的异步加载、取消和权益前置条件。
@Suite("Custom Premium paywall")
@MainActor
struct PremiumPurchaseViewModelTests {
    /// 核对月订、年订及终身方案继续对应既有商品标识和 StoreKit 类型。
    @Test("Custom plans preserve all existing App Store product identifiers")
    func plansPreservePurchaseIdentity() {
        #expect(PremiumPlan.annual.productID == "LZQ777")
        #expect(PremiumPlan.monthly.productID == "LLL777")
        #expect(PremiumPlan.lifetime.productID == "filecleaner.lifetime")
        #expect(Set(PremiumPlan.allCases.map(\.productID)) == PremiumConfiguration.productIDs)
        #expect(PremiumPlan.annual.productType == .autoRenewable)
        #expect(PremiumPlan.monthly.productType == .autoRenewable)
        #expect(PremiumPlan.lifetime.productType == .nonConsumable)
    }

    /// 离线时不虚构价格或试用资格，避免误导购买决定。
    @Test("Offline catalogue never invents prices or free-trial eligibility")
    func offlineCatalogueDoesNotInventPurchaseData() async {
        let model = PremiumPurchaseViewModel(productLookup: { throw URLError(.notConnectedToInternet) })
        await model.loadProducts().value
        #expect(model.catalogueState == .unavailable)
        #expect(model.products.isEmpty)
        #expect(model.eligibleIntroOffers.isEmpty)
        #expect(model.activity == .idle)
        for plan in PremiumPlan.allCases {
            #expect(!plan.title.isEmpty)
            #expect(model.priceDescription(for: plan) == nil)
            #expect(model.offerDescription(for: plan) == nil)
        }
    }

    /// 商店返回空列表时显示不可用状态，仍可选择方案但没有可购买商品。
    @Test("An empty product response is an unavailable catalogue, not a blank page")
    func emptyCatalogueIsUnavailable() async {
        let model = PremiumPurchaseViewModel(productLookup: { [] })
        await model.loadProducts().value
        #expect(model.catalogueState == .unavailable)
        #expect(PremiumPlan.allCases.count == 3)
        model.selectedPlan = .lifetime
        #expect(model.selectedPlan == .lifetime)
        #expect(model.selectedProduct == nil)
    }

    /// 并发目录请求共享一次查询，避免重复访问商店。
    @Test("Overlapping catalogue requests share one lookup")
    func catalogueRequestsAreCoalesced() async {
        let probe = SuspendedPremiumCatalogue()
        let model = PremiumPurchaseViewModel(productLookup: { await probe.lookup() })
        let first = model.loadProducts()
        await probe.waitForLookup(1)
        let second = model.loadProducts()
        #expect(probe.callCount == 1)
        probe.finishLookup(1)
        await first.value
        await second.value
        #expect(model.catalogueState == .unavailable)
    }

    /// 已取消的旧请求即使晚返回，也不能覆盖或结束当前重试。
    @Test("An old cancelled request cannot replace or finish the current request")
    func staleCatalogueCannotOverwriteRetry() async {
        let probe = SuspendedPremiumCatalogue()
        let model = PremiumPurchaseViewModel(productLookup: { await probe.lookup() })
        let first = model.loadProducts()
        await probe.waitForLookup(1)
        model.cancelProductLoading()
        #expect(model.catalogueState == .idle)
        let second = model.loadProducts()
        await probe.waitForLookup(2)
        probe.finishLookup(1)
        await first.value
        #expect(model.catalogueState == .loading)
        probe.finishLookup(2)
        await second.value
        #expect(probe.callCount == 2)
        #expect(model.catalogueState == .unavailable)
    }

    /// 权益状态尚未解析时不发起购买。
    @Test("An unresolved entitlement must not start a purchase")
    func unresolvedEntitlementDoesNotStartPurchase() async {
        let model = PremiumPurchaseViewModel(productLookup: { [] })
        let store = PremiumEntitlementStore()
        #expect(store.accessState == .checking)
        #expect(await model.purchase(using: store) == false)
        #expect(model.activity == .idle)
        #expect(model.feedback == nil)
    }
}

/// 可暂停目录查询以构造并发请求和过期回调。
@MainActor
private final class SuspendedPremiumCatalogue {
    private(set) var callCount = 0
    private var pending: [Int: CheckedContinuation<[Product], Never>] = [:]
    private var entered: [Int: CheckedContinuation<Void, Never>] = [:]

    /// 记录查询序号并挂起返回值，让测试控制每次查询的完成顺序。
    func lookup() async -> [Product] {
        callCount += 1
        let request = callCount
        entered.removeValue(forKey: request)?.resume()
        return await withCheckedContinuation { pending[request] = $0 }
    }

    /// 等待指定序号的查询进入替身，已进入时立即返回。
    func waitForLookup(_ request: Int) async {
        if callCount >= request { return }
        await withCheckedContinuation { entered[request] = $0 }
    }

    /// 以空目录完成指定查询，以模拟迟到结果或重试完成。
    func finishLookup(_ request: Int) {
        pending.removeValue(forKey: request)?.resume(returning: [])
    }
}
