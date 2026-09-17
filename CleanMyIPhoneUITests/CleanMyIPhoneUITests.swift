//
//  CleanMyIPhoneUITests.swift
//  CleanMyIPhoneUITests
//
//  Created by Zane Liao on 8/18/26.
//

import XCTest

final class CleanMyIPhoneUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testAppLaunchesWithPrimaryNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        for (index, tab) in [
            ("tab.media", "Media"),
            ("tab.storage", "Storage"),
            ("tab.convert", "Compress"),
            ("tab.settings", "Settings")
        ].enumerated() {
            let (identifier, label) = tab
            // SwiftUI may expose the same tab as Button or Any depending on
            // whether the custom or native Liquid Glass tab bar is active.
            let identifiedTab = app.descendants(matching: .any)[identifier]
            let nativeTab = app.tabBars.buttons[label]
            let identifiedTimeout: TimeInterval = index == 0 ? 10 : 5

            let identifiedTabExists = identifiedTab.waitForExistence(
                timeout: identifiedTimeout
            )
            let nativeTabExists = identifiedTabExists
                ? false
                : nativeTab.waitForExistence(timeout: 5)

            XCTAssertTrue(
                identifiedTabExists || nativeTabExists,
                "Missing primary tab \(label) (identifier: \(identifier)) after app launch"
            )
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
