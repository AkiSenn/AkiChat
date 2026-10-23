import Foundation

/// Hub levels are opaque strings: new upstream levels must not require a client update.
enum HubReasoning {
    private static func clean(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !text.isEmpty, text.count <= 32,
              text.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 95 || $0 == 45 }) else { return nil }
        return text
    }
    static func levels(_ provider: Provider) -> [String] {
        var seen = Set<String>()
        return (provider.options.workBuddy?.reasoningEfforts ?? []).compactMap { clean($0) }
            .filter { $0 != "none" && seen.insert($0).inserted }
    }
    static func canDisable(_ provider: Provider) -> Bool {
        let hub = provider.options.workBuddy
        return hub?.canDisableThinking == true && hub?.alwaysReasoning != true
    }
    static func fixed(_ provider: Provider) -> String? {
        levels(provider).isEmpty ? clean(provider.options.workBuddy?.fixedEffort) : nil
    }
    static func resolve(provider: Provider, conversation: Conversation) -> String? {
        guard provider.kind == .workBuddy, provider.supportsThinking else { return nil }
        if !conversation.thinking && canDisable(provider) { return "none" }
        let hub = provider.options.workBuddy
        let choices = levels(provider)
        if let fixed = fixed(provider) { return fixed }
        let requested = clean(conversation.options.hubReasoningEffort ?? conversation.effort.rawValue)
        if let requested = requested, choices.contains(requested) { return requested }
        // supportedEfforts wins over a simultaneous fixed-effort metadata field, as in the Hub.
        for candidate in [clean(hub?.defaultEffort), clean(hub?.fixedEffort)] {
            if let candidate = candidate, choices.isEmpty || choices.contains(candidate) { return candidate }
        }
        return choices.first // No declared controls: omit the field and let the gateway decide.
    }
}
