//
//  文件职责：集中定义 AppTheme 相关的生产逻辑与共享能力。
//  所属模块：CleanMyIPhone。
//

import Combine
import Foundation
import SwiftUI
import UIKit

/// 定义 `AppAppearance` 使用的有限状态或选项集合。
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: Self { self }
    var displayName: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// 定义 `AppThemeID` 使用的有限状态或选项集合。
enum AppThemeID: String, CaseIterable, Identifiable, Sendable {
    case system, cream, porcelain, sage, graphite

    var id: Self { self }
    var displayName: LocalizedStringKey {
        switch self {
        case .system: "System Default"
        case .cream: "Cream"
        case .porcelain: "Porcelain"
        case .sage: "Sage"
        case .graphite: "Graphite"
        }
    }
    var theme: Theme {
        switch self {
        case .system: .system
        case .cream: .cream
        case .porcelain: .porcelain
        case .sage: .sage
        case .graphite: .graphite
        }
    }
}

// MARK: - AppThemeColor

/// 保存用户选择的非透明 sRGB 颜色，并提供生成可读语义主题所需的颜色运算。
struct AppThemeColor: Codable, Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    static let brandPink = AppThemeColor(red: 0xE8 / 255, green: 0xA3 / 255, blue: 0x9C / 255)
    static let cream = AppThemeColor(red: 250 / 255, green: 246 / 255, blue: 233 / 255)
    static let black = AppThemeColor(red: 0, green: 0, blue: 0)
    static let white = AppThemeColor(red: 1, green: 1, blue: 1)

    private enum CodingKeys: String, CodingKey {
        case red
        case green
        case blue
    }

    /// 创建规范化颜色，阻止损坏的持久化值越过 sRGB 的有效范围。
    init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    /// 从持久化数据恢复颜色，并通过指定初始化器统一执行范围校验。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            red: try container.decode(Double.self, forKey: .red),
            green: try container.decode(Double.self, forKey: .green),
            blue: try container.decode(Double.self, forKey: .blue)
        )
    }

    /// 将规范化分量编码为稳定、与 SwiftUI 实现细节无关的持久化结构。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(red, forKey: .red)
        try container.encode(green, forKey: .green)
        try container.encode(blue, forKey: .blue)
    }

    /// 返回可直接交给 SwiftUI 绘制的非透明 sRGB Color。
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    /// 将系统 ColorPicker 返回的 Color 固化为 sRGB；转换失败时保留调用方提供的安全值。
    static func resolved(from color: Color, fallback: AppThemeColor) -> AppThemeColor {
        let resolvedColor = UIColor(color).resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light)
        )
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return fallback
        }

        return AppThemeColor(red: Double(red), green: Double(green), blue: Double(blue))
    }

    /// 在当前颜色与目标颜色之间插值，用于生成卡片层级和可读的次级文字。
    func blended(toward target: AppThemeColor, amount: Double) -> AppThemeColor {
        let progress = Self.clamp(amount)
        return AppThemeColor(
            red: red + ((target.red - red) * progress),
            green: green + ((target.green - green) * progress),
            blue: blue + ((target.blue - blue) * progress)
        )
    }

    /// 返回与当前背景对比更高的黑色或白色，供自定义背景建立文字基线。
    var preferredForeground: AppThemeColor {
        contrastRatio(with: .black) >= contrastRatio(with: .white) ? .black : .white
    }

    /// 从当前背景向目标前景逐步插值，找到满足最低对比度的最柔和颜色。
    func contrastingVariant(
        toward foreground: AppThemeColor,
        minimumRatio: Double
    ) -> AppThemeColor {
        for step in 1 ... 100 {
            let candidate = blended(toward: foreground, amount: Double(step) / 100)
            if contrastRatio(with: candidate) >= minimumRatio {
                return candidate
            }
        }
        return foreground
    }

    /// 计算两个 sRGB 颜色的 WCAG 对比度，用于自定义主题的本地可读性保护。
    func contrastRatio(with other: AppThemeColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// 将 sRGB 分量转换为相对亮度，避免直接以平均 RGB 猜测明暗模式。
    private var relativeLuminance: Double {
        (0.2126 * Self.linearized(red))
            + (0.7152 * Self.linearized(green))
            + (0.0722 * Self.linearized(blue))
    }

    /// 将单个 sRGB 分量线性化，以符合标准对比度计算方式。
    private static func linearized(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }

    /// 将任意数值限制在颜色分量允许的闭区间内。
    private static func clamp(_ component: Double) -> Double {
        min(max(component, 0), 1)
    }
}

/// The user-facing ways a custom app background can be composed.
enum AppCustomBackgroundKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case solid
    case linear
    case mesh

    var id: Self { self }

    var displayName: LocalizedStringKey {
        switch self {
        case .solid: "Solid Color"
        case .linear: "Linear Gradient"
        case .mesh: "Freeform Blend"
        }
    }
}

/// A small, explicit direction set keeps the editor predictable and Codable.
enum AppLinearGradientDirection: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case topToBottom
    case leftToRight
    case diagonalDown
    case diagonalUp

    var id: Self { self }

    var displayName: LocalizedStringKey {
        switch self {
        case .topToBottom: "Top to Bottom"
        case .leftToRight: "Left to Right"
        case .diagonalDown: "Diagonal Down"
        case .diagonalUp: "Diagonal Up"
        }
    }

    var points: (start: UnitPoint, end: UnitPoint) {
        switch self {
        case .topToBottom: (.top, .bottom)
        case .leftToRight: (.leading, .trailing)
        case .diagonalDown: (.topLeading, .bottomTrailing)
        case .diagonalUp: (.bottomLeading, .topTrailing)
        }
    }
}

