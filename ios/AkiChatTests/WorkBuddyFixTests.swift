import XCTest
import Combine
import SwiftUI
import UIKit
@testable import AkiChat

final class WorkBuddyFixTests: XCTestCase {
    // Wire-shaped fixture checked against wb_proxy._model_entry at upstream 477ba36.
    private let catalog = Data("""
    {"object":"list","data":[
      {"id":"deepseek-v4.1-flash","name":"Gateway Flash","context_length":1000000,"max_output_tokens":32768,
       "supports_vision":true,"supports_tool_calls":true,"supports_reasoning":true,
       "capabilities":{"vision":true,"tool_calls":true,"reasoning":true},
       "reasoning_efforts":["low","medium","high"],"reasoning_default_effort":"medium","reasoning_can_disable":false},
      {"id":"fixed-model","capabilities":{"tool_calls":true,"vision":false,"reasoning":true},
       "reasoning_fixed_effort":"high","always_reasoning":true,"reasoning_can_disable":false},
      {"id":"unknown-model"}
    ]}
    """.utf8)
    override func tearDown() { MockURLProtocol.handler = nil; super.tearDown() }
    private func gateway() throws -> Provider {
        var base = Provider.workBuddy; base.baseURL = "https://gateway.example/u/account-ref/v1"
        return try XCTUnwrap(ModelDiscovery.parse(catalog, provider: base).first).apply(to: base)
    }
    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }
    func testActualHubMetadataAndConservativeUnknownCapabilities() throws {
        let models = try ModelDiscovery.parse(catalog, provider: .workBuddy)
        let provider = models[0].apply(to: .workBuddy)
        XCTAssertEqual(provider.modelID, "deepseek-v4.1-flash")
        XCTAssertEqual(provider.options.contextWindow, 1000000)
        XCTAssertEqual(provider.options.outputLimit, 32768)
        XCTAssertTrue(provider.supportsVision); XCTAssertTrue(provider.options.supportsTools)
        XCTAssertEqual(HubReasoning.levels(provider), ["low", "medium", "high"])
        XCTAssertTrue(models[1].apply(to: .workBuddy).options.supportsTools)
        XCTAssertFalse(models[1].apply(to: .workBuddy).supportsVision)
        XCTAssertFalse(models[2].apply(to: .workBuddy).supportsThinking)
        XCTAssertFalse(models[2].apply(to: .workBuddy).options.supportsTools)
    }
    func testReasoningFixedDefaultDisableAndOpaqueLevels() throws {
        var provider = try gateway(); var c = Conversation(providerID: provider.id)
        c.effort = .max
        XCTAssertEqual(HubReasoning.resolve(provider: provider, conversation: c), "medium")
        c.thinking = false
        XCTAssertFalse(HubReasoning.canDisable(provider))
        XCTAssertEqual(HubReasoning.resolve(provider: provider, conversation: c), "medium")
        provider.options.workBuddy?.canDisableThinking = true
        XCTAssertEqual(HubReasoning.resolve(provider: provider, conversation: c), "none")
        c.thinking = true; c.options.hubReasoningEffort = "ultra"
        provider.options.workBuddy?.reasoningEfforts = ["minimal", "ultra"]
        provider.options.workBuddy?.defaultEffort = "minimal"
        provider.options.workBuddy?.fixedEffort = "minimal"
        XCTAssertNil(HubReasoning.fixed(provider)) // Selectable list wins over an accompanying effort.
        XCTAssertEqual(HubReasoning.resolve(provider: provider, conversation: c), "ultra")
        let fixed = try XCTUnwrap(ModelDiscovery.parse(catalog, provider: .workBuddy).dropFirst().first).apply(to: .workBuddy)
        XCTAssertEqual(HubReasoning.fixed(fixed), "high")
        c.thinking = false
        XCTAssertEqual(HubReasoning.resolve(provider: fixed, conversation: c), "high")
    }
    func testProviderAndModelSelectionChangesActualRequestAndPersists() throws {
        let db = try LocalDatabase(inMemory: true)
        var hub = Provider.workBuddy; hub.baseURL = "https://gateway.example/u/account-ref/v1"
        let official = Provider.deepSeek
        var models = try ModelDiscovery.parse(catalog, provider: hub)
        var manual = ModelRecord(id: "manual-extra", name: "Manual"); manual.manual = true; models.append(manual)
        try db.save([hub, official], key: "providers.v1")
        try db.save([ModelCatalog(id: hub.id, models: models)], key: "catalogs.v2")
        let store = AppStore(database: db)
        store.selectModel(providerID: hub.id, modelID: "deepseek-v4.1-flash")
        let first = try RequestBuilder.make(provider: XCTUnwrap(store.provider), key: "gateway-key", conversation: XCTUnwrap(store.current), settings: store.settings, stream: true)
        XCTAssertEqual(first.url?.absoluteString, "https://gateway.example/u/account-ref/v1/chat/completions")
        XCTAssertEqual(first.value(forHTTPHeaderField: "Authorization"), "Bearer gateway-key")
        XCTAssertEqual(try body(first)["model"] as? String, "deepseek-v4.1-flash")
        XCTAssertNil(try body(first)["thinking"])
        store.selectModel(providerID: hub.id, modelID: "manual-extra")
        let manualRequest = try RequestBuilder.make(provider: XCTUnwrap(store.provider), key: "gateway-key", conversation: XCTUnwrap(store.current), settings: store.settings, stream: true)
        XCTAssertEqual(try body(manualRequest)["model"] as? String, "manual-extra")
        XCTAssertFalse(try XCTUnwrap(store.provider).supportsVision)
        store.selectModel(providerID: official.id, modelID: "deepseek-flash")
        let second = try RequestBuilder.make(provider: XCTUnwrap(store.provider), key: "official-key", conversation: XCTUnwrap(store.current), settings: store.settings, stream: false)
        XCTAssertEqual(second.url?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(second.value(forHTTPHeaderField: "Authorization"), "Bearer official-key")
        XCTAssertNotNil(try body(second)["thinking"])
        store.selectModel(providerID: hub.id, modelID: "fixed-model")
        let saved = expectation(for: NSPredicate { _, _ in
            (try? db.load("conversations.v1", as: [Conversation].self))?.first?.options.modelID == "fixed-model"
        }, evaluatedWith: nil)
        wait(for: [saved], timeout: 3)
        let restarted = AppStore(database: db)
        XCTAssertEqual(restarted.current?.providerID, hub.id)
        XCTAssertEqual(restarted.provider?.modelID, "fixed-model")
        XCTAssertEqual(restarted.provider?.baseURL, hub.baseURL)
    }
    func testModelsFailuresKeepManualAndCachedModels() throws {
        let db = try LocalDatabase(inMemory: true)
        var provider = Provider.workBuddy; provider.baseURL = "https://mock.invalid/v1"; provider.apiKeyReference = UUID().uuidString
        try KeychainStore.write("mock-gateway-key", reference: provider.apiKeyReference)
        defer { try? KeychainStore.delete(provider.apiKeyReference) }
        var manual = ModelRecord(id: "manual", name: "Manual"); manual.manual = true
        try db.save([provider], key: "providers.v1")
        try db.save([ModelCatalog(id: provider.id, models: [manual])], key: "catalogs.v2")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        let store = AppStore(database: db, modelConfiguration: { config })
        for code in [404, 405, 401, 403, 429, 200] {
            MockURLProtocol.handler = { request, client, proto in
                XCTAssertEqual(request.url?.path, "/v1/models")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mock-gateway-key")
                client.urlProtocol(proto, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                client.urlProtocol(proto, didLoad: Data("{\"data\":[]}".utf8)); client.urlProtocolDidFinishLoading(proto)
            }
            let done = expectation(description: "failed discovery \(code)")
            var sink: AnyCancellable?
            sink = store.$modelErrors.dropFirst().sink { errors in if errors[provider.id] != nil { done.fulfill() } }
            store.refreshModels(provider.id)
            wait(for: [done], timeout: 3); sink?.cancel()
            XCTAssertEqual(store.models(for: provider.id), [manual])
            XCTAssertNotNil(store.modelErrors[provider.id])
            if code != 200 { XCTAssertTrue(store.modelErrors[provider.id]?.contains(String(code)) == true) }
        }
    }
    func testMergeAndPickerRetainManualFavoriteAndOverrides() throws {
        var old = ModelRecord(id: "deepseek-v4.1-flash", name: "Mine")
        old.manual = true; old.favorite = true; old.overrides.vision = false; old.contextWindowOverride = 12345
        let remote = try ModelDiscovery.parse(catalog, provider: .workBuddy)
        let merged = ModelDiscovery.merge(remote, cached: [old, ModelRecord(id: "other", name: "Other")])
        let result = try XCTUnwrap(merged.first)
        XCTAssertTrue(result.manual); XCTAssertTrue(result.favorite); XCTAssertEqual(result.contextWindowOverride, 12345)
        XCTAssertFalse(result.apply(to: .workBuddy).supportsVision)
        XCTAssertEqual(ModelDiscovery.filtered(merged, query: "flash", favoritesOnly: true).map(\.id), [old.id])
        XCTAssertTrue(merged.contains(where: { $0.id == "other" }))
    }
    func testHubToolHistoryAndBudgetIncludeReasoning() throws {
        let provider = try gateway()
        var c = Conversation(providerID: provider.id); c.options.toolsEnabled = true
        let call = ToolCall(id: "call_1", function: .init(name: "current_time", arguments: "{}"))
        c.messages = [Message(role: .user, content: "Time?"), Message(role: .assistant, content: "", reasoning: String(repeating: "r", count: 300), toolCalls: [call]), Message(role: .tool, content: "now", toolCallID: call.id)]
        let definitions = ToolPolicy.definitions(c.options, canSearch: false)
        let request = try RequestBuilder.make(provider: provider, key: "mock", conversation: c, settings: AppSettings(), stream: true, tools: definitions)
        let messages = try XCTUnwrap(try body(request)["messages"] as? [[String: Any]])
        let assistant = try XCTUnwrap(messages.first(where: { $0["role"] as? String == "assistant" }))
        XCTAssertEqual(assistant["reasoning_content"] as? String, c.messages[1].reasoning)
        XCTAssertEqual(messages.last?["tool_call_id"] as? String, call.id)
        let plan = try ContextManager.plan(provider: provider, conversation: c, settings: AppSettings(), tools: true)
        c.messages[1].reasoning = ""
        let shorter = try ContextManager.plan(provider: provider, conversation: c, settings: AppSettings(), tools: true)
        XCTAssertGreaterThan(plan.estimatedTokens, shorter.estimatedTokens)
        XCTAssertFalse(definitions.contains { ($0["function"] as? [String: Any])?["name"] as? String == "web_search" })
    }
    func testOldHubDataAndLocalATSPolicy() throws {
        let old = Data("{\"allowLANHTTP\":false,\"reasoningEfforts\":[\"medium\"]}".utf8)
        let decoded = try JSONDecoder().decode(WorkBuddyOptions.self, from: old)
        XCTAssertNil(decoded.fixedEffort); XCTAssertNil(decoded.alwaysReasoning)
        let ats = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Bool])
        XCTAssertEqual(ats, ["NSAllowsLocalNetworking": true])
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription"))
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "MinimumOSVersion") as? String, "14.0")
        for host in ["192.168.1.100", "10.0.0.2", "172.16.0.2", "gateway.local", "[fd00::1]", "[fe80::1]"] {
            XCTAssertNoThrow(try Endpoint.url("http://\(host):8788/u/ref/v1", path: "/v1/models", allowLANHTTP: true))
            XCTAssertThrowsError(try Endpoint.url("http://\(host):8788/v1", path: "/models"))
        }
        for host in ["8.8.8.8", "172.32.0.1", "example.com", "[2001:4860:4860::8888]"] {
            XCTAssertThrowsError(try Endpoint.url("http://\(host):8788/v1", path: "/models", allowLANHTTP: true))
        }
        XCTAssertEqual(try Endpoint.url("https://host.example/u/ref/v1/chat/completions", path: "/models").path, "/u/ref/v1/models")
        let black = UIColor(Theme.background).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var red: CGFloat = 1, green: CGFloat = 1, blue: CGFloat = 1, alpha: CGFloat = 0
        XCTAssertTrue(black.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(red, 0, accuracy: 0.001); XCTAssertEqual(green, 0, accuracy: 0.001)
        XCTAssertEqual(blue, 0, accuracy: 0.001); XCTAssertEqual(alpha, 1, accuracy: 0.001)
    }
}

