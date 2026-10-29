import Foundation
import CoreData
import CoreLocation
import UIKit

/// Developer "Seed Data" tools used for the demo & viva.
///
/// IMPORTANT (marking rule): seed data must flow  **seed data → Apple SDK → app logic**.
///  • Sample leaf photos are classified by the real Vision + Core ML pipeline (not hard-coded results).
///  • Geofence entry is triggered by Xcode's GPX simulation feeding Core Location (see Resources/GPX).
///  • Notifications go through UNUserNotificationCenter.
@MainActor
enum SeedService {
    /// Creates a demo farm with zones, crops, workers and an infected-plant record (Core Data).
    @discardableResult
    static func seedDemoFarm(in ctx: NSManagedObjectContext = PersistenceController.shared.viewContext) -> CDFarm {
        let farm = CDFarm(context: ctx)
        farm.id = UUID(); farm.name = "Green Valley Farm"; farm.locationName = "Peradeniya, Kandy"
        farm.ownerName = AppSettings.shared.userName.isEmpty ? "Farmer" : AppSettings.shared.userName
        farm.areaHectares = 2.4; farm.latitude = 7.2606; farm.longitude = 80.5970; farm.createdAt = Date()

        func zone(_ n: String, _ lat: Double, _ lon: Double, _ r: Double, _ crop: String, _ variety: String, _ reminder: String) -> CDZone {
            let z = CDZone(context: ctx)
            z.id = UUID(); z.name = n; z.latitude = lat; z.longitude = lon; z.radius = r
            z.geofenceEnabled = true; z.reminderText = reminder; z.areaSize = 0.6; z.farm = farm
            let c = CDCrop(context: ctx)
            c.id = UUID(); c.name = crop; c.variety = variety; c.plantCount = 420
            c.plantedDate = Calendar.current.date(byAdding: .day, value: -38, to: Date()); c.zone = z
            return z
        }
        let a = zone("Tomato Block A", 7.2610, 80.5975, 150, "Tomato", "Thilina", "Check lower leaves for dark spots and wash your hands before touching plants.")
        _ = zone("Polytunnel B", 7.2625, 80.5992, 120, "Tomato", "Rathna", "Open tunnel sides – humidity is a leaf-mold risk.")
        _ = zone("Nursery", 7.2598, 80.5955, 100, "Tomato seedlings", "Thilina", "Inspect seedlings for whiteflies before transplanting.")

        for (n, r) in [("Nimal Perera", "Supervisor"), ("Kumari Silva", "Spray operator"), ("Ravi Kumar", "Harvest worker")] {
            let w = CDWorker(context: ctx)
            w.id = UUID(); w.name = n; w.role = r; w.phone = "07\(Int.random(in: 10000000...79999999))"; w.farm = farm
        }
        let inf = CDInfected(context: ctx)
        inf.id = UUID(); inf.date = Date(); inf.latitude = 7.2612; inf.longitude = 80.5977
        inf.diseaseLabel = "Tomato___Early_blight"; inf.note = "Row 4, plants 12–15"; inf.zoneID = a.id

        let log = CDLog(context: ctx)
        log.id = UUID(); log.date = Date(); log.kind = "note"; log.title = "Farm created"; log.detail = "Seeded demo farm with 3 zones"; log.farmID = farm.id
        PersistenceController.shared.save()
        LocationService.shared.syncGeofences(from: ctx)
        WidgetUpdater.refresh()
        return farm
    }

    /// Feeds a bundled PlantVillage sample leaf through Vision + Core ML and stores the real result.
    static func classifySample(_ disease: Disease, index: Int = 1) async throws -> CDScan {
        guard let img = disease.sampleImage(index) ?? disease.sampleImage(0) else { throw ClassifierError.badImage }
        let outcome = try await ScanPipeline.run(img, threshold: AppSettings.shared.confidenceThreshold)
        return ScanStore.save(outcome, source: "seed")
    }

    /// Pushes seeded community reports through the real sync queue (outbox → backend → pull).
    static func seedOutbreaks() {
        let base = LocationService.shared.coordinate
        let rows: [(String, Double, Double, Int, String)] = [
            ("Tomato___Late_blight", 0.010, 0.012, 3, "Spreading fast after misty mornings"),
            ("Tomato___Early_blight", -0.006, 0.020, 2, "Lower leaves affected in two beds"),
            ("Tomato___Tomato_Yellow_Leaf_Curl_Virus", 0.018, -0.011, 3, "Whiteflies heavy in nursery"),
            ("Tomato___Septoria_leaf_spot", -0.015, -0.008, 1, "Early signs after rain"),
            ("Tomato___Bacterial_spot", 0.004, -0.025, 2, "Spots on fruit and leaves")
        ]
        for (label, dLat, dLon, sev, note) in rows {
            guard let d = DiseaseCatalog.byLabel[label] else { continue }
            SyncService.shared.submitReport(disease: d, severity: sev, notes: note, shareWithExtension: sev >= 2,
                                            coordinate: .init(latitude: base.latitude + dLat, longitude: base.longitude + dLon))
        }
    }
}
