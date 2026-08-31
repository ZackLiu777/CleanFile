import XCTest

final class HelpAndNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAllPrimaryTabsAreReachable() throws {
        let app = launchEnglishApp()

        for tabID in ["tab.media", "tab.storage", "tab.convert", "tab.settings"] {
            let tab = tabElement(in: app, identifier: tabID)
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing tab " + tabID)
            tab.tap()
        }
    }

    @MainActor
    func testSettingsOpensOfflineHelp() throws {
        let app = launchEnglishApp()
        openSettings(in: app)

        let help = identifiedElement(in: app, identifier: "settings.help", fallback: "Help")
        XCTAssertTrue(help.waitForExistence(timeout: 3))
        help.tap()

        XCTAssertTrue(app.navigationBars["Help"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["How can we help?"].exists)
    }

    @MainActor
    func testHelpListsTheThreeToolsAndStorageGuides() throws {
        let app = launchEnglishApp()
        openHelp(in: app)

        for title in ["Meet the App", "Use Media", "Use Storage", "Use Convert", "Common Questions"] {
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3), "Missing help entry " + title)
        }
    }

    @MainActor
    func testStorageHelpShowsActionableStepsAndAppleResource() throws {
        let app = launchEnglishApp()
        openHelp(in: app)

        let storageArticle = identifiedElement(in: app, identifier: "help.article.storage", fallback: "Use Storage")
        XCTAssertTrue(storageArticle.waitForExistence(timeout: 3))
        storageArticle.tap()

        XCTAssertTrue(app.navigationBars["Use Storage"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Choose a folder"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Apple: Delete files or remove downloads"].exists)
    }

    @MainActor
    func testHelpArticleCanReturnToHelpIndex() throws {
        let app = launchEnglishApp()
        openHelp(in: app)

        let mediaArticle = identifiedElement(in: app, identifier: "help.article.media", fallback: "Use Media")
        XCTAssertTrue(mediaArticle.waitForExistence(timeout: 3))
        mediaArticle.tap()
        XCTAssertTrue(app.navigationBars["Use Media"].waitForExistence(timeout: 3))

        let helpBack = app.navigationBars.buttons["Help"]
        XCTAssertTrue(helpBack.waitForExistence(timeout: 3))
        helpBack.tap()
        XCTAssertTrue(app.navigationBars["Help"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testAppearanceSettingsKeepsLiquidGlassControlVisible() throws {
        let app = launchEnglishApp()
        openSettings(in: app)

        let appearance = identifiedElement(in: app, identifier: "settings.appearance", fallback: "Appearance & Theme")
        XCTAssertTrue(appearance.waitForExistence(timeout: 3))
        appearance.tap()

        XCTAssertTrue(app.navigationBars["Appearance & Theme"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Liquid Glass Cards"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func launchEnglishApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    @MainActor
    private func openSettings(in app: XCUIApplication) {
        let settings = tabElement(in: app, identifier: "tab.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func openHelp(in app: XCUIApplication) {
        openSettings(in: app)
        let help = identifiedElement(in: app, identifier: "settings.help", fallback: "Help")
        XCTAssertTrue(help.waitForExistence(timeout: 3))
        help.tap()
        XCTAssertTrue(app.staticTexts["How can we help?"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func tabElement(in app: XCUIApplication, identifier: String) -> XCUIElement {
        let identified = app.descendants(matching: .any)[identifier]
        if identified.exists {
            return identified
        }

        let label: String
        switch identifier {
        case "tab.media": label = "Media"
        case "tab.storage": label = "Storage"
        case "tab.convert": label = "Convert"
        default: label = "Settings"
        }
        return app.tabBars.buttons[label]
    }

    @MainActor
    private func identifiedElement(
        in app: XCUIApplication,
        identifier: String,
        fallback: String
    ) -> XCUIElement {
        let identified = app.descendants(matching: .any)[identifier]
        if identified.exists {
            return identified
        }

        let button = app.buttons[fallback]
        return button.exists ? button : app.staticTexts[fallback]
    }
}
