import Combine
import StoreKit
import OSLog

@MainActor
final class PremiumEntitlementStore: ObservableObject {
    enum AccessState: Equatable {
        case checking
        case entitled
        case notEntitled
    }

    @Published private(set) var accessState: AccessState = .checking

    private var updatesTask: Task<Void, Never>?
    private var hasStarted = false
    /// Prevents an entitlement refresh started before a verified transaction
    /// from overwriting the newer purchase result when it completes later.
    private var entitlementRevision = 0
    private static let logger = Logger(subsystem: "ZaneLiao.CleanPhone", category: "Premium")

    deinit {
        updatesTask?.cancel()
    }

    func start() async {
        guard !hasStarted else {
            await refresh()
            return
        }
        hasStarted = true
        listenForTransactionUpdates()
        await finishDeliveredTransactions()
        await refresh()
    }

    func refresh() async {
        entitlementRevision &+= 1
        let revisionAtStart = entitlementRevision

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  isActivePremiumTransaction(transaction) else {
                continue
            }
            guard revisionAtStart == entitlementRevision, !Task.isCancelled else { return }
            accessState = .entitled
            return
        }

        // Query the product directly too: a purchase callback and enumeration
        // can straddle a StoreKit update. Only verified, unrevoked ownership counts.
        for productID in PremiumConfiguration.productIDs.sorted() {
            let result = await Transaction.latest(for: productID)
            guard revisionAtStart == entitlementRevision, !Task.isCancelled else { return }
            guard let result, case .verified(let transaction) = result else { continue }
            let isActive = isActivePremiumTransaction(transaction)
            Self.logger.debug("Latest entitlement: product=\(productID, privacy: .public) active=\(isActive) revoked=\(transaction.revocationDate != nil) upgraded=\(transaction.isUpgraded)")
            guard isActive else { continue }
            accessState = .entitled
            return
        }

        // Subscription status is also queried because Xcode StoreKit testing can
        // surface an existing subscription without replaying a transaction update.
        if await hasActiveSubscriptionStatus() {
            guard revisionAtStart == entitlementRevision, !Task.isCancelled else { return }
            accessState = .entitled
            return
        }

        guard revisionAtStart == entitlementRevision, !Task.isCancelled else { return }
        accessState = .notEntitled
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
            accessState = .entitled
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

    private func listenForTransactionUpdates() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                guard case .verified(let transaction) = result,
                      PremiumConfiguration.productIDs.contains(transaction.productID) else {
                    continue
                }

                if self?.isActivePremiumTransaction(transaction) == true {
                    self?.entitlementRevision &+= 1
                    self?.accessState = .entitled
                } else {
                    self?.entitlementRevision &+= 1
                    await self?.refresh()
                }
                await transaction.finish()
            }
        }
    }

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

    private func hasActiveSubscriptionStatus() async -> Bool {
        guard let groupID = PremiumConfiguration.subscriptionGroupID,
              let statuses = try? await Product.SubscriptionInfo.status(for: groupID) else {
            return false
        }

        return statuses.contains { status in
            guard status.state == .subscribed || status.state == .inGracePeriod,
                  case .verified(let transaction) = status.transaction else {
                return false
            }
            // Grace-period access remains valid past the transaction expiration.
            return PremiumConfiguration.subscriptionProductIDs.contains(transaction.productID)
                && transaction.revocationDate == nil && !transaction.isUpgraded
        }
    }

    private func isActivePremiumTransaction(_ transaction: Transaction) -> Bool {
        guard PremiumConfiguration.productIDs.contains(transaction.productID),
              transaction.revocationDate == nil, !transaction.isUpgraded else {
            return false
        }
        if transaction.productID == PremiumConfiguration.lifetimeProductID {
            return transaction.productType == .nonConsumable
        }
        return transaction.productType == .autoRenewable
            && (transaction.expirationDate.map { $0 > Date() } ?? false)
    }

    func recordPurchaseError(_ error: Error) {
        let error = error as NSError
        Self.logger.error("Purchase failed: domain=\(error.domain, privacy: .public) code=\(error.code)")
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            Self.logger.error("Underlying purchase error: domain=\(underlying.domain, privacy: .public) code=\(underlying.code)")
        }
    }
}
