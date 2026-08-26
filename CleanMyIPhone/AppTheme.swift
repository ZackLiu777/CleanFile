import Combine
import Foundation
import SwiftUI
import UIKit

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

enum ThemeBackground: Sendable {
    case solid(Color)
    case linearGradient(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint)
}

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
    let accentPrimary: Color
    let accentSecondary: Color
    let positiveGreen: Color
    let negativeRed: Color
    let warningOrange: Color
    let divider: Color
    let navigationBackground: Color
    let emptyStateIcon: Color
    let buttonPrimaryBackground: Color
    let buttonDisabledForeground: Color
    let liquidGlassEnabled: Bool
    let preferredColorScheme: ColorScheme?

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
        preferredColorScheme: .light
    )

}

private struct AppThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = Theme.system
}

extension EnvironmentValues {
    var appTheme: Theme {
        get { self[AppThemeEnvironmentKey.self] }
        set { self[AppThemeEnvironmentKey.self] = newValue }
    }
}

@MainActor
final class ThemeSettings: ObservableObject {
    @Published var appearance: AppAppearance {
        didSet { userDefaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }
    @Published var selectedThemeID: AppThemeID {
        didSet { userDefaults.set(selectedThemeID.rawValue, forKey: Self.themeKey) }
    }

    var theme: Theme { selectedThemeID.theme }
    var effectiveColorScheme: ColorScheme? { theme.preferredColorScheme ?? appearance.colorScheme }

    private static let appearanceKey = "appAppearance"
    private static let themeKey = "appTheme"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let storedTheme = userDefaults.string(forKey: Self.themeKey)
        let migratedTheme = Self.migratedThemeID(from: storedTheme)
        let storedAppearance = userDefaults.string(forKey: Self.appearanceKey)
            .flatMap(AppAppearance.init(rawValue:)) ?? .system

        // Pure Black used to be a separate theme. Preserve its visible result
        // by moving those users to the native theme with Dark appearance.
        appearance = storedTheme == "pureBlack" ? .dark : storedAppearance
        selectedThemeID = migratedTheme

        if storedTheme != nil, storedTheme != migratedTheme.rawValue {
            userDefaults.set(migratedTheme.rawValue, forKey: Self.themeKey)
            if storedTheme == "pureBlack" {
                userDefaults.set(AppAppearance.dark.rawValue, forKey: Self.appearanceKey)
            }
        }
    }

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
}

struct AppBackground: View {
    @Environment(\.appTheme) private var theme

    @ViewBuilder
    var body: some View {
        switch theme.background {
        case let .solid(color):
            color.ignoresSafeArea()
        case let .linearGradient(colors, startPoint, endPoint):
            LinearGradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
                .ignoresSafeArea()
        }
    }
}

private struct AppContentCardModifier: ViewModifier {
    @Environment(\.appTheme) private var theme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(theme.divider.opacity(0.65), lineWidth: 0.5)
            }
    }
}

extension View {
    func appContentCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(AppContentCardModifier(cornerRadius: cornerRadius))
    }

    func appSoftScrollEdge() -> some View {
        modifier(AppSoftScrollEdgeModifier())
    }
}

private struct AppSoftScrollEdgeModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .vertical)
        } else {
            content
        }
    }
}
