//
//  文件职责：集中定义 ConversionTheme 相关的生产逻辑与共享能力。
//  所属模块：ImageFormatConversionKit。
//

import SwiftUI

private struct ConversionFontNameKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

public extension EnvironmentValues {
    var conversionFontName: String? {
        get { self[ConversionFontNameKey.self] }
        set { self[ConversionFontNameKey.self] = newValue }
    }
}

/// Preserves the original font when no named family is selected.
public struct ConversionTypefaceModifier: ViewModifier {
    @Environment(\.conversionFontName) private var name
    let fallback: Font
    let size: CGFloat
    let style: Font.TextStyle
    let weight: Font.Weight

    public init(_ fallback: Font, size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight = .regular) {
        self.fallback = fallback
        self.size = size
        self.style = style
        self.weight = weight
    }

    public func body(content: Content) -> some View {
        content.font(name.map { Font.custom($0, size: size, relativeTo: style).weight(weight) } ?? fallback)
    }
}

extension View {
    func appTypeface(_ fallback: Font, size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        modifier(ConversionTypefaceModifier(fallback, size: size, relativeTo: style, weight: weight))
    }
}
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 定义 `ConversionBackground` 使用的有限状态或选项集合。
public struct ConversionGradientStop: Sendable {
    public let color: Color
    public let location: Double

    public init(color: Color, location: Double) {
        self.color = color
        self.location = min(max(location, 0), 1)
    }
}

public enum ConversionBackground: Sendable {
    case solid(Color)
    /// Legacy color-only case kept for source compatibility with existing package clients.
    case linearGradient(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint)
    /// Position-aware case used by the app's custom background editor.
    case linearGradientStops(stops: [ConversionGradientStop], startPoint: UnitPoint, endPoint: UnitPoint)
    case meshGradient(colors: [Color])
}

/// One renderer prevents the package's five screens from drifting apart as background modes grow.
struct ConversionBackgroundView: View {
    let background: ConversionBackground

    @ViewBuilder
    var body: some View {
        switch background {
        case let .solid(color):
            color
        case let .linearGradient(colors, startPoint, endPoint):
            LinearGradient(
                colors: colors,
                startPoint: startPoint,
                endPoint: endPoint
            )
        case let .linearGradientStops(stops, startPoint, endPoint):
            LinearGradient(
                stops: stops.map {
                    Gradient.Stop(color: $0.color, location: CGFloat($0.location))
                },
                startPoint: startPoint,
                endPoint: endPoint
            )
        case let .meshGradient(colors):
            if #available(iOS 18.0, macOS 15.0, *) {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        SIMD2<Float>(0, 0), SIMD2<Float>(0.5, 0), SIMD2<Float>(1, 0),
                        SIMD2<Float>(0, 0.5), SIMD2<Float>(0.5, 0.5), SIMD2<Float>(1, 0.5),
                        SIMD2<Float>(0, 1), SIMD2<Float>(0.5, 1), SIMD2<Float>(1, 1)
                    ],
                    colors: normalizedMeshColors(colors),
                    smoothsColors: true,
                    colorSpace: .perceptual
                )
            } else {
                LinearGradient(
                    colors: normalizedMeshColors(colors),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private func normalizedMeshColors(_ colors: [Color]) -> [Color] {
        let fallback = colors.last ?? .clear
        return Array((colors + Array(repeating: fallback, count: 9)).prefix(9))
    }
}

/// 定义 `ConversionTheme` 的值语义数据与相关行为。
public struct ConversionTheme: Sendable {
    public let background: ConversionBackground
    public let cardSurface: Color
    public let cardElevated: Color
    public let cardHighlight: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let accent: Color
    public let destructive: Color
    public let divider: Color
    public let liquidGlassEnabled: Bool
    public let liquidGlassCardsEnabled: Bool

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    public init(
        background: ConversionBackground,
        cardSurface: Color,
        cardElevated: Color,
        cardHighlight: Color? = nil,
        textPrimary: Color,
        textSecondary: Color,
        accent: Color,
        destructive: Color,
        divider: Color,
        liquidGlassEnabled: Bool,
        liquidGlassCardsEnabled: Bool = false
    ) {
        self.background = background
        self.cardSurface = cardSurface
        self.cardElevated = cardElevated
        // 允许宿主提供由背景调色盘派生的高亮表面；旧调用方省略时保持原有层级。
        self.cardHighlight = cardHighlight ?? cardElevated
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.accent = accent
        self.destructive = destructive
        self.divider = divider
        self.liquidGlassEnabled = liquidGlassEnabled
        self.liquidGlassCardsEnabled = liquidGlassCardsEnabled
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
        cardHighlight: systemCard,
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
