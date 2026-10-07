import Foundation
import CoreData

struct StoredRecord {
    let key: String
    let kind: String
    let tripID: String
    let date: Date
    let data: Data
    init<T: StoredModel>(_ value: T) throws {
        key = "\(T.kind):\(value.id.uuidString)"
        kind = T.kind
        tripID = value.tripID.uuidString
        date = value.sortDate
        data = try JSONEncoder().encode(value)
    }
}
protocol TripRepository {
    func load<T: StoredModel>(_ type: T.Type, tripID: UUID?) throws -> [T]
    func commit(_ records: [StoredRecord], deleting: [String]) throws
    func deleteTrip(_ id: UUID) throws
}
extension TripRepository {
    func load<T: StoredModel>(_ type: T.Type) throws -> [T] { try load(type, tripID: nil) }
    func save<T: StoredModel>(_ value: T) throws { try commit([StoredRecord(value)], deleting: []) }
}

final class CoreDataRepository: TripRepository {
    private let context: NSManagedObjectContext
    init(url: URL?, inMemory: Bool = false) throws {
        let entity = NSEntityDescription()
        entity.name = "TravelRecord"
        entity.managedObjectClassName = "NSManagedObject"
        let fields: [(String, NSAttributeType)] = [("key", .stringAttributeType), ("kind", .stringAttributeType), ("tripID", .stringAttributeType), ("date", .dateAttributeType), ("payload", .binaryDataAttributeType)]
        entity.properties = fields.map { name, type in
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.attributeType = type
            attribute.isOptional = false
            return attribute
        }
        entity.uniquenessConstraints = [["key"]]
        let model = NSManagedObjectModel()
        model.entities = [entity]
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        var options: [AnyHashable: Any] = [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true]
        #if os(iOS)
        options[NSPersistentStoreFileProtectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        if let url = url { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true) }
        try coordinator.addPersistentStore(ofType: inMemory ? NSInMemoryStoreType : NSSQLiteStoreType, configurationName: nil, at: inMemory ? nil : url, options: options)
        context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.mergePolicy = NSErrorMergePolicy
        context.undoManager = nil
    }
    private func perform<T>(_ operation: () throws -> T) throws -> T {
        var result: Result<T, Error>!
        context.performAndWait { result = Result { try operation() } }
        return try result.get()
    }
    func load<T: StoredModel>(_ type: T.Type, tripID: UUID?) throws -> [T] {
        try perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "TravelRecord")
            var predicates = [NSPredicate(format: "kind == %@", T.kind)]
            if let id = tripID { predicates.append(NSPredicate(format: "tripID == %@", id.uuidString)) }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true), NSSortDescriptor(key: "key", ascending: true)]
            return try context.fetch(request).map { object in
                guard let data = object.value(forKey: "payload") as? Data else { throw TripError.storage("记录内容损坏") }
                return try JSONDecoder().decode(T.self, from: data)
            }
        }
    }
    func commit(_ records: [StoredRecord], deleting keys: [String]) throws {
        try perform {
            do {
                for key in keys {
                    let request = NSFetchRequest<NSManagedObject>(entityName: "TravelRecord")
                    request.predicate = NSPredicate(format: "key == %@", key)
                    for object in try context.fetch(request) { context.delete(object) }
                }
                for record in records {
                    let request = NSFetchRequest<NSManagedObject>(entityName: "TravelRecord")
                    request.predicate = NSPredicate(format: "key == %@", record.key)
                    let object = try context.fetch(request).first ?? NSEntityDescription.insertNewObject(forEntityName: "TravelRecord", into: context)
                    object.setValue(record.key, forKey: "key")
                    object.setValue(record.kind, forKey: "kind")
                    object.setValue(record.tripID, forKey: "tripID")
                    object.setValue(record.date, forKey: "date")
                    object.setValue(record.data, forKey: "payload")
                }
                if context.hasChanges { try context.save() }
            } catch { context.rollback(); throw error }
        }
    }
    func deleteTrip(_ id: UUID) throws {
        try perform {
            do {
                let request = NSFetchRequest<NSManagedObject>(entityName: "TravelRecord")
                request.predicate = NSPredicate(format: "tripID == %@", id.uuidString)
                for object in try context.fetch(request) { context.delete(object) }
                try context.save()
            } catch { context.rollback(); throw error }
        }
    }
}
