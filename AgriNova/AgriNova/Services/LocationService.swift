import CoreLocation
import CoreData
import Observation

struct GeofenceZone: Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let radius: Double
    let reminder: String
    let farmID: UUID?
}

/// Core Location + region monitoring (geofencing) for farm-zone entry/exit reminders.
/// iOS allows at most 20 monitored regions per app, so only the first 20 enabled zones are armed.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()
    static let maxRegions = 20
    /// Fallback when GPS is unavailable (Peradeniya, Sri Lanka).
    static let fallback = CLLocationCoordinate2D(latitude: 7.2606, longitude: 80.5970)

    var authStatus: CLAuthorizationStatus = .notDetermined
    var current: CLLocation?
    var monitored: [GeofenceZone] = []
    var insideZoneIDs: Set<String> = []
    var lastEvent: String = ""
    var lastEventDate: Date?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.pausesLocationUpdatesAutomatically = true
        authStatus = manager.authorizationStatus
    }

    var coordinate: CLLocationCoordinate2D { current?.coordinate ?? Self.fallback }
    var hasFix: Bool { current != nil }
    var isAuthorized: Bool { authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways }
    var hasAlways: Bool { authStatus == .authorizedAlways }

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    func start() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
    }

    func refresh() {
        guard isAuthorized else { requestPermission(); return }
        manager.requestLocation()
    }

    // MARK: Geofencing

    /// Re-arms monitoring from the current Core Data zones. Call after any zone create / edit / delete.
    func syncGeofences(from context: NSManagedObjectContext) {
        let req = NSFetchRequest<CDZone>(entityName: "CDZone")
        req.predicate = NSPredicate(format: "geofenceEnabled == YES")
        let zones = (try? context.fetch(req)) ?? []
        let list = zones.compactMap { z -> GeofenceZone? in
            guard let id = z.id else { return nil }
            return GeofenceZone(id: id.uuidString, name: z.displayName, latitude: z.latitude, longitude: z.longitude,
                                radius: max(50, z.radius), reminder: z.reminderText ?? "", farmID: z.farm?.id)
        }
        apply(list)
    }

    func apply(_ zones: [GeofenceZone]) {
        let armed = Array(zones.prefix(Self.maxRegions))
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { monitored = []; return }
        // Don't tear down and re-register identical regions (this also protects an event being delivered after a background relaunch).
        let maxR = manager.maximumRegionMonitoringDistance
        func sig(_ id: String, _ lat: Double, _ lon: Double, _ r: Double) -> String { "\(id)|\(lat)|\(lon)|\(r)" }
        let existing = Set(manager.monitoredRegions.compactMap { ($0 as? CLCircularRegion).map { sig($0.identifier, $0.center.latitude, $0.center.longitude, $0.radius) } })
        let wanted = Set(armed.map { sig($0.id, $0.latitude, $0.longitude, min($0.radius, maxR)) })
        if existing == wanted { monitored = armed; return }
        for r in manager.monitoredRegions { manager.stopMonitoring(for: r) }
        for z in armed {
            let region = CLCircularRegion(center: .init(latitude: z.latitude, longitude: z.longitude),
                                          radius: min(z.radius, manager.maximumRegionMonitoringDistance), identifier: z.id)
            region.notifyOnEntry = true; region.notifyOnExit = true
            manager.startMonitoring(for: region)
            manager.requestState(for: region)
        }
        monitored = armed
    }

    func zone(for id: String) -> GeofenceZone? { monitored.first { $0.id == id } }

    // MARK: Delegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways { manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.current = loc }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let id = region.identifier
        Task { @MainActor in self.handle(id: id, entered: true) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let id = region.identifier
        Task { @MainActor in self.handle(id: id, entered: false) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        let id = region.identifier
        Task { @MainActor in
            if state == .inside { self.insideZoneIDs.insert(id) } else { self.insideZoneIDs.remove(id) }
        }
    }

    /// Zone info for a region id. Falls back to Core Data because after iOS relaunches the app in the background
    /// for a region event the in-memory `monitored` list is still empty.
    private func lookupZone(_ id: String) -> GeofenceZone? {
        if let z = zone(for: id) { return z }
        guard let uuid = UUID(uuidString: id) else { return nil }
        let req = NSFetchRequest<CDZone>(entityName: "CDZone")
        req.predicate = NSPredicate(format: "id == %@", uuid as CVarArg); req.fetchLimit = 1
        guard let z = (try? PersistenceController.shared.viewContext.fetch(req))?.first else { return nil }
        return GeofenceZone(id: id, name: z.displayName, latitude: z.latitude, longitude: z.longitude,
                            radius: z.radius, reminder: z.reminderText ?? "", farmID: z.farm?.id)
    }

    /// Region entry / exit: writes a farm-log entry and fires a local notification for BOTH directions.
    private func handle(id: String, entered: Bool) {
        let zoneInfo = lookupZone(id)
        let name = zoneInfo?.name ?? "Zone"
        let reminder = zoneInfo?.reminder ?? ""
        if entered { insideZoneIDs.insert(id) } else { insideZoneIDs.remove(id) }
        lastEvent = entered ? "\(tr("geo.entered")) \(name)" : "\(tr("geo.left")) \(name)"
        lastEventDate = Date()

        // Farm log entry
        let ctx = PersistenceController.shared.viewContext
        let log = CDLog(context: ctx)
        log.id = UUID(); log.date = Date(); log.kind = "geofence"
        log.title = lastEvent; log.detail = reminder; log.zoneName = name
        log.farmID = zoneInfo?.farmID
        PersistenceController.shared.save()

        if entered {
            // Reminder: zone note + pending treatment steps
            let req = NSFetchRequest<CDTask>(entityName: "CDTask")
            req.predicate = NSPredicate(format: "done == NO")
            let pending = (try? ctx.count(for: req)) ?? 0
            var body = reminder.isEmpty ? tr("geo.default_reminder") : reminder
            if pending > 0 { body += "\n" + tr("geo.pending", pending) }
            NotificationService.fireNow(title: "\(tr("geo.entered")) \(name)", body: body, userInfo: ["route": "farm"])
        } else {
            NotificationService.fireNow(title: "\(tr("geo.left")) \(name)", body: tr("geo.left_body"), userInfo: ["route": "farm"])
        }
    }
}
