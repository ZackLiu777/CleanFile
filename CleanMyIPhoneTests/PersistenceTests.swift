import Foundation
import SwiftUI
import Testing
@testable import CleanMyIPhone

@Suite("Persisted state contracts")
struct PersistenceTests {
    @Test("Media snapshot preserves complete analysis state")
    func mediaSnapshotRoundTrip() throws {
        let result = MediaClassificationResult(
            similarImageGroups: [
                SimilarImageGroup(
                    id: "group",
                    items: [
                        SimilarImageItem(id: "one", pixelWidth: 10, pixelHeight: 20, creationDate: Date(timeIntervalSince1970: 10)),
                        SimilarImageItem(id: "two", pixelWidth: 30, pixelHeight: 40, creationDate: nil)
                    ],
                    suggestedKeeperID: "two"
                )
            ],
            classifiedVideos: [
                ClassifiedVideo(
                    id: "video",
                    duration: 42,
                    pixelWidth: 3_840,
                    pixelHeight: 2_160,
                    categories: [.fourK, .screenRecording]
                )
            ],
            screenshotIDs: ["shot"],
            livePhotoIDs: ["live"],
            skippedImageCount: 2
        )
        let snapshot = MediaStateSnapshot(result: result, isPartial: true)

        let decoded = try JSONDecoder().decode(
            MediaStateSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        #expect(decoded.result == result)
        #expect(decoded.isPartial)
    }

    @Test("File snapshot preserves relative paths and unknown sizes")
    func fileSnapshotRoundTrip() throws {
        let file = ScannedFile(
            url: URL(fileURLWithPath: "/provider/transient-id"),
            name: "cloud.pdf",
            relativePathComponents: ["Documents", "cloud.pdf"],
            category: .pdf,
            byteCount: 0,
            hasKnownByteCount: false,
            creationDate: Date(timeIntervalSince1970: 20),
            modificationDate: Date(timeIntervalSince1970: 30)
        )
        let snapshot = FileStateSnapshot(
            directoryBookmark: Data([1, 2, 3]),
            selectedDirectoryName: "Documents",
            files: [file],
            skippedFileCount: 4
        )

        let decoded = try JSONDecoder().decode(
            FileStateSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        #expect(decoded.directoryBookmark == Data([1, 2, 3]))
        #expect(decoded.selectedDirectoryName == "Documents")
        #expect(decoded.files == [file])
        #expect(decoded.skippedFileCount == 4)
    }

    @Test("All file categories retain stable persisted raw values")
    func fileCategoryCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(FileCategory.allCases)
        let decoded = try JSONDecoder().decode([FileCategory].self, from: encoded)

        #expect(decoded == FileCategory.allCases)
    }

    @Test("All video categories retain stable persisted raw values")
    func videoCategoryCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(VideoCategory.allCases)
        let decoded = try JSONDecoder().decode([VideoCategory].self, from: encoded)

        #expect(decoded == VideoCategory.allCases)
    }

    @Test("Corrupted media snapshot is rejected")
    func corruptedMediaSnapshotIsRejected() {
        let malformed = Data("{\"result\":false}".utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(MediaStateSnapshot.self, from: malformed)
        }
    }

    @Test("Corrupted file snapshot is rejected")
    func corruptedFileSnapshotIsRejected() {
        let malformed = Data("not-json".utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FileStateSnapshot.self, from: malformed)
        }
    }
}

@MainActor
@Suite("Theme persistence")
struct ThemePersistenceTests {
    @Test("Theme follows the system when no value exists")
    func themeDefaultsToSystem() {
        let defaults = isolatedDefaults()

        let settings = ThemeSettings(userDefaults: defaults)

        #expect(settings.appearance == .system)
        #expect(settings.selectedThemeID == .system)
        #expect(settings.selectedAccentPaletteID == .automatic)
        #expect(settings.effectiveColorScheme == nil)
        #expect(settings.interfaceAnimationsEnabled)
        #expect(settings.mediaDateHeadersEnabled)
        #expect(defaults.string(forKey: "appAccentPalette") == "automatic")
    }

