// 免费用户与高级功能入口的界面测试。
//
// 覆盖未购买时的导航、离线购买界面、不同语言布局以及各功能的访问边界。
// 测试使用受控启动状态，不依赖真实商店购买，也不对真实用户媒体执行删除。
// 同时检查付费墙的退出路径、离线价格状态，以及免费与高级入口的差异。

import XCTest

/// 验证免费用户的导航、购买入口与功能访问边界。
final class PremiumFreeTierUITests: XCTestCase {
    /// 在断言失败时停止当前用例，避免后续操作掩盖最初失败。
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 验证免费状态下主要导航可用，且不出现相关配额文案。
    @MainActor
    func testFreeUserCanReachPrimaryAndSecondaryNavigationWithoutPurchasing() {
        let app = launchFreeApp()
        for (id, label) in [
            ("tab.storage", "Storage"),
            ("tab.convert", "Convert"),
            ("tab.settings", "Settings")
        ] {
            let element = tab(in: app, id: id, label: label)
            XCTAssertTrue(element.waitForExistence(timeout: 5))
            element.tap()
        }
        XCTAssertFalse(app.staticTexts["quota.title"].exists)
        XCTAssertFalse(app.staticTexts["quota.cleanup.remaining"].exists)
        XCTAssertTrue(app.buttons["settings.appearance"].exists)
    }

