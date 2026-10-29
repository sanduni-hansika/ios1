import WidgetKit
import SwiftUI

// MARK: - Timeline

struct AgriEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct AgriProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgriEntry {
        var s = WidgetSnapshot.empty
        s.lastScanTitle = "Early Blight"; s.lastScanHealthy = false; s.lastScanConfidence = 0.92
        s.pendingTasks = 3; s.nearbyOutbreaks = 2; s.fungalRisk = "moderate"; s.temperature = 27; s.humidity = 82; s.rainChance = 40
        return AgriEntry(date: Date(), snapshot: s)
    }
    func getSnapshot(in context: Context, completion: @escaping (AgriEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : AgriEntry(date: Date(), snapshot: SharedStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AgriEntry>) -> Void) {
        let entry = AgriEntry(date: Date(), snapshot: SharedStore.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

// MARK: - Helpers

private enum W {
    static let leaf = Color(red: 0.118, green: 0.62, blue: 0.341)
    static let danger = Color(red: 0.9, green: 0.28, blue: 0.3)
    static let sun = Color(red: 1, green: 0.71, blue: 0.28)
    static func riskColor(_ r: String) -> Color { r == "high" ? danger : (r == "moderate" ? sun : leaf) }
    static func riskText(_ r: String, _ lang: String) -> String {
        let t: [String: [String]] = ["low": ["Low risk", "අඩු අවදානම", "குறைந்த ஆபத்து"], "moderate": ["Moderate risk", "මධ්‍යම අවදානම", "மிதமான ஆபத்து"], "high": ["High risk", "ඉහළ අවදානම", "அதிக ஆபத்து"]]
        let i = lang == "si" ? 1 : (lang == "ta" ? 2 : 0)
        return t[r]?[i] ?? r
    }
    static func label(_ key: String, _ lang: String) -> String {
        let t: [String: [String]] = [
            "pending": ["Open tasks", "ඉතිරි කාර්ය", "நிலுவை பணிகள்"],
            "nearby": ["Outbreaks nearby", "අවට පැතිරීම්", "அருகிலுள்ள பரவல்"],
            "noscan": ["No scans yet", "ස්කෑන් නැත", "ஸ்கேன் இல்லை"],
            "healthy": ["Healthy", "නිරෝගී", "ஆரோக்கியம்"],
            "unhealthy": ["Unhealthy", "රෝගී", "நோயுற்றது"]]
        let i = lang == "si" ? 1 : (lang == "ta" ? 2 : 0)
        return t[key]?[i] ?? key
    }
}

// MARK: - Views

struct AgriWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AgriEntry
    private var s: WidgetSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack { AccessoryWidgetBackground(); VStack(spacing: 0) { Image(systemName: "leaf.fill"); Text("\(s.pendingTasks)").font(.headline.bold()) } }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("AgriNova", systemImage: "leaf.fill").font(.caption.bold())
                Text(s.lastScanTitle.isEmpty ? W.label("noscan", s.languageCode) : s.lastScanTitle).font(.headline).lineLimit(1)
                Text("\(W.label("pending", s.languageCode)): \(s.pendingTasks) • \(W.riskText(s.fungalRisk, s.languageCode))").font(.caption2).lineLimit(1)
            }
        case .accessoryInline:
            Label("\(s.pendingTasks) • \(W.riskText(s.fungalRisk, s.languageCode))", systemImage: "leaf.fill")
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Image(systemName: "leaf.fill").foregroundStyle(W.leaf); Text("AgriNova").font(.caption.bold()); Spacer() }
            Spacer(minLength: 0)
            if let healthy = s.lastScanHealthy {
                Label(healthy ? W.label("healthy", s.languageCode) : W.label("unhealthy", s.languageCode), systemImage: healthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.caption2.bold()).foregroundStyle(healthy ? W.leaf : W.danger)
                Text(s.lastScanTitle).font(.headline).lineLimit(2).minimumScaleFactor(0.7)
            } else { Text(W.label("noscan", s.languageCode)).font(.headline) }
            HStack(spacing: 4) { Circle().fill(W.riskColor(s.fungalRisk)).frame(width: 8, height: 8); Text(W.riskText(s.fungalRisk, s.languageCode)).font(.caption2) }
        }
        .containerBackground(for: .widget) { LinearGradient(colors: [W.leaf.opacity(0.22), Color(.systemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing) }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack { Image(systemName: "leaf.fill").foregroundStyle(W.leaf); Text(s.farmName).font(.caption.bold()).lineLimit(1) }
                if let healthy = s.lastScanHealthy {
                    Label(healthy ? W.label("healthy", s.languageCode) : W.label("unhealthy", s.languageCode), systemImage: healthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.caption.bold()).foregroundStyle(healthy ? W.leaf : W.danger)
                    Text(s.lastScanTitle).font(.title3.bold()).lineLimit(2).minimumScaleFactor(0.7)
                    Text("\(Int(s.lastScanConfidence * 100))%").font(.caption).foregroundStyle(.secondary)
                } else { Text(W.label("noscan", s.languageCode)).font(.title3.bold()) }
                Spacer(minLength: 0)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                stat("checklist", "\(s.pendingTasks)", W.label("pending", s.languageCode), W.sun)
                stat("dot.radiowaves.left.and.right", "\(s.nearbyOutbreaks)", W.label("nearby", s.languageCode), W.danger)
                HStack(spacing: 6) {
                    Image(systemName: "cloud.sun.fill").foregroundStyle(.blue)
                    Text(s.temperature.map { "\(Int($0))°" } ?? "—").font(.subheadline.bold())
                    Text(s.humidity.map { "\(Int($0))%" } ?? "").font(.caption)
                    Circle().fill(W.riskColor(s.fungalRisk)).frame(width: 8, height: 8)
                }
            }
        }
        .containerBackground(for: .widget) { LinearGradient(colors: [W.leaf.opacity(0.22), Color(.systemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing) }
    }

    private func stat(_ icon: String, _ v: String, _ l: String, _ c: Color) -> some View {
        HStack(spacing: 8) { Image(systemName: icon).foregroundStyle(c).frame(width: 18); Text(v).font(.headline.bold()); Text(l).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
    }
}

struct AgriNovaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AgriNovaWidget", provider: AgriProvider()) { entry in AgriWidgetView(entry: entry) }
            .configurationDisplayName("AgriNova")
            .description("Latest scan, open treatment steps, fungal risk and nearby outbreaks.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct AgriNovaWidgetBundle: WidgetBundle {
    var body: some Widget { AgriNovaWidget() }
}
