//
//  定义宿主应用向图片、视频和音频转换提供的使用授权接口。
//  一次许可限制可记录的成功数量，并通过回调通知宿主结果与结束。
//  策略通过 SwiftUI 环境注入；默认策略不限制使用。
//  宿主提供访问判断、批次许可和升级界面，转换页面从环境读取这些能力。
//  许可只报告已交付的成功数量，完成后重复结束不会重复通知宿主。
//

import Foundation
import SwiftUI

/// 宿主可分别授权的转换类别。
public enum ConversionUsageCategory: String, Identifiable, Sendable {
    case images
    case video
    case videoCompression
    case audio

    public var id: Self { self }
}

/// 宿主授权的一次批处理；转换器只报告交付成功数量与结束。
@MainActor
public final class ConversionUsagePermit {
    public private(set) var successfulCount = 0
    private let count: Int
    private let onSuccess: (Int) -> Void
    private let onFinish: () -> Void
    private var isFinished = false

    /// 创建最多可记录指定数量成功项的许可，并保存宿主回调。
    public init(count: Int, onSuccess: @escaping (Int) -> Void = { _ in }, onFinish: @escaping () -> Void = {}) {
        self.count = max(0, count)
        self.onSuccess = onSuccess
        self.onFinish = onFinish
    }

    /// 累计成功项并通知宿主；超出许可数量的部分不再计入。
    public func recordSuccess(_ count: Int = 1) {
        guard !isFinished, count > 0 else { return }
        let delivered = min(count, self.count - successfulCount)
        guard delivered > 0 else { return }
        successfulCount += delivered
        onSuccess(delivered)
    }

    /// 结束许可并只调用一次结束回调；结束后不再记录成功项。
    public func finish() {
        guard !isFinished else { return }
        isFinished = true
        onFinish()
    }
}

/// 由宿主注入的访问判断、批量许可预留及升级界面。
public struct ConversionUsagePolicy: Sendable {
    public var allows: @MainActor @Sendable (ConversionUsageCategory) -> Bool
    public var reserve: @MainActor @Sendable (ConversionUsageCategory, Int) -> ConversionUsagePermit?
    public var upgradeContent: @MainActor @Sendable (ConversionUsageCategory) -> AnyView

    /// 配置各类别的访问判断、许可预留和可选升级界面。
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

/// 未由宿主注入时使用不限制的默认策略。
private struct ConversionUsagePolicyKey: EnvironmentKey {
    static let defaultValue = ConversionUsagePolicy.unrestricted
}

/// 通过 SwiftUI 环境向转换界面传递用量策略。
public extension EnvironmentValues {
    var conversionUsagePolicy: ConversionUsagePolicy {
        get { self[ConversionUsagePolicyKey.self] }
        set { self[ConversionUsagePolicyKey.self] = newValue }
    }
}
