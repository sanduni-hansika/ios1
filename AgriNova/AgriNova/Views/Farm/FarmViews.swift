import SwiftUI
import MapKit
import CoreData

// MARK: - Farms list

struct FarmListView: View {
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDFarm.createdAt)]) private var farms: FetchedResults<CDFarm>
    @Environment(LocationService.self) private var location
    @State private var editing: CDFarm?
    @State private var showEditor = false
    @State private var toDelete: CDFarm?
    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 18)]

    var body: some View {
        ScrollView {
            if farms.isEmpty {
                VStack(spacing: 16) {
                    EmptyStateView(icon: "tree.fill", title: tr("farm.empty"), message: tr("farm.empty_msg"), actionTitle: tr("farm.add")) { editing = nil; showEditor = true }
                }.padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(farms) { f in
                        NavigationLink { FarmDetailView(farm: f) } label: { card(f) }.buttonStyle(CardPressStyle())
                            .contextMenu {
                                Button { editing = f; showEditor = true } label: { Label(tr("common.edit"), systemImage: "pencil") }
                                Button(role: .destructive) { toDelete = f } label: { Label(tr("common.delete"), systemImage: "trash") }
                            }
                    }
                }.padding(20).readableWidth(1100)
            }
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { editing = nil; showEditor = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }.accessibilityLabel(tr("farm.add")) } }
        .sheet(isPresented: $showEditor) { FarmEditor(farm: editing) }
        .confirmationDialog(tr("common.delete_confirm"), isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button(tr("common.delete"), role: .destructive) { if let f = toDelete { withAnimation { FarmViewModel.delete(f) }; ToastCenter.shared.show(tr("common.deleted")) }; toDelete = nil }
        } message: { Text(tr("farm.delete_msg")) }
    }

    private func card(_ f: CDFarm) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                IconBadge(icon: "tree.fill", size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.displayName).font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink)
                    Text(f.locationName ?? "").font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
                }
                Spacer(); Image(systemName: "chevron.right").foregroundStyle(Theme.inkSoft)
            }
            HStack(spacing: 8) {
                Chip(text: "\(f.zoneList.count) \(tr("farm.zones"))", icon: "square.grid.2x2.fill")
                Chip(text: "\(f.workerList.count) \(tr("farm.workers"))", icon: "person.2.fill", color: Theme.sky)
                Chip(text: String(format: "%.1f ha", f.areaHectares), icon: "ruler", color: Theme.sun)
            }
        }.padding(18).softCard()
    }
}

// MARK: - Farm editor

struct FarmEditor: View {
    var farm: CDFarm?
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @Environment(AppSettings.self) private var settings
    @State private var name = ""
    @State private var place = ""
    @State private var owner = ""
    @State private var area = ""
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("farm.details")) {
                    TextField(tr("farm.name"), text: $name)
                    TextField(tr("farm.location"), text: $place)
                    TextField(tr("farm.owner"), text: $owner)
                    TextField(tr("farm.area_ha"), text: $area).keyboardType(.decimalPad)
                }
                Section { Label(location.hasFix ? tr("farm.gps_ok") : tr("farm.gps_default"), systemImage: "location.fill").font(.rounded(.footnote)).foregroundStyle(Theme.inkSoft) }
                if showError { Section { Banner(kind: .error, title: tr("farm.name_required")) }.listRowBackground(Color.clear) }
            }
            .scrollContentBackground(.hidden).background(AppBackground())
            .navigationTitle(farm == nil ? tr("farm.add") : tr("common.edit")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(tr("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button(tr("common.save")) { save() }.bold() }
            }
            .onAppear {
                if let f = farm { name = f.name ?? ""; place = f.locationName ?? ""; owner = f.ownerName ?? ""; area = f.areaHectares == 0 ? "" : String(f.areaHectares) }
                else { owner = settings.userName }
            }
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { showError = true; return }
        let c = farm.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } ?? location.coordinate
        FarmViewModel.saveFarm(farm, name: name, location: place, owner: owner, area: Double(area.replacingOccurrences(of: ",", with: ".")) ?? 0, coordinate: c)
        ToastCenter.shared.show(tr("common.saved")); dismiss()
    }
}

// MARK: - Farm detail

