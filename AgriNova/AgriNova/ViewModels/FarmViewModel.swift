import CoreData
import CoreLocation

/// Farm CRUD operations (create / read / update / delete) kept out of the views – MVVM.
/// Every mutation also writes a farm-log entry and re-arms geofences when zones change.
@MainActor
enum FarmViewModel {
    static var ctx: NSManagedObjectContext { PersistenceController.shared.viewContext }

    static func log(_ kind: String, _ title: String, _ detail: String = "", farm: CDFarm? = nil, zone: String? = nil) {
        let l = CDLog(context: ctx)
        l.id = UUID(); l.date = Date(); l.kind = kind; l.title = title; l.detail = detail; l.farmID = farm?.id; l.zoneName = zone
    }

    @discardableResult
    static func saveFarm(_ farm: CDFarm?, name: String, location: String, owner: String, area: Double, coordinate: CLLocationCoordinate2D) -> CDFarm {
        let f = farm ?? CDFarm(context: ctx)
        let isNew = farm == nil
        if isNew { f.id = UUID(); f.createdAt = Date() }
        f.name = name; f.locationName = location; f.ownerName = owner; f.areaHectares = area
        f.latitude = coordinate.latitude; f.longitude = coordinate.longitude
        log("activity", isNew ? tr("farm.log.created") : tr("farm.log.updated"), name, farm: f)
        PersistenceController.shared.save(); WidgetUpdater.refresh()
        return f
    }

    static func delete(_ farm: CDFarm) {
        ctx.delete(farm)
        PersistenceController.shared.save()
        LocationService.shared.syncGeofences(from: ctx); WidgetUpdater.refresh()
    }

    @discardableResult
    static func saveZone(_ zone: CDZone?, in farm: CDFarm, name: String, coordinate: CLLocationCoordinate2D, radius: Double, geofence: Bool, reminder: String) -> CDZone {
        let z = zone ?? CDZone(context: ctx)
        if zone == nil { z.id = UUID(); z.farm = farm }
        z.name = name; z.latitude = coordinate.latitude; z.longitude = coordinate.longitude
        z.radius = radius; z.geofenceEnabled = geofence; z.reminderText = reminder
        log("activity", zone == nil ? tr("farm.log.zone_added") : tr("farm.log.zone_updated"), name, farm: farm, zone: name)
        PersistenceController.shared.save()
        LocationService.shared.syncGeofences(from: ctx)
        return z
    }

    static func deleteZone(_ z: CDZone) {
        ctx.delete(z); PersistenceController.shared.save(); LocationService.shared.syncGeofences(from: ctx)
    }

    static func saveCrop(_ crop: CDCrop?, in zone: CDZone, name: String, variety: String, planted: Date, count: Int) {
        let c = crop ?? CDCrop(context: ctx)
        if crop == nil { c.id = UUID(); c.zone = zone }
        c.name = name; c.variety = variety; c.plantedDate = planted; c.plantCount = Int32(count)
        log("activity", tr("farm.log.crop"), "\(name) • \(zone.displayName)", farm: zone.farm, zone: zone.displayName)
        PersistenceController.shared.save()
    }

    static func saveWorker(_ w: CDWorker?, in farm: CDFarm, name: String, role: String, phone: String) {
        let x = w ?? CDWorker(context: ctx)
        if w == nil { x.id = UUID(); x.farm = farm }
        x.name = name; x.role = role; x.phone = phone
        PersistenceController.shared.save()
    }

    static func delete(_ obj: NSManagedObject) { ctx.delete(obj); PersistenceController.shared.save() }

    /// Marks the exact spot of an infected plant (from a scan or by tapping the map).
    static func markInfected(disease: Disease?, coordinate: CLLocationCoordinate2D, note: String, zone: CDZone?) {
        let i = CDInfected(context: ctx)
        i.id = UUID(); i.date = Date(); i.latitude = coordinate.latitude; i.longitude = coordinate.longitude
        i.diseaseLabel = disease?.id; i.note = note; i.zoneID = zone?.id
        log("outbreak", "\(tr("farm.log.infected")): \(disease?.displayName ?? "")", note, farm: zone?.farm, zone: zone?.displayName)
        PersistenceController.shared.save()
    }

    static func addNote(_ text: String, farm: CDFarm?, zone: String? = nil) {
        log("note", text, "", farm: farm, zone: zone)
        PersistenceController.shared.save()
    }
}
