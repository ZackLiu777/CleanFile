// 界面测试共用的导航辅助方法。
//
// 应用入口位于媒体首页；这些方法先关闭已打开的页面或返回上一级，再定位目标入口。
// 返回次数和滚动次数均有上限，避免导航状态异常时测试无限等待。
// 各入口以无障碍标识定位；返回首页失败会由 XCTest 明确报告。

import XCTest

/// 关闭当前子页面或逐级返回媒体首页，并断言首页设置入口最终可用。
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

/// 先回到媒体首页，再按入口标识查找目标；转换入口必要时向下滚动。
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