    /// 离线时验证购买页的关闭和继续免费使用入口均能返回设置。
    @MainActor
    func testPaywallHasTopRightCloseAndContinueFreeWithoutStoreConnectivity() {
        let app = launchFreeApp()
        tab(in: app, id: "tab.settings", label: "Settings").tap()
        let premium = app.buttons["settings.premium"]
        XCTAssertTrue(premium.waitForExistence(timeout: 5))
        premium.tap()
        let close = app.buttons["premium.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "premium.close").count, 1)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Close")).count, 1)
        XCTAssertGreaterThan(close.frame.midX, app.frame.midX)
        close.tap()
        XCTAssertTrue(premium.waitForExistence(timeout: 5))

        premium.tap()
        let continueFree = app.buttons["premium.continueFree"]
        for _ in 0..<8 where !continueFree.isHittable { app.swipeUp() }
        XCTAssertTrue(continueFree.exists && continueFree.isHittable)
        continueFree.tap()
        XCTAssertTrue(premium.waitForExistence(timeout: 5))
    }

    /// 检查离线时所有方案仍可访问，但不可发起缺少商店信息的购买。
    @MainActor
    func testCustomPaywallShowsAllPlansOfflineWithoutOfferingInventedPrices() {
        let app = launchFreeApp()
        tab(in: app, id: "tab.settings", label: "Settings").tap()
        let premium = app.buttons["settings.premium"]
        XCTAssertTrue(premium.waitForExistence(timeout: 5))
        premium.tap()
        let purchase = app.buttons["premium.purchase"]
        XCTAssertTrue(purchase.waitForExistence(timeout: 5))
        XCTAssertFalse(purchase.isEnabled)
        XCTAssertTrue(app.buttons["premium.restore"].exists)
        XCTAssertTrue(app.buttons["premium.continueFree"].isHittable)
        let scrollView = app.scrollViews.containing(.button, identifier: "premium.plan.annual").firstMatch
        XCTAssertTrue(scrollView.exists)
        for id in ["premium.plan.annual", "premium.plan.monthly", "premium.plan.lifetime"] {
            let plan = app.buttons[id]
            for _ in 0..<12 where !plan.isHittable || plan.frame.maxY > purchase.frame.minY {
                scrollPaywallContent(scrollView)
            }
            XCTAssertTrue(plan.exists && plan.isHittable)
            XCTAssertLessThanOrEqual(plan.frame.maxY, purchase.frame.minY)
            plan.tap()
        }
        XCTAssertFalse(app.staticTexts["FileCleaner"].exists)
        XCTAssertFalse(purchase.isEnabled)
        app.buttons["premium.continueFree"].tap()
        XCTAssertTrue(premium.waitForExistence(timeout: 5))
    }

    /// 使用简体中文启动，验证购买页控件采用应用本地化文案。
    @MainActor
    func testPaywallWordingUsesAppLanguageInsteadOfStoreProductNames() {
        let app = launchFreeApp(language: "zh-Hans")
        tab(in: app, id: "tab.settings", label: "Settings").tap()
        let premium = app.buttons["settings.premium"]
        XCTAssertTrue(premium.waitForExistence(timeout: 5))
        premium.tap()
        XCTAssertTrue(app.buttons["premium.close"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["premium.close"].label, "关闭")
        XCTAssertEqual(app.buttons["premium.continueFree"].label, "继续免费使用")
        let annual = app.buttons["premium.plan.annual"]
        for _ in 0..<8 where !annual.isHittable { app.swipeUp() }
        XCTAssertTrue(annual.isHittable)
        XCTAssertTrue(annual.label.contains("年度订阅"))
        XCTAssertFalse(annual.label.contains("Annual Subscription"))
    }

    /// 检查多语言下高级功能操作按钮的宽度、对齐和间距。
    @MainActor
    func testPremiumActionsAreFullWidthAlignedAndSeparatedInMultipleLanguages() {
        for language in ["en", "zh-Hans", "de", "ar"] {
            let app = launchFreeApp(language: language)
            tab(in: app, id: "tab.settings", label: "Settings").tap()
            let premium = app.buttons["settings.premium"]
            XCTAssertTrue(premium.waitForExistence(timeout: 5))
            premium.tap()
            let purchase = app.buttons["premium.purchase"]
            let restore = app.buttons["premium.restore"]
            let free = app.buttons["premium.continueFree"]
            XCTAssertTrue(purchase.waitForExistence(timeout: 5))
            XCTAssertTrue(restore.isHittable, "Restore should remain reachable: " + language)
            XCTAssertTrue(free.isHittable, "Free access should remain reachable: " + language)
            XCTAssertEqual(purchase.frame.minX, restore.frame.minX, accuracy: 1)
            XCTAssertEqual(purchase.frame.width, restore.frame.width, accuracy: 1)
            XCTAssertEqual(purchase.frame.minX, free.frame.minX, accuracy: 1)
            XCTAssertEqual(purchase.frame.width, free.frame.width, accuracy: 1)
            XCTAssertEqual(purchase.frame.midX, app.frame.midX, accuracy: 1)
            XCTAssertLessThan(purchase.frame.maxY, restore.frame.minY)
            XCTAssertLessThan(restore.frame.maxY, free.frame.minY)
            XCTAssertGreaterThanOrEqual(purchase.frame.height, 44)
            XCTAssertGreaterThanOrEqual(restore.frame.height, 44)
            XCTAssertGreaterThanOrEqual(free.frame.height, 44)
            XCTAssertFalse(purchase.isEnabled, "Missing prices must still prevent purchasing")
            XCTAssertEqual(app.buttons.matching(identifier: "premium.close").count, 1)
            free.tap()
            XCTAssertTrue(premium.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    /// 检查固定操作区上方的方案和条款内容可通过滚动到达。
    @MainActor
    func testPremiumPlansAndTermsRemainReachableAboveTheFixedActions() {
        let app = launchFreeApp()
        tab(in: app, id: "tab.settings", label: "Settings").tap()
        let premium = app.buttons["settings.premium"]
        XCTAssertTrue(premium.waitForExistence(timeout: 5))
        premium.tap()
        let purchase = app.buttons["premium.purchase"]
        XCTAssertTrue(purchase.waitForExistence(timeout: 5))
        // Settings also has a scroll view behind the sheet; target the paywall itself.
        let scrollView = app.scrollViews.containing(.button, identifier: "premium.plan.annual").firstMatch
        XCTAssertTrue(scrollView.exists)
        // Scroll content, not the fixed action area, to find the subscription disclosures.
        for id in ["premium.plan.annual", "premium.plan.monthly", "premium.plan.lifetime"] {
            let plan = app.buttons[id]
            for _ in 0..<10 where !plan.isHittable || plan.frame.maxY > purchase.frame.minY {
                scrollPaywallContent(scrollView)
            }
            XCTAssertTrue(plan.isHittable)
            XCTAssertLessThanOrEqual(plan.frame.maxY, purchase.frame.minY)
        }
        for id in ["premium.termsLink", "premium.privacyLink"] {
            let link = app.descendants(matching: .any)[id]
            for _ in 0..<10 where !link.isHittable || link.frame.maxY > purchase.frame.minY {
                scrollPaywallContent(scrollView)
            }
            XCTAssertTrue(link.exists && link.isHittable)
            XCTAssertLessThanOrEqual(link.frame.maxY, purchase.frame.minY)
        }
        XCTAssertFalse(app.staticTexts["premium.freeAllowance"].exists)
        XCTAssertFalse(app.staticTexts["premium.subscription.terms"].exists)
        for text in [
            "Media and file processing stays on this device.",
            "Free trials are available only to eligible subscribers. The App Store displays the applicable offer and renewal price before purchase."
        ] {
            let paragraph = app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
            XCTAssertFalse(paragraph.exists)
        }
        XCTAssertTrue(app.buttons["premium.restore"].isHittable)
        XCTAssertTrue(app.buttons["premium.continueFree"].isHittable)
    }

    /// 检查存储功能的权益入口及关闭购买页后的免费导航。
    @MainActor
    func testStorageRequiresPremiumAndClosingPaywallKeepsFreeNavigationAvailable() {
        let app = launchFreeApp()
        tab(in: app, id: "tab.storage", label: "Storage").tap()
        let previewNotice = app.descendants(matching: .any)["storage.preview.notice"].firstMatch
        XCTAssertTrue(previewNotice.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["premium.locked.storage"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["storage.sunburst"].exists)
        // Retain the real dashboard's controls, but never open a picker or a file list for free users.
        for id in ["storage.chooseFolder.toolbar", "storage.addSources.toolbar", "storage.chooseFolder.card", "storage.addSources.card", "storage.category.video", "storage.reviewFiles"] {
            let entry = app.buttons[id]
            for _ in 0..<8 where !entry.isHittable { app.swipeUp() }
            XCTAssertTrue(entry.exists && entry.isHittable, id)
            entry.tap()
            XCTAssertTrue(app.buttons["premium.close"].waitForExistence(timeout: 5), id)
            XCTAssertTrue(app.staticTexts["premium.requiredFeature"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["storage.fileList"].exists)
            app.buttons["premium.close"].tap()
            XCTAssertFalse(app.descendants(matching: .any)["storage.fileList"].exists)
        }
        returnToMedia(in: app)
        XCTAssertFalse(app.buttons["premium.close"].exists)
    }

    /// 验证免费状态下示例存储图可展开、进入子层级并返回。
    @MainActor
    func testStorageExampleMapCanExpandDrillDownAndGoBackWithoutPremium() {
        let app = launchFreeApp()
        tab(in: app, id: "tab.storage", label: "Storage").tap()
        let expand = app.buttons["storage.folderMap.expand"]
        for _ in 0..<5 where !expand.isHittable { app.swipeUp() }
        XCTAssertTrue(expand.isHittable)
        expand.tap()
        let chart = app.descendants(matching: .any)["storage.sunburst.expanded"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["premium.close"].exists)
        let initialRoot = chart.value as? String
        XCTAssertEqual(initialRoot, "Example Folder")
        let radius = min(chart.frame.width, chart.frame.height)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5 + 56 / radius, dy: 0.5)).tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "Example Folder"), object: chart)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        XCTAssertFalse(app.descendants(matching: .any)["storage.fileList"].exists)
        XCTAssertFalse(app.buttons["premium.close"].exists)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Example Folder"), object: chart)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)

        // Both map entry and exit access the coordinator inherited by the Storage sheet.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["storage.close"].waitForExistence(timeout: 5))
        app.buttons["storage.close"].tap()
        XCTAssertTrue(app.buttons["media.storage"].waitForExistence(timeout: 5))
        app.buttons["media.storage"].tap()
        XCTAssertTrue(app.buttons["storage.close"].waitForExistence(timeout: 5))
        for _ in 0..<5 where !expand.isHittable { app.swipeUp() }
        XCTAssertTrue(expand.isHittable)
        expand.tap()
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
    }

    /// 验证快速清理的权益提示可关闭，关闭后仍可使用媒体页面。
    @MainActor
    func testQuickCleanupRequiresPremiumButCanBeDismissedWithoutBlockingMedia() {
        let app = launchFreeApp()
        let quickClean = app.buttons["media.quickClean.open"]
        XCTAssertTrue(quickClean.waitForExistence(timeout: 5))
        XCTAssertTrue(quickClean.isEnabled)
        quickClean.tap()
        XCTAssertTrue(app.buttons["premium.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["premium.requiredFeature"].exists)
        XCTAssertFalse(app.buttons["media.quickClean.delete"].exists)
        app.buttons["premium.close"].tap()
        XCTAssertTrue(app.buttons["media.settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["media.settings"].isEnabled)
        tab(in: app, id: "tab.convert", label: "Convert").tap()
        XCTAssertTrue(app.buttons["conversion.home.video"].waitForExistence(timeout: 5))
    }

    /// 验证缺少高级权益和照片权限时仍可进入快速视频压缩分类。
    @MainActor
    func testQuickVideoCompressionOpensCategoryWithoutPremiumOrPhotoPermission() {
        let app = launchFreeApp()
        let shortcut = app.buttons["media.compress.video"]
        for _ in 0..<6 where !shortcut.isHittable { app.swipeUp() }
        XCTAssertTrue(shortcut.waitForExistence(timeout: 5))
        shortcut.tap()
        XCTAssertTrue(app.navigationBars["Compress videos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["media.compression.empty"].exists)
        XCTAssertTrue(app.buttons["media.compression.start"].exists)
        XCTAssertFalse(app.buttons["media.compression.start"].isEnabled)
        XCTAssertFalse(app.buttons["premium.close"].exists)
        XCTAssertFalse(app.buttons["video.import.files"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["conversion.settings"].exists)
    }

    /// 检查视频、图片和音频转换入口的既定权益边界。
    @MainActor
    func testVideoIsFreeWhileImageAndAudioEntriesRequirePremium() {
        let app = launchFreeApp()
        tab(in: app, id: "tab.convert", label: "Convert").tap()
        for kind in ["image", "audio"] {
            let entry = app.buttons["conversion.home." + kind]
            for _ in 0..<5 where !entry.isHittable { app.swipeUp() }
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            entry.tap()
            XCTAssertTrue(app.buttons["premium.close"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["premium.requiredFeature"].exists)
            app.buttons["premium.close"].tap()
        }
        for _ in 0..<5 where !app.buttons["conversion.home.video"].isHittable { app.swipeDown() }
        app.buttons["conversion.home.video"].tap()
        XCTAssertTrue(app.buttons["video.import.files"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["premium.close"].exists)
        XCTAssertFalse(app.staticTexts["quota.media.remaining"].exists)
    }

    /// 检查预设浅色主题与自定义颜色入口的既定权益边界。
    @MainActor
    func testPresetLightThemeIsFreeAndCustomColorRequiresPremium() {
        let app = launchFreeApp()
        tab(in: app, id: "tab.settings", label: "Settings").tap()
        app.buttons["settings.appearance"].tap()
        let custom = app.buttons["appearance.customColor.locked"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.tap()
        XCTAssertTrue(app.buttons["premium.close"].waitForExistence(timeout: 5))
        app.buttons["premium.close"].tap()
        let cream = app.buttons["appearance.background.cream"]
        for _ in 0..<5 where !cream.isHittable { app.swipeUp() }
        XCTAssertTrue(cream.isHittable)
        cream.tap()
        XCTAssertFalse(app.buttons["premium.close"].exists)
        let palette = app.scrollViews["appearance.background.palette"]
        let graphite = app.buttons["appearance.background.graphite"]
        for _ in 0..<5 where !graphite.isHittable { palette.swipeLeft() }
        XCTAssertTrue(graphite.isHittable)
        graphite.tap()
        XCTAssertTrue(app.buttons["premium.close"].waitForExistence(timeout: 5))
    }

    /// 滚动购买页内容，避开固定操作区域以访问屏幕外的方案。
    @MainActor
    private func scrollPaywallContent(_ scrollView: XCUIElement) {
        // safeAreaInset actions lie within the scroll view's accessibility frame.
        // Start above those fixed buttons so the gesture actually scrolls content.
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// 使用受控的免费用户状态及指定语言启动应用。
    @MainActor
    private func launchFreeApp(language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state", "--ui-test-free-tier", "-AppleLanguages", "(" + language + ")", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    /// 通过共用导航辅助方法定位目标入口。
    @MainActor
    private func tab(in app: XCUIApplication, id: String, label: String) -> XCUIElement {
        appNavigationEntry(in: app, id: id, label: label)
    }
}