    @Test("Display preferences persist and restore")
    func displayPreferencesPersist() {
        let defaults = isolatedDefaults()
        let settings = ThemeSettings(userDefaults: defaults)

        settings.interfaceAnimationsEnabled = false
        settings.mediaDateHeadersEnabled = false
        let restored = ThemeSettings(userDefaults: defaults)

        #expect(!restored.interfaceAnimationsEnabled)
        #expect(!restored.mediaDateHeadersEnabled)
    }

    @Test("Theme restores a persisted dark value")
    func themeRestoresPersistedDarkValue() {
        let defaults = isolatedDefaults()
        defaults.set(AppAppearance.dark.rawValue, forKey: "appAppearance")

        let settings = ThemeSettings(userDefaults: defaults)

        #expect(settings.appearance == .dark)
    }

    @Test("Invalid persisted appearance safely falls back to the system")
    func invalidAppearanceFallsBackToSystem() {
        let defaults = isolatedDefaults()
        defaults.set("unsupported", forKey: "appAppearance")

        let settings = ThemeSettings(userDefaults: defaults)

        #expect(settings.appearance == .system)
    }

    @Test("Changing appearance persists immediately")
    func changingAppearancePersistsImmediately() {
        let defaults = isolatedDefaults()
        let settings = ThemeSettings(userDefaults: defaults)

        settings.appearance = .dark

        #expect(defaults.string(forKey: "appAppearance") == AppAppearance.dark.rawValue)
    }

    @Test("Accent palette restores a persisted value")
    func accentPaletteRestoresPersistedValue() {
        let defaults = isolatedDefaults()
        defaults.set("teal", forKey: "appAccentPalette")

        let settings = ThemeSettings(userDefaults: defaults)

        #expect(settings.selectedAccentPaletteID == .teal)
        #expect(defaults.string(forKey: "appAccentPalette") == "teal")
    }

    @Test("Invalid accent palette is normalized to automatic")
    func invalidAccentPaletteIsNormalized() {
        let defaults = isolatedDefaults()
        defaults.set("unsupported", forKey: "appAccentPalette")

        let settings = ThemeSettings(userDefaults: defaults)

        #expect(settings.selectedAccentPaletteID == .automatic)
        #expect(defaults.string(forKey: "appAccentPalette") == "automatic")
    }

    @Test("Changing accent palette persists immediately")
    func changingAccentPalettePersistsImmediately() {
        let defaults = isolatedDefaults()
        let settings = ThemeSettings(userDefaults: defaults)

        settings.selectedAccentPaletteID = .berry

        #expect(defaults.string(forKey: "appAccentPalette") == "berry")
    }

    @Test("Custom app color persists and restores as the active palette")
    func customAccentColorPersistsAndRestores() {
        let defaults = isolatedDefaults()
        let settings = ThemeSettings(userDefaults: defaults)

        settings.updateCustomAccentColor(
            Color(.sRGB, red: 0.18, green: 0.42, blue: 0.76, opacity: 1)
        )
        let restored = ThemeSettings(userDefaults: defaults)

        #expect(settings.selectedAccentPaletteID == .custom)
        #expect(restored.selectedAccentPaletteID == .custom)
        #expect(abs(restored.customAccentColor.red - 0.18) < 0.001)
        #expect(abs(restored.customAccentColor.green - 0.42) < 0.001)
        #expect(abs(restored.customAccentColor.blue - 0.76) < 0.001)
    }

