import Foundation

enum PromptResolver {
    static func effective(provider: Provider, conversation: Conversation, settings: AppSettings) -> String {
        guard settings.options.promptEnabled else { return "" }
        let presets = settings.options.presets
        func layer(_ label: String, text: String, ids: [UUID]) -> String {
            let selected = ids.compactMap { id in presets.first { $0.id == id && $0.enabled }?.text }
            let values = ([text] + selected).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return values.isEmpty ? "" : "[\(label)]\n" + values.joined(separator: "\n\n")
        }
        let layers = [layer("应用默认", text: settings.systemPrompt, ids: settings.options.presetIDs),
                      layer("Provider / 模型", text: provider.options.systemPrompt, ids: provider.options.presetIDs),
                      layer("会话", text: conversation.options.systemPrompt, ids: conversation.options.presetIDs)].filter { !$0.isEmpty }
        guard !layers.isEmpty else { return "" }
        return "以下按应用、Provider、模型、会话顺序合并；相同主题发生冲突时，后面的更具体配置优先。\n\n" + layers.joined(separator: "\n\n")
    }
}

struct ContextPlan {
    var messages: [Message]
    var summary: String?
    var estimatedTokens: Int
    var fullEstimate: Int
    var totalBudget: Int
    var outputBudget: Int
    var omittedTurns: Int
    var needsCompression: Bool
}
struct CompressionInput {
    var text: String
    var coveredMessageIDs: [UUID]
}
enum ContextManager {
    static func estimate(_ text: String) -> Int { max(1, Int(ceil(Double(text.utf8.count) / 3.0))) }
    static func estimate(_ messages: [Message], reasoning: Bool) -> Int {
        messages.reduce(0) { total, message in
            total + 8 + estimate(message.content) + message.images.count * 1024 +
                (reasoning ? estimate(message.reasoning) : 0) +
                (message.toolCalls ?? []).reduce(0) { $0 + estimate($1.function.name + $1.function.arguments) }
        }
    }
    /// A turn begins at user; a tool chain is retained only if every tool call has a matching result.
    static func turns(_ messages: [Message], tools: Bool = true) -> [[Message]] {
        var raw: [[Message]] = []
        for m in messages where m.role != .system && m.state != .generating {
            if m.role == .user { raw.append([m]) }
            else if !raw.isEmpty { raw[raw.count - 1].append(m) }
        }
        return raw.map { turn in
            var result: [Message] = []; var index = 0
            while index < turn.count {
                let m = turn[index]
                if m.role == .user { result.append(m); index += 1; continue }
                guard m.role == .assistant && m.state == .complete else { index += 1; continue }
                if let calls = m.toolCalls, !calls.isEmpty {
                    var end = index + 1
                    while end < turn.count && turn[end].role == .tool { end += 1 }
                    let outputs = Array(turn[(index + 1)..<end])
                    let ids = Set(calls.map(\.id))
                    if tools && ids.count == calls.count && outputs.count == calls.count && Set(outputs.compactMap(\.toolCallID)) == ids {
                        result.append(m); result += outputs
                    }
                    index = end
                } else { if !m.content.isEmpty { result.append(m) }; index += 1 }
            }
            return result
        }
    }
    static func plan(provider: Provider, conversation: Conversation, settings: AppSettings, tools: Bool) throws -> ContextPlan {
        let options = conversation.options.context
        let budget = max(512, min(provider.options.contextWindow, options.inputBudget))
        let requestedOutput = conversation.advanced == nil ? settings.maxTokens : options.outputBudget
        let output = min(max(256, requestedOutput), max(256, provider.options.outputLimit), max(256, budget / 2))
        let prompt = PromptResolver.effective(provider: provider, conversation: conversation, settings: settings)
        let overhead = (provider.options.supportsSystem ? estimate(prompt) : 0) + (tools ? 900 : 0) + 64
        let reasoning = tools && provider.kind == .deepSeek
        var groups = turns(conversation.messages, tools: tools)
        let fullCount = groups.count
        let keep = max(1, options.recentTurns) + (groups.last?.last?.role == .user ? 1 : 0)
        let scale = min(2, max(0.5, options.calibration ?? 1))
        let fullEstimate = estimate(groups.flatMap { $0 }, reasoning: reasoning) + overhead
        let strategy = options.strategy
        let useSummary = strategy == .summary || (strategy == .automatic && options.autoCompress)
        let active = useSummary ? conversation.activeSummary : nil
        if let active = active {
            let covered = Set(active.coveredMessageIDs)
            groups = groups.filter { !$0.allSatisfy { covered.contains($0.id) } }
        }
        if strategy == .window { groups = Array(groups.suffix(keep)) }
        let summary = active?.text
        let summaryCost = summary.map(estimate) ?? 0
        func cost(_ groups: [[Message]]) -> Int { Int(ceil(Double(estimate(groups.flatMap { $0 }, reasoning: reasoning) + overhead + summaryCost) * scale)) }
        if strategy == .full && cost(groups) + output > budget { throw AppError.validation("完整历史超过上下文预算，请选择滑动窗口、摘要或提高预算；本地原始记录会保留。") }
        while groups.count > 1 && cost(groups) + output > budget { groups.removeFirst() }
        guard cost(groups) + output <= budget else { throw AppError.validation("当前消息、提示词或工具结果已超过上下文预算，请减少附件/消息长度或提高预算。") }
        return ContextPlan(messages: groups.flatMap { $0 }, summary: summary, estimatedTokens: cost(groups), fullEstimate: fullEstimate,
            totalBudget: budget, outputBudget: output, omittedTurns: fullCount - groups.count,
            needsCompression: options.autoCompress && strategy != .window && fullEstimate + output >= Int(Double(budget) * min(0.9, max(0.5, options.threshold))) && fullCount > max(1, options.recentTurns))
    }
    static func shouldCompress(provider: Provider, conversation: Conversation, settings: AppSettings, tools: Bool) -> Bool {
        let options = conversation.options.context
        guard options.autoCompress, options.strategy != .window else { return false }
        let groups = turns(conversation.messages, tools: tools)
        let budget = min(provider.options.contextWindow, options.inputBudget)
        let prompt = PromptResolver.effective(provider: provider, conversation: conversation, settings: settings)
        let covered = Set(conversation.activeSummary?.coveredMessageIDs ?? [])
        let uncovered = groups.filter { group in !group.allSatisfy { covered.contains($0.id) } }
        let input = estimate(uncovered.flatMap { $0 }, reasoning: tools && provider.kind == .deepSeek) + estimate(prompt) + estimate(conversation.activeSummary?.text ?? "") + (tools ? 900 : 64)
        let keep = max(1, options.recentTurns) + (groups.last?.last?.role == .user ? 1 : 0)
        return groups.count > keep && Int(Double(input) * min(2, max(0.5, options.calibration ?? 1))) + options.outputBudget >= Int(Double(budget) * min(0.9, max(0.5, options.threshold)))
    }
    static func compressionInput(conversation: Conversation, provider: Provider) throws -> CompressionInput {
        let groups = turns(conversation.messages)
        let keep = max(1, conversation.options.context.recentTurns) + (groups.last?.last?.role == .user ? 1 : 0)
        guard groups.count > keep else { throw AppError.validation("尚无可压缩的旧轮次，最近 \(keep) 轮将完整保留。") }
        let previous = conversation.activeSummary
        let covered = Set(previous?.coveredMessageIDs ?? [])
        let pending = groups.dropLast(keep).filter { !$0.allSatisfy { covered.contains($0.id) } }
        let budget = max(512, provider.options.contextWindow - min(4096, provider.options.outputLimit) - 1024)
        var selected: [[Message]] = []
        var count = estimate(previous?.text ?? "")
        for group in pending {
            let extra = estimate(group, reasoning: false)
            if count + extra > budget { break }
            selected.append(group); count += extra
        }
        guard !selected.isEmpty else { throw AppError.validation("没有新的可压缩历史，或最早一轮超过摘要模型预算。请指定更大上下文的摘要模型。") }
        let body = selected.flatMap { $0 }.map { message in
            var text = "\(message.role.rawValue): \(message.content)"
            if !message.images.isEmpty { text += " [\(message.images.count) 张历史图片，图像未附加到摘要请求]" }
            if let calls = message.toolCalls { text += "\n工具: " + calls.map { $0.function.name + " " + $0.function.arguments }.joined(separator: "\n") }
            return text
        }.joined(separator: "\n\n")
        return CompressionInput(text: "既有摘要（如有）：\n\(previous?.text ?? "无")\n\n新增历史资料：\n\(body)", coveredMessageIDs: Array(covered) + selected.flatMap { $0 }.map(\.id))
    }
}
