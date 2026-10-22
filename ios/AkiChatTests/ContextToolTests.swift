import XCTest
import Combine
@testable import AkiChat

final class ContextTests: XCTestCase {
    func history(_ count: Int, text: String = "旧消息") -> Conversation {
        var c = Conversation(providerID: Provider.deepSeek.id)
        for i in 0..<count { c.messages += [Message(role: .user, content: "\(i) " + text), Message(role: .assistant, content: "答 " + text, reasoning: "推理\(i)")] }
        c.messages.append(Message(role: .user, content: "当前问题")); return c
    }
    func testBudgetKeepsRawHistoryAndWholeTurns() throws {
        var c = history(5, text: String(repeating: "中", count: 400))
        c.options.context.inputBudget = 4096; c.options.context.outputBudget = 512
        let before = c.messages
        let p = try ContextManager.plan(provider: .deepSeek, conversation: c, settings: AppSettings(), tools: false)
        XCTAssertLessThanOrEqual(p.estimatedTokens + p.outputBudget, p.totalBudget)
        XCTAssertGreaterThan(p.omittedTurns, 0); XCTAssertEqual(p.messages.first?.role, .user)
        XCTAssertEqual(c.messages, before); XCTAssertEqual(p.messages.last?.content, "当前问题")
    }
    func testFullBudgetFailureAndSlidingWindow() throws {
        var c = history(8, text: String(repeating: "中", count: 400))
        c.options.context.inputBudget = 4096; c.options.context.outputBudget = 512; c.options.context.strategy = .full
        XCTAssertThrowsError(try ContextManager.plan(provider: .deepSeek, conversation: c, settings: AppSettings(), tools: false))
        c.options.context.strategy = .window; c.options.context.recentTurns = 1
        let p = try ContextManager.plan(provider: .deepSeek, conversation: c, settings: AppSettings(), tools: false)
        XCTAssertEqual(p.messages.count, 3) // one completed turn plus the current user
    }
    func testAutoCompressionThresholdAndCoverage() throws {
        var c = history(4, text: String(repeating: "中", count: 600))
        c.options.context.inputBudget = 4096; c.options.context.outputBudget = 512
        c.options.context.autoCompress = true; c.options.context.recentTurns = 1
        XCTAssertTrue(ContextManager.shouldCompress(provider: .deepSeek, conversation: c, settings: AppSettings(), tools: false))
        let input = try ContextManager.compressionInput(conversation: c, provider: .deepSeek)
        XCTAssertEqual(input.coveredMessageIDs.count, 6)
        let version = SummaryVersion(text: "摘要", coveredMessageIDs: input.coveredMessageIDs, providerID: Provider.deepSeek.id, modelID: "deepseek-flash")
        c.summaries = [version]; c.activeSummaryID = version.id; c.options.context.strategy = .summary
        let plan = try ContextManager.plan(provider: .deepSeek, conversation: c, settings: AppSettings(), tools: false)
        XCTAssertEqual(plan.summary, "摘要"); XCTAssertEqual(plan.messages.count, 3)
        c.options.context.autoCompress = false
        XCTAssertFalse(ContextManager.shouldCompress(provider: .deepSeek, conversation: c, settings: AppSettings(), tools: false))
    }
    func testAtomicToolChainsAndReasoningRoundTrip() throws {
        let call = ToolCall(id: "call1", function: .init(name: "calculate", arguments: "{\"expression\":\"1+2\"}"))
        var c = Conversation(providerID: Provider.deepSeek.id)
        c.messages = [Message(role: .user, content: "计算"), Message(role: .assistant, content: "", reasoning: "完整历史推理", toolCalls: [call]), Message(role: .tool, content: "3", toolCallID: "call1"), Message(role: .assistant, content: "3"), Message(role: .user, content: "继续")]
        c.options.toolsEnabled = true
        let defs = ToolPolicy.definitions(c.options, canSearch: false)
        let request = try RequestBuilder.make(provider: .deepSeek, key: "mock", conversation: c, settings: AppSettings(), stream: true, tools: defs)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertTrue(messages.contains { $0["reasoning_content"] as? String == "完整历史推理" })
        XCTAssertTrue(messages.contains { $0["tool_call_id"] as? String == "call1" })
        let plain = try RequestBuilder.make(provider: .deepSeek, key: "mock", conversation: c, settings: AppSettings(), stream: false)
        XCTAssertFalse(String(decoding: plain.httpBody!, as: UTF8.self).contains("完整历史推理"))
        c.messages.remove(at: 2)
        XCTAssertFalse(ContextManager.turns(c.messages).flatMap { $0 }.contains { $0.toolCalls != nil })
    }
    func testPromptMergesEveryLayerAndDisabling() {
        var settings = AppSettings(); settings.systemPrompt = "app"
        let preset = PromptPreset(name: "test", text: "preset")
        settings.options.presets = [preset]; settings.options.presetIDs = [preset.id]
        var p = Provider.deepSeek; p.options.systemPrompt = "provider"
        var c = Conversation(providerID: p.id); c.options.systemPrompt = "conversation"
        let text = PromptResolver.effective(provider: p, conversation: c, settings: settings)
        XCTAssertTrue(text.contains("app")); XCTAssertTrue(text.contains("preset")); XCTAssertTrue(text.contains("provider")); XCTAssertTrue(text.hasSuffix("conversation"))
        c.options.systemPrompt = "updated"
        XCTAssertTrue(PromptResolver.effective(provider: p, conversation: c, settings: settings).hasSuffix("updated"))
        settings.options.promptEnabled = false
        XCTAssertEqual(PromptResolver.effective(provider: p, conversation: c, settings: settings), "")
    }
    func testSummaryRollbackAndOriginalMessages() throws {
        let db = try LocalDatabase(inMemory: true)
        var c = history(3)
        let old = SummaryVersion(text: "old", coveredMessageIDs: [c.messages[0].id], providerID: c.providerID, modelID: "deepseek-flash")
        let newer = SummaryVersion(text: "new", coveredMessageIDs: [c.messages[0].id, c.messages[1].id], providerID: c.providerID, modelID: "deepseek-flash")
        c.summaries = [old, newer]; c.activeSummaryID = newer.id
        try db.save([c], key: "conversations.v1")
        let store = AppStore(database: db); store.rollbackSummary()
        XCTAssertEqual(store.current?.activeSummary?.text, "old"); XCTAssertEqual(store.current?.messages, c.messages)
        store.activateSummary(nil); XCTAssertNil(store.current?.activeSummary); XCTAssertEqual(store.current?.summaries?.count, 2)
    }
    func testPrefixUsesBetaAndSeparateAssistantFlag() throws {
        var c = history(0); c.options.prefixEnabled = true; c.options.assistantPrefix = "```swift\n"
        let request = try RequestBuilder.make(provider: .deepSeek, key: "mock", conversation: c, settings: AppSettings(), stream: false)
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/beta/chat/completions")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.last?["prefix"] as? Bool, true); XCTAssertEqual(messages.last?["role"] as? String, "assistant")
        var p = Provider.deepSeek; p.kind = .openAI
        XCTAssertFalse(try RequestBuilder.make(provider: p, key: "mock", conversation: c, settings: AppSettings(), stream: false).url!.path.contains("beta"))
    }
    func testKeychainRoundTripAndDeletion() throws {
        let reference = "test-" + UUID().uuidString
        defer { try? KeychainStore.delete(reference) }
        try KeychainStore.write("mock-unit-test", reference: reference)
        XCTAssertEqual(try KeychainStore.read(reference), "mock-unit-test")
        try KeychainStore.delete(reference); XCTAssertNil(try KeychainStore.read(reference))
    }
}

