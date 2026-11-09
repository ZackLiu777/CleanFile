//
//  主题与背景边界
//
//  覆盖字体、色彩、渐变、显示偏好和主题设置状态。
//  检查无效值修复、渐变节点数量约束及偏好持久化。
//  覆盖颜色和渐变位置范围、节点数量上下限、字体可用性及外观材料选择。
//  持久化用例使用独立偏好域，避免修改用户当前主题设置。
//

import Foundation
import SwiftUI
import Testing
@testable import CleanMyIPhone

/// 验证主题值及背景输入的校验和显示策略。
@Suite("Theme and background edge cases")
struct ThemeEdgeCaseTests {
    /// 命名字体仅在设备可用时出现在选项中，系统字体无需字体名称。
    @Test("Named font choices are exposed only when available on the device")
    @MainActor
    func namedFontsAreAvailable() {
        for style in [AppFontStyle.avenirNext, .helveticaNeue, .georgia, .palatino] {
            #expect(AppFontStyle.availableCases.contains(style) == (style.fontName != nil))
        }
        #expect(AppFontStyle.availableCases.contains(.system))
        #expect(AppFontStyle.system.fontName == nil)
        #expect(AppFontStyle.rounded.fontName == nil)
    }

    // Required: preferences are isolated from the user's defaults.
    /// 用隔离偏好域检查所有字体选项的保存与恢复，非法值回退默认字体。
    @Test("Font selection persists and invalid values fall back safely")
    @MainActor
    func fontSelectionPersists() throws {
        let name = "FontPreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(ThemeSettings(userDefaults: defaults).fontStyle == .georgia)
        for style in AppFontStyle.allCases {
            let settings = ThemeSettings(userDefaults: defaults)
            settings.fontStyle = style
            #expect(ThemeSettings(userDefaults: defaults).fontStyle == style)
        }
        defaults.set("unknown", forKey: "appearance.fontStyle")
        #expect(ThemeSettings(userDefaults: defaults).fontStyle == .georgia)
    }

    /// 验证跟随系统、浅色和深色选项分别映射到预期颜色方案。
    @Test("Appearance choices map to the expected color-scheme policy")
    func appearanceColorSchemePolicyIsStable() {
        #expect(AppAppearance.system.colorScheme == nil)
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
    }

    /// 检查每个预设的主要背景、分隔线与文本颜色不相同。
    @Test("Every preset theme exposes a complete theme value")
    func presetThemesAreComplete() {
        for themeID in AppThemeID.allCases {
            let theme = themeID.theme
            #expect(theme.backgroundPrimary != theme.textPrimary)
            #expect(theme.divider != theme.textPrimary)
        }
    }

    /// 自动及自定义配色不预设颜色，其他色板提供多个明确颜色。
    @Test("Accent palettes keep automatic and custom modes unset")
    func accentPaletteModesAreExplicit() {
        #expect(AppAccentPaletteID.automatic.color == nil)
        #expect(AppAccentPaletteID.custom.color == nil)
        #expect(AppAccentPaletteID.allCases.filter { $0.color != nil }.count >= 5)
    }

    /// 超出 sRGB 范围的颜色分量被限制在零到一之间。
    @Test("Theme color clamps finite components to the sRGB range")
    func themeColorClampsComponents() {
        let color = AppThemeColor(red: -0.5, green: 1.5, blue: 0.25)

        #expect(color.red == 0)
        #expect(color.green == 1)
        #expect(color.blue == 0.25)
    }

    /// 渐变节点位置超出范围时分别限制到起点和终点。
    @Test("Background stop clamps its location")
    func stopClampsLocation() {
        #expect(AppBackgroundColorStop(color: .white, location: -1).location == 0)
        #expect(AppBackgroundColorStop(color: .white, location: 2).location == 1)
    }

    /// 空渐变样式清理后获得安全的默认颜色及有效节点位置。
    @Test("Sanitizing an empty style supplies a safe cream stop")
    func emptyStyleGetsFallbackStop() {
        let style = AppCustomBackgroundStyle(kind: .linear, stops: [], direction: .leftToRight)
        let sanitized = style.sanitized()

        #expect(sanitized.stops.count >= 2)
        #expect(sanitized.stops.first?.color == .cream)
        #expect(sanitized.stops.allSatisfy { $0.location >= 0 && $0.location <= 1 })
    }

