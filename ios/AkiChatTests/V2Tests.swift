import XCTest
@testable import AkiChat

final class DiscoveryTests: XCTestCase {
    func testMetadataAndUnknownCapabilities() throws {
        let data = Data("""
        {"data":[{"id":"deepseek-flash","name":"Flash","context_window":1048576,"max_output_tokens":393216,"input_modalities":["text","image"],"output_modalities":["text"],"effort":{"supported_levels":["low","high","max"]},"api_capabilities":{"anthropic_messages":{"system_prompt_update":"in-history"}}},{"id":"unknown"}]}
        """.utf8)
        let models = try ModelDiscovery.parse(data, provider: .deepSeek)
        XCTAssertEqual(models.count, 2); XCTAssertEqual(models[0].contextWindow, 1048576)
        XCTAssertEqual(models[0].discovered.vision, true); XCTAssertEqual(models[0].discovered.thinking, true)
        XCTAssertNil(models[1].discovered.vision); XCTAssertNil(models[1].discovered.tools)
        XCTAssertFalse(models[1].apply(to: .deepSeek).supportsVision)
        XCTAssertFalse(models[1].apply(to: .deepSeek).options.supportsTools)
    }
    func testMergePreservesCustomizationAndMissingModels() {
        var old = ModelRecord(id: "x", name: "Old"); old.favorite = true; old.overrides.tools = true; old.order = -1
        old.contextWindowOverride = 64000
        let merged = ModelDiscovery.merge([ModelRecord(id: "x", name: "New")], cached: [old, ModelRecord(id: "offline", name: "Offline")])
        XCTAssertEqual(merged[0].name, "New"); XCTAssertTrue(merged[0].favorite)
        XCTAssertEqual(merged[0].overrides.tools, true); XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].contextWindowOverride, 64000)
    }
    func testMalformedModelsAndDuplicateIDs() throws {
        XCTAssertThrowsError(try ModelDiscovery.parse(Data("{}".utf8), provider: .deepSeek))
        XCTAssertEqual(try ModelDiscovery.parse(Data("{\"data\":[{\"id\":\"x\"},{\"id\":\"x\"}]}".utf8), provider: .openAI).count, 1)
    }
    func testConfigurableEndpointJoining() throws {
        XCTAssertEqual(try Endpoint.url("https://api.example.com/v1/chat/completions/", path: "/models").absoluteString, "https://api.example.com/v1/models")
        XCTAssertEqual(try Endpoint.url("https://api.example.com/v1", path: "/v1/chat/completions").absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(try Endpoint.url("https://api.example.com/custom", path: "/generate").absoluteString, "https://api.example.com/custom/generate")
        XCTAssertThrowsError(try Endpoint.url("https://api.example.com", path: "https://other.com"))
    }
    func testOpenAIOutputParameterAndSamplingOverride() throws {
        var p = Provider.openAI; p.modelID = "example-model"
        var c = Conversation(providerID: p.id); c.messages = [Message(role: .user, content: "Hi")]
        let request = try RequestBuilder.make(provider: p, key: "mock", conversation: c, settings: AppSettings(), stream: false)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertNotNil(body["max_completion_tokens"]); XCTAssertNil(body["max_tokens"]); XCTAssertNil(body["temperature"])
        p.options.tokenLimitField = .maxTokens; p.options.sendSamplingParameters = true
        let custom = try RequestBuilder.make(provider: p, key: "mock", conversation: c, settings: AppSettings(), stream: false)
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(custom.httpBody)) as? [String: Any])
        XCTAssertNotNil(value["max_tokens"]); XCTAssertNotNil(value["temperature"])
    }
    func testV1DecodingRemainsCompatible() throws {
        let provider = try JSONDecoder().decode(Provider.self, from: JSONEncoder().encode(Provider.deepSeek))
        XCTAssertNil(provider.advanced); XCTAssertEqual(provider.options.contextWindow, 1048576)
        let c = Conversation(providerID: provider.id)
        let decoded = try ExportService.decode(ExportService.json([c]))
        XCTAssertNil(decoded[0].advanced); XCTAssertEqual(decoded[0].options.context.threshold, 0.75)
    }
    func testModelsHTTPErrorAndCancellation() throws {
        for code in [401, 403, 404, 429] {
            let done = expectation(description: "HTTP \(code)")
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
            MockURLProtocol.handler = { req, client, proto in
                XCTAssertEqual(req.httpMethod, "GET")
                client.urlProtocol(proto, didReceive: HTTPURLResponse(url: req.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                client.urlProtocolDidFinishLoading(proto)
            }
            let client = JSONHTTPClient()
            client.start(try JSONHTTPClient.request(url: Endpoint.url("https://mock.invalid", path: "/models"), key: "mock"), configuration: config) { result in
                guard case .failure(let error) = result else { return XCTFail("Expected HTTP error") }
                XCTAssertTrue(error.localizedDescription.contains(String(code))); done.fulfill()
            }
            wait(for: [done], timeout: 3)
        }
        MockURLProtocol.handler = nil
    }
}


// Regression tests for the WorkBuddy2API-Hub OpenAI-compatible gateway.
final class WorkBuddyHubCompatibilityTests: XCTestCase {
    func testModelMetadataAndCapabilities() throws {
        let json = """
        {"object":"list","data":[
          {"id":"deepseek-v4.1-flash","name":"DeepSeek V4.1 Flash","context_length":1000000,
           "max_output_tokens":32768,"supports_vision":true,"supports_reasoning":true,
           "reasoning_efforts":["low","medium","high"],"reasoning_default_effort":"medium",
           "reasoning_can_disable":false,"capabilities":{"tools":true}},
          {"id":"glm-5.3-flash","capabilities":{"vision":false}}
        ]}
        """
        let models = try ModelDiscovery.parse(Data(json.utf8), provider: .workBuddy)
        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(models[0].contextWindow, 1000000)
        XCTAssertEqual(models[0].effort, ["low","medium","high"])
        XCTAssertEqual(models[0].discovered.vision, true)
        XCTAssertEqual(models[0].discovered.tools, true)
        XCTAssertEqual(models[1].discovered.vision, false)
        let applied = models[0].apply(to: .workBuddy)
        XCTAssertEqual(applied.options.workBuddy?.defaultEffort, "medium")
        XCTAssertEqual(applied.options.workBuddy?.canDisableThinking, false)
    }

    func testHubReasoningWireFormat() throws {
        let raw = """
        {"data":[{"id":"deepseek-v4.1-flash","reasoning_efforts":["low","medium","high"],
                  "reasoning_default_effort":"medium","supports_reasoning":true}]}
        """
        let model = try XCTUnwrap(ModelDiscovery.parse(Data(raw.utf8), provider: .workBuddy).first)
        var provider = model.apply(to: .workBuddy)
        provider.baseURL = "https://gateway.example/v1"
        var c = Conversation(providerID: provider.id)
        c.messages = [Message(role: .user, content: "你好")]
        c.thinking = true
        c.effort = .max
        let request = try RequestBuilder.make(provider: provider, key: "test-key", conversation: c, settings: AppSettings(), stream: true)
        XCTAssertEqual(request.url?.absoluteString, "https://gateway.example/v1/chat/completions")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertNil(body["thinking"])
        XCTAssertEqual(body["reasoning_effort"] as? String, "medium")
        XCTAssertNil(body["temperature"])
        c.thinking = false
        let offRequest = try RequestBuilder.make(provider: provider, key: "test-key", conversation: c, settings: AppSettings(), stream: false)
        let off = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(offRequest.httpBody)) as? [String: Any])
        XCTAssertEqual(off["reasoning_effort"] as? String, "medium") // Unknown disable support must not claim thinking is off.
    }

    func testPrivateLANHTTPRequiresExplicitOptIn() throws {
        XCTAssertThrowsError(try Endpoint.url("http://192.168.1.20:8788/v1", path: "/models"))
        XCTAssertEqual(try Endpoint.url("http://192.168.1.20:8788/v1", path: "/models", allowLANHTTP: true).absoluteString,
                       "http://192.168.1.20:8788/v1/models")
        XCTAssertThrowsError(try Endpoint.url("http://example.com:8788/v1", path: "/models", allowLANHTTP: true))
    }
}