final class ToolTests: XCTestCase {
    func testSafeCalculatorAndRejections() throws {
        XCTAssertEqual(try SafeCalculator.evaluate("(2+3)*4-2^3"), 12)
        XCTAssertEqual(try SafeCalculator.evaluate("-3 + 1.5"), -1.5)
        for expression in ["1/0", "system('ls')", "1e999", String(repeating: "(", count: 40) + "1" + String(repeating: ")", count: 40), "2^99999"] { XCTAssertThrowsError(try SafeCalculator.evaluate(expression)) }
    }
    func testPermissionWhitelistAndURLValidation() {
        var options = ConversationOptions(); options.toolsEnabled = true
        let executor = BuiltInToolExecutor(options: options, search: nil, count: 5)
        _ = executor.execute(ToolCall(id: "a", function: .init(name: "read_file", arguments: "{}"))) { XCTAssertTrue($0.failed) }
        _ = executor.execute(ToolCall(id: "b", function: .init(name: "calculate", arguments: "{\"expression\":\"1+1\",\"command\":\"bad\"}"))) { XCTAssertTrue($0.failed) }
        for url in ["file:///etc/passwd", "https://127.0.0.1", "http://192.168.1.1", "https://local.local", "https://user:pass@example.com"] { XCTAssertNil(ToolPolicy.publicURL(url)) }
        XCTAssertNotNil(ToolPolicy.publicURL("https://example.com/article"))
    }
    func testDeepSeekSearchAndFetchMock() throws {
        let config = { () -> URLSessionConfiguration in let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [MockURLProtocol.self]; return c }
        MockURLProtocol.handler = { request, client, proto in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mock")
            let isSearch = request.url!.path.hasSuffix("search")
            let text = isSearch ? "{\"results\":[{\"title\":\"Source\",\"url\":\"https://example.com/a\",\"summary\":\"external text\"}]}" : "{\"title\":\"Page\",\"content\":\"read text\"}"
            client.urlProtocol(proto, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(proto, didLoad: Data(text.utf8)); client.urlProtocolDidFinishLoading(proto)
        }
        let service = DeepSeekSearchService(key: "mock", configuration: config)
        let searchDone = expectation(description: "search")
        let task = service.search(query: "test", count: 5) { result in XCTAssertEqual(try? result.get().first?.url, "https://example.com/a"); searchDone.fulfill() }
        wait(for: [searchDone], timeout: 3); withExtendedLifetime(task) {}
        let fetchDone = expectation(description: "fetch")
        let fetch = service.fetch(url: "https://example.com/a") { result in XCTAssertTrue((try? result.get().contains("read text")) ?? false); fetchDone.fulfill() }
        wait(for: [fetchDone], timeout: 3); withExtendedLifetime(fetch) {}
        MockURLProtocol.handler = nil
    }
    func testIncrementalToolCallArgumentsOverSSE() {
        let done = expectation(description: "tool SSE")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.handler = { req, client, proto in
            client.urlProtocol(proto, didReceive: HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            let first: [String: Any] = ["index": 0, "id": "a", "type": "function", "function": ["name": "calculate", "arguments": "{\"expression\":\""]]
            let second: [String: Any] = ["index": 0, "function": ["arguments": "1+2\"}"]]
            let frames: [[String: Any]] = [
                ["choices": [["delta": ["tool_calls": [first]]]]],
                ["choices": [["delta": ["tool_calls": [second]], "finish_reason": "tool_calls"]]]]
            for frame in frames {
                let bytes = Data(("data: " + String(decoding: try! JSONSerialization.data(withJSONObject: frame), as: UTF8.self) + "\n\n").utf8)
                for byte in bytes { client.urlProtocol(proto, didLoad: Data([byte])) }
            }
            client.urlProtocol(proto, didLoad: Data("data: [DONE]\n\n".utf8)); client.urlProtocolDidFinishLoading(proto)
        }
        let client = ChatTransport()
        client.start(request: URLRequest(url: URL(string: "https://mock.invalid")!), stream: true, configuration: config, onUpdate: { _ in }, completion: { result in
            let value = try? result.get(); XCTAssertEqual(value?.toolCalls.first?.function.arguments, "{\"expression\":\"1+2\"}")
            XCTAssertEqual(value?.toolCalls.first?.id, "a"); done.fulfill()
        })
        wait(for: [done], timeout: 3); MockURLProtocol.handler = nil
    }
}

final class ScriptedSender: ChatRequestSending {
    let action: (URLRequest, @escaping (Result<ChatSnapshot, Error>) -> Void) -> Void
    var cancelled = false
    init(_ action: @escaping (URLRequest, @escaping (Result<ChatSnapshot, Error>) -> Void) -> Void) { self.action = action }
    func send(_ request: URLRequest, stream: Bool, onUpdate: @escaping (ChatSnapshot) -> Void, completion: @escaping (Result<ChatSnapshot, Error>) -> Void) { action(request, completion) }
    func cancel() { cancelled = true }
}
final class ChatLoopTests: XCTestCase {
    func testFunctionCallingMultiRoundAndReasoning() {
        var c = Conversation(providerID: Provider.deepSeek.id, messages: [Message(role: .user, content: "计算 1+2")]); c.options.toolsEnabled = true
        var requests: [URLRequest] = []
        let done = expectation(description: "tool loop")
        let call = ToolCall(id: "call", function: .init(name: "calculate", arguments: "{\"expression\":\"1+2\"}"))
        let run = ChatRun(provider: .deepSeek, key: "mock", conversation: c, settings: AppSettings(), executor: BuiltInToolExecutor(options: c.options, search: nil, count: 5), canSearch: false, senderFactory: {
            ScriptedSender { request, completion in
                requests.append(request)
                var snapshot = ChatSnapshot()
                if requests.count == 1 { snapshot.reasoning = "需要计算"; snapshot.toolCalls = [call]; snapshot.finishReason = "tool_calls" }
                else { snapshot.content = "结果是 3" }
                DispatchQueue.main.async { completion(.success(snapshot)) }
            }
        }, update: { _, _ in }, completion: { result in
            guard case .success(let messages) = result else { return XCTFail("Expected final answer") }
            XCTAssertEqual(messages.last?.content, "结果是 3"); XCTAssertEqual(requests.count, 2)
            let text = String(decoding: requests[1].httpBody!, as: UTF8.self)
            XCTAssertTrue(text.contains("需要计算")); XCTAssertTrue(text.contains("tool_call_id"))
            XCTAssertEqual(messages.filter { $0.role == .tool }.count, 1); done.fulfill()
        })
        run.start(); wait(for: [done], timeout: 3)
    }
    func testLoopLimitAndCancellation() {
        var c = Conversation(providerID: Provider.deepSeek.id, messages: [Message(role: .user, content: "计算")]); c.options.toolsEnabled = true; c.options.maxToolRounds = 1
        let done = expectation(description: "limit")
        let run = ChatRun(provider: .deepSeek, key: "mock", conversation: c, settings: AppSettings(), executor: BuiltInToolExecutor(options: c.options, search: nil, count: 5), canSearch: false, senderFactory: {
            ScriptedSender { _, completion in
                var s = ChatSnapshot(); s.toolCalls = [ToolCall(id: UUID().uuidString, function: .init(name: "current_time", arguments: "{}"))]
                DispatchQueue.main.async { completion(.success(s)) }
            }
        }, update: { _, _ in }, completion: { result in if case .success = result { XCTFail("Loop must stop") }; done.fulfill() })
        run.start(); wait(for: [done], timeout: 3)
        let cancelled = expectation(description: "cancel")
        let waiting = ChatRun(provider: .deepSeek, key: "mock", conversation: c, settings: AppSettings(), executor: BuiltInToolExecutor(options: c.options, search: nil, count: 5), canSearch: false, senderFactory: { ScriptedSender { _, _ in } }, update: { _, _ in }, completion: { result in
            guard case .failure(let error) = result else { return XCTFail("Expected cancellation") }
            XCTAssertEqual((error as? URLError)?.code, .cancelled); cancelled.fulfill()
        })
        waiting.start(); waiting.cancel(); wait(for: [cancelled], timeout: 3)
    }
    func testInvalidSummaryFailsWithoutReplacingPreviousVersion() throws {
        var c = Conversation(providerID: Provider.deepSeek.id)
        for _ in 0..<3 { c.messages += [Message(role: .user, content: "history"), Message(role: .assistant, content: "answer")] }
        c.options.context.recentTurns = 1
        let old = SummaryVersion(text: "old", coveredMessageIDs: [c.messages[0].id], providerID: c.providerID, modelID: "deepseek-flash")
        c.summaries = [old]; c.activeSummaryID = old.id
        let done = expectation(description: "summary failure")
        let task = try SummaryService.generate(provider: .deepSeek, key: "mock", conversation: c, senderFactory: { ScriptedSender { _, completion in
            var s = ChatSnapshot(); s.content = "not-json"; DispatchQueue.main.async { completion(.success(s)) }
        } }, completion: { result in
            if case .success = result { XCTFail("Invalid summary must fail") }
            XCTAssertEqual(c.activeSummary?.text, "old"); XCTAssertEqual(c.messages.count, 6); done.fulfill()
        })
        wait(for: [done], timeout: 3); withExtendedLifetime(task) {}
    }
}
