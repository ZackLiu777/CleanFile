//
//  定义转换界面可由宿主注入的颜色、背景、字体和卡片效果配置。
//  统一渲染纯色、线性渐变与网格渐变，并为旧系统提供渐变回退。
//  未指定主题或字体时保持系统默认，兼容既有调用方式。
//  宿主可通过主题和 SwiftUI 环境提供颜色、背景与字体给转换组件。
//  卡片材质与背景根据系统能力选择实现；本文件不管理转换业务状态。
//

import SwiftUI

/// 宿主未指定字体名称时沿用每个控件的原始字体。
private struct ConversionFontNameKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

/// 通过 SwiftUI 环境传递转换界面的可选自定义字体名称。
public extension EnvironmentValues {
    var conversionFontName: String? {
        get { self[ConversionFontNameKey.self] }
        set { self[ConversionFontNameKey.self] = newValue }
    }
}

/// 根据环境中的字体名称应用可随文字大小设置缩放的字体，否则使用后备字体。
public struct ConversionTypefaceModifier: ViewModifier {
    @Environment(\.conversionFontName) private var name
    let fallback: Font
    let size: CGFloat
    let style: Font.TextStyle
    let weight: Font.Weight

    /// 保存回退字体、尺寸和文字样式，用于按环境应用字体。
    public init(_ fallback: Font, size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight = .regular) {
        self.fallback = fallback
        self.size = size
        self.style = style
        self.weight = weight
    }

    /// 根据环境字体设置修饰内容，保留调用方提供的回退字体。
    public func body(content: Content) -> some View {
        content.font(name.map { Font.custom($0, size: size, relativeTo: style).weight(weight) } ?? fallback)
    }
}

/// 提供转换组件共用的字体视图修饰入口。
extension View {
    /// 为转换界面统一应用宿主字体和给定的后备字体。
    func appTypeface(_ fallback: Font, size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        modifier(ConversionTypefaceModifier(fallback, size: size, relativeTo: style, weight: weight))
    }
}
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 线性渐变色标；位置限制在零到一之间。
public struct ConversionGradientStop: Sendable {
    public let color: Color
    public let location: Double

    /// 保存渐变色，并将位置限制在零到一之间。
    public init(color: Color, location: Double) {
        self.color = color
        self.location = min(max(location, 0), 1)
    }
}

/// 宿主可选的纯色、线性渐变和网格渐变背景。
public enum ConversionBackground: Sendable {
    case solid(Color)
    /// Legacy color-only case kept for source compatibility with existing package clients.
    case linearGradient(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint)
    /// Position-aware case used by the app's custom background editor.
    case linearGradientStops(stops: [ConversionGradientStop], startPoint: UnitPoint, endPoint: UnitPoint)
    case meshGradient(colors: [Color])
}

/// 集中渲染转换页面背景；不支持网格渐变的系统回退到线性渐变。
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

    /// 网格要求九个颜色，不足时重复末色或透明色，多余颜色截断。
    private func normalizedMeshColors(_ colors: [Color]) -> [Color] {
        let fallback = colors.last ?? .clear
        return Array((colors + Array(repeating: fallback, count: 9)).prefix(9))
    }
}

/// 宿主注入的背景、表面、文字、强调色及玻璃效果配置。
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

    /// 保存转换界面使用的背景、颜色和材质配置。
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

/// 环境未注入主题时使用系统主题。
private struct ConversionThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = ConversionTheme.system
}

/// 通过 SwiftUI 环境向转换界面传递主题。
extension EnvironmentValues {
    var conversionTheme: ConversionTheme {
        get { self[ConversionThemeEnvironmentKey.self] }
        set { self[ConversionThemeEnvironmentKey.self] = newValue }
    }
}
