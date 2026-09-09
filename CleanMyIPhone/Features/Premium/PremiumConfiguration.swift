import Foundation

/// App Store Connect identifiers used by both the subscription store and entitlement verification.
enum PremiumConfiguration {
    static let purchasesEnabled = true
    static let subscriptionGroupID: String? = "22356442"
    static let annualProductID = "LZQ777"
    static let monthlyProductID = "LLL777"
    static let lifetimeProductID = "filecleaner.lifetime"
    static let subscriptionProductIDs: Set<String> = [annualProductID, monthlyProductID]
    static let productIDs: Set<String> = subscriptionProductIDs.union([lifetimeProductID])
    static let privacyPolicyURL = URL(string: "https://zane-liao.github.io/cleanmyiphone/privacy/")!
    static let termsOfServiceURL = URL(string: "https://zane-liao.github.io/cleanmyiphone/terms/")!

    /// UI automation exercises app features rather than the App Store purchase sheet.
    static var bypassesEntitlementForUITesting: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--ui-test") }
#else
        false
#endif
    }
}
