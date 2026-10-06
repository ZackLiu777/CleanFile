import Foundation
import SwiftUI

public enum ConversionUsageCategory: String, Identifiable, Sendable {
    case images
    case video
    case audio

    public var id: Self { self }
}

/// The host app authorizes a batch; converters report delivered results independently of billing.
@MainActor
public final class ConversionUsagePermit {
    public private(set) var successfulCount = 0
    private let count: Int
    private let onSuccess: (Int) -> Void
    private let onFinish: () -> Void
    private var isFinished = false

    public init(count: Int, onSuccess: @escaping (Int) -> Void = { _ in }, onFinish: @escaping () -> Void = {}) {
        self.count = max(0, count)
        self.onSuccess = onSuccess
        self.onFinish = onFinish
    }

    public func recordSuccess(_ count: Int = 1) {
        guard !isFinished, count > 0 else { return }
        let delivered = min(count, self.count - successfulCount)
        guard delivered > 0 else { return }
        successfulCount += delivered
        onSuccess(delivered)
    }

    public func finish() {
        guard !isFinished else { return }
        isFinished = true
        onFinish()
    }
}

public struct ConversionUsagePolicy: Sendable {
    public var allows: @MainActor @Sendable (ConversionUsageCategory) -> Bool
    public var reserve: @MainActor @Sendable (ConversionUsageCategory, Int) -> ConversionUsagePermit?
    public var upgradeContent: @MainActor @Sendable (ConversionUsageCategory) -> AnyView

    public init(
        allows: @escaping @MainActor @Sendable (ConversionUsageCategory) -> Bool = { _ in true },
        reserve: @escaping @MainActor @Sendable (ConversionUsageCategory, Int) -> ConversionUsagePermit?,
        upgradeContent: @escaping @MainActor @Sendable (ConversionUsageCategory) -> AnyView = { _ in AnyView(EmptyView()) }
    ) {
        self.allows = allows
        self.reserve = reserve
        self.upgradeContent = upgradeContent
    }

    public static let unrestricted = ConversionUsagePolicy(reserve: { _, count in
        ConversionUsagePermit(count: count)
    })
}

private struct ConversionUsagePolicyKey: EnvironmentKey {
    static let defaultValue = ConversionUsagePolicy.unrestricted
}

public extension EnvironmentValues {
    var conversionUsagePolicy: ConversionUsagePolicy {
        get { self[ConversionUsagePolicyKey.self] }
        set { self[ConversionUsagePolicyKey.self] = newValue }
    }
}
