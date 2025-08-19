import Foundation
import CoreData

// MARK: - CoreDataStack (in-memory + on-disk контейнер)
final class CoreDataStack {
    static let shared = CoreDataStack()
    private init() {
        persistentContainer = NSPersistentContainer(name: "KVStore")
        if let description = persistentContainer.persistentStoreDescriptions.first {
            description.url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!.appendingPathComponent("KVStore.sqlite")
            try? FileManager.default.createDirectory(
                at: description.url!.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        persistentContainer.loadPersistentStores { _, error in
            if let error = error { fatalError("CoreData load error: \(error)") }
        }
        context = persistentContainer.viewContext
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    let persistentContainer: NSPersistentContainer
    let context: NSManagedObjectContext
}

// MARK: - Модель (программно описываемая схема)
@objc(KVEntry)
final class KVEntry: NSManagedObject {
    @NSManaged var namespace: String
    @NSManaged var key: String
    @NSManaged var payload: Data
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var ttl: Double 
}

extension KVEntry {
    @nonobjc class func fetchRequest(namespace: String, key: String) -> NSFetchRequest<KVEntry> {
        let req = NSFetchRequest<KVEntry>(entityName: "KVEntry")
        req.predicate = NSPredicate(format: "namespace == %@ AND key == %@", namespace, key)
        req.fetchLimit = 1
        return req
    }
}

// MARK: - Описание модели (NSManagedObjectModel) без .xcdatamodeld
private extension NSPersistentContainer {
    convenience init(name: String) {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "KVEntry"
        entity.managedObjectClassName = NSStringFromClass(KVEntry.self)

        let fNamespace = NSAttributeDescription()
        fNamespace.name = "namespace"
        fNamespace.attributeType = .stringAttributeType
        fNamespace.isOptional = false

        let fKey = NSAttributeDescription()
        fKey.name = "key"
        fKey.attributeType = .stringAttributeType
        fKey.isOptional = false

        let fPayload = NSAttributeDescription()
        fPayload.name = "payload"
        fPayload.attributeType = .binaryDataAttributeType
        fPayload.isOptional = false

        let fCreatedAt = NSAttributeDescription()
        fCreatedAt.name = "createdAt"
        fCreatedAt.attributeType = .dateAttributeType
        fCreatedAt.isOptional = false

        let fUpdatedAt = NSAttributeDescription()
        fUpdatedAt.name = "updatedAt"
        fUpdatedAt.attributeType = .dateAttributeType
        fUpdatedAt.isOptional = false

        let fTTL = NSAttributeDescription()
        fTTL.name = "ttl"
        fTTL.attributeType = .doubleAttributeType
        fTTL.isOptional = false
        fTTL.defaultValue = 0.0

        entity.properties = [fNamespace, fKey, fPayload, fCreatedAt, fUpdatedAt, fTTL]

        entity.uniquenessConstraints = [["namespace", "key"]]

        model.entities = [entity]
        self.init(name: name, managedObjectModel: model)
    }
}

// MARK: - API для ViewModel/Repository
/// Универсальное хранилище: сохраняет/читает любые Codable-объекты по ключу.
final class KVStore {
    static let shared = KVStore()
    private let ctx: NSManagedObjectContext
    private init() { ctx = CoreDataStack.shared.context }

    func put<T: Codable>(_ value: T, namespace: String, key: String, ttl: TimeInterval = 0) throws {
        let data = try JSONEncoder().encode(value)
        let now = Date()

        let req = KVEntry.fetchRequest(namespace: namespace, key: key)
        let obj = try ctx.fetch(req).first ?? {
            let ent = NSEntityDescription.insertNewObject(forEntityName: "KVEntry", into: ctx) as! KVEntry
            ent.namespace = namespace
            ent.key = key
            ent.createdAt = now
            return ent
        }()

        obj.payload = data
        obj.updatedAt = now
        obj.ttl = ttl

        try ctx.save()
    }

    func get<T: Codable>(_ type: T.Type, namespace: String, key: String) throws -> T? {
        let req = KVEntry.fetchRequest(namespace: namespace, key: key)
        guard let obj = try ctx.fetch(req).first else { return nil }
        if obj.ttl > 0, Date().timeIntervalSince(obj.updatedAt) > obj.ttl {
            try delete(namespace: namespace, key: key)
            return nil
        }
        return try JSONDecoder().decode(T.self, from: obj.payload)
    }

    func delete(namespace: String, key: String) throws {
        let req = KVEntry.fetchRequest(namespace: namespace, key: key)
        if let obj = try ctx.fetch(req).first {
            ctx.delete(obj)
            try ctx.save()
        }
    }

    func clear(namespace: String) throws {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "KVEntry")
        fetch.predicate = NSPredicate(format: "namespace == %@", namespace)
        let batch = NSBatchDeleteRequest(fetchRequest: fetch)
        try ctx.execute(batch)
        try ctx.save()
    }
}
