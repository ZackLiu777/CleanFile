//
//  文件职责：集中定义 ConversionTheme 相关的生产逻辑与共享能力。
//  所属模块：ImageFormatConversionKit。
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 定义 `ConversionBackground` 使用的有限状态或选项集合。
public enum ConversionBackground: Sendable {
    case solid(Color)
    case linearGradient(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint)
}

/// 定义 `ConversionTheme` 的值语义数据与相关行为。
public struct ConversionTheme: Sendable {
    public let background: ConversionBackground
    public let cardSurface: Color
    public let cardElevated: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let accent: Color
    public let destructive: Color
    public let divider: Color
    public let liquidGlassEnabled: Bool

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    public init(
        background: ConversionBackground,
        cardSurface: Color,
        cardElevated: Color,
        textPrimary: Color,
        textSecondary: Color,
        accent: Color,
        destructive: Color,
        divider: Color,
        liquidGlassEnabled: Bool
    ) {
        self.background = background
        self.cardSurface = cardSurface
        self.cardElevated = cardElevated
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.accent = accent
        self.destructive = destructive
        self.divider = divider
        self.liquidGlassEnabled = liquidGlassEnabled
    }

#if os(iOS)
    private static let systemBackground = Color(uiColor: .systemGroupedBackground)
    private static let systemCard = Color(uiColor: .secondarySystemGroupedBackground)
    private static let systemElevatedCard = Color(uiColor: .tertiarySystemGroupedBackground)
    private static let systemText = Color(uiColor: .label)
    private static let systemSecondaryText = Color(uiColor: .secondaryLabel)
    private static let systemDivider = Color(uiColor: .separator)
#elseif os(macOS)
    private static let systemBackground = Color(nsColor: .windowBackgroundColor)
    private static let systemCard = Color(nsColor: .controlBackgroundColor)
    private static let systemElevatedCard = Color(nsColor: .underPageBackgroundColor)
    private static let systemText = Color(nsColor: .labelColor)
    private static let systemSecondaryText = Color(nsColor: .secondaryLabelColor)
    private static let systemDivider = Color(nsColor: .separatorColor)
#else
    private static let systemBackground = Color.clear
    private static let systemCard = Color.secondary.opacity(0.08)
    private static let systemElevatedCard = Color.secondary.opacity(0.12)
    private static let systemText = Color.primary
    private static let systemSecondaryText = Color.secondary
    private static let systemDivider = Color.secondary.opacity(0.2)
#endif

    public static let system = ConversionTheme(
        background: .solid(systemBackground),
        cardSurface: systemCard,
        cardElevated: systemElevatedCard,
        textPrimary: systemText,
        textSecondary: systemSecondaryText,
        accent: .accentColor,
        destructive: .red,
        divider: systemDivider,
        liquidGlassEnabled: false
    )
}

/// 定义 `ConversionThemeEnvironmentKey` 的值语义数据与相关行为。
private struct ConversionThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = ConversionTheme.system
}

/// 扩展 `EnvironmentValues`，集中实现当前文件所需的附加能力。
extension EnvironmentValues {
    var conversionTheme: ConversionTheme {
        get { self[ConversionThemeEnvironmentKey.self] }
        set { self[ConversionThemeEnvironmentKey.self] = newValue }
    }
}