/// Stable identity prevents color wells from being recreated when a gradient stop is inserted.
struct AppBackgroundColorStop: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var color: AppThemeColor
    var location: Double

    init(id: UUID = UUID(), color: AppThemeColor, location: Double) {
        self.id = id
        self.color = color
        self.location = min(max(location, 0), 1)
    }
}

/// Persisted custom-background value. SwiftUI `Color` never crosses the persistence boundary.
struct AppCustomBackgroundStyle: Codable, Equatable, Sendable {
    static let maximumColorCount = 9

    var kind: AppCustomBackgroundKind
    var stops: [AppBackgroundColorStop]
    var direction: AppLinearGradientDirection

    static func solid(_ color: AppThemeColor) -> AppCustomBackgroundStyle {
        AppCustomBackgroundStyle(
            kind: .solid,
            stops: [AppBackgroundColorStop(color: color, location: 0)],
            direction: .diagonalDown
        )
    }

    var primaryColor: AppThemeColor { stops.first?.color ?? .cream }

    var activeStops: [AppBackgroundColorStop] {
        switch kind {
        case .solid: Array(stops.prefix(1))
        case .linear: Array(stops.prefix(Self.maximumColorCount))
        case .mesh: Array(stops.prefix(9))
        }
    }

    /// Repairs incomplete or future/corrupt values without allowing unbounded view state.
    func sanitized() -> AppCustomBackgroundStyle {
        var result = self
        if result.stops.isEmpty {
            result.stops = [AppBackgroundColorStop(color: .cream, location: 0)]
        }
        if result.stops.count > Self.maximumColorCount {
            result.stops = Array(result.stops.prefix(Self.maximumColorCount))
        }
        var seenIDs = Set<UUID>()
        for index in result.stops.indices {
            let stop = result.stops[index]
            if seenIDs.insert(stop.id).inserted == false {
                // A duplicated persisted ID would make SwiftUI reuse the wrong ColorPicker.
                result.stops[index] = AppBackgroundColorStop(
                    color: stop.color,
                    location: stop.location
                )
            }
        }
        for index in result.stops.indices {
            let location = result.stops[index].location
            result.stops[index].location = location.isFinite ? min(max(location, 0), 1) : 0
        }

        result.ensureMinimumColors(for: result.kind, preferredLinearCount: 2)
        if result.kind == .linear {
            result.stops.sort { $0.location < $1.location }
            let hasUnsafeSpacing = zip(result.stops, result.stops.dropFirst())
                .contains { $0.1.location - $0.0.location < 0.02 }
            if hasUnsafeSpacing {
                result.redistributeLocations()
            }
        }
        return result
    }

    /// Preserves earlier edits when switching modes and only creates missing color slots.
    func prepared(for kind: AppCustomBackgroundKind) -> AppCustomBackgroundStyle {
        var result = sanitized()
        result.kind = kind
        let previousCount = result.stops.count
        result.ensureMinimumColors(for: kind, preferredLinearCount: 5)

        if kind == .linear, result.stops.count != previousCount {
            result.redistributeLocations()
        }
        return result
    }

    private mutating func ensureMinimumColors(
        for kind: AppCustomBackgroundKind,
        preferredLinearCount: Int
    ) {
        let minimumCount: Int
        switch kind {
        case .solid: minimumCount = 1
        case .linear: minimumCount = preferredLinearCount
        case .mesh: minimumCount = 9
        }

        let seed = stops.first?.color ?? .cream
        let targets: [AppThemeColor] = [
            .brandPink,
            AppThemeColor(red: 0.76, green: 0.86, blue: 0.92),
            AppThemeColor(red: 0.72, green: 0.82, blue: 0.70),
            AppThemeColor(red: 0.91, green: 0.78, blue: 0.58),
            AppThemeColor(red: 0.76, green: 0.67, blue: 0.84),
            AppThemeColor(red: 0.47, green: 0.75, blue: 0.72),
            AppThemeColor(red: 0.94, green: 0.70, blue: 0.67),
            seed.preferredForeground
        ]

        while stops.count < minimumCount, stops.count < Self.maximumColorCount {
            let index = stops.count - 1
            let target = targets[index % targets.count]
            let amount = 0.18 + (Double(index % 3) * 0.07)
            stops.append(
                AppBackgroundColorStop(
                    color: seed.blended(toward: target, amount: amount),
                    location: Double(stops.count) / Double(max(minimumCount - 1, 1))
                )
            )
        }
    }

    mutating func redistributeLocations() {
        guard stops.count > 1 else {
            stops[0].location = 0
            return
        }
        for index in stops.indices {
            stops[index].location = Double(index) / Double(stops.count - 1)
        }
    }
}

