import XCTest
import SwiftUI
@testable import AkiChat

final class RequestTests: XCTestCase {
    func body(_ provider: Provider = .deepSeek, thinking: Bool = true, effort: ReasoningEffort = .high, stream: Bool = true) throws -> [String: Any] {
        var c = Conversation(providerID: provider.id); c.thinking = thinking; c.effort = effort
        c.messages = [Message(role: .user, content: "你好")]
        let request = try RequestBuilder.make(provider: provider, key: "mock-key", conversation: c, settings: AppSettings(), stream: stream)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mock-key")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }
    func testDeepSeekDefaults() throws {
        XCTAssertEqual(Provider.deepSeek.modelID, "deepseek-flash")
        XCTAssertEqual(Provider.deepSeek.baseURL, "https://api.deepseek.com")
        XCTAssertEqual(try Endpoint.chatURL(Provider.deepSeek.baseURL).absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(try body()["model"] as? String, "deepseek-flash")
    }
    func testEndpointNormalization() throws {
        for base in ["https://example.com/v1", "https://example.com/v1/", "https://example.com/v1/chat/completions", "https://example.com/v1/chat/completions/"] {
            XCTAssertEqual(try Endpoint.chatURL(base).absoluteString, "https://example.com/v1/chat/completions")
        }
        for invalid in ["http://example.com", "https://user:password@example.com", "https://example.com?key=x", "https://example.com/#x", "file:///tmp"] { XCTAssertThrowsError(try Endpoint.chatURL(invalid)) }
    }
    func testThinkingAndEffort() throws {
        for effort in ReasoningEffort.allCases {
            let value = try body(effort: effort)
            XCTAssertEqual((value["thinking"] as? [String: String])?["type"], "enabled")
            XCTAssertEqual(value["reasoning_effort"] as? String, effort.rawValue)
            XCTAssertNil(value["temperature"])
        }
        let off = try body(thinking: false)
        XCTAssertEqual((off["thinking"] as? [String: String])?["type"], "disabled")
        XCTAssertNil(off["reasoning_effort"])
        XCTAssertNotNil(off["temperature"])
    }
    func testOpenAIAdapterDoesNotLeakDeepSeekParameters() throws {
        var p = Provider.deepSeek; p.kind = .openAI
        p.requestsStreamingUsage = false
        let value = try body(p, stream: false)
        XCTAssertNil(value["thinking"]); XCTAssertNil(value["reasoning_effort"])
        XCTAssertEqual(value["stream"] as? Bool, false); XCTAssertNil(value["stream_options"])
        XCTAssertNil(try body(p)["stream_options"])
    }
    func testSystemContextAndNoHistoricalReasoning() throws {
        let p = Provider.deepSeek
        var c = Conversation(providerID: p.id)
        c.messages = [Message(role: .user, content: "one"), Message(role: .assistant, content: "answer", reasoning: "private-history"), Message(role: .user, content: "two")]
        let request = try RequestBuilder.make(provider: p, key: "mock", conversation: c, settings: AppSettings(), stream: true)
        let data = try XCTUnwrap(request.httpBody)
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try XCTUnwrap(value["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 4)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private-history"))
        XCTAssertTrue(messages.allSatisfy { $0["reasoning_content"] == nil })
    }
    func testContextStartsAtUserAndExcludesFailedAssistant() {
        let m = [Message(role: .user, content: "1"), Message(role: .assistant, content: "2"), Message(role: .user, content: "3"), Message(role: .assistant, content: "bad", state: .failed), Message(role: .user, content: "4")]
        XCTAssertEqual(ContextBuilder.messages(m, limit: 3).map(\.content), ["3", "4"])
    }
    func testVisionBlocksAndCapabilityGuard() throws {
        var p = Provider.deepSeek
        var c = Conversation(providerID: p.id)
        c.messages = [Message(role: .user, content: "describe", images: [Attachment(jpeg: Data([1, 2]), width: 100, height: 100)])]
        let request = try RequestBuilder.make(provider: p, key: "mock", conversation: c, settings: AppSettings(), stream: false)
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let messages = try XCTUnwrap(value["messages"] as? [[String: Any]])
        let blocks = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        XCTAssertEqual(blocks[0]["type"] as? String, "text")
        XCTAssertEqual((blocks[1]["image_url"] as? [String: String])?["url"], "data:image/jpeg;base64,AQI=")
        p.supportsVision = false
        XCTAssertThrowsError(try RequestBuilder.make(provider: p, key: "mock", conversation: c, settings: AppSettings(), stream: false))
    }
    func testKeysAndHeadersValidation() {
        XCTAssertFalse(RequestBuilder.safeHeader("Authorization")); XCTAssertFalse(RequestBuilder.safeHeader("X-Api-Key"))
        XCTAssertFalse(RequestBuilder.safeHeader("X-Token")); XCTAssertFalse(RequestBuilder.safeHeader("A\r\nB"))
        XCTAssertTrue(RequestBuilder.safeHeader("X-Client-Version"))
        XCTAssertThrowsError(try RequestBuilder.make(provider: .deepSeek, key: "", conversation: Conversation(providerID: Provider.deepSeek.id), settings: AppSettings(), stream: true))
    }
}

final class SSETests: XCTestCase {
    func testEveryPossibleByteSplitIncludingUTF8() throws {
        let data = Data("data: {\"choices\":[{\"delta\":{\"content\":\"你好🌸\"}}]}\r\n\r\ndata: [DONE]\n\n".utf8)
        for split in 0...data.count {
            var parser = SSEParser()
            var events = try parser.feed(Data(data.prefix(split)))
            events += try parser.feed(Data(data.dropFirst(split)))
            XCTAssertEqual(events.count, 2)
            XCTAssertEqual(try ChatEnvelope.decode(Data(events[0].utf8)).choices?.first?.delta?.content, "你好🌸")
            XCTAssertEqual(events[1], "[DONE]")
            XCTAssertNoThrow(try parser.finish())
        }
    }
    func testByteAtATimeAndMultilineEvents() throws {
        var parser = SSEParser(), events: [String] = []
        for byte in Data("\u{feff}: ping\rdata: hello\rdata: world\r\rdata:[DONE]\n\n".utf8) { events += try parser.feed(Data([byte])) }
        XCTAssertEqual(events, ["hello\nworld", "[DONE]"])
    }
    func testUnfinishedEventAndInvalidUTF8() throws {
        var parser = SSEParser()
        XCTAssertEqual(try parser.feed(Data("data: {\"choices\":".utf8)), [])
        XCTAssertThrowsError(try parser.finish())
        var invalid = SSEParser()
        XCTAssertThrowsError(try invalid.feed(Data([0x64, 0x61, 0x74, 0x61, 0x3a, 0xff, 0x0a])))
    }
    func testMalformedJSONAndErrorEnvelope() {
        for text in ["{", "{}", "{\"choices\":\"wrong\"}", "{\"error\":{\"message\":\"bad key\"}}"] {
            XCTAssertThrowsError(try ChatEnvelope.decode(Data(text.utf8)))
        }
    }
    func testReasoningAndUsageSeparate() throws {
        let e = try ChatEnvelope.decode(Data("{\"choices\":[{\"delta\":{\"reasoning_content\":\"think\",\"content\":\"answer\"}}],\"usage\":{\"total_tokens\":8}}".utf8))
        XCTAssertEqual(e.choices?.first?.delta?.reasoning_content, "think")
        XCTAssertEqual(e.choices?.first?.delta?.content, "answer")
        XCTAssertEqual(e.usage?.total_tokens, 8)
    }
}

final class StorageTests: XCTestCase {
    func testSQLiteRoundTripAndDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite")
        let c = Conversation(providerID: Provider.deepSeek.id, messages: [Message(role: .user, content: "persist me")])
        do { let db = try LocalDatabase(url: url); try db.save([c], key: "history") }
        let db = try LocalDatabase(url: url)
        XCTAssertEqual(try db.load("history", as: [Conversation].self), [c])
        try db.delete("history")
        XCTAssertNil(try db.load("history", as: [Conversation].self))
    }
    func testProviderManagementPersistsReferencesOnly() throws {
        let db = try LocalDatabase(inMemory: true)
        var p = Provider.deepSeek
        p.customHeaders = ["X-Client": "AkiChat"]
        try db.save([p], key: "providers")
        var loaded = try XCTUnwrap(db.load("providers", as: [Provider].self))
        XCTAssertEqual(loaded, [p]); XCTAssertFalse(String(decoding: try JSONEncoder().encode(p), as: UTF8.self).contains("apiKey\""))
        loaded[0].modelID = "custom-model"; try db.save(loaded, key: "providers")
        XCTAssertEqual(try db.load("providers", as: [Provider].self)?.first?.modelID, "custom-model")
        try db.save([Provider](), key: "providers")
        XCTAssertEqual(try db.load("providers", as: [Provider].self)?.count, 0)
    }
    func testCorruptedRecordDoesNotBecomeEmptyHistory() throws {
        let db = try LocalDatabase(inMemory: true)
        try db.save("invalid", key: "history")
        XCTAssertThrowsError(try db.load("history", as: [Conversation].self))
    }
    func testExportAndImport() throws {
        let c = Conversation(title: "Export", providerID: Provider.deepSeek.id, messages: [Message(role: .user, content: "hello"), Message(role: .assistant, content: "world", reasoning: "thinking")])
        let json = try ExportService.json([c])
        XCTAssertEqual(try ExportService.decode(json), [c])
        let markdown = ExportService.markdown(c)
        XCTAssertTrue(markdown.contains("# Export")); XCTAssertTrue(markdown.contains("world")); XCTAssertTrue(markdown.contains("<details>"))
        XCTAssertFalse(String(decoding: json, as: UTF8.self).contains("apiKeyReference"))
        XCTAssertThrowsError(try ExportService.decode(Data("{\"version\":99,\"conversations\":[]}".utf8)))
    }
    func testDuplicateIDsRejected() throws {
        let c = Conversation(providerID: Provider.deepSeek.id)
        XCTAssertThrowsError(try ExportService.decode(ExportService.json([c, c])))
    }
    func testMarkdownBlocks() {
        let blocks = MarkdownParser.blocks("# Heading\n\n- Item\n\n> Quote\n\n```swift\nlet x = 1\n```\n\n| A | B |\n|---|---|\n| 1 | 2 |")
        XCTAssertEqual(blocks.map(\.kind), [.heading(1), .paragraph, .quote, .code("swift"), .table])
    }
    func testInlineCodeStaysLiteralAndLinksAreNative() {
        let result = InlineMarkdown.render("`**literal**` **bold** _italic_ [link](https://example.com)", size: 16, color: .label, bold: false, enabled: true)
        XCTAssertEqual(result.string, "**literal** bold italic link")
        XCTAssertNotNil(result.attribute(.link, at: result.length - 1, effectiveRange: nil))
    }
    func testMinimumOSVersion() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "MinimumOSVersion") as? String, "14.0")
    }
}

