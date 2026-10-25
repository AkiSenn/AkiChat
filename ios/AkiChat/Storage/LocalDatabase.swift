import CoreData

protocol RecordDatabase: AnyObject {
    func load<T: Decodable>(_ key: String, as type: T.Type) throws -> T?
    func save<T: Encodable>(_ value: T, key: String) throws
}

/// Versioned Codable records in a Core Data SQLite store, with no runtime dependencies.
final class LocalDatabase: RecordDatabase {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext
    init(url: URL? = nil, inMemory: Bool = false) throws {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "Record"; entity.managedObjectClassName = "NSManagedObject"
        let key = NSAttributeDescription(); key.name = "key"; key.attributeType = .stringAttributeType; key.isOptional = false
        let payload = NSAttributeDescription(); payload.name = "payload"; payload.attributeType = .binaryDataAttributeType; payload.isOptional = false
        entity.properties = [key, payload]; entity.uniquenessConstraints = [["key"]]
        model.entities = [entity]
        container = NSPersistentContainer(name: "AkiChat", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        if inMemory { description.type = NSInMemoryStoreType }
        else {
            let location = try url ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("AkiChat.sqlite")
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            description.url = location; description.type = NSSQLiteStoreType
            description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject, forKey: NSPersistentStoreFileProtectionKey)
        }
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        if let failure = failure { throw failure }
        context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    func load<T: Decodable>(_ key: String, as type: T.Type) throws -> T? {
        var result: Result<T?, Error>!
        context.performAndWait {
            result = Result {
                let request = NSFetchRequest<NSManagedObject>(entityName: "Record")
                request.predicate = NSPredicate(format: "key == %@", key); request.fetchLimit = 1
                guard let record = try context.fetch(request).first, let data = record.value(forKey: "payload") as? Data else { return nil }
                return try JSONDecoder().decode(type, from: data)
            }
        }
        return try result.get()
    }
    func save<T: Encodable>(_ value: T, key: String) throws {
        let data = try JSONEncoder().encode(value)
        var failure: Error?
        context.performAndWait {
            do {
                let request = NSFetchRequest<NSManagedObject>(entityName: "Record")
                request.predicate = NSPredicate(format: "key == %@", key)
                let record = try context.fetch(request).first ?? NSEntityDescription.insertNewObject(forEntityName: "Record", into: context)
                record.setValue(key, forKey: "key"); record.setValue(data, forKey: "payload")
                try context.save()
            } catch { context.rollback(); failure = error }
        }
        if let failure = failure { throw failure }
    }
    func delete(_ key: String) throws {
        var failure: Error?
        context.performAndWait {
            do {
                let request = NSFetchRequest<NSManagedObject>(entityName: "Record")
                request.predicate = NSPredicate(format: "key == %@", key)
                try context.fetch(request).forEach(context.delete)
                try context.save()
            } catch { context.rollback(); failure = error }
        }
        if let failure = failure { throw failure }
    }
}