final class RetrySafetyTests: XCTestCase {
    override func tearDown() { MockURLProtocol.handler = nil; super.tearDown() }
    func testBackoffHonorsCooldownAndLimit() {
        func response(_ code: Int, _ delay: String? = nil) -> HTTPURLResponse {
            HTTPURLResponse(url: URL(string: "https://mock.invalid")!, statusCode: code, httpVersion: nil, headerFields: delay.map { ["Retry-After": $0] })!
        }
        XCTAssertEqual(HTTPRetryPolicy.delay(response: response(429), attempt: 0), 1)
        XCTAssertEqual(HTTPRetryPolicy.delay(response: response(429), attempt: 1), 2)
        XCTAssertEqual(HTTPRetryPolicy.delay(response: response(429, "5"), attempt: 0), 5)
        XCTAssertNil(HTTPRetryPolicy.delay(response: response(429, "60"), attempt: 0))
        XCTAssertNil(HTTPRetryPolicy.delay(response: response(429), attempt: 2))
        XCTAssertNil(HTTPRetryPolicy.delay(response: response(403), attempt: 0))
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(HTTPRetryPolicy.delay(response: response(429, "Thu, 01 Jan 1970 00:00:10 GMT"), attempt: 0, now: now), 10)
    }
    func testRejected429RetriesThenSucceeds() {
        let done = expectation(description: "bounded retry succeeds")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        var calls = 0
        MockURLProtocol.handler = { request, client, proto in
            calls += 1
            let status = calls == 1 ? 429 : 200
            client.urlProtocol(proto, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": "0"])!, cacheStoragePolicy: .notAllowed)
            if status == 200 { client.urlProtocol(proto, didLoad: Data("{\"choices\":[{\"message\":{\"content\":\"OK\"}}]}".utf8)) }
            client.urlProtocolDidFinishLoading(proto)
        }
        let transport = ChatTransport()
        transport.start(request: URLRequest(url: URL(string: "https://mock.invalid")!), stream: false, configuration: config, onUpdate: { _ in }) { result in
            XCTAssertEqual(try? result.get().content, "OK"); XCTAssertEqual(calls, 2); done.fulfill()
        }
        wait(for: [done], timeout: 4)
    }
    func testPartialStreamIsNeverReplayed() {
        let done = expectation(description: "partial response preserved")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        var calls = 0; var content = ""
        var disconnect: (() -> Void)?
        MockURLProtocol.handler = { request, client, proto in
            calls += 1
            disconnect = { client.urlProtocol(proto, didFailWithError: URLError(.networkConnectionLost)) }
            client.urlProtocol(proto, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(proto, didLoad: Data("data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n".utf8))
        }
        let transport = ChatTransport()
        transport.start(request: URLRequest(url: URL(string: "https://mock.invalid")!), stream: true, configuration: config, onUpdate: {
            content = $0.content
            // Fail only after actual delegate delivery; URLProtocol may discard buffered data on immediate failure.
            if content == "partial" { let failure = disconnect; disconnect = nil; failure?() }
        }) { result in
            if case .success = result { XCTFail("Must report interrupted stream") }
            XCTAssertEqual(calls, 1); XCTAssertEqual(content, "partial"); done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }
    func testRepeated429StopsAfterTwoRetries() {
        let done = expectation(description: "retry limit")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        var calls = 0
        MockURLProtocol.handler = { request, client, proto in
            calls += 1
            client.urlProtocol(proto, didReceive: HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "0"])!, cacheStoragePolicy: .notAllowed)
            client.urlProtocolDidFinishLoading(proto)
        }
        let transport = ChatTransport()
        transport.start(request: URLRequest(url: URL(string: "https://mock.invalid")!), stream: true, configuration: config, onUpdate: { _ in }) { result in
            guard case .failure(let error) = result else { return XCTFail("Expected 429") }
            XCTAssertTrue(error.localizedDescription.contains("429")); XCTAssertEqual(calls, 3); done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }
    func testCancellationPreventsScheduledReplay() {
        let rejected = expectation(description: "first request")
        let done = expectation(description: "cancelled")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        var calls = 0
        MockURLProtocol.handler = { request, client, proto in
            calls += 1
            client.urlProtocol(proto, didReceive: HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "1"])!, cacheStoragePolicy: .notAllowed)
            client.urlProtocolDidFinishLoading(proto); rejected.fulfill()
        }
        let transport = ChatTransport()
        transport.start(request: URLRequest(url: URL(string: "https://mock.invalid")!), stream: false, configuration: config, onUpdate: { _ in }) { result in
            guard case .failure(let error) = result else { return XCTFail("Expected cancellation") }
            XCTAssertEqual((error as? URLError)?.code, .cancelled); done.fulfill()
        }
        wait(for: [rejected], timeout: 2); transport.cancel(); wait(for: [done], timeout: 2)
        let settled = expectation(description: "retry deadline passed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { settled.fulfill() }
        wait(for: [settled], timeout: 2); XCTAssertEqual(calls, 1)
    }
}
