import Foundation
import SwiftUI
import Testing
@testable import CleanMyIPhone

@Suite("Theme and background edge cases")
struct ThemeEdgeCaseTests {
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
    @Test("Font selection persists and invalid values fall back safely")
    @MainActor
    func fontSelectionPersists() throws {
        let name = "FontPreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(ThemeSettings(userDefaults: defaults).fontStyle == .system)
        for style in AppFontStyle.allCases {
            let settings = ThemeSettings(userDefaults: defaults)
            settings.fontStyle = style
            #expect(ThemeSettings(userDefaults: defaults).fontStyle == style)
        }
        defaults.set("unknown", forKey: "appearance.fontStyle")
        #expect(ThemeSettings(userDefaults: defaults).fontStyle == .system)
    }

    @Test("Appearance choices map to the expected color-scheme policy")
    func appearanceColorSchemePolicyIsStable() {
        #expect(AppAppearance.system.colorScheme == nil)
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
    }

    @Test("Every preset theme exposes a complete theme value")
    func presetThemesAreComplete() {
        for themeID in AppThemeID.allCases {
            let theme = themeID.theme
            #expect(theme.backgroundPrimary != theme.textPrimary)
            #expect(theme.divider != theme.textPrimary)
        }
    }

    @Test("Accent palettes keep automatic and custom modes unset")
    func accentPaletteModesAreExplicit() {
        #expect(AppAccentPaletteID.automatic.color == nil)
        #expect(AppAccentPaletteID.custom.color == nil)
        #expect(AppAccentPaletteID.allCases.filter { $0.color != nil }.count >= 5)
    }

    @Test("Theme color clamps finite components to the sRGB range")
    func themeColorClampsComponents() {
        let color = AppThemeColor(red: -0.5, green: 1.5, blue: 0.25)

        #expect(color.red == 0)
        #expect(color.green == 1)
        #expect(color.blue == 0.25)
    }

    @Test("Background stop clamps its location")
    func stopClampsLocation() {
        #expect(AppBackgroundColorStop(color: .white, location: -1).location == 0)
        #expect(AppBackgroundColorStop(color: .white, location: 2).location == 1)
    }

    @Test("Sanitizing an empty style supplies a safe cream stop")
    func emptyStyleGetsFallbackStop() {
        let style = AppCustomBackgroundStyle(kind: .linear, stops: [], direction: .leftToRight)
        let sanitized = style.sanitized()

        #expect(sanitized.stops.count >= 2)
        #expect(sanitized.stops.first?.color == .cream)
        #expect(sanitized.stops.allSatisfy { $0.location >= 0 && $0.location <= 1 })
    }

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

    @Test("Prepared background modes provide their intended minimum color counts")
    func preparedModesHaveMinimumStops() {
        let source = AppCustomBackgroundStyle.solid(.cream)

        #expect(source.prepared(for: .solid).stops.count == 1)
        #expect(source.prepared(for: .linear).stops.count == 5)
        #expect(source.prepared(for: .mesh).stops.count == 9)
    }

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

    @Test("Gradient direction exposes distinct predictable endpoints")
    func gradientDirectionsExposeEndpoints() {
        #expect(AppLinearGradientDirection.topToBottom.points.start == .top)
        #expect(AppLinearGradientDirection.topToBottom.points.end == .bottom)
        #expect(AppLinearGradientDirection.leftToRight.points.start == .leading)
        #expect(AppLinearGradientDirection.diagonalDown.points.end == .bottomTrailing)
        #expect(AppLinearGradientDirection.diagonalUp.points.start == .bottomLeading)
    }

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

@MainActor
@Suite("Theme settings edge cases")
struct ThemeSettingsEdgeCaseTests {
    @Test("Liquid Glass preference persists and restores")
    func liquidGlassPreferencePersists() {
        let defaults = isolatedDefaults()
        let settings = ThemeSettings(userDefaults: defaults)

        settings.liquidGlassCardsEnabled = true
        let restored = ThemeSettings(userDefaults: defaults)

        #expect(restored.liquidGlassCardsEnabled)
        #expect(restored.theme.liquidGlassCardsEnabled)
    }

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

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "CleanMyIPhone.ThemeEdgeCaseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
