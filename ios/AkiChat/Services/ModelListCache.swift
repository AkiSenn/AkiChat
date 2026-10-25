import Foundation

/// Main-thread memoization of immutable catalog snapshots; no query history grows here.
final class ModelListCache {
    private final class Entry: NSObject {
        let sorted: [ModelRecord]
        var query = ""
        var matches: [ModelRecord]?
        var favorites: [ModelRecord]?
        init(_ sorted: [ModelRecord]) { self.sorted = sorted; matches = sorted }
    }
    private let entries: NSCache<NSUUID, Entry> = {
        let cache = NSCache<NSUUID, Entry>()
        cache.countLimit = 4; cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()
    #if DEBUG
    private(set) var sortCount = 0
    private(set) var filterCount = 0
    #endif
    func invalidate() { entries.removeAllObjects() }
    func models(for id: UUID, source: () -> [ModelRecord], query: String, favoritesOnly: Bool = false) -> [ModelRecord] {
        precondition(Thread.isMainThread)
        let entry: Entry
        if let cached = entries.object(forKey: id as NSUUID) { entry = cached }
        else {
            entry = Entry(ModelDiscovery.filtered(source(), query: ""))
            entries.setObject(entry, forKey: id as NSUUID,
                              cost: entry.sorted.count * MemoryLayout<ModelRecord>.stride * 3)
            #if DEBUG
            sortCount += 1
            #endif
        }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if entry.query != text { entry.query = text; entry.matches = nil; entry.favorites = nil }
        if entry.matches == nil {
            entry.matches = text.isEmpty ? entry.sorted : entry.sorted.filter {
                $0.name.localizedCaseInsensitiveContains(text) || $0.id.localizedCaseInsensitiveContains(text)
            }
            #if DEBUG
            filterCount += 1
            #endif
        }
        if !favoritesOnly { return entry.matches ?? [] }
        if entry.favorites == nil { entry.favorites = entry.matches?.filter(\.favorite) }
        return entry.favorites ?? []
    }
}