struct FarmDetailView: View {
    @ObservedObject var farm: CDFarm
    @Environment(\.managedObjectContext) private var ctx
    @Environment(LocationService.self) private var location
    @State private var showZone = false
    @State private var showWorker = false
    @State private var editingWorker: CDWorker?
    @State private var showNote = false
    @State private var note = ""
    @State private var pdfURL: URL?
    @State private var showPDF = false
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDLog.date, order: .reverse)]) private var logs: FetchedResults<CDLog>

    private var farmLogs: [CDLog] { logs.filter { $0.farmID == farm.id }.prefix(8).map { $0 } }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                summary
                zonesSection
                workersSection
                logsSection
            }.padding(20).readableWidth(900)
        }
        .background(AppBackground())
        .navigationTitle(farm.displayName).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { pdfURL = ReportService.farmReport(farm, in: ctx); showPDF = true } label: { Label(tr("pdf.report"), systemImage: "doc.richtext") }
                Button { showNote = true } label: { Label(tr("farm.add_note"), systemImage: "note.text.badge.plus") }
            } label: { Image(systemName: "ellipsis.circle") }
        } }
        .sheet(isPresented: $showZone) { ZoneEditor(farm: farm, zone: nil) }
        .sheet(isPresented: $showWorker) { WorkerEditor(farm: farm, worker: editingWorker) }
        .sheet(isPresented: $showPDF) { if let pdfURL { PDFViewerSheet(url: pdfURL) } }
        .alert(tr("farm.add_note"), isPresented: $showNote) {
            TextField(tr("farm.note_ph"), text: $note)
            Button(tr("common.save")) { if !note.isEmpty { FarmViewModel.addNote(note, farm: farm); ToastCenter.shared.show(tr("common.saved")) }; note = "" }
            Button(tr("common.cancel"), role: .cancel) { note = "" }
        }
    }

    private var summary: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                IconBadge(icon: "tree.fill", size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(farm.locationName ?? "").font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft)
                    Text("\(tr("farm.owner")): \(farm.ownerName ?? "-")").font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(String(format: "%.1f ha", farm.areaHectares)).font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
            }
            geofenceStatus
        }.padding(18).softCard()
    }

    private var geofenceStatus: some View {
        let armed = location.monitored.count
        return HStack(spacing: 10) {
            Image(systemName: armed > 0 ? "location.circle.fill" : "location.slash.fill").foregroundStyle(armed > 0 ? Theme.leaf : Theme.sun)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("geo.active", armed, LocationService.maxRegions)).font(.rounded(.footnote, weight: .bold)).foregroundStyle(Theme.ink)
                Text(location.hasAlways ? tr("geo.always_ok") : tr("geo.need_always")).font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            if !location.hasAlways { Button(tr("geo.enable")) { location.requestPermission() }.font(.rounded(.footnote, weight: .bold)) }
        }.padding(12).background(Theme.leaf.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var zonesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: tr("farm.zones"), actionTitle: tr("common.add")) { showZone = true }
            if farm.zoneList.isEmpty { Text(tr("farm.no_zones")).font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft) }
            ForEach(farm.zoneList) { z in
                NavigationLink { ZoneDetailView(zone: z) } label: {
                    HStack(spacing: 12) {
                        IconBadge(icon: location.insideZoneIDs.contains(z.id?.uuidString ?? "") ? "location.fill" : "square.grid.2x2.fill",
                                  gradient: z.geofenceEnabled ? Theme.heroGradient : Theme.skyGradient, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(z.displayName).font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.ink)
                            Text(z.cropList.compactMap(\.name).joined(separator: ", ")).font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        if z.geofenceEnabled { Chip(text: "\(Int(z.radius)) m", icon: "dot.circle.and.hand.point.up.left.fill") }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                }.buttonStyle(.plain)
            }
        }.padding(18).softCard()
    }

    private var workersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: tr("farm.workers"), actionTitle: tr("common.add")) { editingWorker = nil; showWorker = true }
            if farm.workerList.isEmpty { Text(tr("farm.no_workers")).font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft) }
            ForEach(farm.workerList) { w in
                HStack(spacing: 12) {
                    Text(String((w.name ?? "?").prefix(1))).font(.rounded(.headline, weight: .bold)).foregroundStyle(.white).frame(width: 38, height: 38).background(Theme.skyGradient, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.name ?? "").font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.ink)
                        Text("\(w.role ?? "") • \(w.phone ?? "")").font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    Menu {
                        Button { editingWorker = w; showWorker = true } label: { Label(tr("common.edit"), systemImage: "pencil") }
                        Button(role: .destructive) { FarmViewModel.delete(w) } label: { Label(tr("common.delete"), systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis").foregroundStyle(Theme.inkSoft).frame(width: 36, height: 36) }
                }
            }
        }.padding(18).softCard()
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: tr("farm.logs"))
            if farmLogs.isEmpty { Text(tr("farm.no_logs")).font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft) }
            ForEach(farmLogs) { l in LogRow(log: l) }
        }.padding(18).softCard()
    }
}

struct LogRow: View {
    let log: CDLog
    static func icon(_ k: String?) -> (String, Color) {
        switch k { case "scan": ("camera.viewfinder", Theme.leaf); case "treatment": ("cross.case.fill", Theme.sun); case "geofence": ("location.fill", Theme.sky)
        case "outbreak": ("megaphone.fill", Theme.danger); case "note": ("note.text", Theme.violet); default: ("clock.fill", Theme.inkSoft) }
    }
    var body: some View {
        let (icon, color) = Self.icon(log.kind)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(.white).frame(width: 32, height: 32).background(color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(log.title ?? "").font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(Theme.ink)
                if let d = log.detail, !d.isEmpty { Text(d).font(.rounded(.caption)).foregroundStyle(Theme.inkSoft) }
                Text((log.date ?? Date()).formatted(date: .abbreviated, time: .shortened)).font(.rounded(.caption2)).foregroundStyle(Theme.inkSoft.opacity(0.8))
            }
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine)
    }
}

// MARK: - Worker editor

struct WorkerEditor: View {
    let farm: CDFarm; var worker: CDWorker?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var role = ""; @State private var phone = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField(tr("farm.worker_name"), text: $name)
                TextField(tr("farm.worker_role"), text: $role)
                TextField(tr("farm.worker_phone"), text: $phone).keyboardType(.phonePad)
            }
            .scrollContentBackground(.hidden).background(AppBackground())
            .navigationTitle(tr("farm.workers")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(tr("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button(tr("common.save")) {
                    guard !name.isEmpty else { return }
                    FarmViewModel.saveWorker(worker, in: farm, name: name, role: role, phone: phone); ToastCenter.shared.show(tr("common.saved")); dismiss()
                }.bold() }
            }
            .onAppear { if let w = worker { name = w.name ?? ""; role = w.role ?? ""; phone = w.phone ?? "" } }
        }.presentationDetents([.medium])
    }
}
