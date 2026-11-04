//
//  状态与主题持久化
//
//  覆盖媒体、文件及仪表盘快照的编码恢复和旧格式兼容。
//  主题用例使用隔离偏好设置，检查默认值、迁移和无效值回退。
//  快照测试还覆盖旧字段名、大小标记和损坏的数据。
//  偏好相关用例使用独立 UserDefaults 域，避免覆盖用户配置。
//

import Foundation
import SwiftUI
import Testing
@testable import CleanMyIPhone

/// 验证业务快照的编码、旧格式读取和损坏数据处理。
@Suite("Persisted state contracts")
struct PersistenceTests {
    /// 编码再解码媒体快照后，相似组、视频分类和部分结果标记均应保留。
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

    /// 验证快照往返保留相对路径和未知大小，而不是依赖临时绝对路径。
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

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(
            FileStateSnapshot.self,
            from: encoded
        )

        #expect(decoded.directoryBookmark == Data([1, 2, 3]))
        #expect(decoded.selectedDirectoryName == "Documents")
        #expect(decoded.files == [PersistedScannedFile(file)])
        #expect(decoded.skippedFileCount == 4)
        #expect(!decoded.requiresRewrite)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("provider/transient-id"))
    }

    /// 旧字段格式仍应被当前快照解码，保护已有用户状态。
    @Test("Legacy file snapshots remain readable after compact persistence")
    func legacyFileSnapshotRemainsReadable() throws {
        let file = ScannedFile(
            url: URL(fileURLWithPath: "/provider/legacy-id"),
            name: "legacy.mov",
            relativePathComponents: ["Videos", "legacy.mov"],
            category: .video,
            byteCount: 42,
            hasKnownByteCount: true
        )
        let legacy = LegacyFileStateSnapshot(
            directoryBookmark: Data([4, 5, 6]),
            selectedDirectoryName: "Videos",
            files: [file],
            skippedFileCount: 0
        )

        let decoded = try JSONDecoder().decode(
            FileStateSnapshot.self,
            from: JSONEncoder().encode(legacy)
        )

        #expect(decoded.files == [PersistedScannedFile(file)])
        #expect(decoded.requiresRewrite)
    }

    /// 仪表盘摘要无需完整文件记录也能保留目录名、统计和跳过数量。
    @Test("Storage dashboard snapshot round-trips without file records")
    func storageDashboardRoundTrip() throws {
        let summary = StorageSummary(
            fileCount: 20_000,
            totalBytes: 8_000_000,
            unknownByteCountFileCount: 2,
            categories: [
                StorageCategorySummary(
                    category: .image,
                    fileCount: 20_000,
                    byteCount: 8_000_000,
                    unknownByteCount: 2,
                    percentage: 1
                )
            ]
        )
        let snapshot = StorageDashboardSnapshot(
            selectedDirectoryName: "Archive",
            summary: summary,
            skippedFileCount: 3
        )

        let decoded = try JSONDecoder().decode(
            StorageDashboardSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        #expect(decoded.selectedDirectoryName == "Archive")
        #expect(decoded.summary == summary)
        #expect(decoded.skippedFileCount == 3)
    }

    /// 全部文件分类经过编码与解码后保持原有枚举值。
    @Test("All file categories retain stable persisted raw values")
    func fileCategoryCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(FileCategory.allCases)
        let decoded = try JSONDecoder().decode([FileCategory].self, from: encoded)

        #expect(decoded == FileCategory.allCases)
    }

    /// 全部视频分类经过编码与解码后保持原有枚举值。
    @Test("All video categories retain stable persisted raw values")
    func videoCategoryCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(VideoCategory.allCases)
        let decoded = try JSONDecoder().decode([VideoCategory].self, from: encoded)

        #expect(decoded == VideoCategory.allCases)
    }

    /// 类型错误的媒体快照必须解码失败，不能当作有效结果恢复。
    @Test("Corrupted media snapshot is rejected")
    func corruptedMediaSnapshotIsRejected() {
        let malformed = Data("{\"result\":false}".utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(MediaStateSnapshot.self, from: malformed)
        }
    }

    /// 损坏的快照数据必须被拒绝，不能伪装成有效状态。
    @Test("Corrupted file snapshot is rejected")
    func corruptedFileSnapshotIsRejected() {
        let malformed = Data("not-json".utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FileStateSnapshot.self, from: malformed)
        }
    }
}

