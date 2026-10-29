import Foundation
import CoreData
import CoreLocation
import Network
import Observation

/// Offline-first synchronisation of community outbreak reports.
/// - Reports are written to Core Data and to an **outbox queue** (CDOutbox) immediately.
/// - When the network is reachable the queue is uploaded to the backend, then fresh reports are pulled
///   and cached so the live map works offline with the last known data.
@MainActor @Observable
final class SyncService {
    static let shared = SyncService()

    var isOnline = true
    var isSyncing = false
    var pendingCount = 0
    var lastSync: Date?
    var lastError: String?
    var backendName: String

    private let monitor = NWPathMonitor()
    private var backend: OutbreakBackend
    private var ctx: NSManagedObjectContext { PersistenceController.shared.viewContext }
    static let alertRadiusKm = 15.0

    init() {
        backend = BackendConfig.isConfigured
            ? FirestoreBackend(projectID: BackendConfig.firebaseProjectID, tokenProvider: { try await AuthSession.shared.validIDToken() })
            : LocalDemoBackend()
        backendName = backend.name
        lastSync = UserDefaults.standard.object(forKey: "lastSync") as? Date
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let was = self.isOnline
                self.isOnline = online
                if online && !was { await self.syncNow() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "agrinova.network"))
        refreshPending()
    }

    func appBecameActive() { Task { await syncNow() } }

    func refreshPending() {
        pendingCount = (try? ctx.count(for: NSFetchRequest<CDOutbox>(entityName: "CDOutbox"))) ?? 0
    }

    // MARK: Submit

    /// Saves a report locally, queues it for upload, and tries to upload straight away if online.
    @discardableResult
    func submitReport(disease: Disease, severity: Int, notes: String, shareWithExtension: Bool,
                      coordinate: CLLocationCoordinate2D, district: String = "") -> OutbreakDTO {
        let dto = OutbreakDTO(id: UUID().uuidString, diseaseLabel: disease.id, species: "Tomato",
                              latitude: coordinate.latitude, longitude: coordinate.longitude, severity: severity,
                              reporter: AppSettings.shared.userName.isEmpty ? "Farmer" : AppSettings.shared.userName,
                              notes: notes, createdAt: Date(), district: district, sharedWithExtension: shareWithExtension,
                              uid: AuthSession.shared.uid ?? "")
        let o = CDOutbreak(context: ctx)
        apply(dto, to: o, synced: false, mine: true)
        let q = CDOutbox(context: ctx)
        q.id = UUID(); q.createdAt = Date(); q.attempts = 0
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        q.payload = try? enc.encode(dto)
        PersistenceController.shared.save()
        refreshPending()
        if isOnline { Task { await syncNow() } }
        return dto
    }

    // MARK: Sync

    func syncNow() async {
        guard !isSyncing else { return }
        isSyncing = true; lastError = nil
        defer { isSyncing = false; refreshPending() }
        await flushOutbox()
        await pull()
    }

    private func flushOutbox() async {
        let req = NSFetchRequest<CDOutbox>(entityName: "CDOutbox")
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        guard let items = try? ctx.fetch(req), !items.isEmpty else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        for item in items {
            guard let data = item.payload, let dto = try? dec.decode(OutbreakDTO.self, from: data) else { ctx.delete(item); continue }
            do {
                try await backend.submit(dto)
                let r = NSFetchRequest<CDOutbreak>(entityName: "CDOutbreak")
                r.predicate = NSPredicate(format: "id == %@", dto.id)
                (try? ctx.fetch(r))?.first?.synced = true
                ctx.delete(item)
            } catch {
                item.attempts += 1; item.lastError = error.localizedDescription
                lastError = error.localizedDescription
            }
        }
        PersistenceController.shared.save()
    }

    private func pull() async {
        do {
            let since = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
            let remote = try await backend.fetch(since: since)
            var fresh: [CDOutbreak] = []
            for dto in remote {
                let r = NSFetchRequest<CDOutbreak>(entityName: "CDOutbreak")
                r.predicate = NSPredicate(format: "id == %@", dto.id); r.fetchLimit = 1
                if let existing = (try? ctx.fetch(r))?.first { existing.synced = true; continue }
                let o = CDOutbreak(context: ctx)
                apply(dto, to: o, synced: true, mine: false)
                fresh.append(o)
            }
            PersistenceController.shared.save()
            lastSync = Date(); UserDefaults.standard.set(lastSync, forKey: "lastSync")
            notifyNearby(fresh)
            WidgetUpdater.refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Nearby-farmer warnings: a local notification for each new report within 15 km that the user didn't file.
    private func notifyNearby(_ reports: [CDOutbreak]) {
        let here = CLLocation(latitude: LocationService.shared.coordinate.latitude, longitude: LocationService.shared.coordinate.longitude)
        for r in reports where !r.isMine && !r.notified {
            let km = here.distance(from: CLLocation(latitude: r.latitude, longitude: r.longitude)) / 1000
            guard km <= Self.alertRadiusKm, let d = r.disease else { continue }
            r.notified = true
            NotificationService.fireNow(title: "⚠️ \(tr("radar.alert_title"))",
                                        body: tr("radar.alert_body", d.displayName, String(format: "%.1f", km)),
                                        userInfo: ["route": "radar"])
        }
        PersistenceController.shared.save()
    }

    private func apply(_ dto: OutbreakDTO, to o: CDOutbreak, synced: Bool, mine: Bool) {
        o.id = dto.id; o.diseaseLabel = dto.diseaseLabel; o.species = dto.species
        o.latitude = dto.latitude; o.longitude = dto.longitude; o.severity = Int16(dto.severity)
        o.reporter = dto.reporter; o.notes = dto.notes; o.createdAt = dto.createdAt; o.district = dto.district
        o.sharedWithExtension = dto.sharedWithExtension; o.synced = synced; o.isMine = mine; o.notified = mine
    }
}
