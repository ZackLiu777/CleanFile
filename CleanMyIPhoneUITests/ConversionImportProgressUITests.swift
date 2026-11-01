// 转换导入进度的界面测试。
//
// 使用专门的测试启动参数和模拟按钮推动进度，检查界面从零更新到一半和完成。
// 等待使用带期限的条件，以容纳界面异步刷新而不是依赖固定延时。
// 测试入口展示合成进度，不需要导入或转换用户文件。

import XCTest

/// 验证导入进度变化能够反映在百分比标签上。
final class ConversionImportProgressUITests: XCTestCase {
    /// 在断言失败时停止当前用例，避免后续操作掩盖最初失败。
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 通过测试入口模拟进度变化，并等待百分比标签依次更新。
    @MainActor
    func testProgressViewRefreshesFromZeroToOneHundredPercent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-import-progress"]
        app.launch()

        let percentage = app.staticTexts["conversion.import.percentage"]
        XCTAssertTrue(percentage.waitForExistence(timeout: 3))
        XCTAssertEqual(percentage.label, "0%")

        app.buttons["conversion.import.simulateHalf"].tap()
        let halfway = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == '50%'"),
            object: percentage
        )
        XCTAssertEqual(XCTWaiter.wait(for: [halfway], timeout: 3), .completed)

        app.buttons["conversion.import.simulateComplete"].tap()
        let complete = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == '100%'"),
            object: percentage
        )
        XCTAssertEqual(XCTWaiter.wait(for: [complete], timeout: 3), .completed)
    }
}
