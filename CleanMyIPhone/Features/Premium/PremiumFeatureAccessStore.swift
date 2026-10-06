import Combine
import ImageFormatConversionKit
import SwiftUI

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

    init(accessState: PremiumEntitlementStore.AccessState = .checking) {
        self.accessState = accessState
        lastResolvedState = accessState == .checking ? nil : accessState
    }

    func update(_ state: PremiumEntitlementStore.AccessState) {
        guard accessState != state else { return }
        if state != .checking { lastResolvedState = state }
        accessState = state
    }

    func allows(_ feature: PremiumFeature) -> Bool {
        !feature.requiresPremium || accessState == .entitled
    }

    // Preserve unknown ownership on upgrade, but a later offline check cannot undo confirmed expiration.
    var preservesPremiumAppearance: Bool { lastResolvedState != .notEntitled }

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

    private func feature(for category: ConversionUsageCategory) -> PremiumFeature {
        switch category {
        case .images: .imageConversion
        case .video: .videoConversion
        case .audio: .audioConversion
        }
    }
}
