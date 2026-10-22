import Foundation

enum ProviderKind: String, Codable, CaseIterable { case deepSeek, openAI }
enum ReasoningEffort: String, Codable, CaseIterable { case low, high, max }
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
    static let deepSeek = Provider(name: "DeepSeek", baseURL: "https://api.deepseek.com",
        modelID: "deepseek-flash", displayName: "DeepSeek V4.1 Flash 1017", kind: .deepSeek,
        supportsVision: true, supportsThinking: true, requestsStreamingUsage: true)
}

enum MessageRole: String, Codable { case system, user, assistant }
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
        var ids = Set<UUID>()
        for c in archive.conversations {
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
        "# \(c.title)\n\n" + c.messages.map { m in
            "## \(m.role == .user ? "你" : "AkiChat")\n\n" +
            (m.reasoning.isEmpty ? "" : "<details><summary>思考</summary>\n\n\(m.reasoning)\n\n</details>\n\n") +
            m.content + m.images.map { "\n\n![图片](\($0.dataURL))" }.joined() + "\n\n"
        }.joined()
    }
}

enum AppError: LocalizedError {
    case validation(String), http(Int), malformed, interrupted, empty, storage(String)
    var errorDescription: String? {
        switch self {
        case .validation(let s), .storage(let s): return s
        case .http(let code):
            switch code {
            case 401, 403: return "认证失败（\(code)），请检查 API Key 和权限。"
            case 402: return "余额不足（402），请检查服务商账户。"
            case 429: return "请求过于频繁或额度不足（429），请稍后重试。"
            case 400, 404, 422: return "请求被拒绝（\(code)），请检查地址、模型 ID 和能力设置。"
            default: return "服务响应错误（HTTP \(code)），请稍后重试。"
            }
        case .malformed: return "服务返回了无法解析的数据，请检查接口兼容性。"
        case .interrupted: return "连接提前中断，已保留收到的内容，可重新生成。"
        case .empty: return "服务未返回回答，请检查模型或重新生成。"
        }
    }
}
