import Foundation
import StoreKit
import Testing
@testable import CleanMyIPhone

@Suite("Custom Premium paywall")
@MainActor
struct PremiumPurchaseViewModelTests {
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

@MainActor
private final class SuspendedPremiumCatalogue {
    private(set) var callCount = 0
    private var pending: [Int: CheckedContinuation<[Product], Never>] = [:]
    private var entered: [Int: CheckedContinuation<Void, Never>] = [:]

    func lookup() async -> [Product] {
        callCount += 1
        let request = callCount
        entered.removeValue(forKey: request)?.resume()
        return await withCheckedContinuation { pending[request] = $0 }
    }

    func waitForLookup(_ request: Int) async {
        if callCount >= request { return }
        await withCheckedContinuation { entered[request] = $0 }
    }

    func finishLookup(_ request: Int) {
        pending.removeValue(forKey: request)?.resume(returning: [])
    }
}
