import Foundation

enum ProviderKind: String, Codable, CaseIterable { case deepSeek, openAI, workBuddy }
enum ReasoningEffort: String, Codable, CaseIterable { case low, medium, high, max }
enum AppearanceMode: String, Codable, CaseIterable { case automatic, light, dark }

struct Provider: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var baseURL: String
    var apiKeyReference = UUID().uuidString
    var modelID: String
    var displayName: String
    var kind: ProviderKind = .openAI
    // Non-secret headers only. Authorization always comes from Keychain.
    var customHeaders: [String: String] = [:]
    var supportsVision = false
    var supportsThinking = false
    var supportsStreaming = true
    var requestsStreamingUsage = false
    var advanced: ProviderOptions?
    static let deepSeek = Provider(name: "DeepSeek", baseURL: "https://api.deepseek.com",
        modelID: "deepseek-flash", displayName: "deepseek-flash", kind: .deepSeek,
        supportsVision: true, supportsThinking: true, requestsStreamingUsage: true)
}

enum MessageRole: String, Codable { case system, user, assistant, tool }
enum MessageState: String, Codable { case complete, generating, stopped, failed }
struct TokenUsage: Codable, Equatable {
    var prompt_tokens: Int?
    var completion_tokens: Int?
    var total_tokens: Int?
}
struct Attachment: Codable, Identifiable, Equatable {
    var id = UUID()
    var jpeg: Data
    var width: Int
    var height: Int
    var dataURL: String { "data:image/jpeg;base64," + jpeg.base64EncodedString() }
}
struct Message: Codable, Identifiable, Equatable {
    var id = UUID()
    var role: MessageRole
    var content: String
    var reasoning = ""
    var images: [Attachment] = []
    var createdAt = Date()
    var state: MessageState = .complete
    var usage: TokenUsage?
    var error: String?
    var finishReason: String?
    var toolCalls: [ToolCall]?
    var toolCallID: String?
    var toolRecords: [ToolRecord]?
    var sources: [SearchSource]?
}
struct Conversation: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = "新对话"
    var providerID: UUID
    var updatedAt = Date()
    var messages: [Message] = []
    var thinking = true
    var effort: ReasoningEffort = .high
    var draft = ""
    var draftImages: [Attachment] = []
    var advanced: ConversationOptions?
    var summaries: [SummaryVersion]?
    var activeSummaryID: UUID?
    var character: CharacterBinding? // Optional: old ordinary conversations decode unchanged.
}
struct AppSettings: Codable, Equatable {
    var appearance: AppearanceMode = .automatic
    var fontSize: Double = 16
    var systemPrompt = "你是一位细致、可靠的 AI 助手。请使用用户的语言回答。"
    var contextCount = 20
    var temperature = 0.7
    var topP = 1.0
    var maxTokens = 4096
    var streaming = true
    var advanced: GlobalOptions?
}
struct Archive: Codable {
    var version = 1
    var conversations: [Conversation]
}