/// 仅供兼容性测试使用的旧快照结构，用来生成历史编码格式。
private struct LegacyFileStateSnapshot: Codable {
    let directoryBookmark: Data
    let selectedDirectoryName: String
    let files: [ScannedFile]
    let skippedFileCount: Int
}

/// 验证隔离偏好中的主题、外观和自定义背景的恢复与迁移。
@MainActor
@Suite("Theme persistence")
struct ThemePersistenceTests {
    /// 无保存值时验证默认主题、强调色、外观及展示偏好的组合。
    @Test("Theme defaults to dark graphite for free users when no value exists")
    func themeDefaultsToGraphite() {
        let defaults = isolatedDefaults()

        let settings = ThemeSettings(userDefaults: defaults)

        #expect(settings.appearance == .system)
        #expect(settings.selectedThemeID == .graphite)
        #expect(!settings.liquidGlassCardsEnabled)
        settings.setPremiumAppearanceAllowed(false)
        #expect(settings.effectiveThemeID == .graphite)
        #expect(!settings.theme.liquidGlassCardsEnabled)
        #expect(settings.selectedAccentPaletteID == .teal)
        #expect(settings.effectiveColorScheme == .dark)
        #expect(settings.interfaceAnimationsEnabled)
        #expect(settings.mediaDateHeadersEnabled)
        #expect(defaults.string(forKey: "appAccentPalette") == "teal")
    }

    /// 用户明确保存的浅色主题不会被新的默认值覆盖。
    @Test("Saved light theme remains selected for free users")
    func savedLightThemeRemainsSelected() {
        let defaults = isolatedDefaults()
        defaults.set(AppThemeID.filevra.rawValue, forKey: "appTheme")
        let settings = ThemeSettings(userDefaults: defaults)
        settings.setPremiumAppearanceAllowed(false)

        #expect(settings.selectedThemeID == .filevra)
        #expect(settings.effectiveThemeID == .filevra)
        #expect(settings.effectiveColorScheme == .light)
    }

    /// 免费用户选择系统主题时仍可使用深色外观。
    @Test("Free users can use dark system appearance")
    func freeUsersCanUseDarkSystemAppearance() {
        let defaults = isolatedDefaults()
        defaults.set(AppThemeID.system.rawValue, forKey: "appTheme")
        defaults.set(AppAppearance.dark.rawValue, forKey: "appAppearance")
        let settings = ThemeSettings(userDefaults: defaults)
        settings.setPremiumAppearanceAllowed(false)

        #expect(settings.effectiveThemeID == .system)
        #expect(settings.effectiveColorScheme == .dark)
    }

    /// 深色主题的自动配色沿用应用蓝色，且与付费权益状态无关。
    @Test("Graphite automatic accent uses the original blue")
    func graphiteAutomaticAccentIsBlue() throws {
        let defaults = isolatedDefaults()
        defaults.set(AppThemeID.graphite.rawValue, forKey: "appTheme")
        defaults.set(AppAccentPaletteID.automatic.rawValue, forKey: "appAccentPalette")
        let settings = ThemeSettings(userDefaults: defaults)
        settings.setPremiumAppearanceAllowed(false)
        let blue = try #require(AppAccentPaletteID.sky.color)

        #expect(settings.effectiveColorScheme == .dark)
        #expect(settings.theme.accentPrimary == blue)
        #expect(settings.theme.buttonPrimaryBackground == blue)
    }

    /// 用户明确选择的其他强调色不会被深色主题的自动配色覆盖。
    @Test("Graphite preserves a saved accent color")
    func graphitePreservesSavedAccent() throws {
        let defaults = isolatedDefaults()
        defaults.set(AppThemeID.graphite.rawValue, forKey: "appTheme")
        defaults.set(AppAccentPaletteID.gold.rawValue, forKey: "appAccentPalette")
        let settings = ThemeSettings(userDefaults: defaults)
        let gold = try #require(AppAccentPaletteID.gold.color)

        #expect(settings.selectedAccentPaletteID == .gold)
        #expect(settings.theme.accentPrimary == gold)
        #expect(settings.effectiveColorScheme == .dark)
    }

    /// 界面动画与媒体日期标题的设置应在重新创建设置对象后恢复。
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

    /// 验证自定义标签栏设置的默认状态及开关后的持久化。
    @Test("System tab bar is the default and custom tab choice persists")
    func customTabBarPreferencePersists() {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: "appLiquidGlassCardsEnabled")
        defaults.set(false, forKey: "appLiquidGlassTabEnabled")

