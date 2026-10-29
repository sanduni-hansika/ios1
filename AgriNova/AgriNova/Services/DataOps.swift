import CoreData
import UIKit
import WidgetKit
import CoreLocation

// MARK: - Scan persistence

enum ScanStore {
    @discardableResult
    static func save(_ outcome: ScanOutcome, source: String, zone: CDZone? = nil,
                     context: NSManagedObjectContext = PersistenceController.shared.viewContext) -> CDScan {
        let s = CDScan(context: context)
        s.id = UUID(); s.date = Date()
        s.imageData = outcome.image.jpegForStorage()
        s.speciesName = Species.tomatoName[0]
        s.diseaseLabel = outcome.disease?.id ?? outcome.top.first?.label
        s.confidence = outcome.confidence
        s.affectedPercent = outcome.affectedPercent
        s.isHealthy = outcome.disease?.isHealthy ?? false
        s.needsRescan = outcome.needsRescan
        s.source = source
        s.topPredictions = outcome.top.map { "\($0.label):\(String(format: "%.3f", $0.confidence))" }.joined(separator: ";")
        let loc = LocationService.shared.current?.coordinate
        s.latitude = loc?.latitude ?? 0; s.longitude = loc?.longitude ?? 0
        if let zone { s.zoneID = zone.id; s.zoneName = zone.name }

        let log = CDLog(context: context)
        log.id = UUID(); log.date = Date(); log.kind = "scan"
        log.title = "\(tr("log.scan")): \(outcome.disease?.displayName ?? "?")"
        log.detail = "\(Int((outcome.confidence * 100).rounded()))% \(tr("scan.confidence"))"
        log.zoneName = zone?.name; log.farmID = zone?.farm?.id
        PersistenceController.shared.save()
        WidgetUpdater.refresh()
        return s
    }

    static func topPredictions(_ s: CDScan) -> [Prediction] {
        (s.topPredictions ?? "").split(separator: ";").compactMap { part in
            let bits = part.split(separator: ":")
            guard bits.count == 2, let c = Double(bits[1]) else { return nil }
            return Prediction(label: String(bits[0]), confidence: c)
        }
    }
}

// MARK: - Treatments

enum TreatmentService {
    static func tasks(for scan: CDScan, in ctx: NSManagedObjectContext) -> [CDTask] {
        let r = NSFetchRequest<CDTask>(entityName: "CDTask")
        r.predicate = NSPredicate(format: "scanID == %@", (scan.id ?? UUID()) as CVarArg)
        r.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        return (try? ctx.fetch(r)) ?? []
    }

    static func progress(for scan: CDScan, in ctx: NSManagedObjectContext) -> [CDProgress] {
        let r = NSFetchRequest<CDProgress>(entityName: "CDProgress")
        r.predicate = NSPredicate(format: "scanID == %@", (scan.id ?? UUID()) as CVarArg)
        r.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        return (try? ctx.fetch(r)) ?? []
    }

    /// Creates the crop-specific checklist (organic / chemical / cultural) and schedules recheck reminders.
    static func start(scan: CDScan, recheckDays: [Int] = [3, 7, 14], in ctx: NSManagedObjectContext) {
        guard !scan.treatmentStarted, let d = scan.disease, !d.isHealthy, let sid = scan.id else { return }
        var order: Int16 = 0
        func add(_ title: String, _ cat: String) {
            let t = CDTask(context: ctx)
            t.id = UUID(); t.scanID = sid; t.title = title; t.category = cat; t.done = false; t.sortOrder = order; order += 1
        }
        d.organic.forEach { add($0, "organic") }
        d.cultural.forEach { add($0, "cultural") }
        d.chemical.forEach { add($0, "chemical") }
        scan.treatmentStarted = true
        scan.treatmentStartDate = Date()
        scan.recheckDays = recheckDays.map(String.init).joined(separator: ",")

        // Baseline (Day 0) so trends have a starting point.
        let p = CDProgress(context: ctx)
        p.id = UUID(); p.scanID = sid; p.date = scan.date ?? Date(); p.dayOffset = 0
        p.affectedPercent = scan.affectedPercent; p.imageData = scan.imageData

        let log = CDLog(context: ctx)
        log.id = UUID(); log.date = Date(); log.kind = "treatment"
        log.title = "\(tr("log.treatment_started")): \(d.displayName)"; log.detail = "\(tr("treat.recheck_in")) \(recheckDays.map(String.init).joined(separator: "/")) \(tr("treat.days"))"
        PersistenceController.shared.save()
        scheduleRechecks(scan: scan, days: recheckDays)
        WidgetUpdater.refresh()
    }