    @Test("Custom background persists and derives a readable appearance")
    func customBackgroundPersistsAndRestores() {
        let defaults = isolatedDefaults()
        let settings = ThemeSettings(userDefaults: defaults)

        settings.updateCustomBackgroundColor(
            Color(.sRGB, red: 0.04, green: 0.06, blue: 0.09, opacity: 1)
        )
        let restored = ThemeSettings(userDefaults: defaults)

        #expect(restored.usesCustomBackground)
        #expect(restored.effectiveColorScheme == .dark)
        #expect(abs(restored.customBackgroundColor.red - 0.04) < 0.001)
        #expect(abs(restored.customBackgroundColor.green - 0.06) < 0.001)
        #expect(abs(restored.customBackgroundColor.blue - 0.09) < 0.001)

        restored.selectBackgroundTheme(.cream)

        #expect(!restored.usesCustomBackground)
        #expect(restored.effectiveColorScheme == .light)
        #expect(!defaults.bool(forKey: "appUsesCustomBackground"))
    }

    @Test("Custom background color math maintains readable text contrast")
    func customBackgroundMaintainsTextContrast() {
        let background = AppThemeColor(red: 0.52, green: 0.48, blue: 0.44)
        let primary = background.preferredForeground
        let secondary = background.contrastingVariant(
            toward: primary,
            minimumRatio: 4.5
        )

        #expect(background.contrastRatio(with: primary) >= 4.5)
        #expect(background.contrastRatio(with: secondary) >= 4.5)
    }

    @Test("Theme selection restores and persists independently")
    func themeSelectionRestoresAndPersists() {
        let defaults = isolatedDefaults()
        defaults.set("sage", forKey: "appTheme")

        let settings = ThemeSettings(userDefaults: defaults)

        #expect(settings.selectedThemeID == .sage)

        settings.selectedThemeID = .graphite

        #expect(defaults.string(forKey: "appTheme") == "graphite")
    }

    @Test("Fixed theme appearance takes precedence over the appearance preference")
    func effectiveColorSchemeUsesThemePrecedence() {
        do {
            let defaults = isolatedDefaults()
            let settings = ThemeSettings(userDefaults: defaults)

            #expect(settings.effectiveColorScheme == nil)
        }

        do {
            let defaults = isolatedDefaults()
            defaults.set("dark", forKey: "appAppearance")
            let settings = ThemeSettings(userDefaults: defaults)

            #expect(settings.effectiveColorScheme == .dark)
        }

        do {
            let defaults = isolatedDefaults()
            defaults.set("dark", forKey: "appAppearance")
            defaults.set("cream", forKey: "appTheme")
            let settings = ThemeSettings(userDefaults: defaults)

            #expect(settings.effectiveColorScheme == .light)
        }

        do {
            let defaults = isolatedDefaults()
            defaults.set("light", forKey: "appAppearance")
            defaults.set("graphite", forKey: "appTheme")
            let settings = ThemeSettings(userDefaults: defaults)

            #expect(settings.effectiveColorScheme == .dark)
        }
    }

    @Test("Every legacy decorative theme migrates to its restrained replacement")
    func legacyThemesAreMigrated() {
        let migrations: [(storedValue: String, expectedTheme: AppThemeID)] = [
            ("sky", .porcelain),
            ("monoStone", .porcelain),
            ("nebula", .porcelain),
            ("forest", .sage),
            ("graphiteGold", .graphite),
            ("roseNoir", .graphite)
        ]

        for migration in migrations {
            let defaults = isolatedDefaults()
            defaults.set(migration.storedValue, forKey: "appTheme")

            let settings = ThemeSettings(userDefaults: defaults)

            #expect(settings.selectedThemeID == migration.expectedTheme)
            #expect(
                defaults.string(forKey: "appTheme") == migration.expectedTheme.rawValue,
                "Failed to migrate legacy theme \(migration.storedValue)"
            )
        }
    }

    @Test("Legacy Pure Black preserves a dark appearance")
    func legacyPureBlackPreservesDarkAppearance() {
        let defaults = isolatedDefaults()
        defaults.set("pureBlack", forKey: "appTheme")

        let settings = ThemeSettings(userDefaults: defaults)

        #expect(settings.selectedThemeID == .system)
        #expect(settings.appearance == .dark)
        #expect(defaults.string(forKey: "appTheme") == AppThemeID.system.rawValue)
        #expect(defaults.string(forKey: "appAppearance") == AppAppearance.dark.rawValue)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "CleanMyIPhoneTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
