import XCTest

@MainActor
func returnToMedia(in app: XCUIApplication) {
    for closeID in ["storage.close", "settings.close"] {
        let close = app.buttons[closeID]
        if close.exists && close.isHittable { close.tap() }
    }
    for _ in 0..<6 where !app.buttons["media.settings"].exists {
        let close = app.buttons["conversion.close"]
        if close.exists && close.isHittable {
            close.tap()
            break
        }
        let back = app.navigationBars.buttons.firstMatch
        guard back.exists && back.isHittable else { break }
        back.tap()
    }
    XCTAssertTrue(app.buttons["media.settings"].waitForExistence(timeout: 5))
}

@MainActor
func appNavigationEntry(in app: XCUIApplication, id: String, label: String) -> XCUIElement {
    returnToMedia(in: app)
    switch id {
    case "tab.convert":
        let convert = app.buttons["media.convert"]
        for _ in 0..<8 where !convert.isHittable { app.swipeDown() }
        return convert
    case "tab.storage": return app.buttons["media.storage"]
    case "tab.settings": return app.buttons["media.settings"]
    default: return app.descendants(matching: .any)[id].firstMatch
    }
}