    /// 清理重复渐变节点标识并限制输入数量，避免异常配置破坏渲染。
    @Test("Sanitizing repairs duplicate IDs and limits unbounded stop input")
    func sanitizingRepairsDuplicateAndOversizedInput() {
        let id = UUID()
        let stops = (0 ..< 20).map {
            AppBackgroundColorStop(id: id, color: .brandPink, location: Double($0) / 20)
        }
        let style = AppCustomBackgroundStyle(kind: .mesh, stops: stops, direction: .diagonalDown)
        let sanitized = style.sanitized()

        #expect(sanitized.stops.count == AppCustomBackgroundStyle.maximumColorCount)
        #expect(Set(sanitized.stops.map { $0.id }).count == sanitized.stops.count)
    }

    /// 修复非有限位置值，保证后续渐变计算可用。
    @Test("Sanitizing repairs non-finite locations")
    func sanitizingRepairsNonFiniteLocations() {
        let style = AppCustomBackgroundStyle(
            kind: .linear,
            stops: [
                AppBackgroundColorStop(color: .black, location: .nan),
                AppBackgroundColorStop(color: .white, location: .infinity)
            ],
            direction: .topToBottom
        )

        let locations = style.sanitized().stops.map(\.location)

        #expect(locations.allSatisfy { $0.isFinite })
        #expect(locations.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    /// 从单色准备不同背景模式时，检查单色、线性和网格各自的节点数。
    @Test("Prepared background modes provide their intended minimum color counts")
    func preparedModesHaveMinimumStops() {
        let source = AppCustomBackgroundStyle.solid(.cream)

        #expect(source.prepared(for: .solid).stops.count == 1)
        #expect(source.prepared(for: .linear).stops.count == 5)
        #expect(source.prepared(for: .mesh).stops.count == 9)
    }

    /// 同一组节点用于不同模式时，单色只使用首项而渐变保留九项。
    @Test("Active stops respect the renderer's solid, linear, and mesh limits")
    func activeStopsRespectModeLimits() {
        let stops = (0 ..< 9).map {
            AppBackgroundColorStop(color: .brandPink, location: Double($0) / 8)
        }
        let solid = AppCustomBackgroundStyle(kind: .solid, stops: stops, direction: .diagonalDown)
        let linear = AppCustomBackgroundStyle(kind: .linear, stops: stops, direction: .diagonalDown)
        let mesh = AppCustomBackgroundStyle(kind: .mesh, stops: stops, direction: .diagonalDown)

        #expect(solid.activeStops.count == 1)
        #expect(linear.activeStops.count == 9)
        #expect(mesh.activeStops.count == 9)
    }

    /// 重排乱序渐变位置后，三个节点均匀分布在零、一半和一。
    @Test("Linear stops are redistributed into a monotonic range")
    func redistributeLocationsIsMonotonic() {
        var style = AppCustomBackgroundStyle(
            kind: .linear,
            stops: [
                AppBackgroundColorStop(color: .black, location: 0.9),
                AppBackgroundColorStop(color: .white, location: 0.1),
                AppBackgroundColorStop(color: .brandPink, location: 0.5)
            ],
            direction: .diagonalUp
        )
        style.redistributeLocations()

        #expect(style.stops.map { $0.location } == [0, 0.5, 1])
    }

    /// 检查各方向映射到预期的起点或终点。
    @Test("Gradient direction exposes distinct predictable endpoints")
    func gradientDirectionsExposeEndpoints() {
        #expect(AppLinearGradientDirection.topToBottom.points.start == .top)
        #expect(AppLinearGradientDirection.topToBottom.points.end == .bottom)
        #expect(AppLinearGradientDirection.leftToRight.points.start == .leading)
        #expect(AppLinearGradientDirection.diagonalDown.points.end == .bottomTrailing)
        #expect(AppLinearGradientDirection.diagonalUp.points.start == .bottomLeading)
    }

    /// 为单色、线性和网格背景构造主题，检查语义颜色及颜色方案仍可用。
    @Test("Custom themes resolve all background styles without losing semantic colors")
    func customThemesResolveAllBackgroundStyles() {
        let styles = [
            AppCustomBackgroundStyle.solid(.cream),
            AppCustomBackgroundStyle.solid(.black).prepared(for: .linear),
            AppCustomBackgroundStyle.solid(.white).prepared(for: .mesh)
        ]

        for style in styles {
            let theme = Theme.custom(backgroundStyle: style)
            #expect(theme.accentPrimary != theme.textPrimary)
            #expect(theme.preferredColorScheme != nil)
        }
    }

    /// 启用玻璃卡片只改变材质标记，基础主题颜色和原实例保持不变。
    @Test("Liquid Glass preference changes only the card-material flag")
    func liquidGlassFlagIsIndependentFromColors() {
        let base = Theme.cream
        let glass = base.applyingLiquidGlassCards(true)

        #expect(glass.liquidGlassCardsEnabled)
        #expect(glass.backgroundPrimary == base.backgroundPrimary)
        #expect(glass.accentPrimary == base.accentPrimary)
        #expect(!base.liquidGlassCardsEnabled)
    }
}

/// 验证主题设置持久化及渐变节点编辑约束。
@MainActor
@Suite("Theme settings edge cases")
struct ThemeSettingsEdgeCaseTests {
    @Test("System theme resolves background and text for the same appearance")
    func systemThemeMatchesResolvedAppearance() {
        let defaults = isolatedDefaults()
        defaults.set(AppThemeID.system.rawValue, forKey: "appTheme")
        let settings = ThemeSettings(userDefaults: defaults)
        let light = settings.theme(for: .light)
        let dark = settings.theme(for: .dark)
        let lightBackground = AppThemeColor.resolved(from: light.backgroundPrimary, fallback: .black)
        let lightText = AppThemeColor.resolved(from: light.textPrimary, fallback: .white)
        let darkBackground = AppThemeColor.resolved(from: dark.backgroundPrimary, fallback: .white)
        let darkText = AppThemeColor.resolved(from: dark.textPrimary, fallback: .black)

        #expect(lightBackground.contrastRatio(with: lightText) >= 4.5)
        #expect(darkBackground.contrastRatio(with: darkText) >= 4.5)
        #expect(lightBackground.preferredForeground == .black)
        #expect(darkBackground.preferredForeground == .white)
    }

