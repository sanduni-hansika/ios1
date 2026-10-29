import Testing
import CoreData
import Foundation
import UIKit
import MapKit
import CoreLocation
@testable import AgriNova

// Unit tests use the Swift Testing framework (not XCTest), as required by the brief.
// They cover core logic and edge cases: weather risk, confidence gating, image quality, trend maths,
// statistics aggregation, localisation completeness, auth validation, Core Data CRUD and the sync queue.

// MARK: - Weather / early warning

@Suite("Fungal risk model")
struct FungalRiskTests {
    @Test("Humid, warm and rainy weather is high risk")
    func highRisk() { #expect(WeatherService.fungalRisk(avgHumidity: 90, avgTemp: 25, rainChance: 80) == .high) }

    @Test("Dry weather is low risk")
    func lowRisk() { #expect(WeatherService.fungalRisk(avgHumidity: 50, avgTemp: 33, rainChance: 5) == .low) }

    @Test("Moderate humidity alone gives moderate risk")
    func moderateRisk() { #expect(WeatherService.fungalRisk(avgHumidity: 80, avgTemp: 25, rainChance: 10) == .moderate) }

    @Test("Boundary: humidity exactly 85 and rain exactly 60 with warm temperature is high")
    func boundary() { #expect(WeatherService.fungalRisk(avgHumidity: 85, avgTemp: 18, rainChance: 60) == .high) }

    @Test("Risk levels are ordered", arguments: [(FungalRisk.low, 0.25), (.moderate, 0.6), (.high, 0.95)])
    func levels(_ r: FungalRisk, _ level: Double) { #expect(r.level == level) }
}

// MARK: - Disease catalogue

@Suite("Disease catalogue")
struct CatalogTests {
    @Test("Ten classes: nine diseases plus healthy") func count() {
        #expect(DiseaseCatalog.all.count == 10)
        #expect(DiseaseCatalog.diseasesOnly.count == 9)
    }
    @Test("Every disease has trilingual name and summary, symptoms and a treatment")
    func completeness() {
        for d in DiseaseCatalog.all {
            #expect(d.name.count == 3 && d.name.allSatisfy { !$0.isEmpty }, "name \(d.id)")
            #expect(d.summary.count == 3 && d.summary.allSatisfy { !$0.isEmpty }, "summary \(d.id)")
            #expect(!d.symptoms.isEmpty)
            if !d.isHealthy { #expect(!(d.organic + d.chemical + d.cultural).isEmpty, "treatment \(d.id)") }
        }
    }
    @Test("Lookup by exact label and tolerant label")
    func lookup() {
        #expect(DiseaseCatalog.find("Tomato___Late_blight")?.key == "late_blight")
        #expect(DiseaseCatalog.find("tomato late blight")?.key == "late_blight")
        #expect(DiseaseCatalog.find("nonsense") == nil)
        #expect(DiseaseCatalog.find("Tomato___Two-spotted spider mite")?.key == "spider_mites")
        // A 38-class PlantVillage model also knows other crops – these must NOT be mistaken for tomato diseases.
        #expect(DiseaseCatalog.find("Potato___Early_blight") == nil)
        #expect(DiseaseCatalog.find("Apple___healthy") == nil)
        #expect(DiseaseCatalog.find("Pepper,_bell___Bacterial_spot") == nil)
    }
    @Test("Only fungal and bacterial diseases are moisture-driven")
    func moisture() {
        #expect(DiseaseCatalog.find("Tomato___Late_blight")?.isMoistureDriven == true)
        #expect(DiseaseCatalog.find("Tomato___Tomato_mosaic_virus")?.isMoistureDriven == false)
    }
}

// MARK: - Localisation

@Suite("Localisation")
struct LocalisationTests {
    @Test("Every string has English, Sinhala and Tamil text")
    func allTranslated() {
        for (key, row) in Strings.table {
            #expect(row.count == 3, "\(key) needs 3 languages")
            #expect(row.allSatisfy { !$0.isEmpty }, "\(key) has an empty translation")
        }
    }
    @Test("Format placeholders match across languages")
    func placeholders() {
        func count(_ s: String) -> Int {
            (try? NSRegularExpression(pattern: #"%(\d\$)?(ld|@)"#).numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s))) ?? 0
        }
        for (key, row) in Strings.table where row[0].contains("%") {
            #expect(count(row[1]) == count(row[0]) && count(row[2]) == count(row[0]), "\(key) placeholder mismatch")
        }
    }
    @Test("Unknown keys fall back to the key itself") func fallback() { #expect(tr("does.not.exist") == "does.not.exist") }
}

// MARK: - Image quality (blur / lighting gate)

@Suite("Image quality checker")
struct ImageQualityTests {
    private func buffer(_ w: Int, _ h: Int, _ f: (Int, Int) -> UInt8) -> [UInt8] {
        (0..<(w * h)).map { f($0 % w, $0 / w) }
    }
    @Test("Flat grey image is flagged as blurry / low contrast")
    func flat() {
        let r = ImageQualityChecker.assess(gray: buffer(100, 100) { _, _ in 128 }, width: 100, height: 100)
        #expect(r.issues.contains(.blurry)); #expect(!r.isAcceptable)
    }
    @Test("Checkerboard is sharp and acceptable")
    func sharp() {
        let r = ImageQualityChecker.assess(gray: buffer(100, 100) { x, y in ((x / 2 + y / 2) % 2 == 0) ? 40 : 200 }, width: 100, height: 100)
        #expect(!r.issues.contains(.blurry)); #expect(r.isAcceptable)
    }
    @Test("Very dark image is flagged too dark")
    func dark() {
        let r = ImageQualityChecker.assess(gray: buffer(100, 100) { x, y in UInt8((x + y) % 2 == 0 ? 10 : 30) }, width: 100, height: 100)
        #expect(r.issues.contains(.tooDark))
    }
    @Test("Very bright image is flagged overexposed")
    func bright() {
        let r = ImageQualityChecker.assess(gray: buffer(100, 100) { x, y in UInt8((x + y) % 2 == 0 ? 245 : 255) }, width: 100, height: 100)
        #expect(r.issues.contains(.overexposed))
    }
    @Test("Tiny buffers do not crash") func tiny() { _ = ImageQualityChecker.assess(gray: [1, 2], width: 2, height: 1) }
}

// MARK: - Affected-area maths

@Suite("Colour analysis")
struct ColourTests {
    @Test("Pure green is hue ~120 with full saturation")
    func green() { let c = LeafAnalyzer.hsv(0, 1, 0); #expect(abs(c.h - 120) < 0.5); #expect(c.s == 1) }
    @Test("Brown has a hue below 70") func brown() { #expect(LeafAnalyzer.hsv(0.55, 0.3, 0.1).h < 70) }
    @Test("Black has zero saturation") func black() { #expect(LeafAnalyzer.hsv(0, 0, 0).s == 0) }
    @Test("Pure green image reports ~0 % affected") func greenImage() {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120)).image { c in UIColor(red: 0.1, green: 0.6, blue: 0.2, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: 120, height: 120)) }
        #expect(LeafAnalyzer.affectedPercent(img) < 5)
    }
    @Test("Brown image reports a high affected share") func brownImage() {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120)).image { c in UIColor(red: 0.5, green: 0.3, blue: 0.1, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: 120, height: 120)) }
        #expect(LeafAnalyzer.affectedPercent(img) > 80)
    }
}

// MARK: - Statistics

@Suite("Insights aggregation")
struct InsightsTests {
    typealias Item = InsightsViewModel.Item
    let now = Date()
    @Test("Empty input yields zeros") func empty() {
        let s = InsightsViewModel.summarize([])
        #expect(s.total == 0); #expect(s.healthyRatio == 0); #expect(s.averageConfidence == 0); #expect(s.weekly.count == 8)
    }
    @Test("Ratios and averages") func ratios() {
        let items = [Item(date: now, label: "Tomato___healthy", healthy: true, confidence: 0.9, lowConfidence: false),
                     Item(date: now, label: "Tomato___Late_blight", healthy: false, confidence: 0.8, lowConfidence: false),
                     Item(date: now, label: "Tomato___Late_blight", healthy: false, confidence: 0.5, lowConfidence: true)]
        let s = InsightsViewModel.summarize(items, now: now)
        #expect(s.total == 3); #expect(s.healthy == 1); #expect(s.unhealthy == 2)
        #expect(abs(s.healthyRatio - 1.0 / 3) < 0.001); #expect(abs(s.averageConfidence - 0.7333) < 0.001)
        #expect(s.lowConfidenceCount == 1); #expect(s.diseases.first?.count == 2)
        #expect(s.weekly.last?.count == 3)
    }
    @Test("Old scans fall outside the weekly window") func window() {
        let old = Calendar.current.date(byAdding: .weekOfYear, value: -20, to: now)!
        let s = InsightsViewModel.summarize([Item(date: old, label: nil, healthy: true, confidence: 1, lowConfidence: false)], now: now)
        #expect(s.weekly.map(\.count).reduce(0, +) == 0)
    }
}

// MARK: - Auth

@Suite("Authentication")
struct AuthTests {
    @Test("Username validation", arguments: [("farmer_01", true), ("a.b", true), ("ab", false), ("has space", false), ("waytoolongusername_over20chars", false), ("", false)])
    func username(_ u: String, _ ok: Bool) { #expect(AuthService.isValid(username: u) == ok) }
    @Test("Optional email validation", arguments: [("farmer@example.com", true), ("a.b+c@d.lk", true), ("no-at.com", false), ("a@b", false), ("", false)])
    func email(_ e: String, _ ok: Bool) { #expect(AuthService.isValid(email: e) == ok) }
    @Test("Password strength", arguments: [("123456", true), ("12345", false), ("", false)])
    func password(_ p: String, _ ok: Bool) { #expect(AuthService.isStrong(password: p) == ok) }
    @Test("Local mode: sign-up, sign-in, wrong password, duplicate and change-password round trip")
    func roundTrip() async throws {
        #expect(!AuthService.usesFirebase, "tests run in device-only mode (no Firebase key configured)")
        let user = "test_\(UUID().uuidString.prefix(6))".lowercased()
        try await AuthService.signUp(name: "Tester", username: user, password: "secret1")
        #expect(AppSettings.shared.username == user); #expect(AppSettings.shared.authMethod == "password")
        try await AuthService.signIn(username: user, password: "secret1")
        await #expect(throws: AuthError.self) { try await AuthService.signIn(username: user, password: "wrong!!") }
        await #expect(throws: AuthError.self) { try await AuthService.signUp(name: "x", username: user, password: "secret1") }
        try await AuthService.changePassword(username: user, old: "secret1", new: "newpass9")
        await #expect(throws: AuthError.self) { try await AuthService.signIn(username: user, password: "secret1") }
        try await AuthService.signIn(username: user, password: "newpass9")
        await #expect(throws: AuthError.self) { try await AuthService.changePassword(username: user, old: "bad", new: "another1") }
        try await AuthService.deleteAccount(username: user)
        await #expect(throws: AuthError.self) { try await AuthService.signIn(username: user, password: "newpass9") }
    }
    @Test("Nonce is random and its SHA-256 matches a known vector")
    func nonce() {
        #expect(AuthService.makeNonce().count == 32); #expect(AuthService.makeNonce() != AuthService.makeNonce())
        #expect(AuthService.sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

// MARK: - Firebase Authentication & access tokens (pure logic – no network)

@Suite("Firebase Auth tokens", .serialized)
struct FirebaseAuthTests {
    @Test("Username maps to a synthetic e-mail on the app domain")
    func email() { #expect(FirebaseAuthClient.email(forUsername: "Farmer_01") == "farmer_01@\(BackendConfig.authEmailDomain)") }

    @Test("Sign-in response is parsed into a session with an expiry")
    func parseSession() throws {
        let json = #"{"idToken":"ID","refreshToken":"RT","localId":"UID1","email":"a@b.c","displayName":"Jane","expiresIn":"3600"}"#
        let now = Date(timeIntervalSince1970: 1_000)
        let s = try FirebaseAuthClient.parseSession(Data(json.utf8), now: now)
        #expect(s.idToken == "ID" && s.refreshToken == "RT" && s.uid == "UID1" && s.displayName == "Jane")
        #expect(s.expiresAt == now.addingTimeInterval(3600))
    }
    @Test("A response without tokens is rejected")
    func parseBad() { #expect(throws: FirebaseAuthError.self) { try FirebaseAuthClient.parseSession(Data("{}".utf8)) } }

    @Test("Token needs a refresh shortly before it expires")
    func refreshWindow() {
        let now = Date()
        let s = FirebaseSession(idToken: "i", refreshToken: "r", uid: "u", email: "e", displayName: "", expiresAt: now.addingTimeInterval(3600))
        #expect(!s.needsRefresh(now: now))
        #expect(s.needsRefresh(now: now.addingTimeInterval(3560)))      // inside the 60 s margin
        #expect(s.needsRefresh(now: now.addingTimeInterval(4000)))      // already expired
    }
    @Test("Refresh response keeps the old identity and swaps the tokens")
    func parseRefresh() throws {
        let old = FirebaseSession(idToken: "old", refreshToken: "oldR", uid: "u", email: "e@x.y", displayName: "Jane", expiresAt: .distantPast)
        let json = #"{"id_token":"new","refresh_token":"newR","user_id":"u","expires_in":"1800"}"#
        let s = try FirebaseAuthClient.parseRefresh(Data(json.utf8), previous: old, now: Date(timeIntervalSince1970: 0))
        #expect(s.idToken == "new" && s.refreshToken == "newR" && s.displayName == "Jane" && s.email == "e@x.y")
        #expect(s.expiresAt == Date(timeIntervalSince1970: 1800))
    }
    @Test("Firebase error codes map to typed errors", arguments: [
        ("EMAIL_EXISTS", FirebaseAuthError.emailExists), ("INVALID_LOGIN_CREDENTIALS", .invalidCredentials),
        ("INVALID_PASSWORD", .invalidCredentials), ("WEAK_PASSWORD : Password should be at least 6 characters", .weakPassword),
        ("TOO_MANY_ATTEMPTS_TRY_LATER", .tooManyAttempts), ("USER_DISABLED", .userDisabled),
        ("CREDENTIAL_TOO_OLD_LOGIN_AGAIN", .requiresRecentLogin), ("TOKEN_EXPIRED", .invalidToken)])
    func errors(_ code: String, _ expected: FirebaseAuthError) {
        #expect(FirebaseAuthClient.parseError(Data(#"{"error":{"code":400,"message":"\#(code)"}}"#.utf8)) == expected)
    }
    @Test("Not signed in → no token") func noSession() async {
        AuthSession.shared.clear()
        await #expect(throws: FirebaseAuthError.self) { _ = try await AuthSession.shared.validIDToken() }
    }
    @Test("A fresh stored session is returned without any network call") func validToken() async throws {
        AuthSession.shared.set(FirebaseSession(idToken: "TOKEN", refreshToken: "r", uid: "u", email: "e", displayName: "", expiresAt: Date().addingTimeInterval(3000)))
        defer { AuthSession.shared.clear() }
        #expect(try await AuthSession.shared.validIDToken() == "TOKEN"); #expect(AuthSession.shared.uid == "u")
    }
    @Test("Reports queued by an older app version (no uid) still decode") func dtoCompat() throws {
        let old = #"{"id":"1","diseaseLabel":"x","species":"Tomato","latitude":1,"longitude":2,"severity":1,"reporter":"a","notes":"","createdAt":"2026-01-01T00:00:00Z","district":"","sharedWithExtension":false}"#
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        #expect(try dec.decode(OutbreakDTO.self, from: Data(old.utf8)).uid == "")
    }
}

// MARK: - Core Data (in-memory)

@Suite("Persistence & treatments", .serialized)
@MainActor
struct PersistenceTests {
    let pc = PersistenceController(inMemory: true, cloud: false)

    private func makeScan(_ label: String = "Tomato___Early_blight", affected: Double = 37) -> CDScan {
        let s = CDScan(context: pc.viewContext)
        s.id = UUID(); s.date = Date(); s.diseaseLabel = label; s.confidence = 0.9; s.affectedPercent = affected; s.isHealthy = false
        return s
    }

    @Test("Starting a treatment builds a checklist, a baseline and marks the scan")
    func startTreatment() throws {
        let scan = makeScan()
        TreatmentService.start(scan: scan, recheckDays: [3, 7], in: pc.viewContext)
        let tasks = TreatmentService.tasks(for: scan, in: pc.viewContext)
        let d = try #require(scan.disease)
        #expect(tasks.count == d.organic.count + d.chemical.count + d.cultural.count)
        #expect(scan.treatmentStarted); #expect(scan.recheckDays == "3,7")
        #expect(TreatmentService.progress(for: scan, in: pc.viewContext).first?.affectedPercent == 37)
    }
    @Test("Healthy scans never get a treatment plan")
    func healthyNoPlan() {
        let s = makeScan("Tomato___healthy", affected: 0)
        TreatmentService.start(scan: s, in: pc.viewContext)
        #expect(!s.treatmentStarted)
    }
    @Test("Starting twice does not duplicate tasks")
    func idempotent() {
        let s = makeScan()
        TreatmentService.start(scan: s, in: pc.viewContext); let n = TreatmentService.tasks(for: s, in: pc.viewContext).count
        TreatmentService.start(scan: s, in: pc.viewContext)
        #expect(TreatmentService.tasks(for: s, in: pc.viewContext).count == n)
    }
    @Test("Trend detection: Day 1 → 37 %, Day 7 → 25 %, Day 14 → 11 % is improving")
    func trend() {
        func p(_ v: Double) -> CDProgress { let x = CDProgress(context: pc.viewContext); x.affectedPercent = v; return x }
        #expect(TreatmentService.trend([p(37), p(25), p(11)]) == .improving)
        #expect(TreatmentService.trend([p(11), p(25)]) == .worsening)
        #expect(TreatmentService.trend([p(30), p(31)]) == .steady)
        #expect(TreatmentService.trend([p(30)]) == .unknown)
        #expect(TreatmentService.trend([]) == .unknown)
    }
    @Test("Ticking a task persists completion date")
    func tick() {
        let s = makeScan(); TreatmentService.start(scan: s, in: pc.viewContext)
        let t = TreatmentService.tasks(for: s, in: pc.viewContext)[0]
        TreatmentService.setDone(t, true); #expect(t.done && t.doneDate != nil)
        TreatmentService.setDone(t, false); #expect(!t.done && t.doneDate == nil)
    }
    @Test("Farm → zone → crop relationships cascade on delete")
    func cascade() throws {
        let ctx = pc.viewContext
        let f = CDFarm(context: ctx); f.id = UUID(); f.name = "F"
        let z = CDZone(context: ctx); z.id = UUID(); z.name = "Z"; z.farm = f
        let c = CDCrop(context: ctx); c.id = UUID(); c.name = "Tomato"; c.zone = z
        try ctx.save()
        #expect(f.zoneList.count == 1); #expect(z.cropList.count == 1)
        ctx.delete(f); try ctx.save()
        #expect(try ctx.count(for: NSFetchRequest<CDZone>(entityName: "CDZone")) == 0)
        #expect(try ctx.count(for: NSFetchRequest<CDCrop>(entityName: "CDCrop")) == 0)
    }
}

// MARK: - Outbreak wire format & geometry

@Suite("Outbreak reports")
struct OutbreakTests {
    @Test("DTO survives a JSON round trip (offline queue payload)")
    func codable() throws {
        let dto = OutbreakDTO(id: "1", diseaseLabel: "Tomato___Late_blight", species: "Tomato", latitude: 7.26, longitude: 80.59, severity: 3, reporter: "A", notes: "n", createdAt: Date(timeIntervalSince1970: 1_700_000_000), district: "Kandy", sharedWithExtension: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        #expect(try dec.decode(OutbreakDTO.self, from: enc.encode(dto)) == dto)
    }
    @Test("Hotspot radius grows with severity")
    func radius() { #expect(RadarViewModel.hotspotRadius(severity: 3) > RadarViewModel.hotspotRadius(severity: 1)); #expect(RadarViewModel.hotspotRadius(severity: 0) > 0) }
    @Test("Demo backend stores and returns reports")
    func demoBackend() async throws {
        let b = LocalDemoBackend()
        let id = UUID().uuidString
        try await b.submit(OutbreakDTO(id: id, diseaseLabel: "x", species: "Tomato", latitude: 1, longitude: 2, severity: 1, reporter: "t", notes: "", createdAt: Date(), district: "", sharedWithExtension: false))
        #expect(try await b.fetch(since: Date().addingTimeInterval(-60)).contains { $0.id == id })
    }
}

// MARK: - Map logic (clustering, risk ring)

@Suite("Radar map logic", .serialized)
@MainActor
struct RadarMapTests {
    let pc = PersistenceController(inMemory: true, cloud: false)
    private func report(_ lat: Double, _ lon: Double, _ sev: Int16) -> CDOutbreak {
        let o = CDOutbreak(context: pc.viewContext)
        o.id = UUID().uuidString; o.latitude = lat; o.longitude = lon; o.severity = sev; o.createdAt = Date()
        return o
    }
    @Test("Nearby reports merge into one cluster when zoomed out") func clusterMerge() {
        let r = [report(7.260, 80.597, 1), report(7.261, 80.598, 3), report(7.800, 81.200, 2)]
        let c = RadarViewModel.clusters(r, cell: 0.1)
        #expect(c.count == 2); #expect(c.map(\.reports.count).sorted() == [1, 2])
        #expect(c.first { $0.reports.count == 2 }?.maxSeverity == 3)
    }
    @Test("No clustering when zoomed in") func noCluster() {
        let r = [report(7.260, 80.597, 1), report(7.261, 80.598, 3)]
        #expect(RadarViewModel.clusters(r, cell: 0).count == 2)
        #expect(RadarViewModel.clusterCell(for: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)) == 0)
        #expect(RadarViewModel.clusterCell(for: MKCoordinateSpan(latitudeDelta: 0.7, longitudeDelta: 0.7)) > 0)
    }
    @Test("Distance ring counts only reports inside the radius") func ring() {
        let here = CLLocationCoordinate2D(latitude: 7.2606, longitude: 80.5970)
        let r = [report(7.2610, 80.5975, 2), report(7.40, 80.80, 3)]
        #expect(RadarViewModel.nearby(r, to: here, km: 5).count == 1)
        #expect(RadarViewModel.nearby(r, to: here, km: 100).count == 2)
    }
    @Test("Risk grows with severity-weighted report count") func risk() {
        #expect(RadarViewModel.riskLevel(score: 0) == .low); #expect(RadarViewModel.riskLevel(score: 3) == .moderate); #expect(RadarViewModel.riskLevel(score: 9) == .high)
        #expect(RadarViewModel.riskScore([report(1, 1, 3), report(1, 1, 2)]) == 5)
    }
}

// MARK: - Confidence gating

@Suite("Confidence gating")
struct GatingTests {
    @Test("54 % confidence needs a re-scan at the default 70 % threshold") func low() { #expect(0.54 < AppSettings.shared.confidenceThreshold) }
    @Test("Language index mapping") func lang() { #expect(AppLanguage.en.index == 0 && AppLanguage.si.index == 1 && AppLanguage.ta.index == 2) }
    @Test("WidgetSnapshot round-trips through JSON") func snapshot() throws {
        var s = WidgetSnapshot.empty; s.pendingTasks = 4; s.fungalRisk = "high"
        #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(s)) == s)
    }
}
