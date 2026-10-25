import XCTest

final class InteractionTests: XCTestCase {
    private func launch(_ count: Int, searchCredential: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixture", String(count)]
        if searchCredential { app.launchArguments += ["--ui-search-credential"] }
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
    func testThinkingButtonOpensPanelAndOffRemainsClickable() {
        let app = launch(0)
        let input = app.textViews["message-input"]; input.tap(); input.typeText("keep draft")
        let button = app.buttons["thinking-button"]
        button.tap()
        XCTAssertTrue(app.navigationBars["深度思考"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["会话控制台"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let toggle = app.switches["thinking-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); toggle.tap()
        app.buttons["完成"].tap()
        XCTAssertEqual(button.value as? String, "已关闭"); XCTAssertTrue(button.isEnabled)
        button.tap(); XCTAssertTrue(toggle.waitForExistence(timeout: 5)); toggle.tap()
        app.buttons["thinking-effort-picker"].tap()
        let low = app.buttons["low"].firstMatch
        XCTAssertTrue(low.waitForExistence(timeout: 5)); low.tap()
        app.buttons["完成"].tap()
        XCTAssertEqual(button.value as? String, "已开启"); XCTAssertTrue(button.label.contains("low"))
        XCTAssertEqual(input.value as? String, "keep draft")
        button.tap(); XCTAssertEqual(toggle.value as? String, "1")
        capture(app, name: "thinking-panel-actual-button-event")
    }
    func testForcedThinkingUnknownModelAndDuplicateControlsAbsent() {
        let app = launch(0)
        app.buttons["model-selector"].tap()
        app.textFields["model-search"].tap(); app.textFields["model-search"].typeText("fixed-thinking")
        app.buttons["choose-model-fixed-thinking"].tap()
        app.buttons["thinking-button"].tap()
        XCTAssertTrue(app.staticTexts["thinking-forced"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["thinking-toggle"].isEnabled)
        app.buttons["完成"].tap()
        XCTAssertEqual(app.buttons["thinking-button"].value as? String, "已开启")
        app.buttons["model-selector"].tap(); app.buttons["choose-model-deepseek-v4-pro"].tap()
        app.buttons["thinking-button"].tap()
        XCTAssertTrue(app.navigationBars["深度思考"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["thinking-toggle"].exists)
        app.buttons["完成"].tap()
        app.buttons["会话控制台"].tap()
        XCTAssertTrue(app.navigationBars["会话控制台"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["thinking-toggle"].exists)
        XCTAssertFalse(app.staticTexts["模型思考设置"].exists)
        XCTAssertFalse(app.segmentedControls["search-mode-picker"].exists)
        XCTAssertFalse(app.buttons["search-provider-picker"].exists)
        app.buttons["完成"].tap()
        app.buttons["search-button"].tap()
        XCTAssertTrue(app.staticTexts["search-auto-unavailable"].waitForExistence(timeout: 5))
        capture(app, name: "search-panel-no-tool-model")
    }
    func testSearchPanelWorksWithoutSourceAndWithConsentAndModes() {
        var app = launch(0)
        let button = app.buttons["search-button"]
        XCTAssertEqual(button.value as? String, "已关闭"); button.tap()
        XCTAssertTrue(app.navigationBars["联网搜索"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["add-search-provider"].firstMatch.exists)
        XCTAssertTrue(app.switches["search-consent-toggle"].exists)
        XCTAssertFalse(app.navigationBars["会话控制台"].exists)
        app.buttons["关闭"].tap(); XCTAssertTrue(button.isEnabled)
        app.terminate()
        app = launch(0, searchCredential: true)
        app.buttons["search-button"].tap()
        let mode = app.segmentedControls["search-mode-picker"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5)); mode.buttons["每次搜索"].tap()
        app.switches["search-consent-toggle"].tap()
        app.buttons["完成"].tap()
        XCTAssertEqual(app.buttons["search-button"].value as? String, "已开启")
        app.buttons["search-button"].tap(); mode.buttons["自动搜索"].tap()
        app.buttons["完成"].tap()
        XCTAssertEqual(app.buttons["search-button"].value as? String, "已开启")
        app.buttons["search-button"].tap(); mode.buttons["关闭"].tap()
        app.buttons["完成"].tap()
        XCTAssertEqual(app.buttons["search-button"].value as? String, "已关闭")
        app.buttons["search-button"].tap()
        XCTAssertTrue(app.navigationBars["联网搜索"].waitForExistence(timeout: 5))
        capture(app, name: "search-panel-actual-button-event")
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