final class LayoutTests: XCTestCase {
    func testIPhoneXRLightAndDarkLayout() throws {
        let database = try LocalDatabase(inMemory: true)
        let draw = {
            let store = AppStore(database: database)
            let host = UIHostingController(rootView: ChatView().environmentObject(store).accentColor(Theme.accent))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 414, height: 896))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            for style in [UIUserInterfaceStyle.light, .dark] {
                window.overrideUserInterfaceStyle = style
                window.layoutIfNeeded(); host.view.layoutIfNeeded()
                XCTAssertEqual(host.view.bounds.width, 414)
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { context in
                    window.layer.render(in: context.cgContext)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = style == .dark ? "iPhone-XR-dark" : "iPhone-XR-light"
                attachment.lifetime = .keepAlways
                self.add(attachment)
                XCTAssertNotNil(image.cgImage)
            }
        }
        if Thread.isMainThread { draw() } else { DispatchQueue.main.sync(execute: draw) }
    }
}

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest, URLProtocolClient, MockURLProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { if let client = client { Self.handler?(request, client, self) } }
    override func stopLoading() {}
}

final class TransportTests: XCTestCase {
    override func tearDown() { MockURLProtocol.handler = nil; super.tearDown() }
    func run(stream: Bool, status: Int = 200, chunks: [Data], error: Error? = nil, verify: @escaping (Result<ChatSnapshot, Error>) -> Void) {
        let finished = expectation(description: "transport completes")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.handler = { request, client, proto in
            client.urlProtocol(proto, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": stream ? "text/event-stream" : "application/json"])!, cacheStoragePolicy: .notAllowed)
            for data in chunks { client.urlProtocol(proto, didLoad: data) }
            if let error = error { client.urlProtocol(proto, didFailWithError: error) }
            else { client.urlProtocolDidFinishLoading(proto) }
        }
        let transport = ChatTransport()
        transport.start(request: URLRequest(url: URL(string: "https://mock.invalid/chat/completions")!), stream: stream, configuration: configuration, onUpdate: { _ in
            XCTAssertTrue(Thread.isMainThread)
        }, completion: { result in XCTAssertTrue(Thread.isMainThread); verify(result); finished.fulfill() })
        wait(for: [finished], timeout: 5)
        withExtendedLifetime(transport) {}
    }
    func testRealDelegateStreamingWithFragmentedMock() {
        let data = Data("data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"思考\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"回答\"},\"finish_reason\":\"stop\"}]}\n\ndata: {\"choices\":[],\"usage\":{\"total_tokens\":9}}\n\ndata: [DONE]\n\n".utf8)
        run(stream: true, chunks: data.map { Data([$0]) }) { result in
            guard case .success(let snapshot) = result else { return XCTFail("Expected success") }
            XCTAssertEqual(snapshot.content, "回答"); XCTAssertEqual(snapshot.reasoning, "思考"); XCTAssertEqual(snapshot.usage?.total_tokens, 9)
        }
    }
    func testNonStreaming() {
        run(stream: false, chunks: [Data("{\"choices\":[{\"message\":{\"content\":\"OK\"}}]}".utf8)]) { result in
            XCTAssertEqual(try? result.get().content, "OK")
        }
    }
    func testHTTPErrorDoesNotExposeResponseBody() {
        run(stream: false, status: 401, chunks: [Data("secret-error-body".utf8)]) { result in
            guard case .failure(let error) = result else { return XCTFail("Expected HTTP error") }
            XCTAssertTrue(error.localizedDescription.contains("401")); XCTAssertFalse(error.localizedDescription.contains("secret-error-body"))
        }
    }
    func testPrematureEOF() {
        run(stream: true, chunks: [Data("data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n".utf8)]) { result in
            if case .success = result { XCTFail("Incomplete stream must fail") }
        }
    }
    func testInvalidJSON() {
        run(stream: true, chunks: [Data("data: invalid\n\n".utf8)]) { result in
            if case .success = result { XCTFail("Malformed JSON must fail") }
        }
    }
    func testTimeout() {
        run(stream: false, chunks: [], error: URLError(.timedOut)) { result in
            guard case .failure(let error) = result else { return XCTFail("Expected timeout") }
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
    }
    func testCancellationCompletesExactlyOnce() {
        let completed = expectation(description: "cancelled")
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.handler = { _, _, _ in }
        let transport = ChatTransport()
        transport.start(request: URLRequest(url: URL(string: "https://mock.invalid")!), stream: true, configuration: configuration, onUpdate: { _ in }, completion: { result in
            guard case .failure(let error) = result else { return XCTFail("Expected cancellation") }
            XCTAssertEqual((error as? URLError)?.code, .cancelled); completed.fulfill()
        })
        transport.cancel(); wait(for: [completed], timeout: 5)
    }
}
