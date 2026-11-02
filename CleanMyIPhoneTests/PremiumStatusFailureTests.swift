// 高级权益、商店状态失败与购买界面的契约测试。
//
// 使用 StoreKit 测试会话构造试用、已有交易和撤销等场景，验证网络或状态查询
// 失败时不会凭空授予或丢失权益，并检查购买页使用真实商品与试用资格。
// 用例串行执行，并在会话结束时恢复测试商店状态，避免交易相互干扰。

import Foundation
import ImageFormatConversionKit
import StoreKit
import StoreKitTest
import Testing
@testable import CleanMyIPhone

/// 验证权益来源、查询失败和购买流程交汇处的状态转换。
@Suite("Premium status failure", .serialized)
@MainActor
struct PremiumStatusFailureTests {
    /// 已验证的有效试用应在状态查询失败时继续提供高级功能访问。
    @Test("Existing seven-day introductory trials unlock all premium features", arguments: ["LLL777", "LZQ777"])
    func activeSevenDayTrial(productID: String) async throws {
        let session = try SKTestSession(configurationFileNamed: "File Cleaner & Media Converter")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer {
            session.clearTransactions()
            session.resetToDefaultState()
        }
        _ = try await buyVisibleEntitlement(productID, in: session)
        let result = try #require(await Transaction.latest(for: productID))
        guard case .verified(let transaction) = result else {
            Issue.record("The introductory trial must be verified")
            return
        }
        #expect(transaction.offer?.type == .introductory)
        #expect(transaction.offer?.paymentMode == .freeTrial)
        let store = PremiumEntitlementStore(subscriptionStatusLookup: { _ in
            throw URLError(.notConnectedToInternet)
        })
        await store.refresh()
        #expect(store.accessState == .entitled)
        let access = PremiumFeatureAccessStore(accessState: store.accessState)
        for feature in PremiumFeature.allCases { #expect(access.allows(feature)) }
    }

    /// 确认试用到期后锁定付费功能，同时保留既有免费入口。
    @Test("Only a confirmed expired trial locks paid features, leaving media and video free", arguments: ["LLL777", "LZQ777"])
    func expiredSevenDayTrial(productID: String) async throws {
        let session = try SKTestSession(configurationFileNamed: "File Cleaner & Media Converter")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer {
            session.clearTransactions()
            session.resetToDefaultState()
        }
        _ = try await buyVisibleEntitlement(productID, in: session)
        let store = PremiumEntitlementStore()
        await store.refresh()
        try #require(store.accessState == .entitled)
        let access = PremiumFeatureAccessStore(accessState: store.accessState)
        for feature in PremiumFeature.allCases { #expect(access.allows(feature)) }

        // A backdated, non-renewing trial supplies a signed expired receipt without changing the device clock.
        // Forced expiration intermittently leaves StoreKit's status subscribed in this simulator runtime.
        session.clearTransactions()
        let expiredPurchase = try await session.buyProduct(identifier: productID, options: [
            .purchaseDate(Date().addingTimeInterval(-8 * 24 * 60 * 60), renewalBehavior: .cancelImmediately)
        ])
        await expiredPurchase.finish()
        let groupID = try #require(PremiumConfiguration.subscriptionGroupID)
        // Assert the fixture is expired before checking the app, rather than confusing StoreKit cache delay with access logic.
        var expiredStatuses: [Product.SubscriptionInfo.Status] = []
        for _ in 0..<100 {
            expiredStatuses = try await Product.SubscriptionInfo.status(for: groupID)
            if expiredStatuses.contains(where: { $0.state == .expired }),
               !expiredStatuses.contains(where: { $0.state == .subscribed || $0.state == .inGracePeriod }) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let confirmedExpired = expiredStatuses.contains { $0.state == .expired }
        try #require(confirmedExpired, "StoreKit must confirm trial expiration")
        let stillActive = expiredStatuses.contains { $0.state == .subscribed || $0.state == .inGracePeriod }
        #expect(!stillActive)
        let latest = try #require(await Transaction.latest(for: productID))
        guard case .verified(let expiredTransaction) = latest else {
            Issue.record("StoreKit must verify the expired trial")
            return
        }
        #expect(expiredTransaction.id == expiredPurchase.id)
        #expect(expiredTransaction.offer?.type == .introductory)
        #expect(expiredTransaction.offer?.paymentMode == .freeTrial)
        let expirationDate = try #require(expiredTransaction.expirationDate)
        #expect(expirationDate <= Date())
        await store.refresh()
        try #require(store.accessState == .notEntitled)
        access.update(store.accessState)
        for feature in PremiumFeature.allCases {
            #expect(access.allows(feature) == [.media, .videoConversion, .darkAppearance].contains(feature))
        }
    }

    /// 使用 StoreKit 测试商品核对方案标识、商品类型及展示价格。
    @Test("Custom paywall uses real prices for the same monthly, annual, and lifetime products")
    func customPaywallUsesExistingProducts() async throws {
        let session = try SKTestSession(configurationFileNamed: "File Cleaner & Media Converter")
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let products = try await Product.products(for: PremiumConfiguration.productIDs.sorted())
        #expect(Set(products.map(\.id)) == PremiumConfiguration.productIDs)
        let model = PremiumPurchaseViewModel(productLookup: { products }, introEligibility: { _ in false })
        await model.loadProducts().value
        #expect(model.catalogueState == .available)
        for plan in PremiumPlan.allCases {
            let product = try #require(model.products[plan])
            #expect(product.id == plan.productID)
            #expect(product.type == plan.productType)
            let price = try #require(model.priceDescription(for: plan))
            #expect(price.contains(product.displayPrice))
            #expect(model.offerDescription(for: plan) == nil)
        }
    }

    /// 只有具备资格的订阅显示免费试用，终身商品和无资格方案不显示。
    @Test("Trial wording is shown only for a confirmed eligible free introductory offer")
    func customPaywallChecksTrialEligibility() async throws {
        let session = try SKTestSession(configurationFileNamed: "File Cleaner & Media Converter")
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let products = try await Product.products(for: PremiumConfiguration.productIDs.sorted())
        let eligible = PremiumPurchaseViewModel(productLookup: { products }, introEligibility: { _ in true })
        await eligible.loadProducts().value
        for plan in [PremiumPlan.annual, .monthly] {
            let product = try #require(eligible.products[plan])
            #expect(product.subscription?.introductoryOffer?.paymentMode == .freeTrial)
            let offer = try #require(eligible.offerDescription(for: plan))
            #expect(offer.contains(product.displayPrice))
        }
        #expect(eligible.offerDescription(for: .lifetime) == nil)
        let ineligible = PremiumPurchaseViewModel(productLookup: { products }, introEligibility: { _ in false })
        await ineligible.loadProducts().value
        #expect(ineligible.eligibleIntroOffers.isEmpty)
        #expect(ineligible.offerDescription(for: .annual) == nil)
        #expect(ineligible.offerDescription(for: .monthly) == nil)
    }

    /// 仅返回终身商品时目录仍可用，缺失订阅不应隐藏已有方案。
    @Test("A lifetime product remains available even if subscriptions are missing")
    func partialCatalogueDoesNotHideLifetime() async throws {
        let session = try SKTestSession(configurationFileNamed: "File Cleaner & Media Converter")
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let products = try await Product.products(for: [PremiumConfiguration.lifetimeProductID])
        try #require(products.count == 1)
        let model = PremiumPurchaseViewModel(productLookup: { products })
        await model.loadProducts().value
        model.selectedPlan = .lifetime
        #expect(model.catalogueState == .available)
        #expect(model.selectedProduct?.id == PremiumConfiguration.lifetimeProductID)
        #expect(model.priceDescription(for: .lifetime) != nil)
        #expect(model.priceDescription(for: .annual) == nil)
        #expect(model.offerDescription(for: .lifetime) == nil)
    }

    @Test("Opening the custom paywall does not invalidate an existing verified purchase", arguments: [
        "LLL777", "LZQ777", "filecleaner.lifetime"
    ])
    /// 已有已验证购买时，离线打开购买页不会撤销权益或创建新的购买身份。
    func customPaywallPreservesExistingAccess(productID: String) async throws {
        let session = try SKTestSession(configurationFileNamed: "File Cleaner & Media Converter")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer {
            session.clearTransactions()
            session.resetToDefaultState()
        }
        _ = try await buyVisibleEntitlement(productID, in: session)
        let store = PremiumEntitlementStore()
        await store.refresh()
        try #require(store.accessState == .entitled)
        let existingPurchases = Set(session.allTransactions().map(\.originalTransactionIdentifier))
        let model = PremiumPurchaseViewModel(productLookup: { throw URLError(.notConnectedToInternet) })
        await model.loadProducts().value
        #expect(await model.purchase(using: store))
        #expect(store.accessState == .entitled)
        #expect(model.activity == .idle)
        // Automatic renewals may add transactions, but must not create a new purchase identity.
        #expect(Set(session.allTransactions().map(\.originalTransactionIdentifier)) == existingPurchases)
    }

    @Test("Custom purchase delivers the same verified monthly, annual, and lifetime entitlements", arguments: [
        "LLL777", "LZQ777", "filecleaner.lifetime"
    ])
    /// 分别购买月订、年订和终身方案，检查实际商品与恢复后的权益一致。
    func customPurchaseDeliversOriginalEntitlement(productID: String) async throws {
        let session = try SKTestSession(configurationFileNamed: "File Cleaner & Media Converter")
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let products = try await Product.products(for: [productID])
        let plan = try #require(PremiumPlan.allCases.first { $0.productID == productID })
        let model = PremiumPurchaseViewModel(productLookup: { products }, introEligibility: { _ in false })
        await model.loadProducts().value
        model.selectedPlan = plan
        let store = PremiumEntitlementStore(subscriptionStatusLookup: { _ in [] })
        await store.refresh()
        try #require(store.accessState == .notEntitled)
        #expect(await model.purchase(using: store))
        #expect(store.accessState == .entitled)
        #expect(model.activity == .idle)
        #expect(model.feedback == nil)
        #expect(session.allTransactions().contains { $0.productIdentifier == productID })
    }

    /// 并发的启动和前台刷新应共享查询，避免重复请求及结果竞争。
    @Test("Overlapping startup and foreground refreshes share one StoreKit lookup")
    func overlappingRefreshesAreCoalesced() async throws {
        let session = try SKTestSession(configurationFileNamed: "File Cleaner & Media Converter")
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }

        let probe = SuspendedStatusLookup()
        let store = PremiumEntitlementStore(subscriptionStatusLookup: { _ in
            try await probe.lookup()
        })
        let first = Task { await store.refresh() }
        await probe.waitForLookup()
        var second: Task<Void, Never>?
        await withCheckedContinuation { started in
            second = Task { @MainActor in
                started.resume()
                await store.refresh()
            }
        }
        probe.failPendingLookups()
        await first.value
        await second?.value
        #expect(probe.callCount == 1)
        #expect(store.accessState == .checking)
        #expect(store.verificationUnavailable)
    }

    /// 模拟宽限期及状态查询离线，验证已确认的订阅权益仍保留。
    @Test("Grace-period subscriber remains entitled if status lookup fails")
    func gracePeriodWithStatusFailure() async throws {
        let session = try SKTestSession(configurationFileNamed: "File Cleaner & Media Converter")
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        session.billingGracePeriodIsEnabled = true
        session.shouldEnterBillingRetryOnRenewal = true

        _ = try await session.buyProduct(identifier: PremiumConfiguration.monthlyProductID)
        try session.forceRenewalOfSubscription(productIdentifier: PremiumConfiguration.monthlyProductID)

        let groupID = try #require(PremiumConfiguration.subscriptionGroupID)
        var isInGracePeriod = false
        for _ in 0..<20 {
            let statuses = try await Product.SubscriptionInfo.status(for: groupID)
            if statuses.contains(where: { $0.state == .inGracePeriod }) {
                isInGracePeriod = true
                break
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        try #require(isInGracePeriod, "The simulated subscription must be in grace period")

        let store = PremiumEntitlementStore(subscriptionStatusLookup: { _ in
            throw URLError(.notConnectedToInternet)
        })
        await store.refresh()

        #expect(store.accessState == .entitled)
        store.markStartupVerificationDelayed()
        #expect(store.accessState == .entitled)
        #expect(!store.verificationUnavailable)
        let access = PremiumFeatureAccessStore(accessState: store.accessState)
        for feature in PremiumFeature.allCases { #expect(access.allows(feature)) }
    }

    @Test("Existing monthly, annual trial, and lifetime transactions remain unlimited after relaunch", arguments: [
        PremiumConfiguration.monthlyProductID,
        PremiumConfiguration.annualProductID,
        PremiumConfiguration.lifetimeProductID
    ])
    /// 模拟重建权益存储并使状态查询失败，验证既有购买仍解锁功能和转换。
    func existingPurchaseKeepsUnlimitedAccess(productID: String) async throws {
        let session = try SKTestSession(configurationFileNamed: "File Cleaner & Media Converter")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer {
            session.clearTransactions()
            session.resetToDefaultState()
        }
        _ = try await buyVisibleEntitlement(productID, in: session)

        // Recreating the entitlement store represents an upgrade or reinstall with no app-local ownership flag.
        for _ in 0..<2 {
            let store = PremiumEntitlementStore(subscriptionStatusLookup: { _ in
                throw URLError(.notConnectedToInternet)
            })
            await store.refresh()
            #expect(store.accessState == .entitled)
            let access = PremiumFeatureAccessStore(accessState: store.accessState)
            for feature in PremiumFeature.allCases { #expect(access.allows(feature)) }
            for category in [ConversionUsageCategory.images, .video, .audio] {
                let permit = try #require(access.conversionPolicy.reserve(category, 1_000))
                permit.recordSuccess(1_000)
                permit.finish()
            }
        }
    }

    /// 既无可用查询结果也无本地交易时，不能将未知状态当作已确认无权益。
    @Test("Unavailable status and no local transaction keep verification pending")
    func unavailableStatusWithoutLocalTransaction() async throws {
        let session = try SKTestSession(configurationFileNamed: "File Cleaner & Media Converter")
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }

        var lookupWasCalled = false
        let store = PremiumEntitlementStore(subscriptionStatusLookup: { _ in
            lookupWasCalled = true
            throw URLError(.notConnectedToInternet)
        })
        await store.refresh()

        #expect(lookupWasCalled)
        #expect(store.accessState == .checking)
        store.markStartupVerificationDelayed()
        #expect(store.accessState == .checking)
        #expect(store.verificationUnavailable)
    }

    @Test("Region changes and removing app preferences do not replace paid ownership", arguments: [
        "LLL777", "LZQ777", "filecleaner.lifetime"
    ])
    /// 改变商店地区并清除应用偏好后，既有购买身份和权益仍可恢复。
    func paidOwnershipSurvivesRegionAndLocalDataChanges(productID: String) async throws {
        let session = try SKTestSession(configurationFileNamed: "File Cleaner & Media Converter")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer {
            session.clearTransactions()
            session.resetToDefaultState()
        }
        _ = try await buyVisibleEntitlement(productID, in: session)
        let identities = Set(session.allTransactions().map(\.originalTransactionIdentifier))
        let domain = "FilevraPaidReinstallTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        // Simulate the app-local data loss of reinstall, keeping the StoreKit account's transactions.
        defaults.set("old app preferences", forKey: "filevra.freeUsage.v1")
        defaults.removePersistentDomain(forName: domain)
        for (region, locale) in [("USA", "en_US"), ("CHN", "zh_CN"), ("DEU", "de_DE")] {
            session.storefront = region
            session.locale = Locale(identifier: locale)
            let store = PremiumEntitlementStore(subscriptionStatusLookup: { _ in
                throw URLError(.notConnectedToInternet)
            })
            await store.refresh()
            #expect(store.accessState == .entitled)
            let access = PremiumFeatureAccessStore(accessState: store.accessState)
            for feature in PremiumFeature.allCases { #expect(access.allows(feature)) }
            for category in [ConversionUsageCategory.images, .video, .audio] {
                let permit = try #require(access.conversionPolicy.reserve(category, 1_000))
                permit.recordSuccess(1_000)
                permit.finish()
            }
            // Selecting Premium again must dismiss instead of creating another purchase.
            let model = PremiumPurchaseViewModel(productLookup: { throw URLError(.notConnectedToInternet) })
            #expect(await model.purchase(using: store))
            #expect(Set(session.allTransactions().map(\.originalTransactionIdentifier)) == identities)
        }
    }

    /// 未验证交易在各续订状态下都不能作为确定的权益证据。
    @Test("Unverified subscription evidence is unknown, including inactive states")
    func unverifiedSubscriptionEvidence() async throws {
        let session = try SKTestSession(configurationFileNamed: "File Cleaner & Media Converter")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let transaction = try await buyVisibleEntitlement("LLL777", in: session)
        let unverified: VerificationResult<Transaction> = .unverified(transaction, .invalidSignature)
        for state: Product.SubscriptionInfo.RenewalState in [.subscribed, .inGracePeriod, .expired, .revoked] {
            #expect(PremiumEntitlementStore.subscriptionStatusEvidence(state: state, transaction: unverified) == nil)
        }
        #expect(PremiumEntitlementStore.subscriptionStatusEvidence(state: .subscribed, transaction: .verified(transaction)) == true)
        #expect(PremiumEntitlementStore.subscriptionStatusEvidence(state: .expired, transaction: .verified(transaction)) == false)
    }

    /// 已验证退款不能因为状态查询失败而继续保留对应权益；同时覆盖有无其他订阅。
    @Test("A verified refund cannot retain access when status lookup fails", arguments: [false, true])
    func refundedLifetimeWithUnavailableStatus(keepSubscription: Bool) async throws {
        let session = try SKTestSession(configurationFileNamed: "File Cleaner & Media Converter")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let lifetime = try await buyVisibleEntitlement(PremiumConfiguration.lifetimeProductID, in: session)
        let store = PremiumEntitlementStore(subscriptionStatusLookup: { _ in
            throw URLError(.notConnectedToInternet)
        })
        await store.refresh()
        try #require(store.accessState == .entitled)
        if keepSubscription { _ = try await buyVisibleEntitlement("LLL777", in: session) }
        try session.refundTransaction(identifier: #require(UInt(exactly: lifetime.id)))
        var revoked: Transaction?
        for _ in 0..<50 {
            if case .verified(let transaction) = await Transaction.latest(for: lifetime.productID),
               transaction.revocationDate != nil {
                revoked = transaction
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        let transaction = try #require(revoked)
        await store.handleVerifiedTransactionUpdate(transaction)
        #expect(store.accessState == (keepSubscription ? .entitled : .checking))
        #expect(store.verificationUnavailable == !keepSubscription)
        // Repeated refreshes cannot resurrect the revoked purchase from retained state.
        await store.refresh()
        #expect(store.accessState == (keepSubscription ? .entitled : .checking))
    }

    /// 创建并完成测试交易，等待其出现在已验证权益中，再模拟重启场景。
    private func buyVisibleEntitlement(_ productID: String, in session: SKTestSession) async throws -> Transaction {
        let purchased = try await session.buyProduct(identifier: productID)
        await purchased.finish()
        // These scenarios model existing owners at relaunch, not a new purchase callback before StoreKit's cache catches up.
        var isVisible = false
        for _ in 0..<50 {
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result, transaction.id == purchased.id {
                    isVisible = true
                    break
                }
            }
            if isVisible { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try #require(isVisible, "StoreKit must expose the new verified entitlement before simulating a relaunch")
        return purchased
    }
}

/// 可控暂停状态查询并集中注入离线错误，构造重叠刷新和失败时序。
@MainActor
private final class SuspendedStatusLookup {
    private(set) var callCount = 0
    private var released = false
    private var pending: [CheckedContinuation<[Product.SubscriptionInfo.Status], Error>] = []
    private var entered: CheckedContinuation<Void, Never>?

    /// 记录查询并暂停；释放后发起的查询直接返回模拟离线错误。
    func lookup() async throws -> [Product.SubscriptionInfo.Status] {
        callCount += 1
        entered?.resume()
        entered = nil
        if released { throw URLError(.notConnectedToInternet) }
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }

    /// 等待至少一次查询进入替身，避免以时间延迟猜测执行顺序。
    func waitForLookup() async {
        if callCount > 0 { return }
        await withCheckedContinuation { entered = $0 }
    }

    /// 标记释放并以离线错误恢复全部等待中的查询。
    func failPendingLookups() {
        released = true
        let continuations = pending
        pending = []
        continuations.forEach { $0.resume(throwing: URLError(.notConnectedToInternet)) }
    }
}
