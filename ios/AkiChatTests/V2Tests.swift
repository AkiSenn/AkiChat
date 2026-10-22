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