        let settings = ThemeSettings(userDefaults: defaults)
        #expect(!settings.customTabBarEnabled)

        settings.customTabBarEnabled = true
        #expect(ThemeSettings(userDefaults: defaults).customTabBarEnabled)

        settings.customTabBarEnabled = false
        #expect(!ThemeSettings(userDefaults: defaults).customTabBarEnabled)
    }

    /// 已保存的深色外观应在初始化时恢复。
    @Test("Theme restores a persisted dark value")
    func themeRestoresPersistedDarkValue() {
        let defaults = isolatedDefaults()
        defaults.set(AppAppearance.dark.rawValue, forKey: "appAppearance")

        let settings = ThemeSettings(userDefaults: defaults)

        #expect(settings.appearance == .dark)
    }

    /// 无法识别的外观值回退为跟随系统，避免恢复无效状态。
    @Test("Invalid persisted appearance safely falls back to the system")
    func invalidAppearanceFallsBackToSystem() {
        let defaults = isolatedDefaults()
        defaults.set("unsupported", forKey: "appAppearance")

        let settings = ThemeSettings(userDefaults: defaults)

        #expect(settings.appearance == .system)
    }

    /// 修改外观后立即写入偏好，供后续启动恢复。
    @Test("Changing appearance persists immediately")
    func changingAppearancePersistsImmediately() {
        let defaults = isolatedDefaults()
        let settings = ThemeSettings(userDefaults: defaults)

        settings.appearance = .dark

        #expect(defaults.string(forKey: "appAppearance") == AppAppearance.dark.rawValue)
    }

    /// 恢复已保存的强调色，并保留对应的持久化标识。
    @Test("Accent palette restores a persisted value")
    func accentPaletteRestoresPersistedValue() {
        let defaults = isolatedDefaults()
        defaults.set("teal", forKey: "appAccentPalette")

        let settings = ThemeSettings(userDefaults: defaults)

        #expect(settings.selectedAccentPaletteID == .teal)
        #expect(defaults.string(forKey: "appAccentPalette") == "teal")
    }

    /// 无效强调色回退到默认色，并将规范值写回偏好。
    @Test("Invalid accent palette is normalized to Teal")
    func invalidAccentPaletteIsNormalized() {
        let defaults = isolatedDefaults()
        defaults.set("unsupported", forKey: "appAccentPalette")

        let settings = ThemeSettings(userDefaults: defaults)

        #expect(settings.selectedAccentPaletteID == .teal)
        #expect(defaults.string(forKey: "appAccentPalette") == "teal")
    }

    /// 切换强调色后无需等待其他操作即可持久化。
    @Test("Changing accent palette persists immediately")
    func changingAccentPalettePersistsImmediately() {
        let defaults = isolatedDefaults()
        let settings = ThemeSettings(userDefaults: defaults)

        settings.selectedAccentPaletteID = .berry

        #expect(defaults.string(forKey: "appAccentPalette") == "berry")
    }

    /// 自定义强调色的分量与选中状态在重新创建设置对象后保留。
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

    /// 恢复自定义背景并推导深色外观；改选预设后清除自定义状态。
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

    /// 背景颜色与主要、次要文字的对比度均达到用例要求的 4.5。
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

    /// 主题选择可从偏好恢复，更新后独立保存。
    @Test("Theme selection restores and persists independently")
    func themeSelectionRestoresAndPersists() {
        let defaults = isolatedDefaults()
        defaults.set("sage", forKey: "appTheme")

        let settings = ThemeSettings(userDefaults: defaults)

        #expect(settings.selectedThemeID == .sage)

        settings.selectedThemeID = .graphite

        #expect(defaults.string(forKey: "appTheme") == "graphite")
    }

    /// 固定主题的明暗配置优先于独立外观偏好，覆盖相互冲突的组合。
    @Test("Fixed theme appearance takes precedence over the appearance preference")
    func effectiveColorSchemeUsesThemePrecedence() {
        do {
            let defaults = isolatedDefaults()
            let settings = ThemeSettings(userDefaults: defaults)

            #expect(settings.effectiveColorScheme == .dark)
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

    /// 逐项检查旧主题映射，避免升级后丢失用户的外观选择。
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

    /// 旧纯黑主题迁移为系统主题时，同时保留深色外观及持久化值。
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

    /// 创建唯一的偏好域，避免主题测试共享真实应用设置或相互污染。
    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "CleanMyIPhoneTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
