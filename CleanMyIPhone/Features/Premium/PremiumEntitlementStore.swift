import Combine
import StoreKit

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
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  isActivePremiumTransaction(transaction) else {
                continue
            }
            accessState = .entitled
            return
        }

        // Subscription status is also queried because Xcode StoreKit testing can
        // surface an existing subscription without replaying a transaction update.
        if await hasActiveSubscriptionStatus() {
            accessState = .entitled
            return
        }

        accessState = .notEntitled
    }

    func handlePurchaseResult(_ result: Product.PurchaseResult) async {
        switch result {
        case .success(let verificationResult):
            guard case .verified(let transaction) = verificationResult,
                  PremiumConfiguration.productIDs.contains(transaction.productID) else {
                await refresh()
                return
            }

            // Access is delivered before finishing, as required by StoreKit.
            accessState = .entitled
            await transaction.finish()
        case .pending, .userCancelled:
            await refresh()
        @unknown default:
            await refresh()
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
                    self?.accessState = .entitled
                } else {
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
            return isActivePremiumTransaction(transaction)
        }
    }

    private func isActivePremiumTransaction(_ transaction: Transaction) -> Bool {
        guard PremiumConfiguration.productIDs.contains(transaction.productID),
              transaction.revocationDate == nil else {
            return false
        }
        return transaction.expirationDate.map { $0 > Date() } ?? true
    }
}
