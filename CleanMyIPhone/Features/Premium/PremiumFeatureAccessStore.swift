// 将已核验的 Premium 状态映射到应用功能和转换包权限。
// 免费功能无需等待订阅；付费功能在 checking 时不会获得执行许可。
// 外观偏好使用最近一次确定状态，避免临时核验期间丢失用户设置。
import Combine
import ImageFormatConversionKit
import SwiftUI

/// 应用内受权限策略管理的功能及其本地化展示信息。
enum PremiumFeature: String, CaseIterable, Identifiable {
    case media
    case quickClean
    case videoConversion
    case storage
    case imageConversion
    case audioConversion
    case darkAppearance
    case customColors

    var id: Self { self }

    var requiresPremium: Bool {
        switch self {
        case .media, .videoConversion: false
        case .quickClean, .storage, .imageConversion, .audioConversion, .darkAppearance, .customColors: true
        }
    }

    var titleKey: String.LocalizationValue {
        switch self {
        case .media: "premium.feature.media"
        case .quickClean: "Quick Cleanup"
        case .videoConversion: "premium.feature.videoConversion"
        case .storage: "premium.feature.storage"
        case .imageConversion: "premium.feature.imageConversion"
        case .audioConversion: "premium.feature.audioConversion"
        case .darkAppearance: "premium.feature.darkAppearance"
        case .customColors: "premium.feature.customColors"
        }
    }
}

/// Feature access follows verified StoreKit ownership, including an active introductory trial.
@MainActor
final class PremiumFeatureAccessStore: ObservableObject {
    @Published private(set) var accessState: PremiumEntitlementStore.AccessState
    private var lastResolvedState: PremiumEntitlementStore.AccessState?

    /// 以已知权益初始化；checking 不覆盖最后一次确定的结果。
    init(accessState: PremiumEntitlementStore.AccessState = .checking) {
        self.accessState = accessState
        lastResolvedState = accessState == .checking ? nil : accessState
    }

    /// 发布状态变化，并仅保存确定的权益结果供外观策略使用。
    func update(_ state: PremiumEntitlementStore.AccessState) {
        guard accessState != state else { return }
        if state != .checking { lastResolvedState = state }
        accessState = state
    }

    /// 免费功能始终开放，付费功能要求当前状态为 entitled。
    func allows(_ feature: PremiumFeature) -> Bool {
        !feature.requiresPremium || accessState == .entitled
    }

    // Preserve unknown ownership on upgrade, but a later offline check cannot undo confirmed expiration.
    var preservesPremiumAppearance: Bool { lastResolvedState != .notEntitled }

    /// 提供转换包使用的实时权限检查、批量许可和升级页面。
    var conversionPolicy: ConversionUsagePolicy {
        ConversionUsagePolicy(
            allows: { [self] category in allows(feature(for: category)) },
            reserve: { [self] category, count in
                guard count > 0, allows(feature(for: category)) else { return nil }
                return ConversionUsagePermit(count: count)
            },
            upgradeContent: { [self] category in
                AnyView(PremiumSubscriptionView(requiredFeature: feature(for: category)))
            }
        )
    }

    /// 将转换包的媒体类别映射到应用内功能权限。
    private func feature(for category: ConversionUsageCategory) -> PremiumFeature {
        switch category {
        case .images: .imageConversion
        case .video: .videoConversion
        case .audio: .audioConversion
        }
    }
}
