import Foundation

struct ProviderOptions: Codable, Equatable {
    var chatPath = "/chat/completions"
    var modelsPath = "/models"
    var timeout: Double = 120
    var supportsTools = false
    var supportsSystem = true
    var supportsPrefix = false
    var contextWindow = 32768
    var outputLimit = 4096
    var systemPrompt = ""
    var presetIDs: [UUID] = []
}
extension Provider {
    var options: ProviderOptions {
        get {
            if let advanced = advanced { return advanced }
            var value = ProviderOptions()
            if kind == .deepSeek { value.supportsTools = true; value.supportsPrefix = true; value.contextWindow = 1048576; value.outputLimit = 32768 }
            return value
        }
        set { advanced = newValue }
    }
    static let openAI = Provider(name: "OpenAI", baseURL: "https://api.openai.com/v1", modelID: "", displayName: "手动选择 OpenAI 模型")
}

struct ModelCapabilities: Codable, Equatable {
    var vision: Bool?
    var thinking: Bool?
    var tools: Bool?
    var streaming: Bool?
    var systemPrompt: Bool?
    var prefix: Bool?
}
struct ModelRecord: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var contextWindow: Int?
    var outputLimit: Int?
    var inputModalities: [String] = []
    var outputModalities: [String] = []
    var effort: [String] = []
    var metadata: String = "{}"
    var discovered = ModelCapabilities()
    var overrides = ModelCapabilities()
    var favorite = false
    var order = 0
    var manual = false
    var systemPrompt = ""
    var presetIDs: [UUID] = []
    func apply(to base: Provider) -> Provider {
        var result = base
        result.modelID = id; result.displayName = name
        result.supportsVision = overrides.vision ?? discovered.vision ?? false
        result.supportsThinking = overrides.thinking ?? discovered.thinking ?? false
        result.supportsStreaming = overrides.streaming ?? discovered.streaming ?? base.supportsStreaming
        var options = result.options
        options.supportsTools = overrides.tools ?? discovered.tools ?? false
        options.supportsSystem = overrides.systemPrompt ?? discovered.systemPrompt ?? base.options.supportsSystem
        options.supportsPrefix = overrides.prefix ?? discovered.prefix ?? false
        options.contextWindow = contextWindow ?? base.options.contextWindow
        options.outputLimit = outputLimit ?? base.options.outputLimit
        options.systemPrompt += (options.systemPrompt.isEmpty || systemPrompt.isEmpty ? "" : "\n\n") + systemPrompt
        options.presetIDs += presetIDs
        result.options = options
        return result
    }
}
struct ModelCatalog: Codable, Identifiable {
    var id: UUID // Provider id
    var models: [ModelRecord] = []
    var syncedAt: Date?
}
enum ContextStrategy: String, Codable, CaseIterable { case automatic, full, window, summary }
enum SearchMode: String, Codable, CaseIterable { case off, automatic, always }
struct ContextOptions: Codable, Equatable {
    var inputBudget = 32768 // total input + reserved output
    var outputBudget = 4096
    var strategy: ContextStrategy = .automatic
    var recentTurns = 8
    var autoCompress = false
    var threshold = 0.75
    var summaryProviderID: UUID?
    var summaryModelID: String?
    var calibration: Double?
}
struct ConversationOptions: Codable, Equatable {
    var modelID: String?
    var context = ContextOptions()
    var systemPrompt = ""
    var presetIDs: [UUID] = []
    var toolsEnabled = false
    var searchMode: SearchMode = .off
    var searchTool = true
    var fetchTool = true
    var dateTool = true
    var calculatorTool = true
    var maxToolRounds = 4
    var prefixEnabled = false
    var assistantPrefix = ""
}
struct SummaryVersion: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var coveredMessageIDs: [UUID]
    var createdAt = Date()
    var usage: TokenUsage?
    var providerID: UUID
    var modelID: String
}
struct PromptPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var text: String
    var enabled = true
    static let defaults: [PromptPreset] = [
        PromptPreset(name: "通用助手", text: "提供准确、清楚、有帮助的回答。"),
        PromptPreset(name: "中文技术助手", text: "用清晰中文解释技术问题，标注不确定性。"),
        PromptPreset(name: "Swift 专家", text: "你擅长 Swift 和原生 iOS 开发；回答时关注 API 可用性和可维护性。"),
        PromptPreset(name: "翻译助手", text: "忠实保留原意、术语与语气，并给出自然的译文。"),
        PromptPreset(name: "编程助手", text: "优先给出可验证的实现，解释关键假设和测试方法。")]
}
struct GlobalOptions: Codable, Equatable {
    var presets: [PromptPreset] = PromptPreset.defaults
    var presetIDs: [UUID] = []
    var promptEnabled = true
    var externalConsent = false
    var searchProviderID: UUID?
    var searchCount = 5
    var imageDimension = 2048
    var imageQuality = 0.82
}
extension Conversation {
    var options: ConversationOptions {
        get { advanced ?? ConversationOptions() }
        set { advanced = newValue }
    }
    var activeSummary: SummaryVersion? { summaries?.first { $0.id == activeSummaryID } }
}
extension AppSettings {
    var options: GlobalOptions {
        get { advanced ?? GlobalOptions() }
        set { advanced = newValue }
    }
}

struct ToolCall: Codable, Identifiable, Equatable {
    struct Function: Codable, Equatable { var name: String; var arguments: String }
    var id: String
    var type = "function"
    var function: Function
}
struct SearchSource: Codable, Identifiable, Equatable {
    var id: String { url }
    var title: String
    var url: String
    var summary: String
    var query: String
}
struct ToolRecord: Codable, Identifiable, Equatable {
    var id: String { call.id }
    var call: ToolCall
    var result: String
    var failed = false
    var createdAt = Date()
    var sources: [SearchSource] = []
}
