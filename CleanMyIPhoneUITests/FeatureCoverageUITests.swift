import XCTest

final class FeatureCoverageUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMediaAndStorageExposeTheirPrimaryActions() throws {
        let app = launchEnglishApp()

        let mediaTab = tab(in: app, id: "tab.media", label: "Media")
        XCTAssertTrue(mediaTab.waitForExistence(timeout: 5))
        mediaTab.tap()
        XCTAssertTrue(
            mediaActionsButton(in: app).waitForExistence(timeout: 5),
            "Missing Media Actions menu"
        )

        tab(in: app, id: "tab.storage", label: "Storage").tap()
        XCTAssertTrue(app.descendants(matching: .any)["storage.status"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["storage.chooseFolder.card"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["storage.chooseFolder.toolbar"].exists)
    }

    @MainActor
    func testEveryConversionToolCanOpenAndReturnHome() throws {
        let app = launchEnglishApp()
        tab(in: app, id: "tab.convert", label: "Compress").tap()

        for (id, title) in [
            ("conversion.home.image", "Compress Images"),
            ("conversion.home.video", "Compress Video"),
            ("conversion.home.audio", "Compress Audio")
        ] {
            let tool = reveal(app.buttons[id], in: app)
            XCTAssertTrue(
                tool.exists && tool.isHittable,
                "Missing conversion tool \(id)"
            )
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
        tab(in: app, id: "tab.convert", label: "Compress").tap()

        let guide = app.buttons["conversion.guide.button"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5))
        guide.tap()
        XCTAssertTrue(app.navigationBars["Compression Guide"].waitForExistence(timeout: 5))

        for (id, title) in [
            ("conversion.guide.tool.image", "Compress Images"),
            ("conversion.guide.tool.video", "Compress Video"),
            ("conversion.guide.tool.audio", "Compress Audio")
        ] {
            let item = reveal(app.descendants(matching: .any)[id], in: app)
            XCTAssertTrue(item.exists, "Missing guide item \(id)")
            item.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        XCTAssertTrue(reveal(app.buttons["Done"], in: app).exists)
        app.buttons["Done"].tap()
        XCTAssertFalse(app.navigationBars["Compression Guide"].waitForExistence(timeout: 2))
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

        tapSwitch(toggle)
        XCTAssertTrue(
            waitForSwitch(toggle, toDifferFrom: originalValue),
            "Liquid Glass switch accessibility value did not update"
        )

        tapSwitch(toggle)
        XCTAssertTrue(
            waitForSwitch(toggle, toEqual: originalValue),
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
            let option = app.segmentedControls["appearance.mode"].buttons[label]
            XCTAssertTrue(option.exists, "Missing appearance option \(label)")
            option.tap()
            XCTAssertTrue(
                selectedAppearanceOption(label, in: app).waitForExistence(timeout: 3),
                "Appearance option \(label) did not become selected"
            )
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
    private func mediaActionsButton(in app: XCUIApplication) -> XCUIElement {
        let identified = app.descendants(matching: .any)["media.actions"]
        return identified.waitForExistence(timeout: 2)
            ? identified
            : app.descendants(matching: .any)["Media Actions"]
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
    private func tapSwitch(_ element: XCUIElement) {
        element.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()
    }

    @MainActor
    private func waitForSwitch(_ element: XCUIElement, toDifferFrom value: String) -> Bool {
        waitForSwitch(element) { $0 != value }
    }

    @MainActor
    private func waitForSwitch(_ element: XCUIElement, toEqual value: String) -> Bool {
        waitForSwitch(element) { $0 == value }
    }

    @MainActor
    private func waitForSwitch(
        _ element: XCUIElement,
        condition: @escaping (String) -> Bool
    ) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let switchElement = object as? XCUIElement,
                  let value = switchElement.value as? String else {
                return false
            }
            return condition(value)
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: 3
        ) == .completed
    }

    @MainActor
    private func selectedAppearanceOption(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.segmentedControls["appearance.mode"]
            .buttons
            .matching(identifier: label)
            .matching(NSPredicate(format: "selected == true"))
            .firstMatch
    }
}
