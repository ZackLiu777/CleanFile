//
//  高级功能访问边界
//
//  覆盖免费、验证中、有效及过期权益下的功能访问。
//  检查执行前重新确认权限，以及预览与外观偏好的保留。
//  测试转换策略在执行时重新读取权限，免费用户的选择操作不会直接删除媒体。
//  偏好迁移使用独立 UserDefaults 域；存储预览和资源标识均为合成数据。
//

import Foundation
import ImageFormatConversionKit
import SwiftUI
import Testing
@testable import CleanMyIPhone

/// 检查各类权益状态的功能门禁和偏好保留。
@Suite("Premium feature access")
@MainActor
struct PremiumFeatureAccessTests {
    /// 遍历功能，确认未订阅时只有媒体与视频转换可用。
    @Test("Free access is limited by feature, never by batch size", arguments: PremiumFeature.allCases)
    func freeFeatureMatrix(feature: PremiumFeature) {
        let access = PremiumFeatureAccessStore(accessState: .notEntitled)
        #expect(access.allows(feature) == [.media, .videoConversion].contains(feature))
    }

    /// 权益待验证时保留媒体、视频转换和已保存的高级外观。
    @Test("Pending verification keeps media and video available", arguments: PremiumFeature.allCases)
    func pendingFeatureMatrix(feature: PremiumFeature) {
        let access = PremiumFeatureAccessStore()
        #expect(access.allows(feature) == [.media, .videoConversion].contains(feature))
        #expect(access.preservesPremiumAppearance)
    }

    /// 有效权益应解锁枚举中的每项功能。
    @Test("A valid trial or purchase unlocks every feature", arguments: PremiumFeature.allCases)
    func premiumFeatureMatrix(feature: PremiumFeature) {
        let access = PremiumFeatureAccessStore(accessState: .entitled)
        #expect(access.allows(feature))
    }

    /// 重复完成及取消大批视频转换后仍可预留视频；无效数量和付费格式被拒绝。
    @Test("Video batches stay free after repeated successes and cancellation")
    func unlimitedFreeVideo() throws {
        let access = PremiumFeatureAccessStore(accessState: .notEntitled)
        for _ in 0..<3 {
            let permit = try #require(access.conversionPolicy.reserve(.video, 10_000))
            permit.recordSuccess(10_000)
            permit.finish()
        }
        let cancelled = try #require(access.conversionPolicy.reserve(.video, 1_000))
        cancelled.finish()
        #expect(access.conversionPolicy.reserve(.video, 1_000) != nil)
        #expect(access.conversionPolicy.reserve(.images, 1) == nil)
        #expect(access.conversionPolicy.reserve(.audio, 1) == nil)
        #expect(access.conversionPolicy.reserve(.video, 0) == nil)
        #expect(access.conversionPolicy.reserve(.video, -1) == nil)
    }

    /// 已创建的转换策略在真正执行时重新检查权益变化。
    @Test("A retained conversion policy rechecks ownership at execution")
    func upgradeAndExpiration() throws {
        let access = PremiumFeatureAccessStore(accessState: .notEntitled)
        let policy = access.conversionPolicy
        #expect(!policy.allows(.images))
        #expect(policy.reserve(.images, 1) == nil)
        access.update(.entitled)
        for category in [ConversionUsageCategory.images, .video, .audio] {
            #expect(policy.allows(category))
            let permit = try #require(policy.reserve(category, 1_000))
            permit.recordSuccess(1_000)
            permit.finish()
        }
        access.update(.notEntitled)
        #expect(!policy.allows(.images))
        #expect(policy.reserve(.images, 1) == nil)
        #expect(policy.reserve(.audio, 1) == nil)
        #expect(policy.reserve(.video, 1_000) != nil)
        #expect(access.allows(.media))
        #expect(!access.allows(.storage))
    }