/// 定义应用强调色调色盘；`automatic` 保留所选背景主题原有的协调色。
enum AppAccentPaletteID: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case custom
    case pink
    case coral
    case gold
    case sage
    case sky
    case teal
    case berry

    var id: Self { self }

    /// 返回调色盘在设置页显示的本地化名称。
    var displayName: LocalizedStringKey {
        switch self {
        case .automatic: "Automatic"
        case .custom: "Custom"
        case .pink: "CleanMyIPhone Pink"
        case .coral: "Coral"
        case .gold: "Graphite Gold"
        case .sage: "Sage"
        case .sky: "Sky"
        case .teal: "Teal"
        case .berry: "Berry"
        }
    }

    /// 返回策划过的强调色；自动模式由当前背景主题提供，因此返回 nil。
    var color: Color? {
        switch self {
        case .automatic, .custom: nil
        case .pink: Color(red: 0xE8 / 255, green: 0xA3 / 255, blue: 0x9C / 255)
        case .coral: Color(red: 0.82, green: 0.39, blue: 0.33)
        case .gold: Color(red: 0.69, green: 0.53, blue: 0.35)
        case .sage: Color(red: 0.396, green: 0.478, blue: 0.400)
        case .sky: Color(red: 0.333, green: 0.459, blue: 0.510)
        case .teal: Color(red: 0.22, green: 0.50, blue: 0.43)
        case .berry: Color(red: 0.57, green: 0.31, blue: 0.43)
        }
    }
}

/// 定义 `ThemeBackground` 使用的有限状态或选项集合。
enum ThemeBackground: Sendable {
    case solid(Color)
    case linearGradient(stops: [AppBackgroundColorStop], startPoint: UnitPoint, endPoint: UnitPoint)
    case meshGradient(colors: [Color])
}

private struct ResolvedCustomBackground {
    let background: ThemeBackground
    let representativeColor: AppThemeColor
    let foregroundColor: AppThemeColor
}

/// 定义 `Theme` 的值语义数据与相关行为。
struct Theme: Sendable {
    let background: ThemeBackground
    let backgroundPrimary: Color
    let backgroundSecondary: Color
    let backgroundGrouped: Color
    let cardSurface: Color
    let cardElevated: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let textInverted: Color
    var accentPrimary: Color
    var accentSecondary: Color
    let positiveGreen: Color
    let negativeRed: Color
    let warningOrange: Color
    let divider: Color
    let navigationBackground: Color
    let emptyStateIcon: Color
    var buttonPrimaryBackground: Color
    let buttonDisabledForeground: Color
    let liquidGlassEnabled: Bool
    var liquidGlassCardsEnabled: Bool
    let preferredColorScheme: ColorScheme?

    /// 计算 `fileCategoryColor` 所需的派生值，避免展示层重复实现相同规则。
    func fileCategoryColor(_ category: FileCategory?) -> Color {
        switch category {
        case .video: accentPrimary
        case .image: warningOrange
        case .audio: Color(red: 0.66, green: 0.52, blue: 0.86)
        case .document: Color(red: 0.38, green: 0.63, blue: 0.90)
        case .pdf: negativeRed
        case .archive: positiveGreen
        case .other, nil: textSecondary
        }
    }

    /// 将可选强调色叠加到完整背景主题上，同时保留成功、警告和删除等语义色。
    func applyingAccent(_ accent: Color?) -> Theme {
        guard let accent else { return self }
        var resolved = self
        resolved.accentPrimary = accent
        resolved.accentSecondary = accent.opacity(0.38)
        resolved.buttonPrimaryBackground = accent
        return resolved
    }

    /// Applies the user's card-material preference independently of the selected color theme.
    func applyingLiquidGlassCards(_ isEnabled: Bool) -> Theme {
        var resolved = self
        resolved.liquidGlassCardsEnabled = isEnabled
        return resolved
    }

    static let system = Theme(
        background: .solid(Color(uiColor: .systemGroupedBackground)),
        backgroundPrimary: Color(uiColor: .systemGroupedBackground),
        backgroundSecondary: Color(uiColor: .secondarySystemGroupedBackground),
        backgroundGrouped: Color(uiColor: .systemGroupedBackground),
        cardSurface: Color(uiColor: .secondarySystemGroupedBackground),
        cardElevated: Color(uiColor: .tertiarySystemGroupedBackground),
        textPrimary: Color(uiColor: .label),
        textSecondary: Color(uiColor: .secondaryLabel),
        textTertiary: Color(uiColor: .tertiaryLabel),
        textInverted: .white,
        accentPrimary: Color(red: 0xE8 / 255, green: 0xA3 / 255, blue: 0x9C / 255),
        accentSecondary: Color(red: 0.96, green: 0.80, blue: 0.78),
        positiveGreen: .green,
        negativeRed: .red,
        warningOrange: Color(red: 0.95, green: 0.67, blue: 0.42),
        divider: Color(uiColor: .separator),
        navigationBackground: Color(uiColor: .systemGroupedBackground),
        emptyStateIcon: Color(uiColor: .secondaryLabel),
        buttonPrimaryBackground: Color(red: 0xE8 / 255, green: 0xA3 / 255, blue: 0x9C / 255),
        buttonDisabledForeground: Color(uiColor: .tertiaryLabel),
        liquidGlassEnabled: true,
        liquidGlassCardsEnabled: false,
        preferredColorScheme: nil
    )

