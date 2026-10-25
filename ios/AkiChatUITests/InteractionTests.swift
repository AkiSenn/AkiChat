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
        app.buttons["�Ự����"].tap()
        XCTAssertTrue(app.navigationBars["�Ի��ռ�"].waitForExistence(timeout: 5))
        app.buttons["���"].tap()
        XCTAssertTrue(app.buttons["model-selector"].exists)
        capture(app, name: "empty-after-switch-keyboard-drawer")
    }
    func testWelcomeOpensProvidersAndSimpleAddFormDirectly() {
        let app = launch(0)
        app.buttons["configure-api"].tap()
        XCTAssertTrue(app.navigationBars["API ������"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["����Ľ���"].exists)
        let add = app.buttons["add-api-provider"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        XCTAssertTrue(app.textFields["provider-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["provider-url"].exists)
        XCTAssertTrue(app.secureTextFields["provider-key"].exists)
        XCTAssertTrue(app.buttons["save-discover-models"].exists)
        XCTAssertFalse(app.textFields["Ĭ��ģ�� ID����ѡ��"].exists)
        XCTAssertFalse(app.textFields["Ĭ��ģ����ʾ���ƣ���ѡ��"].exists)
        capture(app, name: "stage-a-simple-api-form")
        app.buttons["ȡ��"].tap()
        app.buttons["���"].tap()
        XCTAssertTrue(app.buttons["model-selector"].exists)
    }
    func testThinkingButtonOpensPanelAndOffRemainsClickable() {
        let app = launch(0)
        let input = app.textViews["message-input"]; input.tap(); input.typeText("keep draft")
        let button = app.buttons["thinking-button"]
        button.tap()
        XCTAssertTrue(app.navigationBars["���˼��"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["�Ự����̨"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let toggle = app.switches["thinking-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); toggle.tap()
        app.buttons["���"].tap()
        XCTAssertEqual(button.value as? String, "�ѹر�"); XCTAssertTrue(button.isEnabled)
        button.tap(); XCTAssertTrue(toggle.waitForExistence(timeout: 5)); toggle.tap()
        app.buttons["thinking-effort-picker"].tap()
        let low = app.buttons["low"].firstMatch
        XCTAssertTrue(low.waitForExistence(timeout: 5)); low.tap()
        app.buttons["���"].tap()
        XCTAssertEqual(button.value as? String, "�ѿ���"); XCTAssertTrue(button.label.contains("low"))
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
        app.buttons["���"].tap()
        XCTAssertEqual(app.buttons["thinking-button"].value as? String, "�ѿ���")
        app.buttons["model-selector"].tap(); app.buttons["choose-model-deepseek-v4-pro"].tap()
        app.buttons["thinking-button"].tap()
        XCTAssertTrue(app.navigationBars["���˼��"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["thinking-toggle"].exists)
        app.buttons["���"].tap()
        app.buttons["�Ự����̨"].tap()
        XCTAssertTrue(app.navigationBars["�Ự����̨"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["thinking-toggle"].exists)
        XCTAssertFalse(app.staticTexts["ģ��˼������"].exists)
        XCTAssertFalse(app.segmentedControls["search-mode-picker"].exists)
        XCTAssertFalse(app.buttons["search-provider-picker"].exists)
        app.buttons["���"].tap()
        app.buttons["search-button"].tap()
        XCTAssertTrue(app.staticTexts["search-auto-unavailable"].waitForExistence(timeout: 5))
        capture(app, name: "search-panel-no-tool-model")
    }
    func testSearchPanelWorksWithoutSourceAndWithConsentAndModes() {
        var app = launch(0)
        let button = app.buttons["search-button"]
        XCTAssertEqual(button.value as? String, "�ѹر�"); button.tap()
        XCTAssertTrue(app.navigationBars["��������"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["add-search-provider"].firstMatch.exists)
        XCTAssertTrue(app.switches["search-consent-toggle"].exists)
        XCTAssertFalse(app.navigationBars["�Ự����̨"].exists)
        app.buttons["�ر�"].tap(); XCTAssertTrue(button.isEnabled)
        app.terminate()
        app = launch(0, searchCredential: true)
        app.buttons["search-button"].tap()
        let mode = app.segmentedControls["search-mode-picker"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5)); mode.buttons["ÿ������"].tap()
        app.switches["search-consent-toggle"].tap()
        app.buttons["���"].tap()
        XCTAssertEqual(app.buttons["search-button"].value as? String, "�ѿ���")
        app.buttons["search-button"].tap(); mode.buttons["�Զ�����"].tap()
        app.buttons["���"].tap()
        XCTAssertEqual(app.buttons["search-button"].value as? String, "�ѿ���")
        app.buttons["search-button"].tap(); mode.buttons["�ر�"].tap()
        app.buttons["���"].tap()
        XCTAssertEqual(app.buttons["search-button"].value as? String, "�ѹر�")
        app.buttons["search-button"].tap()
        XCTAssertTrue(app.navigationBars["��������"].waitForExistence(timeout: 5))
        capture(app, name: "search-panel-actual-button-event")
    }
    func testHundredMessageScrollAndModelPanel() {
        let app = launch(100)
        app.scrollViews.firstMatch.swipeDown()
        app.buttons["model-selector"].tap()
        XCTAssertTrue(app.textFields["model-search"].waitForExistence(timeout: 5))
        capture(app, name: "model-panel-100-messages")
        app.buttons["���"].tap()
        capture(app, name: "chat-100-messages")
    }
    func testFiveHundredMessageScrollAndReturnLatest() {
        let app = launch(500)
        app.scrollViews.firstMatch.swipeDown(); app.scrollViews.firstMatch.swipeDown()
        let latest = app.buttons["����������Ϣ"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5)); latest.tap()
        app.buttons["�Ự����"].tap()
        XCTAssertTrue(app.navigationBars["�Ի��ռ�"].waitForExistence(timeout: 5))
        app.buttons["���"].tap(); capture(app, name: "chat-500-messages-dark")
    }
}
