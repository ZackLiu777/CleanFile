// 帮助中心与应用导航的界面测试。
//
// 用例从媒体首页进入设置和离线帮助，检查文章入口、存储说明及返回路径。
// 测试固定英文界面并重置状态，使文案断言与应用启动环境保持一致。
// 存储文章同时检查步骤与 Apple 资源入口，帮助文章必须能够返回目录。

import XCTest

/// 验证帮助内容、次级页面的可达性与返回路径。
final class HelpAndNavigationUITests: XCTestCase {
    /// 在断言失败时停止当前用例，避免后续操作掩盖最初失败。
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 从媒体首页依次验证存储、转换和设置入口可达。
    @MainActor
    func testMediaHomeAndSecondaryDestinationsAreReachable() throws {
        let app = launchEnglishApp()

        XCTAssertTrue(app.buttons["media.settings"].waitForExistence(timeout: 10))
        for tabID in ["tab.storage", "tab.convert", "tab.settings"] {
            let tab = tabElement(in: app, identifier: tabID)
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing tab " + tabID)
            tab.tap()
        }
    }

    /// 验证设置中的帮助入口打开本地帮助首页。
    @MainActor
    func testSettingsOpensOfflineHelp() throws {
        let app = launchEnglishApp()
        openSettings(in: app)

        let help = app.buttons["settings.help"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        help.tap()

        XCTAssertTrue(app.navigationBars["Help"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["How can we help?"].waitForExistence(timeout: 3))
    }

    /// 检查帮助首页包含应用介绍、媒体、存储、转换及常见问题入口。
    @MainActor
    func testHelpListsTheThreeToolsAndStorageGuides() throws {
        let app = launchEnglishApp()
        openHelp(in: app)

        for title in ["Meet the App", "Use Media", "Use Storage", "Use Convert", "Common Questions"] {
            let entry = reveal(app.staticTexts[title], in: app)
            XCTAssertTrue(entry.exists, "Missing help entry " + title)
        }
    }

    /// 验证存储帮助展示操作步骤和 Apple 官方参考资源入口。
    @MainActor
    func testStorageHelpShowsActionableStepsAndAppleResource() throws {
        let app = launchEnglishApp()
        openHelp(in: app)

        let storageArticle = app.buttons["help.article.storage"]
        XCTAssertTrue(storageArticle.waitForExistence(timeout: 5))
        storageArticle.tap()

        XCTAssertTrue(app.navigationBars["Use Storage"].waitForExistence(timeout: 5))
        XCTAssertTrue(reveal(app.staticTexts["Choose a folder"], in: app).exists)
        XCTAssertTrue(
            reveal(
                app.descendants(matching: .any)["help.resource.storage.files"],
                in: app
            ).exists
        )
    }

    /// 进入媒体帮助文章后通过导航栏返回帮助目录。
    @MainActor
    func testHelpArticleCanReturnToHelpIndex() throws {
        let app = launchEnglishApp()
        openHelp(in: app)

        let mediaArticle = app.buttons["help.article.media"]
        XCTAssertTrue(mediaArticle.waitForExistence(timeout: 5))
        mediaArticle.tap()
        XCTAssertTrue(app.navigationBars["Use Media"].waitForExistence(timeout: 5))

        let helpBack = app.navigationBars["Use Media"].buttons["Help"]
        XCTAssertTrue(helpBack.waitForExistence(timeout: 3))
        helpBack.tap()
        XCTAssertTrue(app.navigationBars["Help"].waitForExistence(timeout: 3))
    }

    /// 确认外观页面中的玻璃效果开关可以被发现。
    @MainActor
    func testAppearanceSettingsKeepsLiquidGlassControlVisible() throws {
        let app = launchEnglishApp()
        openSettings(in: app)

        let appearance = app.buttons["settings.appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        appearance.tap()

        XCTAssertTrue(app.navigationBars["Appearance & Theme"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            reveal(app.switches["appearance.liquidGlass"], in: app).exists
        )
    }

    /// 以英文及重置后的状态启动应用，保证文案与导航断言可复现。
    @MainActor
    private func launchEnglishApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
        return app
    }

    /// 从媒体首页打开设置，并等待设置页面出现。
    @MainActor
    private func openSettings(in app: XCUIApplication) {
        let settings = tabElement(in: app, identifier: "tab.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let settingsScreen = app.otherElements["settings.screen"]
        if !settingsScreen.waitForExistence(timeout: 3) {
            XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        }
    }

    /// 进入设置后打开帮助目录。
    @MainActor
    private func openHelp(in app: XCUIApplication) {
        openSettings(in: app)
        let help = app.buttons["settings.help"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        help.tap()
        XCTAssertTrue(app.navigationBars["Help"].waitForExistence(timeout: 5))
    }

    /// 通过共用导航辅助方法定位指定入口。
    @MainActor
    private func tabElement(in app: XCUIApplication, identifier: String) -> XCUIElement {
        appNavigationEntry(in: app, id: identifier, label: identifier == "tab.convert" ? "Convert" : "Media")
    }

    /// 在限定滚动次数内尝试让目标元素可见并返回该元素。
    @MainActor
    private func reveal(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 8
    ) -> XCUIElement {
        for _ in 0..<maxSwipes where !element.exists || !element.isHittable {
            app.swipeUp()
        }
        return element
    }
}
