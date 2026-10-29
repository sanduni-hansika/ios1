import Foundation

/// Pure aggregation logic for the statistics dashboard – kept free of UI so it can be unit-tested.
struct InsightsSummary {
    struct WeekPoint: Identifiable { let id = UUID(); let weekStart: Date; let count: Int }
    struct DiseaseSlice: Identifiable { let id: String; let name: String; let count: Int }
    struct ConfidencePoint: Identifiable { let id = UUID(); let date: Date; let confidence: Double }

    let total: Int
    let healthy: Int
    let unhealthy: Int
    let healthyRatio: Double
    let averageConfidence: Double
    let lowConfidenceCount: Int
    let weekly: [WeekPoint]
    let diseases: [DiseaseSlice]
    let confidenceSeries: [ConfidencePoint]
}

enum InsightsViewModel {
    struct Item { let date: Date; let label: String?; let healthy: Bool; let confidence: Double; let lowConfidence: Bool }

    static func summarize(_ items: [Item], weeks: Int = 8, now: Date = Date(), calendar: Calendar = .current) -> InsightsSummary {
        let total = items.count
        let healthy = items.filter(\.healthy).count
        let avg = total == 0 ? 0 : items.map(\.confidence).reduce(0, +) / Double(total)

        // Scans per week for the last N weeks (oldest → newest).
        let startOfThisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let weekly: [InsightsSummary.WeekPoint] = (0..<weeks).reversed().map { back in
            let start = calendar.date(byAdding: .weekOfYear, value: -back, to: startOfThisWeek) ?? startOfThisWeek
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
            return .init(weekStart: start, count: items.filter { $0.date >= start && $0.date < end }.count)
        }

        var counts: [String: Int] = [:]
        for i in items where !i.healthy { if let l = i.label { counts[l, default: 0] += 1 } }
        let slices = counts.map { InsightsSummary.DiseaseSlice(id: $0.key, name: DiseaseCatalog.find($0.key)?.displayName ?? $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        let series = items.sorted { $0.date < $1.date }.map { InsightsSummary.ConfidencePoint(date: $0.date, confidence: $0.confidence) }
        return .init(total: total, healthy: healthy, unhealthy: total - healthy,
                     healthyRatio: total == 0 ? 0 : Double(healthy) / Double(total),
                     averageConfidence: avg, lowConfidenceCount: items.filter(\.lowConfidence).count,
                     weekly: weekly, diseases: slices, confidenceSeries: series)
    }
}