enum ExportService {
    static func json(_ conversations: [Conversation]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Archive(conversations: conversations))
    }
    static func decode(_ data: Data) throws -> [Conversation] {
        guard data.count <= 80 * 1024 * 1024 else { throw AppError.validation("导入文件不得超过 80 MiB") }
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.version == 1 else { throw AppError.validation("不支持的数据版本") }
        guard archive.conversations.count <= 5000 else { throw AppError.validation("会话数量超过导入限制") }
        var ids = Set<UUID>()
        for c in archive.conversations {
            if let binding = c.character {
                try CharacterCardParser.validate(binding.snapshot)
                guard binding.characterID == binding.snapshot.id else { throw CharacterImportError.invalid }
                if let greeting = binding.greetingMessageID {
                    guard c.messages.first?.id == greeting, c.messages.first?.role == .assistant else { throw CharacterImportError.invalid }
                }
            }
            let options = c.options
            guard (1...32).contains(options.context.recentTurns), (1024...4000000).contains(options.context.inputBudget),
                  (256...393216).contains(options.context.outputBudget), (1...8).contains(options.maxToolRounds),
                  c.messages.count <= 100000, (c.summaries ?? []).count <= 1000,
                  (c.summaries ?? []).allSatisfy({ $0.text.utf8.count <= 64000 }) else { throw AppError.validation("导入配置或摘要超出限制") }
            for m in c.messages {
                guard m.content.utf8.count <= 8 * 1024 * 1024, m.reasoning.utf8.count <= 8 * 1024 * 1024,
                      (m.toolCalls ?? []).count <= 8, (m.toolCalls ?? []).allSatisfy({ $0.function.arguments.utf8.count <= 65536 }) else { throw AppError.validation("导入消息或工具参数超出限制") }
            }
            guard ids.insert(c.id).inserted, Set(c.messages.map(\.id)).count == c.messages.count else {
                throw AppError.validation("记录包含重复 ID")
            }
            for image in c.messages.flatMap(\.images) + c.draftImages {
                guard image.jpeg.count <= 4 * 1024 * 1024, image.width > 0, image.height > 0,
                      image.width <= 2048, image.height <= 2048 else {
                    throw AppError.validation("导入记录中的图片超出客户端限制")
                }
            }
        }
        return archive.conversations
    }
    static func markdown(_ c: Conversation) -> String {
        let messages = c.messages.map { m -> String in
            let role = m.role == .user ? "你" : (m.role == .tool ? "工具结果" : "AkiChat")
            let tools = (m.toolCalls ?? []).map { "\n\n工具 \($0.function.name)（\($0.id)）\n\n```json\n\($0.function.arguments)\n```" }.joined()
            let sources = (m.sources ?? []).map { "\n- [\($0.title)](\($0.url))" }.joined()
            return "## \(role)\n\n" +
            (m.reasoning.isEmpty ? "" : "<details><summary>思考</summary>\n\n\(m.reasoning)\n\n</details>\n\n") +
            m.content + tools + m.images.map { "\n\n![图片](\($0.dataURL))" }.joined() + sources + "\n\n"
        }.joined()
        let summaries = (c.summaries ?? []).map { "## 摘要版本 \($0.id)\n\n\($0.text)\n\n覆盖 \($0.coveredMessageIDs.count) 条原始消息；额外用量 \($0.usage?.total_tokens.map(String.init) ?? "未返回") tokens。\n\n" }.joined()
        return "# \(c.title)\n\n" + (c.character.map { "角色：" + $0.snapshot.fields.name + "（角色设定保存在 JSON 导出中）\n\n" } ?? "") + messages + summaries
    }
}

enum AppError: LocalizedError {
    case validation(String), http(Int), malformed, interrupted, empty, storage(String)
    var errorDescription: String? {
        switch self {
        case .validation(let s), .storage(let s): return s
        case .http(let code):
            switch code {
            case 401: return "认证失败（401），请检查 API Key；Hub 需要网关 Key，不是面板密码。"
            case 403: return "权限不足（403），请检查 Key 是否启用及模型白名单、区域与账号权限。"
            case 402: return "余额不足（402），请检查服务商账户。"
            case 429: return "限流或额度不足（429），也可能是网关账号额度或模型冷却，请稍后重试。"
            case 400, 422: return "请求被拒绝（\(code)），请检查模型是否启用、Key 白名单、区域与参数能力。"
            case 404, 405: return "接口不可用（\(code)），请检查地址和路径；模型列表不可用时可手动添加模型。"
            default: return "服务响应错误（HTTP \(code)），请稍后重试。"
            }
        case .malformed: return "服务返回了无法解析的数据，请检查接口兼容性。"
        case .interrupted: return "连接提前中断，已保留收到的内容，可重新生成。"
        case .empty: return "服务未返回回答，请检查模型或重新生成。"
        }
    }
}
