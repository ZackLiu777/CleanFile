import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import CleanMyIPhone

@Suite("Premium status failure", .serialized)
@MainActor
struct PremiumStatusFailureTests {
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
    }
}
