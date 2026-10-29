import SwiftUI
import CoreData

/// Unified farm history: scans, diagnoses, treatments, geofence events, outbreak reports and farmer notes.
struct HistoryView: View {
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDLog.date, order: .reverse)]) private var logs: FetchedResults<CDLog>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDScan.date, order: .reverse)]) private var scans: FetchedResults<CDScan>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDFarm.createdAt)]) private var farms: FetchedResults<CDFarm>
    @State private var filter = "all"
    @State private var query = ""
    @State private var showNote = false
    @State private var note = ""
    @State private var pdfURL: URL?
    @State private var showPDF = false
    @Environment(\.managedObjectContext) private var ctx

    private let kinds = ["all", "scan", "treatment", "note", "outbreak", "geofence"]

    private var rows: [CDLog] {
        logs.filter { (filter == "all" || $0.kind == filter) && (query.isEmpty || ($0.title ?? "").localizedCaseInsensitiveContains(query) || ($0.detail ?? "").localizedCaseInsensitiveContains(query)) }
    }
    private func scan(for log: CDLog) -> CDScan? {
        guard log.kind == "scan" else { return nil }
        return scans.min { abs(($0.date ?? .distantPast).timeIntervalSince(log.date ?? .distantPast)) < abs(($1.date ?? .distantPast).timeIntervalSince(log.date ?? .distantPast)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(kinds, id: \.self) { k in
                            Button { withAnimation(.spring) { filter = k } } label: { Chip(text: tr("hist.\(k)"), color: Theme.leafDeep, filled: filter == k) }.buttonStyle(.plain)
                        }
                    }
                }
                if rows.isEmpty { EmptyStateView(icon: "clock.arrow.circlepath", title: tr("hist.empty"), message: tr("hist.empty_msg")) }
                LazyVStack(spacing: 12) {
                    ForEach(rows) { l in
                        Group {
                            if let s = scan(for: l) { NavigationLink { ScanResultView(scan: s) } label: { row(l, chevron: true) }.buttonStyle(.plain) }
                            else { row(l, chevron: false) }
                        }
                        .contextMenu { Button(role: .destructive) { ctx.delete(l); PersistenceController.shared.save() } label: { Label(tr("common.delete"), systemImage: "trash") } }
                    }
                }
            }.padding(20).readableWidth(820)
        }
        .searchable(text: $query, prompt: tr("hist.search"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { showNote = true } label: { Image(systemName: "note.text.badge.plus") }.accessibilityLabel(tr("farm.add_note")) }
            ToolbarItem(placement: .topBarTrailing) {
                Button { if let f = farms.first { pdfURL = ReportService.farmReport(f, in: ctx); showPDF = true } else { ToastCenter.shared.show(tr("farm.empty"), kind: .info) } } label: { Image(systemName: "doc.richtext") }.accessibilityLabel(tr("pdf.report"))
            }
        }
        .alert(tr("farm.add_note"), isPresented: $showNote) {
            TextField(tr("farm.note_ph"), text: $note)
            Button(tr("common.save")) { if !note.isEmpty { FarmViewModel.addNote(note, farm: farms.first); ToastCenter.shared.show(tr("common.saved")) }; note = "" }
            Button(tr("common.cancel"), role: .cancel) { note = "" }
        }
        .sheet(isPresented: $showPDF) { if let pdfURL { PDFViewerSheet(url: pdfURL) } }
    }

    private func row(_ l: CDLog, chevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            LogRow(log: l)
            if chevron { Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.inkSoft).padding(.top, 8) }
        }.padding(14).softCard(radius: 20, depth: 6)
    }
}