    static let porcelain = Theme(
        background: .solid(Color(red: 0.949, green: 0.965, blue: 0.969)),
        backgroundPrimary: Color(red: 0.949, green: 0.965, blue: 0.969),
        backgroundSecondary: Color(red: 0.949, green: 0.965, blue: 0.969),
        backgroundGrouped: Color(red: 0.949, green: 0.965, blue: 0.969),
        cardSurface: Color(red: 0.949, green: 0.965, blue: 0.969),
        cardElevated: Color(red: 0.949, green: 0.965, blue: 0.969),
        textPrimary: Color(red: 0.149, green: 0.196, blue: 0.220),
        textSecondary: Color(red: 0.373, green: 0.424, blue: 0.447),
        textTertiary: Color(red: 0.510, green: 0.557, blue: 0.576),
        textInverted: .white,
        accentPrimary: Color(red: 0.333, green: 0.459, blue: 0.510),
        accentSecondary: Color(red: 0.710, green: 0.776, blue: 0.804),
        positiveGreen: Color(red: 0.28, green: 0.58, blue: 0.38),
        negativeRed: Color(red: 0.78, green: 0.27, blue: 0.25),
        warningOrange: Color(red: 0.82, green: 0.52, blue: 0.20),
        divider: Color(red: 0.843, green: 0.871, blue: 0.882),
        navigationBackground: Color(red: 0.949, green: 0.965, blue: 0.969),
        emptyStateIcon: Color(red: 0.45, green: 0.52, blue: 0.55),
        buttonPrimaryBackground: Color(red: 0.333, green: 0.459, blue: 0.510),
        buttonDisabledForeground: Color(red: 0.62, green: 0.66, blue: 0.68),
        liquidGlassEnabled: false,
        liquidGlassCardsEnabled: false,
        preferredColorScheme: .light
    )

    static let sage = Theme(
        background: .solid(Color(red: 0.945, green: 0.957, blue: 0.937)),
        backgroundPrimary: Color(red: 0.945, green: 0.957, blue: 0.937),
        backgroundSecondary: Color(red: 0.945, green: 0.957, blue: 0.937),
        backgroundGrouped: Color(red: 0.945, green: 0.957, blue: 0.937),
        cardSurface: Color(red: 0.945, green: 0.957, blue: 0.937),
        cardElevated: Color(red: 0.945, green: 0.957, blue: 0.937),
        textPrimary: Color(red: 0.161, green: 0.188, blue: 0.161),
        textSecondary: Color(red: 0.365, green: 0.408, blue: 0.365),
        textTertiary: Color(red: 0.510, green: 0.553, blue: 0.510),
        textInverted: .white,
        accentPrimary: Color(red: 0.396, green: 0.478, blue: 0.400),
        accentSecondary: Color(red: 0.718, green: 0.765, blue: 0.706),
        positiveGreen: Color(red: 0.25, green: 0.58, blue: 0.34),
        negativeRed: Color(red: 0.78, green: 0.27, blue: 0.25),
        warningOrange: Color(red: 0.82, green: 0.52, blue: 0.20),
        divider: Color(red: 0.847, green: 0.871, blue: 0.835),
        navigationBackground: Color(red: 0.945, green: 0.957, blue: 0.937),
        emptyStateIcon: Color(red: 0.45, green: 0.51, blue: 0.45),
        buttonPrimaryBackground: Color(red: 0.396, green: 0.478, blue: 0.400),
        buttonDisabledForeground: Color(red: 0.61, green: 0.65, blue: 0.60),
        liquidGlassEnabled: false,
        liquidGlassCardsEnabled: false,
        preferredColorScheme: .light
    )

    static let graphite = Theme(
        background: .solid(Color(red: 0.063, green: 0.067, blue: 0.071)),
        backgroundPrimary: Color(red: 0.063, green: 0.067, blue: 0.071),
        backgroundSecondary: Color(red: 0.098, green: 0.102, blue: 0.110),
        backgroundGrouped: Color(red: 0.063, green: 0.067, blue: 0.071),
        cardSurface: Color(red: 0.098, green: 0.102, blue: 0.110),
        cardElevated: Color(red: 0.098, green: 0.102, blue: 0.110),
        textPrimary: Color(red: 0.957, green: 0.957, blue: 0.949),
        textSecondary: Color(red: 0.647, green: 0.651, blue: 0.639),
        textTertiary: Color(red: 0.475, green: 0.482, blue: 0.475),
        textInverted: Color(red: 0.063, green: 0.067, blue: 0.071),
        accentPrimary: Color(red: 0.776, green: 0.678, blue: 0.502),
        accentSecondary: Color(red: 0.494, green: 0.447, blue: 0.361),
        positiveGreen: Color(red: 0.36, green: 0.72, blue: 0.47),
        negativeRed: Color(red: 0.92, green: 0.38, blue: 0.34),
        warningOrange: Color(red: 0.92, green: 0.62, blue: 0.27),
        divider: Color(red: 0.188, green: 0.196, blue: 0.208),
        navigationBackground: Color(red: 0.063, green: 0.067, blue: 0.071),
        emptyStateIcon: Color(red: 0.47, green: 0.48, blue: 0.47),
        buttonPrimaryBackground: Color(red: 0.776, green: 0.678, blue: 0.502),
        buttonDisabledForeground: Color(red: 0.32, green: 0.33, blue: 0.33),
        liquidGlassEnabled: false,
        liquidGlassCardsEnabled: false,
        preferredColorScheme: .dark
    )

