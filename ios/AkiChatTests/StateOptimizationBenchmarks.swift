import XCTest
import Foundation
import CoreFoundation
@testable import AkiChat

final class StateOptimizationBenchmarks: XCTestCase {
    private func report(_ values: [String: Any]) throws {
        print("STATE_OPTIMIZATION_BENCHMARK " + String(decoding: try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]), as: UTF8.self))
    }
    private func elapsed(_ action: () -> Void) -> Double {
        let start = CFAbsoluteTimeGetCurrent(); action(); return (CFAbsoluteTimeGetCurrent() - start) * 1000
    }
    private func flush(_ store: AppStore) {
        let done = expectation(description: "flush")
        store.flushPersistence { done.fulfill() }; wait(for: [done], timeout: 3)
    }
    func testCompareModelSwitchStateWork() throws {
        for count in [100, 500] {
            let db = RecordingDatabase(), p = Provider.deepSeek
            let messages = (0..<count).map { Message(role: .user, content: String(repeating: "history \($0) ", count: 20)) }
            try db.save([p], key: "providers.v1")
            try db.save([Conversation(providerID: p.id, messages: messages)], key: "conversations.v1")
            try db.save([ModelCatalog(id: p.id, models: [ModelRecord(id: p.modelID, name: "Flash"), ModelRecord(id: "other", name: "Other")])], key: "catalogs.v2")
            let store = AppStore(database: db); flush(store)
            for trial in 0..<4 {
                var oldMS = 0.0, newMS = 0.0
                let before = store.chat.reconciliationCount
                // The legacy mutation path always reconciled messages; the rest of
                // the real AppStore selection path is identical on both sides.
                for tick in 0..<24 {
                    let id = tick.isMultiple(of: 2) ? p.modelID : "other"
                    func old() { store.selectModel(providerID: p.id, modelID: id); store.chat.reconcile(store.messages) }
                    func new() { store.selectModel(providerID: p.id, modelID: id) }
                    if (tick + trial).isMultiple(of: 2) { oldMS += elapsed(old); newMS += elapsed(new) }
                    else { newMS += elapsed(new); oldMS += elapsed(old) }
                }
                XCTAssertEqual(store.chat.reconciliationCount - before, 24)
                XCTAssertEqual(store.messages, messages)
                try report(["case": "model-switch", "messages": count, "trial": trial, "switchesPerPath": 24,
                            "legacyMS": oldMS, "optimizedMS": newMS, "legacyReconciles": 24, "optimizedReconciles": 0])
            }
        }
    }
    func testCompareModelPanelRepeatedReads() throws {
        let id = UUID()
        let values = (0..<1000).map { ModelRecord(id: "model-\($0)", name: "Model \($0)") }
        for trial in 0..<4 {
            let cache = ModelListCache()
            var old: [ModelRecord] = [], new: [ModelRecord] = []
            func oldWork() { for _ in 0..<10 { old = ModelDiscovery.filtered(values, query: "model"); old = ModelDiscovery.filtered(values, query: "model") } }
            func newWork() { for _ in 0..<10 { new = cache.models(for: id, source: { values }, query: "model"); new = cache.models(for: id, source: { values }, query: "model") } }
            var oldMS = 0.0, newMS = 0.0
            if trial.isMultiple(of: 2) { oldMS = elapsed(oldWork); newMS = elapsed(newWork) }
            else { newMS = elapsed(newWork); oldMS = elapsed(oldWork) }
            XCTAssertEqual(old, new); XCTAssertEqual(cache.sortCount, 1); XCTAssertEqual(cache.filterCount, 1)
            try report(["case": "model-panel", "models": values.count, "trial": trial, "reads": 20,
                        "legacyMS": oldMS, "optimizedMS": newMS, "legacySorts": 20, "optimizedSorts": cache.sortCount])
        }
    }
    func testCompareIndexedCatalogMerge() throws {
        var cached = (0..<2000).map { ModelRecord(id: "model-\($0)", name: "Cached \($0)") }
        cached[5].favorite = true; cached[7].manual = true; cached[7].overrides.tools = false
        let remote = (0..<2000).map { ModelRecord(id: "model-\($0 + 500)", name: "Remote \($0)") }
        for trial in 0..<4 {
            var old: [ModelRecord] = [], new: [ModelRecord] = []
            var oldMS = 0.0, newMS = 0.0
            if trial.isMultiple(of: 2) {
                oldMS = elapsed { old = legacyCatalogMerge(remote, cached: cached) }
                newMS = elapsed { new = ModelDiscovery.merge(remote, cached: cached) }
            } else {
                newMS = elapsed { new = ModelDiscovery.merge(remote, cached: cached) }
                oldMS = elapsed { old = legacyCatalogMerge(remote, cached: cached) }
            }
            XCTAssertEqual(old, new)
            try report(["case": "catalog-merge", "remote": remote.count, "cached": cached.count, "trial": trial,
                        "legacyMS": oldMS, "optimizedMS": newMS])
        }
    }
    func testCompareStorageWriteVolume() throws {
        let db = RecordingDatabase(), p = Provider.deepSeek
        let messages = (0..<500).map { Message(role: .user, content: String(repeating: "history \($0) ", count: 100)) }
        try db.save([p], key: "providers.v1")
        try db.save([Conversation(providerID: p.id, messages: messages)], key: "conversations.v1")
        try db.save([ModelCatalog(id: p.id, models: (0..<1000).map { ModelRecord(id: "model-\($0)", name: "Model \($0)") })], key: "catalogs.v2")
        let store = AppStore(database: db); flush(store); db.clearWrites()
        func legacyBytes() throws -> Int {
            let encoder = JSONEncoder()
            return try encoder.encode(store.exportConversations()).count + encoder.encode(store.providers).count +
                encoder.encode(store.settings).count + encoder.encode(store.catalogs).count
        }
        store.updateSetting(\.fontSize, 19)
        let settingsBaseline = try legacyBytes(); flush(store)
        XCTAssertEqual(db.writes.map(\.key), ["settings.v1"])
        try report(["case": "settings-save", "legacyRecords": 4, "optimizedRecords": db.writes.count,
                    "legacyEncodedBytes": settingsBaseline, "optimizedEncodedBytes": db.writes.reduce(0) { $0 + $1.bytes }])
        db.clearWrites(); store.setDraft("draft update")
        let draftBaseline = try legacyBytes(); flush(store)
        XCTAssertEqual(db.writes.map(\.key), ["conversations.v1"])
        try report(["case": "draft-save", "legacyRecords": 4, "optimizedRecords": db.writes.count,
                    "legacyEncodedBytes": draftBaseline, "optimizedEncodedBytes": db.writes.reduce(0) { $0 + $1.bytes }])
    }
}