    static func scheduleRechecks(scan: CDScan, days: [Int]) {
        guard let sid = scan.id, let d = scan.disease else { return }
        for day in days {
            let id = "recheck-\(sid.uuidString)-\(day)"
            NotificationService.cancel(ids: [id])
            NotificationService.schedule(id: id, title: "\(tr("notif.recheck_title")) – \(d.displayName)",
                                         body: tr("notif.recheck_body", day),
                                         at: Calendar.current.date(byAdding: .day, value: day, to: Date()) ?? Date(),
                                         userInfo: ["route": "treatments"])
        }
    }

    static func setDone(_ task: CDTask, _ done: Bool) {
        task.done = done; task.doneDate = done ? Date() : nil
        PersistenceController.shared.save()
        WidgetUpdater.refresh()
    }

    static func addProgress(scan: CDScan, image: UIImage, percent: Double, in ctx: NSManagedObjectContext) {
        let start = scan.treatmentStartDate ?? scan.date ?? Date()
        let day = max(0, Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0)
        let p = CDProgress(context: ctx)
        p.id = UUID(); p.scanID = scan.id; p.date = Date(); p.dayOffset = Int16(day)
        p.affectedPercent = percent; p.imageData = image.jpegForStorage(maxSide: 700)
        let log = CDLog(context: ctx)
        log.id = UUID(); log.date = Date(); log.kind = "treatment"
        log.title = "\(tr("log.recheck")) \(tr("treat.day")) \(day)"; log.detail = "\(Int(percent))% \(tr("treat.affected"))"
        PersistenceController.shared.save()
    }

    enum Trend { case improving, worsening, steady, unknown }
    static func trend(_ points: [CDProgress]) -> Trend {
        guard points.count >= 2 else { return .unknown }
        let diff = points[points.count - 1].affectedPercent - points[points.count - 2].affectedPercent
        return diff < -2 ? .improving : (diff > 2 ? .worsening : .steady)
    }
}

// MARK: - Widgets

enum WidgetUpdater {
    static func refresh() {
        let ctx = PersistenceController.shared.viewContext
        var snap = WidgetSnapshot.empty
        snap.languageCode = AppSettings.shared.language.rawValue

        let sr = NSFetchRequest<CDScan>(entityName: "CDScan")
        sr.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]; sr.fetchLimit = 1
        if let s = (try? ctx.fetch(sr))?.first {
            snap.lastScanTitle = s.disease?.displayName ?? ""
            snap.lastScanHealthy = s.isHealthy; snap.lastScanConfidence = s.confidence; snap.lastScanDate = s.date
        }
        let tr_ = NSFetchRequest<CDTask>(entityName: "CDTask"); tr_.predicate = NSPredicate(format: "done == NO")
        snap.pendingTasks = (try? ctx.count(for: tr_)) ?? 0

        let fr = NSFetchRequest<CDFarm>(entityName: "CDFarm"); fr.fetchLimit = 1
        fr.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        snap.farmName = (try? ctx.fetch(fr))?.first?.displayName ?? "AgriNova"

        let or = NSFetchRequest<CDOutbreak>(entityName: "CDOutbreak")
        or.predicate = NSPredicate(format: "createdAt >= %@", Calendar.current.date(byAdding: .day, value: -14, to: Date())! as NSDate)
        let here = CLLocation(latitude: LocationService.shared.coordinate.latitude, longitude: LocationService.shared.coordinate.longitude)
        snap.nearbyOutbreaks = ((try? ctx.fetch(or)) ?? []).filter {
            here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= 25_000
        }.count

        if let w = WeatherService.cached() {
            snap.fungalRisk = w.fungalRisk.rawValue; snap.temperature = w.temperature
            snap.humidity = w.humidity; snap.rainChance = w.rainChance
        }
        SharedStore.save(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