    static let cream = Theme(
        background: .solid(Color(red: 250 / 255, green: 246 / 255, blue: 233 / 255)),
        backgroundPrimary: Color(red: 250 / 255, green: 246 / 255, blue: 233 / 255),
        backgroundSecondary: Color(red: 250 / 255, green: 246 / 255, blue: 233 / 255),
        backgroundGrouped: Color(red: 250 / 255, green: 246 / 255, blue: 233 / 255),
        cardSurface: Color(red: 250 / 255, green: 246 / 255, blue: 233 / 255),
        cardElevated: Color(red: 250 / 255, green: 246 / 255, blue: 233 / 255),
        textPrimary: Color(red: 0.30, green: 0.26, blue: 0.20),
        textSecondary: Color(red: 0.45, green: 0.40, blue: 0.32),
        textTertiary: Color(red: 0.58, green: 0.53, blue: 0.45),
        textInverted: .white,
        accentPrimary: Color(red: 0.69, green: 0.53, blue: 0.35),
        accentSecondary: Color(red: 232 / 255, green: 223 / 255, blue: 209 / 255),
        positiveGreen: Color(red: 0.45, green: 0.60, blue: 0.35),
        negativeRed: Color(red: 0.75, green: 0.35, blue: 0.30),
        warningOrange: Color(red: 0.80, green: 0.55, blue: 0.25),
        divider: Color(red: 0.84, green: 0.80, blue: 0.72),
        navigationBackground: Color(red: 250 / 255, green: 246 / 255, blue: 233 / 255),
        emptyStateIcon: Color(red: 0.58, green: 0.53, blue: 0.45),
        buttonPrimaryBackground: Color(red: 0.69, green: 0.53, blue: 0.35),
        buttonDisabledForeground: Color(red: 0.80, green: 0.76, blue: 0.68),
        liquidGlassEnabled: false,
        liquidGlassCardsEnabled: false,
        preferredColorScheme: .light
    )

    /// Preserves the original single-color API for persisted-data migration and tests.
    static func custom(background: AppThemeColor) -> Theme {
        custom(backgroundStyle: .solid(background))
    }

    /// Resolves every custom composition into one complete semantic theme.
    static func custom(backgroundStyle: AppCustomBackgroundStyle) -> Theme {
        let resolved = resolveCustomBackground(backgroundStyle.sanitized())
        let background = resolved.representativeColor
        let foreground = resolved.foregroundColor
        let secondaryText = background.contrastingVariant(
            toward: foreground,
            minimumRatio: 4.5
        )
        let tertiaryText = background.contrastingVariant(
            toward: foreground,
            minimumRatio: 3
        )
        let divider = background.contrastingVariant(
            toward: foreground,
            minimumRatio: 1.5
        )
        let isDarkBackground = foreground == .white

        return Theme(
            background: resolved.background,
            backgroundPrimary: background.color,
            backgroundSecondary: background.blended(toward: foreground, amount: 0.035).color,
            backgroundGrouped: background.color,
            cardSurface: background.blended(toward: foreground, amount: 0.055).color,
            cardElevated: background.blended(toward: foreground, amount: 0.10).color,
            textPrimary: foreground.color,
            textSecondary: secondaryText.color,
            textTertiary: tertiaryText.color,
            textInverted: isDarkBackground ? AppThemeColor.black.color : AppThemeColor.white.color,
            accentPrimary: AppThemeColor.brandPink.color,
            accentSecondary: AppThemeColor.brandPink.color.opacity(0.38),
            positiveGreen: Color(red: 0.25, green: 0.62, blue: 0.38),
            negativeRed: Color(red: 0.82, green: 0.28, blue: 0.25),
            warningOrange: Color(red: 0.86, green: 0.55, blue: 0.20),
            divider: divider.color,
            navigationBackground: background.color,
            emptyStateIcon: tertiaryText.color,
            buttonPrimaryBackground: AppThemeColor.brandPink.color,
            buttonDisabledForeground: tertiaryText.color,
            liquidGlassEnabled: false,
            liquidGlassCardsEnabled: false,
            preferredColorScheme: isDarkBackground ? .dark : .light
        )
    }

    /// A mixed light/dark palette may have no single readable foreground. Apply one uniform,
    /// minimal wash to the full palette, then derive all semantic tokens from the result.
    private static func resolveCustomBackground(
        _ style: AppCustomBackgroundStyle
    ) -> ResolvedCustomBackground {
        let activeStops = style.activeStops
        let sourceColors = activeStops.map(\.color)
        let blackWash = requiredWash(
            for: sourceColors,
            foreground: .black,
            washTarget: .white
        )
        let whiteWash = requiredWash(
            for: sourceColors,
            foreground: .white,
            washTarget: .black
        )
        let foreground: AppThemeColor
        let washTarget: AppThemeColor
        let washAmount: Double

        if blackWash < whiteWash
            || (blackWash == whiteWash && style.primaryColor.preferredForeground == .black)
        {
            foreground = .black
            washTarget = .white
            washAmount = blackWash
        } else {
            foreground = .white
            washTarget = .black
            washAmount = whiteWash
        }

        let resolvedColors = sourceColors.map {
            $0.blended(toward: washTarget, amount: washAmount)
        }
        let count = Double(max(resolvedColors.count, 1))
        let representative = AppThemeColor(
            red: resolvedColors.reduce(0) { $0 + $1.red } / count,
            green: resolvedColors.reduce(0) { $0 + $1.green } / count,
            blue: resolvedColors.reduce(0) { $0 + $1.blue } / count
        )

        let background: ThemeBackground
        switch style.kind {
        case .solid:
            background = .solid((resolvedColors.first ?? .cream).color)
        case .linear:
            let points = style.direction.points
            let stops = zip(activeStops, resolvedColors).map { stop, color in
                AppBackgroundColorStop(
                    id: stop.id,
                    color: color,
                    location: stop.location
                )
            }
            background = .linearGradient(
                stops: stops,
                startPoint: points.start,
                endPoint: points.end
            )
        case .mesh:
            background = .meshGradient(colors: Array(resolvedColors.prefix(9)).map(\.color))
        }

        return ResolvedCustomBackground(
            background: background,
            representativeColor: representative,
            foregroundColor: foreground
        )
    }

