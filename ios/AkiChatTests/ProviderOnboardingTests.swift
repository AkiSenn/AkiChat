import XCTest
import Combine
@testable import AkiChat

final class ProviderOnboardingTests: XCTestCase {
    override func tearDown() { MockURLProtocol.handler = nil; super.tearDown() }
    private func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]; return config
    }
    private func provider() -> Provider {
        var value = Provider.newCompatible; value.name = "New API"; value.baseURL = "https://mock.invalid/v1"; return value
    }
    private func flush(_ store: AppStore) {
        let done = expectation(description: "storage barrier")
        store.flushPersistence { done.fulfill() }; wait(for: [done], timeout: 3)
    }
    func testSaveWithoutModelAutomaticallyDiscoversThenSelectsRealRequest() throws {
        let db = RecordingDatabase(), config = configuration()
        let store = AppStore(database: db, modelConfiguration: { config })
        let p = provider(); defer { try? KeychainStore.delete(p.apiKeyReference) }
        let done = expectation(description: "automatically discovered")
        MockURLProtocol.handler = { request, client, proto in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "https://mock.invalid/v1/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mock-new-key")
            client.urlProtocol(proto, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(proto, didLoad: Data("{\"data\":[{\"id\":\"model-a\"},{\"id\":\"model-b\"}]}".utf8))
            client.urlProtocolDidFinishLoading(proto)
        }
        let sink = store.$catalogs.sink { values in
            if values.first(where: { $0.id == p.id })?.syncedAt != nil { done.fulfill() }
        }
        try store.saveProvider(p, newKey: "mock-new-key")
        XCTAssertTrue(try XCTUnwrap(store.providers.first(where: { $0.id == p.id })).modelID.isEmpty)
        wait(for: [done], timeout: 4); sink.cancel()
        XCTAssertEqual(store.models(for: p.id).map(\.id), ["model-a", "model-b"])
        try store.chooseDefaultModel(providerID: p.id, modelID: "model-b")
        let selected = try XCTUnwrap(store.provider)
        let request = try RequestBuilder.make(provider: selected, key: KeychainStore.read(selected.apiKeyReference) ?? "", conversation: XCTUnwrap(store.current), settings: store.settings, stream: false)
        XCTAssertEqual(request.url?.absoluteString, "https://mock.invalid/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mock-new-key")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "model-b")
        flush(store)
        let saved = try XCTUnwrap(db.load("providers.v1", as: [Provider].self)?.first(where: { $0.id == p.id }))
        XCTAssertEqual(saved.modelID, "model-b"); XCTAssertEqual(saved.apiKeyReference, p.apiKeyReference)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(saved), as: UTF8.self).contains("mock-new-key"))
        let restarted = AppStore(database: db)
        XCTAssertEqual(restarted.provider?.id, p.id); XCTAssertEqual(restarted.provider?.modelID, "model-b")
    }
    func testUnsupportedDiscoveryAllowsManualAlongsideCachedAndPreservesHistory() throws {
        let db = RecordingDatabase(), config = configuration()
        var p = provider(); p.modelID = "cached"; p.displayName = "Cached"
        defer { try? KeychainStore.delete(p.apiKeyReference) }
        try KeychainStore.write("mock", reference: p.apiKeyReference)
        var old = Conversation(providerID: p.id, messages: [Message(role: .user, content: "Keep history")])
        let summary = SummaryVersion(text: "Keep summary", coveredMessageIDs: [], providerID: p.id, modelID: "old-model")
        old.summaries = [summary]; old.activeSummaryID = summary.id
        old.options.context.summaryProviderID = UUID(); old.options.context.summaryModelID = "old-summary-model"
        var other = Conversation(providerID: p.id); other.updatedAt = .distantPast
        try db.save([p], key: "providers.v1"); try db.save([old, other], key: "conversations.v1")
        let cached = ModelRecord(id: "cached", name: "Cached")
        try db.save([ModelCatalog(id: p.id, models: [cached])], key: "catalogs.v2")
        let store = AppStore(database: db, modelConfiguration: { config })
        MockURLProtocol.handler = { request, client, proto in
            client.urlProtocol(proto, didReceive: HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client.urlProtocolDidFinishLoading(proto)
        }
        let done = expectation(description: "compatibility mode")
        let sink = store.$modelIssues.sink { if $0[p.id]?.kind == .unsupported { done.fulfill() } }
        try store.saveProvider(p, newKey: nil)
        wait(for: [done], timeout: 3); sink.cancel()
        XCTAssertEqual(store.models(for: p.id), [cached])
        XCTAssertTrue(store.modelErrors[p.id]?.contains("兼容模式") == true)
        var manual = ModelRecord(id: "manual", name: "Manual"); manual.manual = true
        store.saveModel(manual, providerID: p.id)
        try store.chooseDefaultModel(providerID: p.id, modelID: manual.id)
        XCTAssertEqual(store.models(for: p.id).map(\.id), ["cached", "manual"])
        flush(store)
        let restarted = AppStore(database: db)
        XCTAssertEqual(restarted.current?.messages, old.messages)
        XCTAssertEqual(restarted.current?.summaries, old.summaries)
        XCTAssertEqual(restarted.current?.options.context.summaryModelID, "old-summary-model")
        XCTAssertEqual(restarted.provider?.modelID, manual.id)
        XCTAssertEqual(restarted.conversations.first(where: { $0.id == other.id })?.options.modelID, "cached")
        XCTAssertEqual(try KeychainStore.read(p.apiKeyReference), "mock")
    }
    func testDiscoveryFailureCategoriesDoNotMislabelKeys() throws {
        let codes: [(Int, ModelDiscoveryIssue.Kind)] = [(401, .authentication), (403, .permission), (404, .unsupported), (405, .unsupported), (429, .rateLimited)]
        for (code, kind) in codes { XCTAssertEqual(ModelDiscoveryIssue(AppError.http(code)).kind, kind) }
        XCTAssertEqual(ModelDiscoveryIssue(URLError(.timedOut)).kind, .timeout)
        for input in ["not json", "{\"data\":{}}", "{}"] {
            XCTAssertThrowsError(try ModelDiscovery.parse(Data(input.utf8), provider: provider())) { error in
                XCTAssertEqual(ModelDiscoveryIssue(error).kind, .format)
            }
        }
    }
    func testNewEndpointsNormalizeAndOldProviderConfigurationIsUnchanged() throws {
        let p = Provider.newCompatible
        for base in ["https://mock.invalid", "https://mock.invalid/v1/", "https://mock.invalid/v1/chat/completions"] {
            XCTAssertEqual(try Endpoint.url(base, path: p.options.modelsPath).path, "/v1/models")
            XCTAssertEqual(try Endpoint.chatURL(base, path: p.options.chatPath).path, "/v1/chat/completions")
        }
        var old = Provider(name: "Legacy", baseURL: "https://mock.invalid/custom", modelID: "legacy", displayName: "Legacy model")
        old.options.chatPath = "/legacy/chat"; old.options.modelsPath = "/catalog"
        let decoded = try JSONDecoder().decode(Provider.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(decoded, old)
        XCTAssertEqual(try Endpoint.url(decoded.baseURL, path: decoded.options.modelsPath).path, "/custom/catalog")
        XCTAssertEqual(try Endpoint.url(Provider.deepSeek.baseURL, path: Provider.deepSeek.options.modelsPath).path, "/models")
    }
    func testInvalidSaveDoesNotPersistProviderOrCredential() throws {
        let db = RecordingDatabase(), store = AppStore(database: db)
        var p = provider(); defer { try? KeychainStore.delete(p.apiKeyReference) }
        XCTAssertThrowsError(try store.saveProvider(p, newKey: "  "))
        p.options.modelsPath = "not-a-path"
        XCTAssertThrowsError(try store.saveProvider(p, newKey: "mock"))
        XCTAssertNil(try KeychainStore.read(p.apiKeyReference))
        XCTAssertFalse(store.providers.contains(where: { $0.id == p.id }))
        XCTAssertFalse(store.refreshingModels.contains(p.id))
    }
}
