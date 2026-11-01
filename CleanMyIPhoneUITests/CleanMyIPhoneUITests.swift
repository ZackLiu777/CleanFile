// 应用启动和主要导航的界面测试。
//
// 用例从重置状态启动应用，验证媒体首页入口、转换页面和设置页面的可达性，
// 并单独记录启动性能；测试通过无障碍标识访问控件，不操作用户文件。
// 导航用例固定英文环境并核对首页入口的相对位置及关闭后的返回路径。

//
//  CleanMyIPhoneUITests.swift
//  CleanMyIPhoneUITests
//
//  Created by Zane Liao on 8/18/26.
//

import XCTest

/// 验证应用启动、首页导航与启动性能的界面行为。
final class CleanMyIPhoneUITests: XCTestCase {

    /// 在断言失败时停止当前用例，避免后续操作掩盖最初失败。
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    /// 保留 XCTest 的清理钩子；当前用例没有额外的显式清理。
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    /// 验证首页主要入口、转换页面往返及设置入口的展示与位置关系。
    @MainActor
    func testAppLaunchesWithPrimaryNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["media.convert"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        for id in ["tab.media", "tab.convert", "tab.storage", "tab.settings"] {
            XCTAssertFalse(app.descendants(matching: .any)[id].exists)
        }
        XCTAssertTrue(app.buttons["media.quickClean.open"].exists)
        app.buttons["media.convert"].tap()
        XCTAssertTrue(app.buttons["conversion.home.video"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Convert Media"].exists)
        XCTAssertTrue(app.buttons["conversion.home.video"].label.contains("Convert Videos"))
        XCTAssertTrue(app.buttons["conversion.close"].exists)
        app.buttons["conversion.close"].tap()
        XCTAssertTrue(app.buttons["media.convert"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["media.storage"].exists)
        XCTAssertLessThan(app.buttons["media.quickClean.open"].frame.midX, app.buttons["media.storage"].frame.midX)
        XCTAssertLessThan(app.buttons["media.storage"].frame.midX, app.frame.midX)
        XCTAssertGreaterThan(app.buttons["media.settings"].frame.midX, app.frame.midX)
        XCTAssertTrue(app.buttons["media.settings"].exists)
        XCTAssertFalse(app.buttons["media.actions"].exists)
        XCTAssertFalse(app.buttons["media.delete"].exists)
        XCTAssertFalse(app.buttons["Analyze"].exists)
        XCTAssertFalse(app.buttons["Refresh"].exists)
        app.buttons["media.settings"].tap()
        XCTAssertTrue(app.buttons["settings.close"].waitForExistence(timeout: 5))
    }

    /// 通过 XCTest 启动指标测量应用启动耗时。
    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
