import CoreData
import CoreLocation
import UIKit

// NSManagedObject subclasses. The model itself is built in code (see PersistenceController) so the
// project needs no .xcdatamodeld file. All attributes are optional/defaulted and relationships are
// optional with inverses, which keeps the schema CloudKit-compatible.

@objc(CDFarm) final class CDFarm: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var locationName: String?
    @NSManaged var ownerName: String?
    @NSManaged var areaHectares: Double
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    @NSManaged var createdAt: Date?
    @NSManaged var zones: NSSet?
    @NSManaged var workers: NSSet?
    var zoneList: [CDZone] { (zones as? Set<CDZone> ?? []).sorted { ($0.name ?? "") < ($1.name ?? "") } }
    var workerList: [CDWorker] { (workers as? Set<CDWorker> ?? []).sorted { ($0.name ?? "") < ($1.name ?? "") } }
    var displayName: String { name ?? "Farm" }
}

@objc(CDZone) final class CDZone: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    @NSManaged var radius: Double
    @NSManaged var geofenceEnabled: Bool
    @NSManaged var reminderText: String?
    @NSManaged var areaSize: Double
    @NSManaged var farm: CDFarm?
    @NSManaged var crops: NSSet?
    var cropList: [CDCrop] { (crops as? Set<CDCrop> ?? []).sorted { ($0.name ?? "") < ($1.name ?? "") } }
    var displayName: String { name ?? "Zone" }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

@objc(CDCrop) final class CDCrop: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var variety: String?
    @NSManaged var plantedDate: Date?
    @NSManaged var plantCount: Int32
    @NSManaged var zone: CDZone?
}

@objc(CDWorker) final class CDWorker: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var role: String?
    @NSManaged var phone: String?
    @NSManaged var farm: CDFarm?
}

@objc(CDScan) final class CDScan: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var date: Date?
    @NSManaged var imageData: Data?
    @NSManaged var speciesName: String?
    @NSManaged var diseaseLabel: String?
    @NSManaged var confidence: Double
    @NSManaged var affectedPercent: Double
    @NSManaged var isHealthy: Bool
    @NSManaged var needsRescan: Bool
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    @NSManaged var zoneID: UUID?
    @NSManaged var zoneName: String?
    @NSManaged var source: String?
    @NSManaged var treatmentStarted: Bool
    @NSManaged var treatmentStartDate: Date?
    @NSManaged var recheckDays: String?
    @NSManaged var topPredictions: String?    // "label:0.91;label2:0.05"
    var disease: Disease? { diseaseLabel.flatMap(DiseaseCatalog.find) }
    var image: UIImage? { imageData.flatMap(UIImage.init(data:)) }
    var hasLocation: Bool { latitude != 0 || longitude != 0 }
}

@objc(CDTask) final class CDTask: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var scanID: UUID?
    @NSManaged var title: String?
    @NSManaged var category: String?          // organic | chemical | cultural
    @NSManaged var done: Bool
    @NSManaged var doneDate: Date?
    @NSManaged var sortOrder: Int16
}

@objc(CDProgress) final class CDProgress: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var scanID: UUID?
    @NSManaged var date: Date?
    @NSManaged var dayOffset: Int16
    @NSManaged var affectedPercent: Double
    @NSManaged var imageData: Data?
}

@objc(CDLog) final class CDLog: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var date: Date?
    @NSManaged var kind: String?              // note | scan | treatment | geofence | outbreak | activity
    @NSManaged var title: String?
    @NSManaged var detail: String?
    @NSManaged var farmID: UUID?
    @NSManaged var zoneName: String?
}

@objc(CDInfected) final class CDInfected: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var date: Date?
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    @NSManaged var diseaseLabel: String?
    @NSManaged var note: String?
    @NSManaged var zoneID: UUID?
    @NSManaged var resolved: Bool
}

@objc(CDOutbreak) final class CDOutbreak: NSManagedObject, Identifiable {
    @NSManaged var id: String?
    @NSManaged var diseaseLabel: String?
    @NSManaged var species: String?
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    @NSManaged var severity: Int16
    @NSManaged var reporter: String?
    @NSManaged var notes: String?
    @NSManaged var createdAt: Date?
    @NSManaged var district: String?
    @NSManaged var synced: Bool
    @NSManaged var sharedWithExtension: Bool
    @NSManaged var isMine: Bool
    @NSManaged var notified: Bool
    var disease: Disease? { diseaseLabel.flatMap(DiseaseCatalog.find) }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

/// Offline synchronisation queue item – a JSON-encoded OutbreakDTO waiting for connectivity.
@objc(CDOutbox) final class CDOutbox: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var payload: Data?
    @NSManaged var createdAt: Date?
    @NSManaged var attempts: Int16
    @NSManaged var lastError: String?
}
