import Foundation

// MARK: - Backend configuration

/// Fill these in with your Firebase project (see docs/BACKEND_SETUP.md). With them blank the app uses the
/// on-device demo backend so every screen still works.
enum BackendConfig {
    static let firebaseProjectID = ""      // e.g. "agrinova-12345"
    static let firebaseWebAPIKey = ""      // Firebase console → Project settings → Web API key
    /// Firebase Authentication (real accounts + access tokens) needs only the Web API key.
    static var isAuthConfigured: Bool { !firebaseWebAPIKey.isEmpty }
    /// Firestore (shared outbreak reports) needs the project id too.
    static var isConfigured: Bool { !firebaseProjectID.isEmpty && isAuthConfigured }
    /// Usernames are mapped to "<username>@<this domain>" because Firebase Auth identifies accounts by e-mail.
    static let authEmailDomain = "users.agrinova.app"
}

/// Wire format of one shared outbreak report.
struct OutbreakDTO: Codable, Identifiable, Hashable {
    var id: String
    var diseaseLabel: String
    var species: String
    var latitude: Double
    var longitude: Double
    var severity: Int               // 1 low, 2 medium, 3 high
    var reporter: String
    var notes: String
    var createdAt: Date
    var district: String
    var sharedWithExtension: Bool
    var uid: String = ""            // Firebase Auth user id of the reporter (used by Firestore security rules)
}

extension OutbreakDTO {
    /// Tolerant decoder: reports queued by older app versions have no `uid`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); diseaseLabel = try c.decode(String.self, forKey: .diseaseLabel)
        species = try c.decode(String.self, forKey: .species); latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude); severity = try c.decode(Int.self, forKey: .severity)
        reporter = try c.decode(String.self, forKey: .reporter); notes = try c.decode(String.self, forKey: .notes)
        createdAt = try c.decode(Date.self, forKey: .createdAt); district = try c.decode(String.self, forKey: .district)
        sharedWithExtension = try c.decode(Bool.self, forKey: .sharedWithExtension)
        uid = try c.decodeIfPresent(String.self, forKey: .uid) ?? ""
    }
}

enum OutbreakBackendError: LocalizedError {
    case unauthorized, http(Int)
    var errorDescription: String? {
        switch self { case .unauthorized: tr("sync.err.unauthorized"); case .http(let c): "HTTP \(c)" }
    }
}

protocol OutbreakBackend {
    var name: String { get }
    func fetch(since: Date) async throws -> [OutbreakDTO]
    func submit(_ report: OutbreakDTO) async throws
}

// MARK: - Firebase Firestore (REST, no SDK required)

struct FirestoreBackend: OutbreakBackend {
    let projectID: String
    /// Supplies a valid Firebase **ID token** (refreshed automatically). Every request is sent with `Authorization: Bearer <token>`
    /// so Firestore security rules can check `request.auth`.
    var tokenProvider: () async throws -> String
    var name: String { "Firebase Firestore" }

    private var base: String { "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents/outbreaks" }

    private func authorized(_ url: URL, method: String = "GET", body: Data? = nil) async throws -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method; req.timeoutInterval = 20
        let token = try await tokenProvider()
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return req
    }

    private func check(_ resp: URLResponse, allow409: Bool = false) throws {
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw OutbreakBackendError.unauthorized }
        // 409 = document already exists (a retried upload) – treated as success.
        guard (200..<300).contains(code) || (allow409 && code == 409) else { throw OutbreakBackendError.http(code) }
    }

    func fetch(since: Date) async throws -> [OutbreakDTO] {
        var out: [OutbreakDTO] = []
        var pageToken: String?
        repeat {
            var c = URLComponents(string: base)!
            c.queryItems = [.init(name: "pageSize", value: "300")]
            if let pageToken { c.queryItems?.append(.init(name: "pageToken", value: pageToken)) }
            let (data, resp) = try await URLSession.shared.data(for: try await authorized(c.url!))
            try check(resp)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            for doc in (json["documents"] as? [[String: Any]] ?? []) {
                if let dto = Self.parse(doc), dto.createdAt >= since { out.append(dto) }
            }
            pageToken = json["nextPageToken"] as? String
        } while pageToken != nil
        return out
    }

    func submit(_ r: OutbreakDTO) async throws {
        var c = URLComponents(string: base)!
        c.queryItems = [.init(name: "documentId", value: r.id)]
        let iso = ISO8601DateFormatter().string(from: r.createdAt)
        let body: [String: Any] = ["fields": [
            "diseaseLabel": ["stringValue": r.diseaseLabel], "species": ["stringValue": r.species],
            "latitude": ["doubleValue": r.latitude], "longitude": ["doubleValue": r.longitude],
            "severity": ["integerValue": String(r.severity)], "reporter": ["stringValue": r.reporter],
            "notes": ["stringValue": r.notes], "district": ["stringValue": r.district], "uid": ["stringValue": r.uid],
            "createdAt": ["timestampValue": iso], "sharedWithExtension": ["booleanValue": r.sharedWithExtension]
        ]]
        let req = try await authorized(c.url!, method: "POST", body: try JSONSerialization.data(withJSONObject: body))
        let (_, resp) = try await URLSession.shared.data(for: req)
        try check(resp, allow409: true)
    }

    private static func parse(_ doc: [String: Any]) -> OutbreakDTO? {
        guard let name = doc["name"] as? String, let f = doc["fields"] as? [String: Any] else { return nil }
        func str(_ k: String) -> String { (f[k] as? [String: Any])?["stringValue"] as? String ?? "" }
        func dbl(_ k: String) -> Double {
            let v = f[k] as? [String: Any]
            if let d = v?["doubleValue"] as? Double { return d }
            if let s = v?["integerValue"] as? String { return Double(s) ?? 0 }
            return 0
        }
        let ts = (f["createdAt"] as? [String: Any])?["timestampValue"] as? String ?? ""
        let fmt = ISO8601DateFormatter(); fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fmt.date(from: ts) ?? ISO8601DateFormatter().date(from: ts) ?? Date()
        return OutbreakDTO(id: String(name.split(separator: "/").last ?? ""), diseaseLabel: str("diseaseLabel"),
                           species: str("species"), latitude: dbl("latitude"), longitude: dbl("longitude"),
                           severity: Int(dbl("severity")), reporter: str("reporter"), notes: str("notes"), createdAt: date,
                           district: str("district"),
                           sharedWithExtension: (f["sharedWithExtension"] as? [String: Any])?["booleanValue"] as? Bool ?? false,
                           uid: str("uid"))
    }
}

// MARK: - Demo backend (file on device – used until Firebase is configured)

struct LocalDemoBackend: OutbreakBackend {
    var name: String { "On-device demo backend" }
    private var url: URL { URL.documentsDirectory.appendingPathComponent("demo_backend.json") }

    private func load() -> [OutbreakDTO] {
        guard let d = try? Data(contentsOf: url) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([OutbreakDTO].self, from: d)) ?? []
    }
    func fetch(since: Date) async throws -> [OutbreakDTO] { load().filter { $0.createdAt >= since } }
    func submit(_ report: OutbreakDTO) async throws {
        var all = load().filter { $0.id != report.id }
        all.append(report)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try enc.encode(all).write(to: url, options: .atomic)
    }
}
