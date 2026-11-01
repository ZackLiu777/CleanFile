// Premium 权益的 StoreKit 数据入口。
// 启动与前台刷新合并查询，分别处理已验证交易、无法验证和确认无权益。
// 已验证的撤销按交易身份处理；其他有效商品与订阅宽限期仍可授予访问。
// 该对象只维护本次运行的状态，购买记录由 StoreKit 管理。
import Combine
import StoreKit
import OSLog

@MainActor
/// 协调 StoreKit 交易监听和权益刷新，向界面发布当前访问状态。
final class PremiumEntitlementStore: ObservableObject {
    /// 应用自身的启动联网探测结果，与交易签名验证结果相互独立。
    enum StartupConnectivity: Equatable {
        case pending
        case available
        case unavailable
    }

    /// 未完成核验、已确认有权益、已确认无权益三种界面状态。
    enum AccessState: Equatable {
        case checking
        case entitled
        case notEntitled
    }

    @Published private(set) var accessState: AccessState = .checking
    @Published private(set) var startupConnectivity: StartupConnectivity = .pending
    @Published private(set) var verificationUnavailable = false

    private var updatesTask: Task<Void, Never>?
    private var connectivityTask: Task<Void, Never>?
    private var unfinishedTransactionsTask: Task<Void, Never>?
    private var startupTimeoutTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var hasStarted = false
    private let subscriptionStatusLookup: @MainActor (String) async throws -> [Product.SubscriptionInfo.Status]
    /// Prevents an entitlement refresh started before a verified transaction
    /// from overwriting the newer purchase result when it completes later.
    private var entitlementRevision = 0
    private var grantedTransaction: Transaction?
    private var revokedTransactionIDs: Set<UInt64> = []
    private static let logger = Logger(subsystem: "ZaneLiao.CleanPhone", category: "Premium")

    /// 注入订阅状态查询；默认通过 StoreKit 读取真实订阅状态。
    init(
        subscriptionStatusLookup: @escaping @MainActor (String) async throws -> [Product.SubscriptionInfo.Status] = {
            try await Product.SubscriptionInfo.status(for: $0)
        }
    ) {
        self.subscriptionStatusLookup = subscriptionStatusLookup
    }

    deinit {
        updatesTask?.cancel()
        connectivityTask?.cancel()
        unfinishedTransactionsTask?.cancel()
        startupTimeoutTask?.cancel()
        refreshTask?.cancel()
    }

