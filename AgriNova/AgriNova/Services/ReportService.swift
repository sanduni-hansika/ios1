import UIKit
import PDFKit
import CoreData
import SwiftUI

/// PDF generation with UIGraphicsPDFRenderer (A4). Viewing is done with PDFKit (see PDFKitView).
enum ReportService {
    private struct Writer {
        let ctx: UIGraphicsPDFRendererContext
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        var y: CGFloat = 40
        let margin: CGFloat = 40

        mutating func newPageIfNeeded(_ needed: CGFloat) {
            if y + needed > page.height - 50 { ctx.beginPage(); y = 40 }
        }
        mutating func header(_ s: String, size: CGFloat = 22, color: UIColor = UIColor(Theme.leafDeep)) {
            text(s, font: .systemFont(ofSize: size, weight: .bold), color: color, after: 8)
        }
        mutating func text(_ s: String, font: UIFont = .systemFont(ofSize: 12), color: UIColor = .black, after: CGFloat = 4) {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let width = page.width - margin * 2
            let h = (s as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                 options: .usesLineFragmentOrigin, attributes: attrs, context: nil).height
            newPageIfNeeded(h + after)
            (s as NSString).draw(in: CGRect(x: margin, y: y, width: width, height: h), withAttributes: attrs)
            y += h + after
        }
        mutating func image(_ img: UIImage, maxHeight: CGFloat = 220) {
            let ratio = img.size.width / max(1, img.size.height)
            let h = min(maxHeight, 240 / ratio), w = h * ratio
            newPageIfNeeded(h + 10)
            img.draw(in: CGRect(x: margin, y: y, width: w, height: h))
            y += h + 10
        }
        mutating func rule() {
            newPageIfNeeded(12)
            UIColor.lightGray.setFill()
            UIRectFill(CGRect(x: margin, y: y + 4, width: page.width - margin * 2, height: 0.7)); y += 12
        }
    }

    private static func render(_ name: String, _ draw: (inout Writer) -> Void) -> URL {
        let url = URL.temporaryDirectory.appendingPathComponent("\(name).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        try? renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            var w = Writer(ctx: ctx)
            w.header("AgriNova", size: 28)
            w.text(tr("pdf.tagline"), color: .darkGray, after: 6)
            w.rule()
            draw(&w)
            w.rule()
            w.text("\(tr("pdf.generated")) \(Date().formatted(date: .long, time: .shortened))", font: .systemFont(ofSize: 9), color: .gray)
        }
        return url
    }

    static func scanReport(_ scan: CDScan, in ctx: NSManagedObjectContext) -> URL {
        let d = scan.disease
        let tasks = TreatmentService.tasks(for: scan, in: ctx)
        let progress = TreatmentService.progress(for: scan, in: ctx)
        return render("AgriNova-Scan-\((scan.id ?? UUID()).uuidString.prefix(6))") { w in
            w.header(tr("pdf.scan_report"))
            if let img = scan.image { w.image(img) }
            w.text("\(tr("pdf.date")): \((scan.date ?? Date()).formatted(date: .long, time: .shortened))")
            w.text("\(tr("pdf.species")): \(Species.tomatoName.localized)")
            w.text("\(tr("pdf.result")): \(scan.isHealthy ? tr("status.healthy") : tr("status.unhealthy")) – \(d?.displayName ?? "?")", font: .systemFont(ofSize: 14, weight: .semibold))
            w.text("\(tr("scan.confidence")): \(Int((scan.confidence * 100).rounded()))%   •   \(tr("treat.affected")): \(Int(scan.affectedPercent))%")
            if scan.hasLocation { w.text(String(format: "GPS: %.5f, %.5f", scan.latitude, scan.longitude)) }
            if let d { w.rule(); w.header(tr("pdf.about"), size: 15); w.text(d.displaySummary)
                w.header(tr("lib.symptoms"), size: 15); d.symptoms.forEach { w.text("• \($0)") } }
            if !tasks.isEmpty {
                w.rule(); w.header(tr("treat.checklist"), size: 15)
                tasks.forEach { w.text("\($0.done ? "☑" : "☐") \($0.title ?? "") (\($0.category ?? ""))") }
            }
            if progress.count > 0 {
                w.rule(); w.header(tr("treat.progress"), size: 15)
                progress.forEach { w.text("\(tr("treat.day")) \($0.dayOffset): \(Int($0.affectedPercent))% \(tr("treat.affected"))") }
                switch TreatmentService.trend(progress) {
                case .improving: w.text("↓ \(tr("treat.decreasing"))", font: .systemFont(ofSize: 13, weight: .semibold), color: .systemGreen)
                case .worsening: w.text("↑ \(tr("treat.progressing"))", font: .systemFont(ofSize: 13, weight: .semibold), color: .systemRed)
                default: break }
            }
        }
    }

    static func farmReport(_ farm: CDFarm, in ctx: NSManagedObjectContext) -> URL {
        let sr = NSFetchRequest<CDScan>(entityName: "CDScan")
        sr.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]; sr.fetchLimit = 25
        let scans = (try? ctx.fetch(sr)) ?? []
        let lr = NSFetchRequest<CDLog>(entityName: "CDLog")
        lr.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]; lr.fetchLimit = 40
        let logs = (try? ctx.fetch(lr)) ?? []
        return render("AgriNova-Farm-\(farm.displayName.replacingOccurrences(of: " ", with: "-"))") { w in
            w.header(farm.displayName)
            w.text("\(tr("farm.owner")): \(farm.ownerName ?? "-")   •   \(tr("farm.area")): \(String(format: "%.1f", farm.areaHectares)) ha")
            w.text("\(farm.locationName ?? "")")
            w.rule(); w.header(tr("farm.zones"), size: 15)
            farm.zoneList.forEach { z in
                w.text("• \(z.displayName) – \(z.cropList.compactMap(\.name).joined(separator: ", ")) – \(Int(z.radius)) m")
            }
            w.rule(); w.header(tr("farm.workers"), size: 15)
            farm.workerList.forEach { w.text("• \($0.name ?? "") – \($0.role ?? "")") }
            w.rule(); w.header(tr("pdf.recent_scans"), size: 15)
            scans.forEach { s in
                w.text("\((s.date ?? Date()).formatted(date: .abbreviated, time: .shortened)) – \(s.disease?.displayName ?? "?") – \(Int((s.confidence * 100).rounded()))% – \(s.zoneName ?? "")")
            }
            w.rule(); w.header(tr("farm.logs"), size: 15)
            logs.forEach { l in w.text("\((l.date ?? Date()).formatted(date: .abbreviated, time: .shortened)) • \(l.title ?? "")") }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true; v.displayMode = .singlePageContinuous; v.displayDirection = .vertical
        v.document = PDFDocument(url: url)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url { v.document = PDFDocument(url: url) }
    }
}

struct PDFViewerSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            PDFKitView(url: url).ignoresSafeArea(edges: .bottom)
                .navigationTitle(tr("pdf.title")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button(tr("common.done")) { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") } }
                }
        }
    }
}
