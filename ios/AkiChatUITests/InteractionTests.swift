import XCTest

final class InteractionTests: XCTestCase {
    private func launch(_ count: Int) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixture", String(count)]
        app.launch(); XCTAssertTrue(app.buttons["model-selector"].waitForExistence(timeout: 15))
        return app
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    func testEmptyChatKeyboardDrawerAndProviderModelSwitching() {
        let app = launch(0)
        XCTAssertTrue(app.buttons["model-selector"].label.contains("DeepSeek"))
        let input = app.textViews["message-input"]; XCTAssertTrue(input.exists)
        input.tap(); input.typeText("draft remains")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.buttons["model-selector"].tap()
        XCTAssertTrue(app.textFields["model-search"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["choose-model-deepseek-v4-pro"].tap()
        XCTAssertTrue(app.buttons["model-selector"].label.contains("deepseek-v4-pro"))
        XCTAssertEqual(input.value as? String, "draft remains")
        app.buttons["model-selector"].tap()
        let search = app.textFields["model-search"]; search.tap(); search.typeText("Tencent")
        app.buttons["choose-model-deepseek-v4.1-flash"].tap()
        XCTAssertTrue(app.buttons["model-selector"].label.contains("Tencent WorkBuddy"))
        app.buttons["会话抽屉"].tap()
        XCTAssertTrue(app.navigationBars["对话空间"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["model-selector"].exists)
        capture(app, name: "empty-after-switch-keyboard-drawer")
    }
    func testWelcomeOpensProvidersAndSimpleAddFormDirectly() {
        let app = launch(0)
        app.buttons["configure-api"].tap()
        XCTAssertTrue(app.navigationBars["API 服务商"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["按你的节奏"].exists)
        let add = app.buttons["add-api-provider"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        XCTAssertTrue(app.textFields["provider-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["provider-url"].exists)
        XCTAssertTrue(app.secureTextFields["provider-key"].exists)
        XCTAssertTrue(app.buttons["save-discover-models"].exists)
        XCTAssertFalse(app.textFields["默认模型 ID（可选）"].exists)
        XCTAssertFalse(app.textFields["默认模型显示名称（可选）"].exists)
        capture(app, name: "stage-a-simple-api-form")
        app.buttons["取消"].tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["model-selector"].exists)
    }
    func testHundredMessageScrollAndModelPanel() {
        let app = launch(100)
        app.scrollViews.firstMatch.swipeDown()
        app.buttons["model-selector"].tap()
        XCTAssertTrue(app.textFields["model-search"].waitForExistence(timeout: 5))
        capture(app, name: "model-panel-100-messages")
        app.buttons["完成"].tap()
        capture(app, name: "chat-100-messages")
    }
    func testFiveHundredMessageScrollAndReturnLatest() {
        let app = launch(500)
        app.scrollViews.firstMatch.swipeDown(); app.scrollViews.firstMatch.swipeDown()
        let latest = app.buttons["返回最新消息"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5)); latest.tap()
        app.buttons["会话抽屉"].tap()
        XCTAssertTrue(app.navigationBars["对话空间"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap(); capture(app, name: "chat-500-messages-dark")
    }
}
