import Foundation

enum Endpoint {
    static func chatURL(_ input: String) throws -> URL {
        guard var parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
            throw AppError.validation("Base URL 必须是无账号、查询参数和片段的 HTTPS 地址。")
        }
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/chat/completions") { path += "/chat/completions" }
        parts.path = path
        guard let url = parts.url else { throw AppError.validation("API 地址无效") }
        return url
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
                     settings: AppSettings, stream: Bool) throws -> URLRequest {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !key.contains("\n"), !key.contains("\r") else {
            throw AppError.validation("请先在“设置 → 模型与 API Key”保存有效密钥。")
        }
        guard !provider.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.validation("模型 ID 不能为空")
        }
        var messages: [[String: Any]] = []
        if !settings.systemPrompt.isEmpty { messages.append(["role": "system", "content": settings.systemPrompt]) }
        let history = ContextBuilder.messages(conversation.messages, limit: settings.contextCount)
        let images = history.flatMap(\.images)
        guard images.count <= 600 else { throw AppError.validation("上下文图片数量超出限制") }
        let estimatedImageBytes = images.reduce(0) { $0 + (($1.jpeg.count + 2) / 3) * 4 + 128 }
        let estimatedTextBytes = history.reduce(settings.systemPrompt.utf8.count) { $0 + $1.content.utf8.count }
        guard estimatedImageBytes + estimatedTextBytes < 48 * 1024 * 1024 else {
            throw AppError.validation("图片与上下文编码后将超过 48 MiB，请减少上下文或图片。")
        }
        guard images.allSatisfy({ $0.jpeg.count <= 32 * 1024 * 1024 && $0.width > 0 && $0.height > 0 && $0.width <= (images.count >= 15 ? 4096 : 8192) && $0.height <= (images.count >= 15 ? 4096 : 8192) }),
              images.reduce(0, { $0 + $1.jpeg.count }) <= 64 * 1024 * 1024 else {
            throw AppError.validation("图片尺寸或总大小超出 API 限制")
        }
        for message in history {
            if !message.images.isEmpty {
                guard provider.supportsVision, message.role == .user else { throw AppError.validation("当前模型未启用图片理解，请切换模型。") }
                var blocks: [[String: Any]] = [["type": "text", "text": message.content]]
                blocks += message.images.map { ["type": "image_url", "image_url": ["url": $0.dataURL]] }
                messages.append(["role": message.role.rawValue, "content": blocks])
            } else { messages.append(["role": message.role.rawValue, "content": message.content]) }
            // No tools in v1: never return stored reasoning_content to the API.
        }
        var body: [String: Any] = ["model": provider.modelID, "messages": messages,
            "stream": stream, "max_tokens": min(32768, max(256, settings.maxTokens))]
        if provider.kind == .deepSeek && provider.supportsThinking {
            body["thinking"] = ["type": conversation.thinking ? "enabled" : "disabled"]
            if conversation.thinking { body["reasoning_effort"] = conversation.effort.rawValue }
        }
        if !(provider.kind == .deepSeek && provider.supportsThinking && conversation.thinking) {
            body["temperature"] = min(2, max(0, settings.temperature))
        }
        body["top_p"] = provider.kind == .deepSeek && conversation.thinking ? max(0.95, settings.topP) : settings.topP
        if stream && provider.requestsStreamingUsage { body["stream_options"] = ["include_usage": true] }
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        guard data.count <= 48 * 1024 * 1024 else { throw AppError.validation("请求体超过 48 MiB，请减少上下文或图片。") }
        var request = URLRequest(url: try Endpoint.chatURL(provider.baseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        for (name, value) in provider.customHeaders {
            guard safeHeader(name), !value.contains("\n"), !value.contains("\r") else { throw AppError.validation("自定义 Header 非法，敏感 Header 必须使用密钥管理。") }
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
}
