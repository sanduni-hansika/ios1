import CoreData
import CoreLocation

/// Builds the Core Data model in code and owns the (optionally CloudKit-mirrored) container.
final class PersistenceController {
    static let shared = PersistenceController()
    static let cloudContainerID = "iCloud.com.agrinova.app"

    let container: NSPersistentCloudKitContainer
    var viewContext: NSManagedObjectContext { container.viewContext }

    /// - Parameters:
    ///   - inMemory: use a throw-away store (unit tests)
    ///   - cloud: mirror to the user's private iCloud database (Settings → iCloud sync)
    init(inMemory: Bool = false, cloud: Bool = AppSettings.shared.cloudSyncEnabled) {
        container = NSPersistentCloudKitContainer(name: "AgriNova", managedObjectModel: Self.model)
        let url = inMemory ? URL(fileURLWithPath: "/dev/null")
                           : NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("AgriNova.sqlite")
        let desc = NSPersistentStoreDescription(url: url)
        desc.shouldMigrateStoreAutomatically = true
        desc.shouldInferMappingModelAutomatically = true
        desc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        desc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        desc.cloudKitContainerOptions = (cloud && !inMemory)
            ? NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudContainerID) : nil
        container.persistentStoreDescriptions = [desc]
        container.loadPersistentStores { _, error in
            if let error { print("⚠️ Core Data failed to load: \(error)") }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func save() {
        let ctx = viewContext
        guard ctx.hasChanges else { return }
        do { try ctx.save() } catch { print("⚠️ Core Data save error: \(error)") }
    }

    /// Deletes every record (Settings → Reset data).
    func wipeAll() {
        let names = Self.model.entities.compactMap(\.name)
        for n in names {
            let req = NSFetchRequest<NSFetchRequestResult>(entityName: n)
            let del = NSBatchDeleteRequest(fetchRequest: req)
            del.resultType = .resultTypeObjectIDs
            if let res = try? viewContext.execute(del) as? NSBatchDeleteResult,
               let ids = res.result as? [NSManagedObjectID] {
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [NSDeletedObjectsKey: ids], into: [viewContext])
            }
        }
        viewContext.reset()
    }

    // MARK: - Model

    static let model: NSManagedObjectModel = {
        func attr(_ name: String, _ type: NSAttributeType, def: Any? = nil, external: Bool = false) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name; a.attributeType = type; a.isOptional = true
            if let def { a.defaultValue = def }
            a.allowsExternalBinaryDataStorage = external
            return a
        }
        func s(_ n: String) -> NSAttributeDescription { attr(n, .stringAttributeType) }
        func d(_ n: String) -> NSAttributeDescription { attr(n, .doubleAttributeType, def: 0.0) }
        func b(_ n: String, _ v: Bool = false) -> NSAttributeDescription { attr(n, .booleanAttributeType, def: v) }
        func i(_ n: String) -> NSAttributeDescription { attr(n, .integer32AttributeType, def: 0) }
        func i16(_ n: String) -> NSAttributeDescription { attr(n, .integer16AttributeType, def: 0) }
        func dt(_ n: String) -> NSAttributeDescription { attr(n, .dateAttributeType) }
        func u(_ n: String) -> NSAttributeDescription { attr(n, .UUIDAttributeType) }
        func bin(_ n: String) -> NSAttributeDescription { attr(n, .binaryDataAttributeType, external: true) }

        func entity(_ name: String, _ cls: AnyClass, _ props: [NSPropertyDescription]) -> NSEntityDescription {
            let e = NSEntityDescription()
            e.name = name; e.managedObjectClassName = NSStringFromClass(cls); e.properties = props
            return e
        }
        func rel(_ name: String, to dest: NSEntityDescription, many: Bool, rule: NSDeleteRule) -> NSRelationshipDescription {
            let r = NSRelationshipDescription()
            r.name = name; r.destinationEntity = dest; r.isOptional = true
            r.minCount = 0; r.maxCount = many ? 0 : 1; r.deleteRule = rule
            return r
        }

        let farm = entity("CDFarm", CDFarm.self, [u("id"), s("name"), s("locationName"), s("ownerName"), d("areaHectares"), d("latitude"), d("longitude"), dt("createdAt")])
        let zone = entity("CDZone", CDZone.self, [u("id"), s("name"), d("latitude"), d("longitude"), d("radius"), b("geofenceEnabled"), s("reminderText"), d("areaSize")])
        let crop = entity("CDCrop", CDCrop.self, [u("id"), s("name"), s("variety"), dt("plantedDate"), i("plantCount")])
        let worker = entity("CDWorker", CDWorker.self, [u("id"), s("name"), s("role"), s("phone")])

        let farmZones = rel("zones", to: zone, many: true, rule: .cascadeDeleteRule)
        let zoneFarm = rel("farm", to: farm, many: false, rule: .nullifyDeleteRule)
        farmZones.inverseRelationship = zoneFarm; zoneFarm.inverseRelationship = farmZones
        let farmWorkers = rel("workers", to: worker, many: true, rule: .cascadeDeleteRule)
        let workerFarm = rel("farm", to: farm, many: false, rule: .nullifyDeleteRule)
        farmWorkers.inverseRelationship = workerFarm; workerFarm.inverseRelationship = farmWorkers
        let zoneCrops = rel("crops", to: crop, many: true, rule: .cascadeDeleteRule)
        let cropZone = rel("zone", to: zone, many: false, rule: .nullifyDeleteRule)
        zoneCrops.inverseRelationship = cropZone; cropZone.inverseRelationship = zoneCrops
        farm.properties += [farmZones, farmWorkers]
        zone.properties += [zoneFarm, zoneCrops]
        crop.properties += [cropZone]
        worker.properties += [workerFarm]

        let scan = entity("CDScan", CDScan.self, [u("id"), dt("date"), bin("imageData"), s("speciesName"), s("diseaseLabel"), d("confidence"), d("affectedPercent"), b("isHealthy"), b("needsRescan"), d("latitude"), d("longitude"), u("zoneID"), s("zoneName"), s("source"), b("treatmentStarted"), dt("treatmentStartDate"), s("recheckDays"), s("topPredictions")])
        let task = entity("CDTask", CDTask.self, [u("id"), u("scanID"), s("title"), s("category"), b("done"), dt("doneDate"), i16("sortOrder")])
        let progress = entity("CDProgress", CDProgress.self, [u("id"), u("scanID"), dt("date"), i16("dayOffset"), d("affectedPercent"), bin("imageData")])
        let log = entity("CDLog", CDLog.self, [u("id"), dt("date"), s("kind"), s("title"), s("detail"), u("farmID"), s("zoneName")])
        let infected = entity("CDInfected", CDInfected.self, [u("id"), dt("date"), d("latitude"), d("longitude"), s("diseaseLabel"), s("note"), u("zoneID"), b("resolved")])
        let outbreak = entity("CDOutbreak", CDOutbreak.self, [s("id"), s("diseaseLabel"), s("species"), d("latitude"), d("longitude"), i16("severity"), s("reporter"), s("notes"), dt("createdAt"), s("district"), b("synced"), b("sharedWithExtension"), b("isMine"), b("notified")])
        let outbox = entity("CDOutbox", CDOutbox.self, [u("id"), attr("payload", .binaryDataAttributeType), dt("createdAt"), i16("attempts"), s("lastError")])

        let m = NSManagedObjectModel()
        m.entities = [farm, zone, crop, worker, scan, task, progress, log, infected, outbreak, outbox]
        return m
    }()
}
