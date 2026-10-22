import Foundation

struct ChatSnapshot {
    var content = ""
    var reasoning = ""
    var usage: TokenUsage?
    var finishReason: String?
    var toolCalls: [ToolCall] = []
}

/// Each instance owns exactly one request. Delegate work and throttling share a serial queue.
final class ChatTransport: NSObject, URLSessionDataDelegate {
    private let worker = DispatchQueue(label: "app.akichat.transport", qos: .userInitiated)
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var parser = SSEParser()
    private var buffer = Data()
    private var snapshot = ChatSnapshot()
    private var timer: DispatchSourceTimer?
    private var dirty = false
    private var terminal = false
    private var sawDone = false
    private var sawFinish = false
    private var stream = true
    private var status = 0
    private var toolParts: [Int: ToolCall] = [:]
    private var onUpdate: ((ChatSnapshot) -> Void)?
    private var onCompletion: ((Result<ChatSnapshot, Error>) -> Void)?
    // Inject URLProtocol through configuration in tests. Never log request headers or body.
    func start(request: URLRequest, stream: Bool, configuration: URLSessionConfiguration = .ephemeral,
               onUpdate: @escaping (ChatSnapshot) -> Void,
               completion: @escaping (Result<ChatSnapshot, Error>) -> Void) {
        worker.async {
            self.stream = stream; self.onUpdate = onUpdate; self.onCompletion = completion
            configuration.timeoutIntervalForRequest = request.timeoutInterval
            configuration.timeoutIntervalForResource = max(120, request.timeoutInterval * 5)
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1; queue.underlyingQueue = self.worker
            self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
            let timer = DispatchSource.makeTimerSource(queue: self.worker)
            timer.schedule(deadline: .now() + .milliseconds(80), repeating: .milliseconds(80))
            timer.setEventHandler { [weak self] in self?.flush() }
            self.timer = timer; timer.resume()
            self.task = self.session?.dataTask(with: request); self.task?.resume()
        }
    }
    func cancel() {
        worker.async { self.task?.cancel(); self.complete(.failure(URLError(.cancelled))) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else { completionHandler(.cancel); complete(.failure(AppError.malformed)); return }
        status = http.statusCode
        guard (200...299).contains(status) else {
            completionHandler(.cancel); complete(.failure(AppError.http(status))); return
        }
        completionHandler(.allow)
    }
    // Prevent redirects from leaking Authorization/custom headers to a different endpoint.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
        complete(.failure(AppError.validation("API 返回重定向，请填写最终 HTTPS 地址。")))
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !terminal else { return }
        do {
            if stream {
                for event in try parser.feed(data) {
                    if event.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" { sawDone = true; continue }
                    guard !sawDone else { continue }
                    try consume(ChatEnvelope.decode(Data(event.utf8)))
                }
                if sawDone { completeSuccess(); task?.cancel() }
            } else {
                buffer.append(data)
                guard buffer.count <= 16 * 1024 * 1024 else { throw AppError.malformed }
            }
        } catch { complete(.failure(error)); task?.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !terminal else { return }
        if let error = error { complete(.failure(error)); return }
        do {
            if stream {
                _ = try parser.finish()
                guard sawDone || sawFinish else { throw AppError.interrupted }
            } else { try consume(ChatEnvelope.decode(buffer)) }
            completeSuccess()
        } catch { complete(.failure(error)) }
    }
    private func consume(_ envelope: ChatEnvelope) throws {
        if let usage = envelope.usage { snapshot.usage = usage }
        if let choice = envelope.choices?.first {
            let part = stream ? choice.delta : choice.message
            snapshot.content += part?.content ?? ""
            snapshot.reasoning += part?.reasoning_content ?? ""
            for (position, delta) in (part?.tool_calls ?? []).enumerated() {
                let index = delta.index ?? position
                guard index >= 0, index < 8 else { throw AppError.validation("单轮最多 8 个工具调用") }
                var call = toolParts[index] ?? ToolCall(id: "", function: .init(name: "", arguments: ""))
                if let id = delta.id { call.id = id }
                if let type = delta.type { call.type = type }
                call.function.name += delta.function?.name ?? ""
                call.function.arguments += delta.function?.arguments ?? ""
                guard call.function.arguments.utf8.count <= 65536, call.function.name.count <= 128, call.id.count <= 256 else { throw AppError.validation("工具参数超出长度限制") }
                toolParts[index] = call
            }
            snapshot.toolCalls = toolParts.keys.sorted().compactMap { toolParts[$0] }
            if let reason = choice.finish_reason, !reason.isEmpty {
                sawFinish = true
                snapshot.finishReason = reason
                if reason == "content_filter" { throw AppError.validation("服务商拦截了这次回答。") }
            }
        }
        guard snapshot.content.utf8.count + snapshot.reasoning.utf8.count <= 8 * 1024 * 1024 else { throw AppError.validation("回答超出客户端长度限制，已保留内容。") }
        dirty = true
    }
    private func flush() {
        guard dirty else { return }; dirty = false
        let value = snapshot, callback = onUpdate
        DispatchQueue.main.async { callback?(value) }
    }
    private func completeSuccess() {
        if snapshot.content.isEmpty && snapshot.toolCalls.isEmpty { complete(.failure(AppError.empty)) }
        else { complete(.success(snapshot)) }
    }
    private func complete(_ result: Result<ChatSnapshot, Error>) {
        guard !terminal else { return }; terminal = true
        flush(); timer?.cancel(); timer = nil
        let callback = onCompletion; onCompletion = nil; onUpdate = nil
        session?.invalidateAndCancel(); session = nil; task = nil
        DispatchQueue.main.async { callback?(result) }
    }
}
