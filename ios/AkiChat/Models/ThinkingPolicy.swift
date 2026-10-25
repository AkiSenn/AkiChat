import Foundation

/// Optional metadata on the resolved model; older provider archives remain decodable.
struct ReasoningMetadata: Codable, Equatable {
    var levels: [String] = []
    var defaultLevel: String?
    var fixedLevel: String?
    var canDisable: Bool?
    var alwaysOn: Bool?
}

enum ThinkingPolicy {
    private static func clean(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !text.isEmpty && text.count <= 32 && text.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 || $0 == 45 } ? text : nil
    }
    static func levels(_ p: Provider) -> [String] {
        if p.kind == .workBuddy { return HubReasoning.levels(p) }
        let declared = p.options.reasoning?.levels ?? []
        let source = declared.isEmpty && p.kind == .deepSeek && ["deepseek-flash", "deepseek-v4-pro"].contains(p.modelID) ? ["low", "high", "max"] : declared
        var seen = Set<String>()
        return source.compactMap(clean).filter { !$0.isEmpty && $0 != "none" && $0 != "default" && $0.count <= 32 && seen.insert($0).inserted }
    }
    static func canDisable(_ p: Provider) -> Bool {
        if p.kind == .deepSeek { return true }
        if p.kind == .workBuddy { return HubReasoning.canDisable(p) }
        return p.options.reasoning?.canDisable == true && p.options.reasoning?.alwaysOn != true
    }
    static func forced(_ p: Provider) -> Bool {
        if p.kind == .deepSeek { return false }
        if p.kind == .workBuddy { return p.options.workBuddy?.canDisableThinking == false || p.options.workBuddy?.alwaysReasoning == true }
        return p.options.reasoning?.canDisable == false || p.options.reasoning?.alwaysOn == true
    }
    static func active(_ p: Provider?, _ c: Conversation?) -> Bool {
        guard let p = p, let c = c, p.supportsThinking else { return false }
        return c.thinking || !canDisable(p)
    }
    static func selection(_ p: Provider, _ c: Conversation) -> String {
        if c.options.hubReasoningEffort == "default" { return "default" }
        let requested = c.options.hubReasoningEffort ?? (p.kind == .openAI ? "default" : (p.kind == .deepSeek && c.effort == .medium ? "high" : c.effort.rawValue))
        return levels(p).contains(requested) ? requested : "default"
    }
    static func effort(_ p: Provider, _ c: Conversation) -> String? {
        guard p.supportsThinking else { return nil }
        if p.kind == .workBuddy { return HubReasoning.resolve(provider: p, conversation: c) }
        if !c.thinking && canDisable(p) { return p.kind == .openAI ? "none" : nil }
        if let fixed = p.options.reasoning?.fixedLevel, levels(p).isEmpty { return clean(fixed) }
        let selected = selection(p, c)
        return selected == "default" ? nil : selected
    }
}
