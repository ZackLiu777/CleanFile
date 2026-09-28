import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import CleanMyIPhone

@Suite("Premium status failure", .serialized)
@MainActor
struct PremiumStatusFailureTests {
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
    }

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
}

@MainActor
private final class SuspendedStatusLookup {
    private(set) var callCount = 0
    private var released = false
    private var pending: [CheckedContinuation<[Product.SubscriptionInfo.Status], Error>] = []
    private var entered: CheckedContinuation<Void, Never>?

    func lookup() async throws -> [Product.SubscriptionInfo.Status] {
        callCount += 1
        entered?.resume()
        entered = nil
        if released { throw URLError(.notConnectedToInternet) }
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }

    func waitForLookup() async {
        if callCount > 0 { return }
        await withCheckedContinuation { entered = $0 }
    }

    func failPendingLookups() {
        released = true
        let continuations = pending
        pending = []
        continuations.forEach { $0.resume(throwing: URLError(.notConnectedToInternet)) }
    }
}
