#if DEBUG
import Foundation

extension AppStore {
    /// Isolated in-memory data for UI automation. Compiled out of the Release IPA.
    static func uiFixtureDatabase() throws -> LocalDatabase? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--ui-fixture"), args.indices.contains(index + 1),
              let count = Int(args[index + 1]), [0, 100, 500].contains(count) else { return nil }
        let db = try LocalDatabase(inMemory: true)
        let deepSeek = Provider.deepSeek
        var hub = Provider.workBuddy; hub.baseURL = "https://fixture.invalid/v1"; hub.name = "Tencent WorkBuddy"
        var flash = ModelRecord(id: "deepseek-flash", name: "deepseek-flash")
        flash.discovered = ModelCapabilities(vision: true, thinking: true, tools: true, streaming: true)
        let pro = ModelRecord(id: "deepseek-v4-pro", name: "deepseek-v4-pro")
        let hubModel = ModelRecord(id: "deepseek-v4.1-flash", name: "Hub Flash")
        let messages = (0..<count).map { index in
            Message(role: index.isMultiple(of: 2) ? .user : .assistant,
                    content: "测试消息 \(index) · **Markdown**\n\n```swift\nlet value = \(index)\n```\n\n这是界面性能检查使用的合成内容。")
        }
        try db.save([deepSeek, hub], key: "providers.v1")
        try db.save([ModelCatalog(id: deepSeek.id, models: [flash, pro]), ModelCatalog(id: hub.id, models: [hubModel])], key: "catalogs.v2")
        try db.save([Conversation(title: "Fixture \(count) messages", providerID: deepSeek.id, messages: messages)], key: "conversations.v1")
        var settings = AppSettings(); settings.appearance = .dark
        try db.save(settings, key: "settings.v1")
        return db
    }
}
#endif
