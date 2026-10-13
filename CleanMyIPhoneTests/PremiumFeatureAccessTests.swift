import Foundation
import ImageFormatConversionKit
import SwiftUI
import Testing
@testable import CleanMyIPhone

@Suite("Premium feature access")
@MainActor
struct PremiumFeatureAccessTests {
    @Test("Free access is limited by feature, never by batch size", arguments: PremiumFeature.allCases)
    func freeFeatureMatrix(feature: PremiumFeature) {
        let access = PremiumFeatureAccessStore(accessState: .notEntitled)
        #expect(access.allows(feature) == [.media, .videoConversion].contains(feature))
    }

    @Test("Pending verification keeps media and video available", arguments: PremiumFeature.allCases)
    func pendingFeatureMatrix(feature: PremiumFeature) {
        let access = PremiumFeatureAccessStore()
        #expect(access.allows(feature) == [.media, .videoConversion].contains(feature))
        #expect(access.preservesPremiumAppearance)
    }

    @Test("A valid trial or purchase unlocks every feature", arguments: PremiumFeature.allCases)
    func premiumFeatureMatrix(feature: PremiumFeature) {
        let access = PremiumFeatureAccessStore(accessState: .entitled)
        #expect(access.allows(feature))
    }

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

    @Test("Quick cleanup rechecks access for selection and execution without locking ordinary media")
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
        #expect(model.selectedCategoryIDs.isEmpty)
        #expect(accessChecks == 1)
        model.toggleAllCategories()
        #expect(accessChecks == 2)
        let rejected = await model.deleteSelection()
        #expect(!rejected)
        #expect(accessChecks == 3)
        #expect(library.deletionState == .idle)

        access.update(.entitled)
        model.toggle(category)
        #expect(model.selectedCategoryIDs == [.screenshots])
        access.update(.notEntitled)
        model.toggle(category)
        #expect(model.selectedCategoryIDs == [.screenshots])
        let expired = await model.deleteSelection()
        #expect(!expired)
        #expect(library.deletionState == .idle)
        #expect(access.allows(.media))
        #expect(!access.allows(.quickClean))
    }

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