    /// 在隔离偏好域中保存材质选项，再由新设置实例恢复。
    @Test("Liquid Glass preference persists and restores")
    func liquidGlassPreferencePersists() {
        let defaults = isolatedDefaults()
        let settings = ThemeSettings(userDefaults: defaults)

        #expect(!settings.liquidGlassCardsEnabled)
        settings.liquidGlassCardsEnabled = true
        let restored = ThemeSettings(userDefaults: defaults)

        #expect(restored.liquidGlassCardsEnabled)
        #expect(restored.theme.liquidGlassCardsEnabled)
        restored.liquidGlassCardsEnabled = false
        #expect(!ThemeSettings(userDefaults: defaults).liquidGlassCardsEnabled)
    }

    /// 切换预设时关闭自定义背景，但保留颜色供之后恢复。
    @Test("Changing a preset disables custom background without deleting its colors")
    func selectingPresetKeepsCustomBackgroundForLater() {
        let defaults = isolatedDefaults()
        let settings = ThemeSettings(userDefaults: defaults)
        settings.selectCustomBackgroundKind(.linear)
        let originalStops = settings.customBackgroundStyle.stops

        settings.selectBackgroundTheme(.sage)
        #expect(!settings.usesCustomBackground)

        settings.selectCustomBackground()
        #expect(settings.usesCustomBackground)
        #expect(settings.customBackgroundStyle.stops == originalStops)
    }

    /// 重复添加渐变颜色后，节点数量不会超过配置的上限。
    @Test("Adding gradient colors stops at the configured maximum")
    func addingGradientColorsIsBounded() {
        let defaults = isolatedDefaults()
        let settings = ThemeSettings(userDefaults: defaults)
        settings.selectCustomBackgroundKind(.linear)

        for _ in 0 ..< 20 {
            settings.addCustomGradientColor()
        }

        #expect(settings.customBackgroundStyle.stops.count == AppCustomBackgroundStyle.maximumColorCount)
    }

    /// 移除渐变颜色时保留最低节点数量。
    @Test("Removing gradient colors never removes the final two stops")
    func removingGradientColorsPreservesMinimum() {
        let defaults = isolatedDefaults()
        let settings = ThemeSettings(userDefaults: defaults)
        settings.selectCustomBackgroundKind(.linear)

        while let stop = settings.customBackgroundStyle.stops.first,
              settings.customBackgroundStyle.stops.count > 2 {
            settings.removeCustomGradientColor(stopID: stop.id)
        }
        if let stopID = settings.customBackgroundStyle.stops.first?.id {
            settings.removeCustomGradientColor(stopID: stopID)
        }

        #expect(settings.customBackgroundStyle.stops.count == 2)
    }

    /// 创建唯一的 UserDefaults 测试域，避免读写用户现有主题偏好。
    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "CleanMyIPhone.ThemeEdgeCaseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
