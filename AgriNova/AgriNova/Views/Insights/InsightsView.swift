import SwiftUI
import Charts

struct InsightsView: View {
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDScan.date)]) private var scans: FetchedResults<CDScan>
    @FetchRequest(sortDescriptors: []) private var tasks: FetchedResults<CDTask>
    @Environment(AppRouter.self) private var router
    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 18, alignment: .top)]

    private var summary: InsightsSummary {
        InsightsViewModel.summarize(scans.map { .init(date: $0.date ?? Date(), label: $0.diseaseLabel, healthy: $0.isHealthy, confidence: $0.confidence, lowConfidence: $0.needsRescan) })
    }

    var body: some View {
        let s = summary
        ScrollView {
            if s.total == 0 {
                EmptyStateView(icon: "chart.xyaxis.line", title: tr("ins.empty"), message: tr("ins.empty_msg"), actionTitle: tr("nav.scan")) { router.go(.scan) }.padding(.top, 40)
            } else {
                VStack(spacing: 18) {
                    kpis(s)
                    LazyVGrid(columns: columns, spacing: 18) {
                        ratioCard(s); weeklyCard(s); diseaseCard(s); confidenceCard(s); treatmentCard
                    }
                }.padding(20).readableWidth(1100)
            }
        }
    }

    private func kpis(_ s: InsightsSummary) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            kpi("\(s.total)", tr("dash.scans"), "camera.viewfinder", Theme.heroGradient)
            kpi("\(Int(s.healthyRatio * 100))%", tr("ins.healthy_ratio"), "checkmark.seal.fill", Theme.heroGradient)
            kpi("\(Int(s.averageConfidence * 100))%", tr("ins.avg_conf"), "gauge.with.dots.needle.67percent", Theme.skyGradient)
            kpi("\(s.lowConfidenceCount)", tr("ins.rescans"), "arrow.counterclockwise.camera.fill", Theme.sunGradient)
        }
    }

    private func kpi(_ v: String, _ l: String, _ icon: String, _ g: LinearGradient) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            IconBadge(icon: icon, gradient: g, size: 34)
            Text(v).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink).minimumScaleFactor(0.6)
            Text(l).font(.rounded(.caption2, weight: .semibold)).foregroundStyle(Theme.inkSoft).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).softCard(radius: 20, depth: 6)
        .accessibilityElement(children: .ignore).accessibilityLabel("\(l): \(v)")
    }

    private func card<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { Text(title).font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink); content() }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18).softCard()
    }

    private func ratioCard(_ s: InsightsSummary) -> some View {
        card(tr("ins.ratio")) {
            Chart {
                SectorMark(angle: .value("n", s.healthy), innerRadius: .ratio(0.62), angularInset: 2).foregroundStyle(Theme.leaf).cornerRadius(6)
                SectorMark(angle: .value("n", s.unhealthy), innerRadius: .ratio(0.62), angularInset: 2).foregroundStyle(Theme.danger).cornerRadius(6)
            }
            .frame(height: 190)
            .chartBackground { _ in VStack { Text("\(Int(s.healthyRatio * 100))%").font(.system(size: 30, weight: .bold, design: .rounded)); Text(tr("status.healthy")).font(.caption) }.foregroundStyle(Theme.ink) }
            HStack(spacing: 14) {
                Label("\(tr("status.healthy")) \(s.healthy)", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.leaf)
                Label("\(tr("status.unhealthy")) \(s.unhealthy)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
            }.font(.rounded(.footnote, weight: .semibold))
        }
    }

    private func weeklyCard(_ s: InsightsSummary) -> some View {
        card(tr("ins.weekly")) {
            Chart(s.weekly) { w in
                BarMark(x: .value("Week", w.weekStart, unit: .weekOfYear), y: .value("Scans", w.count)).foregroundStyle(Theme.heroGradient).cornerRadius(6)
            }.frame(height: 190)
            .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
            .accessibilityLabel(tr("ins.weekly")).accessibilityValue(s.weekly.map { "\($0.count)" }.joined(separator: ", "))
        }
    }

    private func diseaseCard(_ s: InsightsSummary) -> some View {
        card(tr("ins.diseases")) {
            if s.diseases.isEmpty { Text(tr("ins.no_diseases")).font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft) }
            else {
                Chart(s.diseases) { d in
                    BarMark(x: .value("n", d.count), y: .value("Disease", d.name)).foregroundStyle(Theme.dangerGradient).cornerRadius(6)
                        .annotation(position: .trailing) { Text("\(d.count)").font(.caption.bold()).foregroundStyle(Theme.ink) }
                }.frame(height: CGFloat(max(1, s.diseases.count)) * 42 + 20)
            }
        }
    }

    private func confidenceCard(_ s: InsightsSummary) -> some View {
        card(tr("ins.confidence")) {
            Chart(s.confidenceSeries) { p in
                LineMark(x: .value("Date", p.date), y: .value("Confidence", p.confidence * 100)).foregroundStyle(Theme.sky).interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                PointMark(x: .value("Date", p.date), y: .value("Confidence", p.confidence * 100)).foregroundStyle(p.confidence < AppSettings.shared.confidenceThreshold ? Theme.sun : Theme.sky)
                RuleMark(y: .value("Threshold", AppSettings.shared.confidenceThreshold * 100)).foregroundStyle(Theme.sun.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }.chartYScale(domain: 0...100).frame(height: 190)
            Text(tr("ins.threshold_note", Int(AppSettings.shared.confidenceThreshold * 100))).font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
        }
    }

    private var treatmentCard: some View {
        let done = tasks.filter(\.done).count
        let frac = tasks.isEmpty ? 0 : Double(done) / Double(tasks.count)
        return card(tr("ins.treatment")) {
            HStack(spacing: 18) {
                ConfidenceRing(value: frac, size: 96, tint: Theme.sun)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(done) / \(tasks.count)").font(.rounded(.title2, weight: .bold)).foregroundStyle(Theme.ink)
                    Text(tr("ins.steps_completed")).font(.rounded(.footnote)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }
}
