// Premium 商品与相关链接的集中配置。
// 商品标识同时用于商品查询、交易核验和订阅组查询，须与商店配置保持一致。
// UI 测试开关仅在 DEBUG 构建可用，不作为正式版的权益来源。
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
    static let privacyPolicyURL = URL(string: "https://zane-liao.github.io/privacy/")!
    static let termsOfServiceURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// UI automation exercises app features rather than the App Store purchase sheet.
    static var bypassesEntitlementForUITesting: Bool {
#if DEBUG
        !usesFreeTierForUITesting && ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--ui-test") }
#else
        false
#endif
    }

    static var usesFreeTierForUITesting: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-test-free-tier")
#else
        false
#endif
    }
}
