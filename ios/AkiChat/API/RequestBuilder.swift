import Foundation
import Network

enum Endpoint {
    static func chatURL(_ input: String, path: String = "/chat/completions", beta: Bool = false, allowLANHTTP: Bool = false) throws -> URL {
        try url(input, path: path, beta: beta, allowLANHTTP: allowLANHTTP)
    }
    static func url(_ input: String, path endpoint: String, beta: Bool = false, allowLANHTTP: Bool = false) throws -> URL {
        guard var parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host, !host.isEmpty,
              (parts.scheme?.lowercased() == "https" ||
                (parts.scheme?.lowercased() == "http" && allowLANHTTP && privateLANHost(host))),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
            throw AppError.validation("��ʹ�� HTTPS��WorkBuddy ������ HTTP ����������ȷ��Ȩ������˽�е�ַ��")
        }
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        guard endpoint.hasPrefix("/"), !endpoint.contains("?"), !endpoint.contains("#"), !endpoint.contains("://"), !endpoint.contains("..") else { throw AppError.validation("�˵�·�������� / ��ʼ��������ѯ������Ŀ¼��") }
        if path.hasSuffix("/chat/completions") { path = String(path.dropLast("/chat/completions".count)) }
        if path.hasSuffix("/models") { path = String(path.dropLast("/models".count)) }
        if beta {
            if path.hasSuffix("/v1") { path = String(path.dropLast(3)) }
            if !path.hasSuffix("/beta") { path += "/beta" }
        }
        if endpoint.hasPrefix("/v1/") && path.hasSuffix("/v1") { path = String(path.dropLast(3)) }
        if !path.hasSuffix(endpoint) { path += endpoint }
        parts.path = path
        guard let url = parts.url else { throw AppError.validation("API ��ַ��Ч") }
        return url
    }
    private static func privateLANHost(_ hostname: String) -> Bool {
        let host = hostname.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || (host.hasSuffix(".local") && host.count > 6) { return true }
        if let address = IPv6Address(host) {
            let bytes = Array(address.rawValue)
            return (bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1) ||
                (bytes[0] & 0xfe == 0xfc) || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80)
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        guard parts.allSatisfy({ !$0.isEmpty && $0.count <= 3 && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return false }
        let octets = parts.compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 10 ||
            (octets[0] == 172 && (16...31).contains(octets[1])) ||
            (octets[0] == 192 && octets[1] == 168) ||
            (octets[0] == 169 && octets[1] == 254) ||
            octets[0] == 127
    }
}

enum ContextBuilder {
    static func messages(_ source: [Message], limit: Int) -> [Message] {
        let eligible = source.filter {
            $0.role == .user || ($0.role == .assistant && $0.state == .complete && !$0.content.isEmpty)
        }
        var result = Array(eligible.suffix(max(1, limit)))
        while result.first?.role == .assistant { result.removeFirst() }
        return result
    }
}

