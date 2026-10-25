#if DEBUG
import Foundation
import UIKit

extension AppStore {
    /// Isolated in-memory data for UI automation. Compiled out of the Release IPA.
    static func uiFixtureDatabase() throws -> LocalDatabase? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--ui-fixture"), args.indices.contains(index + 1),
              let count = Int(args[index + 1]), [0, 100, 500].contains(count) else { return nil }
        let db = try LocalDatabase(inMemory: true)
        var deepSeek = Provider.deepSeek
        if args.contains("--ui-search-credential") {
            deepSeek.apiKeyReference = "akichat.ui-tests.search"
            try KeychainStore.write("mock-ui-search-credential", reference: deepSeek.apiKeyReference)
        }
        var hub = Provider.workBuddy; hub.baseURL = "https://fixture.invalid/v1"; hub.name = "Tencent WorkBuddy"
        var flash = ModelRecord(id: "deepseek-flash", name: "deepseek-flash")
        flash.effort = ["low", "high", "max"]
        flash.discovered = ModelCapabilities(vision: true, thinking: true, tools: true, streaming: true)
        let pro = ModelRecord(id: "deepseek-v4-pro", name: "deepseek-v4-pro")
        var fixed = ModelRecord(id: "fixed-thinking", name: "Fixed Thinking")
        fixed.discovered.thinking = true
        fixed.metadata = "{\"reasoning_fixed_effort\":\"high\",\"always_reasoning\":true,\"reasoning_can_disable\":false}"
        let hubModel = ModelRecord(id: "deepseek-v4.1-flash", name: "Hub Flash")
        if args.contains("--ui-characters") {
            let json: [String: Any] = ["spec": "chara_card_v3", "spec_version": "3.0", "data": ["name": "星海旅人", "description": "来自星海的向导", "personality": "温柔", "scenario": "星空下", "first_mes": "{{user}}，欢迎来到星海。", "mes_example": "", "tags": ["冒险"], "alternate_greetings": ["{{user}}，准备出发了吗？"]]]
            let raw = try JSONSerialization.data(withJSONObject: json)
            var card = try CharacterCardParser.json(raw)
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
            card.avatarJPEG = renderer.jpegData(withCompressionQuality: 0.8) { context in UIColor.systemBlue.setFill(); context.cgContext.fill(CGRect(x: 0, y: 0, width: 16, height: 16)) }
            try db.save([card], key: "characters.v1")
        }
        var messages = (0..<count).map { index in
            Message(role: index.isMultiple(of: 2) ? .user : .assistant,
                    content: "测试消息 \(index) · **Markdown**\n\n```swift\nlet value = \(index)\n```\n\n这是界面性能检查使用的合成内容。")
        }
        if count == 500 {
            messages[count - 1].content += "\n\n```swift\n" + (0..<500).map { "let longCodeLine\($0) = \($0) // synthetic fixture" }.joined(separator: "\n") + "\n```"
        }
        try db.save([deepSeek, hub], key: "providers.v1")
        try db.save([ModelCatalog(id: deepSeek.id, models: [flash, pro]), ModelCatalog(id: hub.id, models: [hubModel, fixed])], key: "catalogs.v2")
        try db.save([Conversation(title: "Fixture \(count) messages", providerID: deepSeek.id, messages: messages)], key: "conversations.v1")
        var settings = AppSettings(); settings.appearance = .dark
        try db.save(settings, key: "settings.v1")
        return db
    }
}
#endif
