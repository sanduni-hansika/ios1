import Foundation
import CoreLocation
import MapKit
import SwiftUI
import Observation

/// Cluster of nearby outbreak reports (a single report is a cluster of one).
struct ReportCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let reports: [CDOutbreak]
    var maxSeverity: Int { Int(reports.map(\.severity).max() ?? 1) }
}

enum MapStyleChoice: String, CaseIterable, Identifiable {
    case standard, hybrid, imagery
    var id: String { rawValue }
    var titleKey: String { "radar.style.\(rawValue)" }
    var style: MapStyle {
        switch self {
        case .standard: .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
        case .hybrid: .hybrid(elevation: .realistic)
        case .imagery: .imagery(elevation: .realistic)
        }
    }
}

@MainActor @Observable
final class RadarViewModel {
    enum Range: Int, CaseIterable { case week = 7, month = 30, all = 3650
        var titleKey: String { switch self { case .week: "radar.7d"; case .month: "radar.30d"; case .all: "radar.all" } } }

    var range: Range = .month
    var diseaseFilter: String? = nil           // model label
    var selected: CDOutbreak?

    // Map layers & tools
    var mapStyle: MapStyleChoice = .standard
    var showZones = true
    var showServices = false
    var ringKm = 0                              // 0 = off, else 5 / 10 / 25
    var timelineOn = false
    var timelineProgress = 1.0                  // 0…1 across the filtered reports' date span
    var span: MKCoordinateSpan?                 // current visible span (drives clustering)

    // Results of MapKit services
    var services: [MKMapItem] = []
    var isSearching = false
    var route: MKRoute?
    var routeTarget: CDOutbreak?

    func filtered(_ all: [CDOutbreak]) -> [CDOutbreak] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -range.rawValue, to: Date()) ?? .distantPast
        return all.filter { ($0.createdAt ?? .distantPast) >= cutoff && (diseaseFilter == nil || $0.diseaseLabel == diseaseFilter) }
    }

    // MARK: Spread timeline (replay how reports appeared over time)
    func dateRange(_ reports: [CDOutbreak]) -> ClosedRange<Date>? {
        let dates = reports.compactMap(\.createdAt)
        guard let lo = dates.min(), let hi = dates.max(), lo < hi else { return nil }
        return lo...hi
    }
    func timelineDate(_ reports: [CDOutbreak]) -> Date? {
        guard let r = dateRange(reports) else { return nil }
        return r.lowerBound.addingTimeInterval(r.upperBound.timeIntervalSince(r.lowerBound) * timelineProgress)
    }
    func visible(_ reports: [CDOutbreak]) -> [CDOutbreak] {
        guard timelineOn, let d = timelineDate(reports) else { return reports }
        return reports.filter { ($0.createdAt ?? .distantPast) <= d }
    }

    // MARK: Distance, ring & risk
    static func distanceKm(_ o: CDOutbreak, from c: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: CLLocation(latitude: o.latitude, longitude: o.longitude)) / 1000
    }

    /// Reports within `km` of a point.
    static func nearby(_ reports: [CDOutbreak], to c: CLLocationCoordinate2D, km: Double) -> [CDOutbreak] {
        reports.filter { distanceKm($0, from: c) <= km }
    }

    static func hotspotRadius(severity: Int16) -> Double { Double(max(1, Int(severity))) * 450 }

    /// Severity-weighted local risk: each report adds its severity (1–3).
    static func riskLevel(score: Int) -> FungalRisk { score >= 7 ? .high : (score >= 3 ? .moderate : .low) }
    static func riskScore(_ reports: [CDOutbreak]) -> Int { reports.reduce(0) { $0 + max(1, Int($1.severity)) } }

    // MARK: Clustering (grid based, depends on zoom)
    /// Cell size in degrees for the current zoom; 0 means "don't cluster" (zoomed in close).
    static func clusterCell(for span: MKCoordinateSpan?) -> Double {
        guard let span, span.latitudeDelta > 0.03 else { return 0 }
        return span.latitudeDelta / 7
    }

    static func clusters(_ reports: [CDOutbreak], cell: Double) -> [ReportCluster] {
        guard cell > 0 else {
            return reports.map { ReportCluster(id: $0.id ?? UUID().uuidString, coordinate: $0.coordinate, reports: [$0]) }
        }
        var buckets: [String: [CDOutbreak]] = [:]
        for r in reports {
            let key = "\(Int(floor(r.latitude / cell)))_\(Int(floor(r.longitude / cell)))"
            buckets[key, default: []].append(r)
        }
        return buckets.map { key, list in
            let lat = list.map(\.latitude).reduce(0, +) / Double(list.count)
            let lon = list.map(\.longitude).reduce(0, +) / Double(list.count)
            return ReportCluster(id: list.count == 1 ? (list[0].id ?? key) : "c\(key)", coordinate: .init(latitude: lat, longitude: lon), reports: list)
        }
    }

    // MARK: MapKit services – local search & directions
    /// Finds agri-related places (extension offices, agro shops) near the user with MKLocalSearch.
    func searchServices(near c: CLLocationCoordinate2D) async {
        isSearching = true; defer { isSearching = false }
        var found: [MKMapItem] = []
        for q in ["agriculture office", "agro supplies", "fertilizer shop"] {
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = q
            req.region = MKCoordinateRegion(center: c, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
            if let res = try? await MKLocalSearch(request: req).start() {
                for item in res.mapItems where !found.contains(where: { $0.name == item.name && abs($0.placemark.coordinate.latitude - item.placemark.coordinate.latitude) < 0.0005 }) {
                    found.append(item)
                }
            }
        }
        services = found
        if found.isEmpty { ToastCenter.shared.show(tr("radar.services_none"), kind: .info) }
    }

    /// Driving route from the user to a report, drawn on the map with an ETA.
    func buildRoute(to report: CDOutbreak, from c: CLLocationCoordinate2D) async -> MKMapRect? {
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: c))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: report.coordinate))
        req.transportType = .automobile
        do {
            let res = try await MKDirections(request: req).calculate()
            route = res.routes.first; routeTarget = report
            guard let r = route?.polyline.boundingMapRect else { return nil }
            let pad = max(r.size.width, r.size.height) * 0.3
            return r.insetBy(dx: -pad, dy: -pad)
        } catch {
            route = nil; routeTarget = nil
            ToastCenter.shared.show(tr("radar.route_fail"), kind: .error)
            return nil
        }
    }
    func clearRoute() { route = nil; routeTarget = nil }
}