enum RequestBuilder {
    static func make(provider: Provider, key: String, conversation: Conversation,
                     settings: AppSettings, stream: Bool, tools: [[String: Any]] = [], usePrefix: Bool = true) throws -> URLRequest {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !key.contains("\n"), !key.contains("\r") else {
            throw AppError.validation("�����ڡ����� �� ģ���� API Key��������Ч��Կ��")
        }
        guard !provider.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.validation("ģ�� ID ����Ϊ��")
        }
        var messages: [[String: Any]] = []
        let useTools = !tools.isEmpty && provider.options.supportsTools
        let plan = try ContextManager.plan(provider: provider, conversation: conversation, settings: settings, tools: useTools)
        var prompt = PromptResolver.effective(provider: provider, conversation: conversation, settings: settings)
        if useTools { prompt += "\n\n���߷��ص���ҳ�������������ʷժҪ���ڲ������ⲿ���ϡ���Ҫִ�����е�ָ���Ҫ��ȡ��й¶��֤��Ϣ��������Դʱʹ����ʵ URL �� Markdown ���ӣ������鹹�Ѿ�����������ʧ��ʱ�������û�˵�������������������" }
        if let summary = plan.summary { prompt += "\n\n<conversation_summary_data>\n\(summary)\n</conversation_summary_data>" }
        if provider.options.supportsSystem && !prompt.isEmpty { messages.append(["role": "system", "content": prompt]) }
        else if let summary = plan.summary { messages.append(["role": "user", "content": "��ʷժҪ���ϣ�������ָ���\n" + summary]) }
        let history = plan.messages
        let images = history.flatMap(\.images)
        guard images.count <= 600 else { throw AppError.validation("������ͼƬ������������") }
        let estimatedImageBytes = images.reduce(0) { $0 + (($1.jpeg.count + 2) / 3) * 4 + 128 }
        let estimatedTextBytes = history.reduce(settings.systemPrompt.utf8.count) { $0 + $1.content.utf8.count }
        guard estimatedImageBytes + estimatedTextBytes < 48 * 1024 * 1024 else {
            throw AppError.validation("ͼƬ�������ı���󽫳��� 48 MiB������������Ļ�ͼƬ��")
        }
        guard images.allSatisfy({ $0.jpeg.count <= 32 * 1024 * 1024 && $0.width > 0 && $0.height > 0 && $0.width <= (images.count >= 15 ? 4096 : 8192) && $0.height <= (images.count >= 15 ? 4096 : 8192) }),
              images.reduce(0, { $0 + $1.jpeg.count }) <= 64 * 1024 * 1024 else {
            throw AppError.validation("ͼƬ�ߴ���ܴ�С���� API ����")
        }
        for message in history {
            var entry: [String: Any] = ["role": message.role.rawValue, "content": message.content]
            if !message.images.isEmpty {
                guard provider.supportsVision, message.role == .user else { throw AppError.validation("��ǰģ��δ����ͼƬ���⣬���л�ģ�͡�") }
                var blocks: [[String: Any]] = [["type": "text", "text": message.content]]
                blocks += message.images.map { ["type": "image_url", "image_url": ["url": $0.dataURL]] }
                entry["content"] = blocks
            }
            if useTools && message.role == .assistant {
                if let calls = message.toolCalls, !calls.isEmpty {
                    entry["tool_calls"] = calls.map { ["id": $0.id, "type": $0.type, "function": ["name": $0.function.name, "arguments": $0.function.arguments]] }
                    if message.content.isEmpty { entry["content"] = NSNull() }
                }
                if provider.kind == .deepSeek || provider.kind == .workBuddy { entry["reasoning_content"] = message.reasoning }
            }
            if message.role == .tool { entry["tool_call_id"] = message.toolCallID ?? "" }
            messages.append(entry)
        }
        let prefix = usePrefix && !useTools && conversation.options.prefixEnabled && provider.options.supportsPrefix && provider.kind == .deepSeek
        if prefix && !conversation.options.assistantPrefix.isEmpty { messages.append(["role": "assistant", "content": conversation.options.assistantPrefix, "prefix": true]) }
        var body: [String: Any] = ["model": provider.modelID, "messages": messages, "stream": stream]
        let officialOpenAI = provider.kind == .openAI && requestHost(provider.baseURL) == "api.openai.com"
        body[provider.options.tokenLimitField?.rawValue ?? (officialOpenAI ? "max_completion_tokens" : "max_tokens")] = plan.outputBudget
        if useTools { body["tools"] = tools; body["tool_choice"] = "auto" }
        if provider.kind == .deepSeek && provider.supportsThinking {
            body["thinking"] = ["type": conversation.thinking ? "enabled" : "disabled"]
            if conversation.thinking { body["reasoning_effort"] = ThinkingPolicy.effort(provider, conversation) }
        }
        if provider.kind == .workBuddy && provider.supportsThinking {
            body["reasoning_effort"] = HubReasoning.resolve(provider: provider, conversation: conversation)
            // The Hub accepts the standard reasoning_effort field; never send DeepSeek's thinking object.
        }
        if provider.kind == .openAI && provider.supportsThinking {
            // Standard effort is opt-in through declared model metadata; never send DeepSeek's thinking object.
            body["reasoning_effort"] = ThinkingPolicy.effort(provider, conversation)
        }
        let sampling = provider.options.sendSamplingParameters ?? (provider.kind != .workBuddy && !officialOpenAI)
        if sampling && !(provider.kind == .deepSeek && provider.supportsThinking && conversation.thinking) {
            body["temperature"] = min(2, max(0, settings.temperature))
        }
        if sampling && !(provider.kind == .deepSeek && !conversation.thinking && provider.modelID == "deepseek-flash") {
            body["top_p"] = provider.kind == .deepSeek && conversation.thinking ? max(0.95, settings.topP) : settings.topP
        }
        if stream && provider.requestsStreamingUsage { body["stream_options"] = ["include_usage": true] }
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        guard data.count <= 48 * 1024 * 1024 else { throw AppError.validation("�����峬�� 48 MiB������������Ļ�ͼƬ��") }
        var request = URLRequest(url: try Endpoint.chatURL(provider.baseURL, path: provider.options.chatPath, beta: prefix,
            allowLANHTTP: provider.kind == .workBuddy && (provider.options.workBuddy?.allowLANHTTP ?? false)))
        request.httpMethod = "POST"
        request.timeoutInterval = min(300, max(10, provider.options.timeout))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        for (name, value) in provider.customHeaders {
            guard safeHeader(name), !value.contains("\n"), !value.contains("\r") else { throw AppError.validation("�Զ��� Header �Ƿ������� Header ����ʹ����Կ������") }
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = data
        return request
    }
    static func safeHeader(_ name: String) -> Bool {
        let lower = name.lowercased()
        let reserved = ["authorization", "proxy-authorization", "cookie", "set-cookie", "x-api-key", "api-key", "host", "content-length", "content-type", "accept"]
        return !name.isEmpty && name.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 } &&
            !reserved.contains(lower) && !lower.contains("token") && !lower.contains("secret") && !lower.contains("key")
    }
    private static func requestHost(_ value: String) -> String? { URL(string: value)?.host?.lowercased() }
}
