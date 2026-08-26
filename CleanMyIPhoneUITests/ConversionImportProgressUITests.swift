import XCTest

final class ConversionImportProgressUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

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

        let progressBar = app.progressIndicators["conversion.import.progressBar"]
        XCTAssertTrue(progressBar.exists)
        XCTAssertEqual(progressBar.value as? String, "100%")
    }
}
