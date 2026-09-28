import Combine
import StoreKit
import OSLog

@MainActor
final class PremiumEntitlementStore: ObservableObject {
    enum StartupConnectivity: Equatable {
        case pending
        case available
        case unavailable
    }

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
    private static let logger = Logger(subsystem: "ZaneLiao.CleanPhone", category: "Premium")

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

    private func refreshEntitlements(revisionAtStart: Int) async {

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  isCurrentPremiumEntitlement(transaction) else {
                continue
            }
            guard revisionAtStart == entitlementRevision, !Task.isCancelled else { return }
            verificationUnavailable = false
            accessState = .entitled
            startupTimeoutTask?.cancel()
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
            verificationUnavailable = false
            accessState = .entitled
            startupTimeoutTask?.cancel()
            return
        }

        // Subscription status is also queried because Xcode StoreKit testing can
        // surface an existing subscription without replaying a transaction update.
        let subscriptionStatus = await hasActiveSubscriptionStatus()
        if subscriptionStatus == true {
            guard revisionAtStart == entitlementRevision, !Task.isCancelled else { return }
            verificationUnavailable = false
            accessState = .entitled
            startupTimeoutTask?.cancel()
            return
        }

        guard revisionAtStart == entitlementRevision, !Task.isCancelled else { return }
        verificationUnavailable = subscriptionStatus == nil
        // A failed StoreKit lookup is not evidence that a purchase expired.
        // Keep existing access, or keep checking on a fresh installation.
        if subscriptionStatus == false {
            accessState = .notEntitled
            startupTimeoutTask?.cancel()
        } else if accessState != .entitled {
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
            verificationUnavailable = false
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
                    self?.verificationUnavailable = false
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

    private func hasActiveSubscriptionStatus() async -> Bool? {
        guard let groupID = PremiumConfiguration.subscriptionGroupID else { return false }
        guard let statuses = try? await subscriptionStatusLookup(groupID) else { return nil }

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

    private func isCurrentPremiumEntitlement(_ transaction: Transaction) -> Bool {
        guard PremiumConfiguration.productIDs.contains(transaction.productID),
              transaction.revocationDate == nil, !transaction.isUpgraded else { return false }
        if transaction.productID == PremiumConfiguration.lifetimeProductID {
            return transaction.productType == .nonConsumable
        }
        // StoreKit includes both subscribed and in-grace-period subscriptions
        // in currentEntitlements, even if the original transaction has expired.
        return transaction.productType == .autoRenewable
    }

    func recordPurchaseError(_ error: Error) {
        let error = error as NSError
        Self.logger.error("Purchase failed: domain=\(error.domain, privacy: .public) code=\(error.code)")
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            Self.logger.error("Underlying purchase error: domain=\(underlying.domain, privacy: .public) code=\(underlying.code)")
        }
    }
}