    private static func requiredWash(
        for colors: [AppThemeColor],
        foreground: AppThemeColor,
        washTarget: AppThemeColor
    ) -> Double {
        for step in 0 ... 100 {
            let amount = Double(step) / 100
            let isReadable = colors.allSatisfy {
                $0.blended(toward: washTarget, amount: amount)
                    .contrastRatio(with: foreground) >= 4.5
            }
            if isReadable { return amount }
        }
        return 1
    }

}

/// 定义 `AppThemeEnvironmentKey` 的值语义数据与相关行为。
private struct AppThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = Theme.system
}

/// 扩展 `EnvironmentValues`，集中实现当前文件所需的附加能力。
extension EnvironmentValues {
    var appTheme: Theme {
        get { self[AppThemeEnvironmentKey.self] }
        set { self[AppThemeEnvironmentKey.self] = newValue }
    }
}

@MainActor
/// 封装 `ThemeSettings` 的引用语义、状态与业务行为。
final class ThemeSettings: ObservableObject {
    @Published var appearance: AppAppearance {
        didSet { userDefaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }
    @Published var selectedThemeID: AppThemeID {
        didSet {
            userDefaults.set(selectedThemeID.rawValue, forKey: Self.themeKey)
            if usesCustomBackground {
                usesCustomBackground = false
            }
        }
    }
    @Published var selectedAccentPaletteID: AppAccentPaletteID {
        didSet {
            userDefaults.set(selectedAccentPaletteID.rawValue, forKey: Self.accentPaletteKey)
        }
    }
    @Published private(set) var customAccentColor: AppThemeColor {
        didSet {
            Self.persist(
                customAccentColor,
                forKey: Self.customAccentColorKey,
                in: userDefaults
            )
        }
    }
    @Published private(set) var customBackgroundStyle: AppCustomBackgroundStyle {
        didSet {
            Self.persist(
                customBackgroundStyle,
                forKey: Self.customBackgroundStyleKey,
                in: userDefaults
            )
            // Keep the legacy value current so older builds can still recover the primary color.
            Self.persist(
                customBackgroundStyle.primaryColor,
                forKey: Self.customBackgroundColorKey,
                in: userDefaults
            )
        }
    }
    @Published var usesCustomBackground: Bool {
        didSet {
            userDefaults.set(usesCustomBackground, forKey: Self.usesCustomBackgroundKey)
        }
    }
    @Published var liquidGlassCardsEnabled: Bool {
        didSet {
            userDefaults.set(liquidGlassCardsEnabled, forKey: Self.liquidGlassCardsKey)
        }
    }

    var theme: Theme {
        baseTheme
            .applyingAccent(selectedAccentColor)
            .applyingLiquidGlassCards(liquidGlassCardsEnabled)
    }
    var effectiveColorScheme: ColorScheme? { theme.preferredColorScheme ?? appearance.colorScheme }
    var customBackgroundColor: AppThemeColor { customBackgroundStyle.primaryColor }
    var customBackgroundTheme: Theme { Theme.custom(backgroundStyle: customBackgroundStyle) }
    var accentPickerColor: Color {
        selectedAccentPaletteID == .custom
            ? customAccentColor.color
            : (selectedAccentPaletteID.color ?? baseTheme.accentPrimary)
    }
    var backgroundPickerColor: Color {
        usesCustomBackground ? customBackgroundColor.color : selectedThemeID.theme.backgroundPrimary
    }

    private static let appearanceKey = "appAppearance"
    private static let themeKey = "appTheme"
    private static let accentPaletteKey = "appAccentPalette"
    private static let customAccentColorKey = "appCustomAccentColor"
    private static let customBackgroundColorKey = "appCustomBackgroundColor"
    private static let customBackgroundStyleKey = "appCustomBackgroundStyle"
    private static let usesCustomBackgroundKey = "appUsesCustomBackground"
    private static let liquidGlassCardsKey = "appLiquidGlassCardsEnabled"
    private let userDefaults: UserDefaults
    private var baseTheme: Theme {
        usesCustomBackground ? customBackgroundTheme : selectedThemeID.theme
    }
    private var selectedAccentColor: Color? {
        switch selectedAccentPaletteID {
        case .automatic:
            nil
        case .custom:
            customAccentColor.color
        default:
            selectedAccentPaletteID.color
        }
    }

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let storedTheme = userDefaults.string(forKey: Self.themeKey)
        let migratedTheme = Self.migratedThemeID(from: storedTheme)
        let storedAppearance = userDefaults.string(forKey: Self.appearanceKey)
            .flatMap(AppAppearance.init(rawValue:)) ?? .system
        let storedAccentPalette = userDefaults.string(forKey: Self.accentPaletteKey)
            .flatMap(AppAccentPaletteID.init(rawValue:)) ?? .automatic
        let storedCustomAccentColor = Self.restoreColor(
            forKey: Self.customAccentColorKey,
            from: userDefaults,
            fallback: .brandPink
        )
        let storedCustomBackgroundColor = Self.restoreColor(
            forKey: Self.customBackgroundColorKey,
            from: userDefaults,
            fallback: .cream
        )
        let storedCustomBackgroundStyle = Self.restoreBackgroundStyle(
            forKey: Self.customBackgroundStyleKey,
            from: userDefaults,
            fallback: .solid(storedCustomBackgroundColor)
        )

        // Pure Black used to be a separate theme. Preserve its visible result
        // by moving those users to the native theme with Dark appearance.
        appearance = storedTheme == "pureBlack" ? .dark : storedAppearance
        selectedThemeID = migratedTheme
        selectedAccentPaletteID = storedAccentPalette
        customAccentColor = storedCustomAccentColor
        customBackgroundStyle = storedCustomBackgroundStyle
        usesCustomBackground = userDefaults.bool(forKey: Self.usesCustomBackgroundKey)
        liquidGlassCardsEnabled = userDefaults.bool(forKey: Self.liquidGlassCardsKey)

        if userDefaults.string(forKey: Self.accentPaletteKey) != storedAccentPalette.rawValue {
            userDefaults.set(storedAccentPalette.rawValue, forKey: Self.accentPaletteKey)
        }
        Self.persist(storedCustomAccentColor, forKey: Self.customAccentColorKey, in: userDefaults)
        Self.persist(storedCustomBackgroundStyle, forKey: Self.customBackgroundStyleKey, in: userDefaults)
        Self.persist(storedCustomBackgroundStyle.primaryColor, forKey: Self.customBackgroundColorKey, in: userDefaults)

        if storedTheme != nil, storedTheme != migratedTheme.rawValue {
            userDefaults.set(migratedTheme.rawValue, forKey: Self.themeKey)
            if storedTheme == "pureBlack" {
                userDefaults.set(AppAppearance.dark.rawValue, forKey: Self.appearanceKey)
            }
        }
    }