    /// 首次启动监听与后台清理；后续调用只刷新权益。
    func start() async {
        guard !hasStarted else {
            await refresh()
            return
        }
        hasStarted = true
        listenForTransactionUpdates()
        // Neither a cellular-data probe nor unfinished-transaction cleanup may hold
        // the first entitlement check behind network-dependent work.
        connectivityTask = Task { [weak self] in
            _ = await self?.refreshStartupConnectivity()
        }
        unfinishedTransactionsTask = Task { [weak self] in
            await self?.finishDeliveredTransactions()
        }
        startupTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.markStartupVerificationDelayed()
        }
        await refresh()
    }

    /// A slow StoreKit response is not proof that an existing subscription expired.
    /// Stop displaying an indefinite spinner while verification continues in the background.
    func markStartupVerificationDelayed() {
        guard accessState == .checking else { return }
        verificationUnavailable = true
    }

    /// A normal app-owned request is required for iOS to present its cellular-data
    /// choice. StoreKit traffic is system-owned and may not trigger that prompt.
    @discardableResult
    func refreshStartupConnectivity() async -> Bool {
        var request = URLRequest(url: URL(string: "https://www.apple.com/library/test/success.html")!)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 6

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<400).contains(response.statusCode) else {
                startupConnectivity = .unavailable
                return false
            }
            startupConnectivity = .available
            return true
        } catch {
            startupConnectivity = .unavailable
            return false
        }
    }

    /// 合并并发刷新；查询期间收到新交易时以新的版本重新计算。
    func refresh() async {
        // Launch, scene activation, and unfinished transactions share one lookup.
        // Only a transaction event invalidates its result, not another caller.
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            defer { refreshTask = nil }
            repeat {
                let revision = entitlementRevision
                await refreshEntitlements(revisionAtStart: revision)
                if revision == entitlementRevision { break }
                // A purchase/revocation arrived while the lookup was suspended.
                // Re-evaluate instead of losing that event to a stale in-flight call.
            } while !Task.isCancelled
        }
        refreshTask = task
        await task.value
    }

    /// 优先使用当前权益，再检查最新交易及订阅状态；未知结果不视为到期。
    private func refreshEntitlements(revisionAtStart: Int) async {

        var sawUnverifiedTransaction = false
        for await result in Transaction.currentEntitlements {
            if case .unverified = result { sawUnverifiedTransaction = true }
            guard case .verified(let transaction) = result,
                  isCurrentPremiumEntitlement(transaction) else {
                continue
            }
            guard revisionAtStart == entitlementRevision, !Task.isCancelled else { return }
            grantAccess(for: transaction)
            return
        }

        // Query the product directly too: a purchase callback and enumeration
        // can straddle a StoreKit update. Only verified, unrevoked ownership counts.
        for productID in PremiumConfiguration.productIDs.sorted() {
            let result = await Transaction.latest(for: productID)
            guard revisionAtStart == entitlementRevision, !Task.isCancelled else { return }
            guard let result else { continue }
            if case .unverified = result { sawUnverifiedTransaction = true }
            guard case .verified(let transaction) = result else { continue }
            invalidateAccessIfNeeded(for: transaction)
            let isActive = isActivePremiumTransaction(transaction)
            Self.logger.debug("Latest entitlement: product=\(productID, privacy: .public) active=\(isActive) revoked=\(transaction.revocationDate != nil) upgraded=\(transaction.isUpgraded)")
            guard isActive else { continue }
            grantAccess(for: transaction)
            return
        }

        // Subscription status is also queried because Xcode StoreKit testing can
        // surface an existing subscription without replaying a transaction update.
        let subscriptionStatus = await hasActiveSubscriptionStatus(revisionAtStart: revisionAtStart)
        if subscriptionStatus.active == true {
            guard revisionAtStart == entitlementRevision, !Task.isCancelled else { return }
            verificationUnavailable = false
            accessState = .entitled
            startupTimeoutTask?.cancel()
            return
        }

        guard revisionAtStart == entitlementRevision, !Task.isCancelled else { return }
        let statusIsUnknown = subscriptionStatus.active == nil || sawUnverifiedTransaction
        verificationUnavailable = statusIsUnknown
        // A failed StoreKit lookup is not evidence that a purchase expired.
        // Keep existing access, or keep checking on a fresh installation.
        if !statusIsUnknown {
            accessState = .notEntitled
            startupTimeoutTask?.cancel()
        } else if sawUnverifiedTransaction || subscriptionStatus.verificationFailed || accessState != .entitled {
            accessState = .checking
        }
    }

    /// Returns true only when StoreKit delivered a verified Premium transaction.
    /// Callers use the result to close an already-entitled paywall as well as a
    /// paywall whose entitlement state changes during this purchase.
    @discardableResult
    func handlePurchaseResult(_ result: Product.PurchaseResult) async -> Bool {
        switch result {
        case .success(let verificationResult):
            guard case .verified(let transaction) = verificationResult,
                  isActivePremiumTransaction(transaction) else {
                await refresh()
                return false
            }

            // Access is delivered before finishing, as required by StoreKit.
            entitlementRevision &+= 1
            grantAccess(for: transaction)
            await transaction.finish()
            return true
        case .pending, .userCancelled:
            await refresh()
            return false
        @unknown default:
            await refresh()
            return false
        }
    }

    /// 消费 StoreKit 投递的已验证交易，并在处理后结束该交易。
    private func listenForTransactionUpdates() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                guard case .verified(let transaction) = result,
                      PremiumConfiguration.productIDs.contains(transaction.productID) else {
                    continue
                }

                await self?.handleVerifiedTransactionUpdate(transaction)
                await transaction.finish()
            }
        }
    }

    /// 对启动时遗留的交易重新核验；确认已提供权益后才结束交易。
    private func finishDeliveredTransactions() async {
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result,
                  PremiumConfiguration.productIDs.contains(transaction.productID) else {
                continue
            }
            await refresh()
            if accessState == .entitled {
                await transaction.finish()
            }
        }
    }

    /// 查询订阅组；nil 表示不可确定，独立标记签名验证失败。
    private func hasActiveSubscriptionStatus(revisionAtStart: Int) async -> (active: Bool?, verificationFailed: Bool) {
        guard let groupID = PremiumConfiguration.subscriptionGroupID else { return (false, false) }
        guard let statuses = try? await subscriptionStatusLookup(groupID) else { return (nil, false) }
        guard revisionAtStart == entitlementRevision, !Task.isCancelled else { return (nil, false) }

        var hasUnverifiedStatus = false
        for status in statuses {
            guard case .verified(let transaction) = status.transaction else {
                hasUnverifiedStatus = true
                continue
            }
            guard PremiumConfiguration.subscriptionProductIDs.contains(transaction.productID) else { continue }
            if Self.subscriptionStatusEvidence(state: status.state, transaction: status.transaction) == true,
               !revokedTransactionIDs.contains(transaction.id) {
                grantedTransaction = transaction
                return (true, false)
            }
        }
        return (hasUnverifiedStatus ? nil : false, hasUnverifiedStatus)
    }

    /// Unknown verification is neither a new entitlement nor evidence of expiration.
    static func subscriptionStatusEvidence(
        state: Product.SubscriptionInfo.RenewalState,
        transaction result: VerificationResult<Transaction>
    ) -> Bool? {
        guard case .verified(let transaction) = result else { return nil }
        return (state == .subscribed || state == .inGracePeriod)
            && PremiumConfiguration.subscriptionProductIDs.contains(transaction.productID)
            && transaction.productType == .autoRenewable
            && transaction.revocationDate == nil && !transaction.isUpgraded
    }

    /// 保存授予访问的交易身份，以便后续撤销只影响相应权益。
    private func grantAccess(for transaction: Transaction) {
        grantedTransaction = transaction
        verificationUnavailable = false
        accessState = .entitled
        startupTimeoutTask?.cancel()
    }

    /// 收到同一交易或同商品更新交易的失效证据时，停止沿用旧权益。
    private func invalidateAccessIfNeeded(for transaction: Transaction) {
        if transaction.revocationDate != nil || transaction.isUpgraded {
            // A stale enumeration must not resurrect this exact revoked transaction.
            revokedTransactionIDs.insert(transaction.id)
        }
        guard !isActivePremiumTransaction(transaction), let grantedTransaction,
              grantedTransaction.productID == transaction.productID,
              (grantedTransaction.id == transaction.id || transaction.purchaseDate > grantedTransaction.purchaseDate) else { return }
        self.grantedTransaction = nil
        accessState = .checking
    }

    /// 应用已验证的交易更新；无效交易触发全部商品的重新核验。
    func handleVerifiedTransactionUpdate(_ transaction: Transaction) async {
        guard PremiumConfiguration.productIDs.contains(transaction.productID) else { return }
        entitlementRevision &+= 1
        invalidateAccessIfNeeded(for: transaction)
        if isActivePremiumTransaction(transaction) {
            grantAccess(for: transaction)
        } else {
            // Re-resolve all products: another subscription or lifetime purchase may remain valid.
            await refresh()
        }
    }

    /// 判断普通交易是否仍在有效期；终身商品无需到期时间。
    private func isActivePremiumTransaction(_ transaction: Transaction) -> Bool {
        guard PremiumConfiguration.productIDs.contains(transaction.productID),
              transaction.revocationDate == nil, !transaction.isUpgraded,
              !revokedTransactionIDs.contains(transaction.id) else {
            return false
        }
        if transaction.productID == PremiumConfiguration.lifetimeProductID {
            return transaction.productType == .nonConsumable
        }
        return transaction.productType == .autoRenewable
            && (transaction.expirationDate.map { $0 > Date() } ?? false)
    }

    /// 判断 StoreKit 当前权益；订阅宽限期不按原交易到期时间排除。
    private func isCurrentPremiumEntitlement(_ transaction: Transaction) -> Bool {
        guard PremiumConfiguration.productIDs.contains(transaction.productID),
              transaction.revocationDate == nil, !transaction.isUpgraded,
              !revokedTransactionIDs.contains(transaction.id) else { return false }
        if transaction.productID == PremiumConfiguration.lifetimeProductID {
            return transaction.productType == .nonConsumable
        }
        // StoreKit includes both subscribed and in-grace-period subscriptions
        // in currentEntitlements, even if the original transaction has expired.
        return transaction.productType == .autoRenewable
    }

    /// 仅记录错误域和代码，不记录交易内容或用户文件。
    func recordPurchaseError(_ error: Error) {
        let error = error as NSError
        Self.logger.error("Purchase failed: domain=\(error.domain, privacy: .public) code=\(error.code)")
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            Self.logger.error("Underlying purchase error: domain=\(underlying.domain, privacy: .public) code=\(underlying.code)")
        }
    }
}
