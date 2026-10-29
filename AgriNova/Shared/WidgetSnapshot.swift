import Foundation

/// Lightweight snapshot of live app data, shared with the WidgetKit extension through an App Group.
/// The app writes it whenever scans / treatments / weather / outbreaks change.
struct WidgetSnapshot: Codable, Equatable {
    var farmName: String
    var lastScanTitle: String
    var lastScanHealthy: Bool?
    var lastScanConfidence: Double
    var lastScanDate: Date?
    var pendingTasks: Int
    var nearbyOutbreaks: Int
    var fungalRisk: String          // "low" | "moderate" | "high"
    var temperature: Double?
    var humidity: Double?
    var rainChance: Double?
    var languageCode: String        // "en" | "si" | "ta"

    static let empty = WidgetSnapshot(farmName: "AgriNova", lastScanTitle: "", lastScanHealthy: nil,
                                      lastScanConfidence: 0, lastScanDate: nil, pendingTasks: 0,
                                      nearbyOutbreaks: 0, fungalRisk: "low", temperature: nil,
                                      humidity: nil, rainChance: nil, languageCode: "en")
}

enum SharedStore {
    static let groupID = "group.com.agrinova.app"
    private static let key = "widget.snapshot"

    static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }

    static func save(_ snapshot: WidgetSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: key) }
    }

    static func load() -> WidgetSnapshot {
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return .empty }
        return s
    }
}