    /// 检查旧配额数据、地区设置变化及重新创建访问状态不会解锁付费功能。
    @Test("Old free counters and calendar preferences cannot unlock paid features")
    func obsoleteQuotaAndRelaunch() throws {
        let domain = "FilevraFeatureMigrationTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(Data(#"{"day":999999999999,"used":{"images":-100},"resetAt":0}"#.utf8),
                     forKey: "filevra.freeUsage.v1")
        for locale in ["en_US", "zh_CN", "ar_SA"] {
            defaults.set(locale, forKey: "AppleLocale")
            let access = PremiumFeatureAccessStore(accessState: .notEntitled)
            #expect(access.allows(.media))
            #expect(access.conversionPolicy.reserve(.video, 1_000) != nil)
            #expect(access.conversionPolicy.reserve(.images, 1) == nil)
            #expect(access.conversionPolicy.reserve(.audio, 1) == nil)
        }
        defaults.removePersistentDomain(forName: domain)
        let reinstalled = PremiumFeatureAccessStore(accessState: .notEntitled)
        #expect(!reinstalled.allows(.storage))
        #expect(!reinstalled.allows(.customColors))
        #expect(reinstalled.conversionPolicy.reserve(.images, 1) == nil)
    }

    /// 没有权益时阻止恢复、扫描和删除等存储操作。
    @Test("Storage cannot start restoration, scans, or deletion without access")
    func storageExecutionGate() async {
        let access = PremiumFeatureAccessStore(accessState: .notEntitled)
        let model = FileScannerViewModel(canUseStorage: { access.allows(.storage) })
        let url = URL(fileURLWithPath: "/filevra-feature-test-not-an-existing-folder")
        model.loadIfNeeded()
        model.scan(directory: url)
        model.scan(sources: [url])
        await model.deleteFiles(withURLs: [url])
        #expect(!model.state.isScanning)
        #expect(model.files.isEmpty)
        #expect(model.selectedDirectoryName == nil)
        #expect(!model.isRestoringStoredFiles)
        #expect(model.deletionState == .idle)
    }

    /// 免费用户可浏览和选择候选，但执行清理仍需通过权限检查。
    @Test("Free users can select quick cleanup items but execution still requires Premium")
    func quickCleanExecutionGate() async {
        let access = PremiumFeatureAccessStore(accessState: .notEntitled)
        let library = PhotoLibraryViewModel()
        var accessChecks = 0
        let model = MediaQuickCleanViewModel(photoLibrary: library, canUseQuickClean: {
            accessChecks += 1
            return access.allows(.quickClean)
        })
        let category = MediaQuickCleanViewModel.Category(
            id: .screenshots, title: "Screenshots", systemImage: "iphone", assetIDs: ["example"]
        )
        model.toggle(category)
        #expect(model.selectedCategoryIDs == [.screenshots])
        #expect(accessChecks == 0)
        let rejected = await model.deleteSelection()
        #expect(!rejected)
        #expect(accessChecks == 1)
        #expect(model.selectedCategoryIDs == [.screenshots])
        #expect(library.deletionState == .idle)

        model.toggle(category)
        #expect(model.selectedCategoryIDs.isEmpty)
        model.toggleAllCategories()
        #expect(accessChecks == 1)
        access.update(.entitled)
        model.toggle(category)
        access.update(.notEntitled)
        let expired = await model.deleteSelection()
        #expect(!expired)
        #expect(model.selectedCategoryIDs == [.screenshots])
        #expect(library.deletionState == .idle)
        #expect(access.allows(.media))
        #expect(!access.allows(.quickClean))
    }

    /// 解锁存储权限本身不会伪造选择的目录、汇总或文件树。
    @Test("Unlocking storage does not fabricate a selected source or consume its preview")
    @MainActor
    func storageUnlockPreservesNoSourceState() {
        var allowed = false
        let scanner = FileScannerViewModel(canUseStorage: { allowed })
        #expect(!scanner.hasSelectedStorageSource)
        allowed = true
        #expect(!scanner.hasSelectedStorageSource)
        #expect(scanner.summary == nil)
        #expect(scanner.fileTree == nil)
    }

    /// 重复生成预览并核对树叶节点与分类数量、字节汇总及标识的一致性。
    @Test("The storage preview is deterministic and its summary matches its URL-free tree")
    func storagePreviewConsistency() {
        let preview = StorageDashboardPreview.make()
        let repeated = StorageDashboardPreview.make()
        #expect(preview.summary == repeated.summary)
        #expect(preview.fileTree == repeated.fileTree)
        #expect(preview.summary.fileCount == 190)
        #expect(preview.summary.totalBytes == 9_560_000_000)
        #expect(preview.fileTree.byteCount == preview.summary.totalBytes)
        #expect(preview.summary.unknownByteCountFileCount == 0)
        #expect(preview.summary.nonEmptyCategories.count == FileCategory.allCases.count)

        /// 递归收集预览树中的文件叶节点，用于与分类统计逐项对照。
        func leaves(_ node: FileNode) -> [FileNode] {
            node.isDirectory ? node.children.flatMap(leaves) : [node]
        }
        let files = leaves(preview.fileTree)
        #expect(files.count == preview.summary.fileCount)
        #expect(Set(files.map(\.id)).count == files.count)
        #expect(files.allSatisfy { $0.id.hasPrefix("preview/") && $0.byteCount > 0 })
        for category in preview.summary.categories {
            let categoryFiles = files.filter { $0.category == category.category }
            #expect(categoryFiles.count == category.fileCount)
            #expect(categoryFiles.reduce(Int64.zero) { $0 + $1.byteCount } == category.byteCount)
        }
        #expect(FileTreeDiagnostics.maximumDepth(of: preview.fileTree) >= 4)
    }

    /// 无高级权益时允许免费浅色主题，拒绝高级主题及自定义颜色生效。
    @Test("Light preset themes remain free", arguments: [AppThemeID.system, .cream, .porcelain, .sage])
    func freeLightThemes(themeID: AppThemeID) throws {
        let domain = "FilevraFreeThemesTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = ThemeSettings(userDefaults: defaults)
        settings.setPremiumAppearanceAllowed(false)
        settings.selectBackgroundTheme(themeID)
        #expect(settings.effectiveThemeID == themeID)
        #expect(settings.effectiveColorScheme == .light)
        settings.selectBackgroundTheme(.graphite)
        #expect(settings.effectiveThemeID == themeID)
        settings.selectCustomBackground()
        settings.updateCustomAccentColor(.red)
        settings.updateCustomBackgroundColor(.black)
        #expect(!settings.isUsingCustomBackground)
        #expect(settings.effectiveAccentPaletteID != .custom)
    }

    /// 权益过期后回退有效外观，但重建设置并恢复权益后仍可找回原偏好。
    @Test("Expired access hides premium appearance while preserving preferences through relaunch")
    func preservesThemePreferences() throws {
        let domain = "FilevraPremiumThemeRestoreTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = ThemeSettings(userDefaults: defaults)
        settings.selectBackgroundTheme(.graphite)
        settings.appearance = .dark
        settings.updateCustomAccentColor(.red)
        settings.updateCustomBackgroundColor(.black)
        let color = settings.customAccentColor
        let background = settings.customBackgroundStyle
        settings.setPremiumAppearanceAllowed(false)
        #expect(settings.effectiveThemeID == .cream)
        #expect(settings.effectiveColorScheme == .light)
        #expect(!settings.isUsingCustomBackground)
        #expect(settings.effectiveAccentPaletteID == .automatic)
        #expect(settings.selectedThemeID == .graphite)
        #expect(settings.usesCustomBackground)
        let restored = ThemeSettings(userDefaults: defaults)
        restored.setPremiumAppearanceAllowed(false)
        #expect(restored.effectiveColorScheme == .light)
        restored.setPremiumAppearanceAllowed(true)
        #expect(restored.isUsingCustomBackground)
        #expect(restored.effectiveThemeID == .graphite)
        #expect(restored.effectiveAccentPaletteID == .custom)
        #expect(restored.customAccentColor == color)
        #expect(restored.customBackgroundStyle == background)
        #expect(restored.effectiveColorScheme == .dark)
    }

    /// 权益尚未确认时保留偏好；确认过期后才允许回退外观。
    @Test("Unknown ownership preserves saved appearance; confirmed expiration enables fallback")
    func pendingAppearance() {
        let access = PremiumFeatureAccessStore()
        #expect(access.preservesPremiumAppearance)
        access.update(.entitled)
        #expect(access.preservesPremiumAppearance)
        access.update(.checking)
        #expect(access.preservesPremiumAppearance)
        access.update(.notEntitled)
        #expect(!access.preservesPremiumAppearance)
        access.update(.checking)
        #expect(!access.preservesPremiumAppearance)
        #expect(!access.allows(.darkAppearance))
        #expect(!access.allows(.customColors))
        access.update(.entitled)
        #expect(access.preservesPremiumAppearance)

        let confirmedFree = PremiumFeatureAccessStore(accessState: .notEntitled)
        confirmedFree.update(.checking)
        #expect(!confirmedFree.preservesPremiumAppearance)
    }
}
