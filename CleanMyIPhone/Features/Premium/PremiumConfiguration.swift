import Foundation

/// Keep purchasing unavailable until the subscription catalogue and entitlement delivery are ready.
enum PremiumConfiguration {
    static let purchasesEnabled = false
    static let subscriptionGroupID: String? = nil
    static let privacyPolicyURL: URL? = nil
    static let termsOfServiceURL: URL? = nil
}