    /// 选择预设应用颜色；自定义颜色仍保留，以便用户稍后重新启用。
    func selectAccentPalette(_ paletteID: AppAccentPaletteID) {
        selectedAccentPaletteID = paletteID
    }

    /// 保存 ColorPicker 产生的任意应用颜色，并立即切换到自定义调色盘。
    func updateCustomAccentColor(_ color: Color) {
        customAccentColor = AppThemeColor.resolved(from: color, fallback: customAccentColor)
        selectedAccentPaletteID = .custom
    }

    /// 选择完整背景预设，并关闭自定义背景，但不丢弃用户已经编辑的颜色。
    func selectBackgroundTheme(_ themeID: AppThemeID) {
        selectedThemeID = themeID
        usesCustomBackground = false
    }

    /// 重新启用上一次保存的自定义背景颜色。
    func selectCustomBackground() {
        usesCustomBackground = true
    }

    /// 保存 ColorPicker 产生的任意背景色，并用它重新派生整套语义主题。
    func updateCustomBackgroundColor(_ color: Color) {
        var style = customBackgroundStyle
        let fallback = style.stops.first?.color ?? .cream
        style.stops[0].color = AppThemeColor.resolved(from: color, fallback: fallback)
        customBackgroundStyle = style
        usesCustomBackground = true
    }

    /// Changes composition mode while preserving all previously edited colors where possible.
    func selectCustomBackgroundKind(_ kind: AppCustomBackgroundKind) {
        customBackgroundStyle = customBackgroundStyle.prepared(for: kind)
        usesCustomBackground = true
    }

    func updateCustomBackgroundColor(_ color: Color, stopID: UUID) {
        guard let index = customBackgroundStyle.stops.firstIndex(where: { $0.id == stopID }) else {
            return
        }
        var style = customBackgroundStyle
        style.stops[index].color = AppThemeColor.resolved(
            from: color,
            fallback: style.stops[index].color
        )
        customBackgroundStyle = style
        usesCustomBackground = true
    }

    func updateCustomGradientLocation(_ location: Double, stopID: UUID) {
        guard customBackgroundStyle.kind == .linear,
              let index = customBackgroundStyle.stops.firstIndex(where: { $0.id == stopID })
        else {
            return
        }

        var style = customBackgroundStyle
        let lowerBound = index == style.stops.startIndex
            ? 0
            : style.stops[index - 1].location + 0.02
        let upperBound = index == style.stops.index(before: style.stops.endIndex)
            ? 1
            : style.stops[index + 1].location - 0.02
        style.stops[index].location = min(max(location, lowerBound), upperBound)
        customBackgroundStyle = style
        usesCustomBackground = true
    }

    func updateCustomGradientDirection(_ direction: AppLinearGradientDirection) {
        var style = customBackgroundStyle
        style.direction = direction
        customBackgroundStyle = style
        usesCustomBackground = true
    }

    func addCustomGradientColor() {
        guard customBackgroundStyle.kind == .linear,
              customBackgroundStyle.stops.count < AppCustomBackgroundStyle.maximumColorCount
        else {
            return
        }

        var style = customBackgroundStyle
        style.stops.sort { $0.location < $1.location }
        guard let insertion = zip(style.stops, style.stops.dropFirst())
            .max(by: { ($0.1.location - $0.0.location) < ($1.1.location - $1.0.location) })
        else {
            return
        }

        let location = (insertion.0.location + insertion.1.location) / 2
        let color = insertion.0.color.blended(toward: insertion.1.color, amount: 0.5)
        style.stops.append(AppBackgroundColorStop(color: color, location: location))
        style.stops.sort { $0.location < $1.location }
        customBackgroundStyle = style
        usesCustomBackground = true
    }

