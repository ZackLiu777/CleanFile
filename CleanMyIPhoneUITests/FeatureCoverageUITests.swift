import XCTest

final class FeatureCoverageUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMediaAndStorageExposeTheirPrimaryActions() throws {
        let app = launchEnglishApp()

        XCTAssertTrue(tab(in: app, id: "tab.media", label: "Media").waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["media.actions"].waitForExistence(timeout: 5)
        )

        tab(in: app, id: "tab.storage", label: "Storage").tap()
        XCTAssertTrue(app.descendants(matching: .any)["storage.status"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["storage.chooseFolder.card"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["storage.chooseFolder.toolbar"].exists)
    }

    @MainActor
    func testEveryConversionToolCanOpenAndReturnHome() throws {
        let app = launchEnglishApp()
        tab(in: app, id: "tab.convert", label: "Convert").tap()

        for (id, title) in [
            ("conversion.home.image", "Convert Images"),
            ("conversion.home.video", "Convert Video"),
            ("conversion.home.audio", "Convert Audio")
        ] {
            let tool = app.buttons[id]
            XCTAssertTrue(tool.waitForExistence(timeout: 5), "Missing conversion tool \(id)")
            tool.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))

            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.waitForExistence(timeout: 3))
            back.tap()
        }
    }

    @MainActor
    func testConversionGuideCoversImagesVideoAndAudio() throws {
        let app = launchEnglishApp()
        tab(in: app, id: "tab.convert", label: "Convert").tap()

        let guide = app.buttons["conversion.guide.button"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5))
        guide.tap()
        XCTAssertTrue(app.navigationBars["Conversion Guide"].waitForExistence(timeout: 5))

        for (id, title) in [
            ("conversion.guide.tool.image", "Convert Images"),
            ("conversion.guide.tool.video", "Convert Video"),
            ("conversion.guide.tool.audio", "Convert Audio")
        ] {
            let item = reveal(app.descendants(matching: .any)[id], in: app)
            XCTAssertTrue(item.exists, "Missing guide item \(id)")
            item.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        XCTAssertTrue(reveal(app.buttons["Done"], in: app).exists)
        app.buttons["Done"].tap()
        XCTAssertFalse(app.navigationBars["Conversion Guide"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testLiquidGlassToggleChangesStateAndCanBeRestored() throws {
        let app = launchAppearance(in: launchEnglishApp())
        let toggle = app.switches["appearance.liquidGlass"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        guard let originalValue = toggle.value as? String else {
            XCTFail("Liquid Glass switch did not expose an accessibility value")
            return
        }

        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let changedToggle = switchElement(in: app, valueDifferentFrom: originalValue)
        XCTAssertTrue(
            changedToggle.waitForExistence(timeout: 3),
            "Liquid Glass switch accessibility value did not update"
        )

        changedToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(
            switchElement(in: app, valueEqualTo: originalValue).waitForExistence(timeout: 3),
            "Liquid Glass switch did not return to its original value"
        )
    }

    @MainActor
    func testCustomBackgroundSupportsAtLeastFiveGradientColors() throws {
        let app = launchAppearance(in: launchEnglishApp())
        let custom = reveal(
            app.descendants(matching: .any)["appearance.background.custom"],
            in: app
        )
        XCTAssertTrue(custom.exists)
        custom.tap()

        let style = reveal(app.segmentedControls["appearance.background.style"], in: app)
        XCTAssertTrue(style.exists)
        style.buttons["Linear Gradient"].tap()

        let addColor = app.buttons["Add Color"]
        for _ in 0..<3 {
            XCTAssertTrue(reveal(addColor, in: app).exists)
            addColor.tap()
        }

        XCTAssertTrue(reveal(app.staticTexts["Color 5"], in: app).exists)
    }

    @MainActor
    func testAppearanceCanSwitchBetweenSystemLightAndDark() throws {
        let app = launchAppearance(in: launchEnglishApp())
        let appearance = reveal(app.segmentedControls["appearance.mode"], in: app)
        XCTAssertTrue(appearance.exists)

        for label in ["Light", "Dark", "System"] {
            let option = appearance.buttons[label]
            XCTAssertTrue(option.exists, "Missing appearance option \(label)")
            option.tap()
            XCTAssertTrue(option.isSelected)
        }
    }

    @MainActor
    func testHelpCatalogExposesEveryArticle() throws {
        let app = launchEnglishApp()
        openHelp(in: app)

        let articleIDs = [
            "overview", "media", "storage", "conversion", "storage-plan",
            "photos-cleanup", "files-cleanup", "apps-cleanup",
            "messages-safari", "system-data", "faq", "permissions-privacy"
        ]

        for articleID in articleIDs {
            let article = reveal(
                app.buttons["help.article.\(articleID)"],
                in: app,
                maxSwipes: 10
            )
            XCTAssertTrue(article.exists, "Missing help article \(articleID)")
        }
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
    private func launchAppearance(in app: XCUIApplication) -> XCUIApplication {
        tab(in: app, id: "tab.settings", label: "Settings").tap()
        let appearance = app.buttons["settings.appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        appearance.tap()
        XCTAssertTrue(app.navigationBars["Appearance & Theme"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func openHelp(in app: XCUIApplication) {
        tab(in: app, id: "tab.settings", label: "Settings").tap()
        let help = app.buttons["settings.help"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        help.tap()
        XCTAssertTrue(app.navigationBars["Help"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func tab(in app: XCUIApplication, id: String, label: String) -> XCUIElement {
        let identified = app.buttons[id]
        return identified.waitForExistence(timeout: 2)
            ? identified
            : app.tabBars.buttons[label]
    }

    @MainActor
    private func reveal(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 6
    ) -> XCUIElement {
        for _ in 0..<maxSwipes where !element.exists || !element.isHittable {
            app.swipeUp()
        }
        return element
    }

    @MainActor
    private func switchElement(in app: XCUIApplication, valueDifferentFrom value: String) -> XCUIElement {
        app.switches
            .matching(identifier: "appearance.liquidGlass")
            .matching(NSPredicate(format: "value != %@", value))
            .firstMatch
    }

    @MainActor
    private func switchElement(in app: XCUIApplication, valueEqualTo value: String) -> XCUIElement {
        app.switches
            .matching(identifier: "appearance.liquidGlass")
            .matching(NSPredicate(format: "value == %@", value))
            .firstMatch
    }
}
