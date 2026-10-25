import XCTest
import Foundation
import Combine
@testable import AkiChat

final class StateOptimizationTests: XCTestCase {
    override func tearDown() { MockURLProtocol.handler = nil; super.tearDown() }
    private func flush(_ store: AppStore) {
        let done = expectation(description: "serial storage barrier")
        store.flushPersistence { done.fulfill() }; wait(for: [done], timeout: 3)
    }
    func testModelAndOptionChangesDoNotReconcileHistory() throws {
        let db = RecordingDatabase()
        let p = Provider.deepSeek
        let history = (0..<500).map { Message(role: .user, content: "history \($0)") }
        try db.save([p], key: "providers.v1")
        try db.save([Conversation(providerID: p.id, messages: history)], key: "conversations.v1")
        let store = AppStore(database: db); flush(store)
        let count = store.chat.reconciliationCount, rows = store.chat.rows
        store.selectModel(providerID: p.id, modelID: p.modelID)
        store.setThinking(false); store.setEffort(.low)
        store.updateConversationOption(\.systemPrompt, "changed")
        XCTAssertEqual(store.chat.reconciliationCount, count)
        XCTAssertEqual(store.messages, history)
        XCTAssertTrue(zip(rows, store.chat.rows).allSatisfy { $0 === $1 })
        store.clearCurrent()
        XCTAssertGreaterThan(store.chat.reconciliationCount, count)
        XCTAssertTrue(store.chat.rows.isEmpty)
    }
    func testListCacheReusesSortAndFiltersAndInvalidates() throws {
        let cache = ModelListCache(), id = UUID()
        var values = (0..<100).map { ModelRecord(id: "model-\($0)", name: "Model \($0)") }
        values[3].favorite = true
        for _ in 0..<10 {
            for favorites in [false, true] {
                XCTAssertEqual(cache.models(for: id, source: { values }, query: " model ", favoritesOnly: favorites),
                               ModelDiscovery.filtered(values, query: " model ", favoritesOnly: favorites))
            }
        }
        XCTAssertEqual(cache.sortCount, 1); XCTAssertEqual(cache.filterCount, 1)
        _ = cache.models(for: id, source: { values }, query: "99")
        XCTAssertEqual(cache.sortCount, 1); XCTAssertEqual(cache.filterCount, 2)
        values[0].favorite = true; cache.invalidate()
        XCTAssertEqual(cache.models(for: id, source: { values }, query: "", favoritesOnly: true).count, 2)
        XCTAssertEqual(cache.sortCount, 2)
        let db = RecordingDatabase(); let store = AppStore(database: db)
        let p = try XCTUnwrap(store.providers.first)
        _ = store.filteredModels(for: p.id, query: "", favoritesOnly: true)
        var model = try XCTUnwrap(store.models(for: p.id).first); model.favorite = true
        store.saveModel(model, providerID: p.id)
        XCTAssertEqual(store.filteredModels(for: p.id, query: "", favoritesOnly: true).map(\.id), [model.id])
    }
    func testDirtyRecordsWriteOnlyChangedDomains() throws {
        let db = RecordingDatabase()
        let actual = AppStore(database: db); flush(actual); db.clearWrites()
        actual.setDraft("latest draft"); flush(actual)
        XCTAssertEqual(db.writes.map(\.key), ["conversations.v1"])
        XCTAssertEqual(try db.load("conversations.v1", as: [Conversation].self)?.first?.draft, "latest draft")
        db.clearWrites(); actual.updateSetting(\.fontSize, 20); flush(actual)
        XCTAssertEqual(db.writes.map(\.key), ["settings.v1"])
        db.clearWrites()
        let p = try XCTUnwrap(actual.providers.first)
        actual.saveModel(ModelRecord(id: "manual", name: "Manual"), providerID: p.id); flush(actual)
        XCTAssertEqual(db.writes.map(\.key), ["catalogs.v2"])
        db.clearWrites()
        var edited = p; edited.name = "Renamed"; edited.apiKeyReference = UUID().uuidString
        try actual.saveProvider(edited, newKey: nil, deleteKey: true); flush(actual)
        XCTAssertEqual(db.writes.map(\.key), ["providers.v1"])
        db.clearWrites(); flush(actual); XCTAssertTrue(db.writes.isEmpty)
    }
    func testFailedSaveKeepsDirtyDataForRetry() throws {
        let db = RecordingDatabase()
        let actual = AppStore(database: db); flush(actual); db.clearWrites()
        db.failNext("settings.v1")
        actual.updateSetting(\.fontSize, 23); flush(actual)
        XCTAssertNotNil(actual.notice)
        flush(actual)
        XCTAssertEqual(db.writes.map(\.key), ["settings.v1", "settings.v1"])
        XCTAssertEqual(try db.load("settings.v1", as: AppSettings.self)?.fontSize, 23)
    }
    func testEditsWhileWriteIsPendingKeepLatestSnapshot() throws {
        let db = RecordingDatabase(), store = AppStore(database: db); flush(store); db.clearWrites()
        let writing = expectation(description: "first write in flight"), gate = DispatchSemaphore(value: 0)
        var first = true
        db.setObserver { key in
            if key == "conversations.v1" && first {
                first = false; writing.fulfill()
                XCTAssertEqual(gate.wait(timeout: .now() + 2), .success)
            }
        }
        store.setDraft("old"); store.flushPersistence()
        wait(for: [writing], timeout: 2)
        store.setDraft("new"); gate.signal(); flush(store)
        XCTAssertEqual(try db.load("conversations.v1", as: [Conversation].self)?.first?.draft, "new")
        XCTAssertEqual(db.writes.map(\.key), ["conversations.v1", "conversations.v1"])
    }
    func testIndexedMergePreservesLegacyRulesIncludingDuplicates() {
        var old = ModelRecord(id: "same", name: "local"); old.favorite = true; old.manual = true
        old.overrides.thinking = true; old.contextWindowOverride = 1234
        let cached = [old, ModelRecord(id: "same", name: "duplicate"), ModelRecord(id: "missing", name: "A"), ModelRecord(id: "missing", name: "B")]
        let fetched = [ModelRecord(id: "same", name: "remote"), ModelRecord(id: "new", name: "New")]
        XCTAssertEqual(ModelDiscovery.merge(fetched, cached: cached), legacyCatalogMerge(fetched, cached: cached))
    }
    private func refreshStore(_ worker: CatalogWorker) throws -> (AppStore, Provider) {
        let db = RecordingDatabase()
        var p = Provider.deepSeek; p.baseURL = "https://mock.invalid"; p.apiKeyReference = UUID().uuidString
        try KeychainStore.write("mock", reference: p.apiKeyReference)
        addTeardownBlock { try? KeychainStore.delete(p.apiKeyReference) }
        try db.save([p, Provider.openAI], key: "providers.v1")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.handler = { request, client, proto in
            client.urlProtocol(proto, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(proto, didLoad: Data("{\"data\":[{\"id\":\"deepseek-flash\"},{\"id\":\"remote\"}]}".utf8))
            client.urlProtocolDidFinishLoading(proto)
        }
        return (AppStore(database: db, modelConfiguration: { config }, catalogWorker: worker), p)
    }
    func testWorkerParsesOffMainAndDeliversOnMain() {
        let done = expectation(description: "worker delivery"), worker = CatalogWorker()
        worker.submit({
            XCTAssertFalse(Thread.isMainThread)
            return try? ModelDiscovery.parse(Data("{\"data\":[{\"id\":\"test\"}]}".utf8), provider: .openAI)
        }) { models in
            XCTAssertTrue(Thread.isMainThread); XCTAssertEqual(models?.first?.id, "test"); done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }
    func testRefreshRebasesWhenLocalModelChangesDuringMerge() throws {
        let worker = CatalogWorker()
        let (actual, provider) = try refreshStore(worker)
        var phase = 0
        worker.onSubmit = { [weak actual] in
            phase += 1
            if phase == 2, let actual = actual {
                var favorite = actual.models(for: provider.id)[0]; favorite.favorite = true
                actual.saveModel(favorite, providerID: provider.id)
                var manual = ModelRecord(id: "local-extra", name: "Local"); manual.manual = true
                actual.saveModel(manual, providerID: provider.id)
            }
        }
        actual.refreshModels(provider.id)
        let done = expectation(for: NSPredicate { _, _ in actual.catalogs.first?.syncedAt != nil }, evaluatedWith: nil)
        wait(for: [done], timeout: 3)
        XCTAssertGreaterThanOrEqual(phase, 3)
        XCTAssertTrue(actual.models(for: provider.id).first(where: { $0.id == "deepseek-flash" })?.favorite == true)
        XCTAssertTrue(actual.models(for: provider.id).contains { $0.id == "local-extra" && $0.manual })
        XCTAssertFalse(actual.refreshingModels.contains(provider.id)); XCTAssertNil(actual.modelErrors[provider.id])
    }
    func testCancelAndProviderDeletionRejectQueuedCatalogResults() throws {
        for deleting in [false, true] {
            let queue = OperationQueue(); queue.isSuspended = true
            let worker = CatalogWorker(queue: queue)
            let (actual, provider) = try refreshStore(worker)
            let queued = expectation(description: "parse queued")
            worker.onSubmit = { queued.fulfill() }
            actual.refreshModels(provider.id); wait(for: [queued], timeout: 3)
            worker.onSubmit = nil
            if deleting { try actual.deleteProvider(provider.id) } else { actual.cancelModelRefresh(provider.id) }
            let drained = expectation(description: "worker drained")
            worker.submit({ true }) { _ in drained.fulfill() }
            queue.isSuspended = false; wait(for: [drained], timeout: 3)
            XCTAssertFalse(actual.refreshingModels.contains(provider.id))
            XCTAssertNil(actual.catalogs.first(where: { $0.id == provider.id })?.syncedAt)
        }
    }
}

final class RecordingDatabase: RecordDatabase {
    struct Write { var key: String; var bytes: Int }
    private let lock = NSLock()
    private var records: [String: Data] = [:]
    private var attempts: [Write] = []
    private var failKey: String?
    private var observer: ((String) -> Void)?
    var writes: [Write] { lock.lock(); defer { lock.unlock() }; return attempts }
    func clearWrites() { lock.lock(); attempts = []; lock.unlock() }
    func failNext(_ key: String) { lock.lock(); failKey = key; lock.unlock() }
    func setObserver(_ value: @escaping (String) -> Void) { lock.lock(); observer = value; lock.unlock() }
    func load<T: Decodable>(_ key: String, as type: T.Type) throws -> T? {
        lock.lock(); let data = records[key]; lock.unlock()
        return try data.map { try JSONDecoder().decode(type, from: $0) }
    }
    func save<T: Encodable>(_ value: T, key: String) throws {
        let data = try JSONEncoder().encode(value)
        lock.lock()
        let callback = observer, failing = failKey == key
        if failing { failKey = nil }
        attempts.append(Write(key: key, bytes: data.count)); lock.unlock()
        callback?(key)
        if failing { throw AppError.storage("mock write failure") }
        lock.lock(); records[key] = data; lock.unlock()
    }
}

// Exact pre-optimization merge, retained only as a semantic and timing baseline.
func legacyCatalogMerge(_ fetched: [ModelRecord], cached: [ModelRecord]) -> [ModelRecord] {
    var result = fetched.map { remote -> ModelRecord in
        var value = remote
        if let old = cached.first(where: { $0.id == remote.id }) {
            value.favorite = old.favorite; value.order = old.order; value.overrides = old.overrides
            value.manual = old.manual; value.systemPrompt = old.systemPrompt; value.presetIDs = old.presetIDs
            value.contextWindowOverride = old.contextWindowOverride; value.outputLimitOverride = old.outputLimitOverride
            if old.manual { value.contextWindow = old.contextWindow ?? value.contextWindow; value.outputLimit = old.outputLimit ?? value.outputLimit }
        }
        return value
    }
    result += cached.filter { old in !result.contains(where: { $0.id == old.id }) }
    return result
}