    func removeCustomGradientColor(stopID: UUID) {
        guard customBackgroundStyle.kind == .linear,
              customBackgroundStyle.stops.count > 2
        else {
            return
        }
        var style = customBackgroundStyle
        style.stops.removeAll { $0.id == stopID }
        customBackgroundStyle = style
        usesCustomBackground = true
    }

    /// 封装 `migratedThemeID` 对应的局部行为，供当前类型在统一入口下复用。
    private static func migratedThemeID(from rawValue: String?) -> AppThemeID {
        if let rawValue, let currentTheme = AppThemeID(rawValue: rawValue) {
            return currentTheme
        }

        switch rawValue {
        case "sky", "monoStone", "nebula": return .porcelain
        case "forest": return .sage
        case "graphiteGold", "roseNoir": return .graphite
        case "pureBlack", nil: return .system
        default: return .system
        }
    }

    /// 从 UserDefaults 恢复结构化 sRGB 颜色；数据不存在或损坏时使用安全默认值。
    private static func restoreColor(
        forKey key: String,
        from userDefaults: UserDefaults,
        fallback: AppThemeColor
    ) -> AppThemeColor {
        guard let data = userDefaults.data(forKey: key),
              let color = try? JSONDecoder().decode(AppThemeColor.self, from: data)
        else {
            return fallback
        }
        return color
    }

    private static func restoreBackgroundStyle(
        forKey key: String,
        from userDefaults: UserDefaults,
        fallback: AppCustomBackgroundStyle
    ) -> AppCustomBackgroundStyle {
        guard let data = userDefaults.data(forKey: key),
              let style = try? JSONDecoder().decode(AppCustomBackgroundStyle.self, from: data)
        else {
            return fallback
        }
        return style.sanitized()
    }

    /// 将结构化颜色编码到 UserDefaults，避免依赖 UIColor 或 SwiftUI Color 的非稳定归档格式。
    private static func persist(
        _ color: AppThemeColor,
        forKey key: String,
        in userDefaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(color) else { return }
        userDefaults.set(data, forKey: key)
    }


    private static func persist(
        _ style: AppCustomBackgroundStyle,
        forKey key: String,
        in userDefaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(style.sanitized()) else { return }
        userDefaults.set(data, forKey: key)
    }
}

/// 定义 `AppBackground` 的值语义数据与相关行为。
struct AppBackground: View {
    @Environment(\.appTheme) private var theme

    @ViewBuilder
    var body: some View {
        ThemeBackgroundLayer(background: theme.background)
            .ignoresSafeArea()
    }
}

/// Shared renderer keeps full-screen backgrounds, previews, and swatches visually identical.
struct ThemeBackgroundLayer: View {
    let background: ThemeBackground

    @ViewBuilder
    var body: some View {
        switch background {
        case let .solid(color):
            color
        case let .linearGradient(stops, startPoint, endPoint):
            LinearGradient(
                stops: stops.map {
                    Gradient.Stop(color: $0.color.color, location: CGFloat($0.location))
                },
                startPoint: startPoint,
                endPoint: endPoint
            )
        case let .meshGradient(colors):
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
        }
    }

    private func normalizedMeshColors(_ colors: [Color]) -> [Color] {
        let fallback = colors.last ?? .clear
        return Array((colors + Array(repeating: fallback, count: 9)).prefix(9))
    }
}

/// 定义 `AppContentCardModifier` 的值语义数据与相关行为。
private struct AppContentCardModifier: ViewModifier {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat

    /// 封装 `body` 对应的局部行为，供当前类型在统一入口下复用。
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), theme.liquidGlassCardsEnabled, !reduceTransparency {
            content.glassEffect(
                .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            content
                .background(
                    theme.cardSurface,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(theme.divider.opacity(0.65), lineWidth: 0.5)
                }
        }
    }
}

private struct AppListCardModifier: ViewModifier {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), theme.liquidGlassCardsEnabled, !reduceTransparency {
            // 玻璃必须位于 Row 的完整背景边界；直接修饰 content 会把 Label、footer 等拆成独立胶囊。
            content.listRowBackground(
                Color.clear
                    .glassEffect(
                        .regular,
                        in: .rect(cornerRadius: 20)
                    )
            )
        } else {
            content.listRowBackground(theme.cardSurface)
        }
    }
}

/// 扩展 `View`，集中实现当前文件所需的附加能力。
extension View {
    /// 封装 `appContentCard` 对应的局部行为，供当前类型在统一入口下复用。
    func appContentCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(AppContentCardModifier(cornerRadius: cornerRadius))
    }

    /// Keeps grouped-list rows on a stable surface; SwiftUI sections are not single card shapes.
    func appListCard() -> some View {
        modifier(AppListCardModifier())
    }

    /// 封装 `appSoftScrollEdge` 对应的局部行为，供当前类型在统一入口下复用。
    func appSoftScrollEdge() -> some View {
        modifier(AppSoftScrollEdgeModifier())
    }
}

/// 定义 `AppSoftScrollEdgeModifier` 的值语义数据与相关行为。
private struct AppSoftScrollEdgeModifier: ViewModifier {
    @ViewBuilder
    /// 封装 `body` 对应的局部行为，供当前类型在统一入口下复用。
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .vertical)
        } else {
            content
        }
    }
}
