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

        let help = app.buttons["settings.help"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        help.tap()

        XCTAssertTrue(app.navigationBars["Help"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["How can we help?"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testHelpListsTheThreeToolsAndStorageGuides() throws {
        let app = launchEnglishApp()
        openHelp(in: app)

        for title in ["Meet the App", "Use Media", "Use Storage", "Use Compress", "Common Questions"] {
            let entry = reveal(app.staticTexts[title], in: app)
            XCTAssertTrue(entry.exists, "Missing help entry " + title)
        }
    }

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

    @MainActor
    private func openHelp(in app: XCUIApplication) {
        openSettings(in: app)
        let help = app.buttons["settings.help"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        help.tap()
        XCTAssertTrue(app.navigationBars["Help"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func tabElement(in app: XCUIApplication, identifier: String) -> XCUIElement {
        let identified = app.descendants(matching: .any)[identifier]
        if identified.waitForExistence(timeout: 2) {
            return identified
        }

        let label: String
        switch identifier {
        case "tab.media": label = "Media"
        case "tab.storage": label = "Storage"
        case "tab.convert": label = "Compress"
        default: label = "Settings"
        }
        return app.tabBars.buttons[label]
    }

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
