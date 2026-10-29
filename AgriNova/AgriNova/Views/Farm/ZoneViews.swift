import SwiftUI
import MapKit
import CoreData

// MARK: - Zone editor (tap the map to place the zone, slider sets geofence radius)

struct ZoneEditor: View {
    let farm: CDFarm
    var zone: CDZone?
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @State private var name = ""
    @State private var lat = 0.0
    @State private var lon = 0.0
    @State private var radius = 120.0
    @State private var geofence = true
    @State private var reminder = ""
    @State private var camera: MapCameraPosition = .automatic
    @State private var error = false

    private var coord: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("farm.zone_details")) {
                    TextField(tr("farm.zone_name"), text: $name)
                    TextField(tr("farm.zone_reminder"), text: $reminder, axis: .vertical).lineLimit(2...4)
                }
                Section(tr("farm.zone_place")) {
                    MapReader { proxy in
                        Map(position: $camera) {
                            UserAnnotation()
                            MapCircle(center: coord, radius: radius).foregroundStyle(Theme.leaf.opacity(0.25)).stroke(Theme.leaf, lineWidth: 2)
                            Annotation(name.isEmpty ? tr("farm.zone") : name, coordinate: coord) {
                                Image(systemName: "mappin.circle.fill").font(.title).foregroundStyle(Theme.leaf, .white)
                            }
                        }
                        .mapStyle(.hybrid)
                        .frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .onTapGesture { p in if let c = proxy.convert(p, from: .local) { lat = c.latitude; lon = c.longitude } }
                    }
                    .listRowInsets(EdgeInsets())
                    Button { lat = location.coordinate.latitude; lon = location.coordinate.longitude; recenter() } label: { Label(tr("farm.use_location"), systemImage: "location.fill") }
                    VStack(alignment: .leading) {
                        Text("\(tr("farm.radius")): \(Int(radius)) m").font(.rounded(.subheadline, weight: .semibold))
                        Slider(value: $radius, in: 50...500, step: 10).tint(Theme.leaf)
                    }
                    Toggle(isOn: $geofence) { Label(tr("farm.geofence"), systemImage: "bell.and.waves.left.and.right.fill") }.tint(Theme.leaf)
                    Text(tr("farm.geofence_note", LocationService.maxRegions)).font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
                }
                if error { Banner(kind: .error, title: tr("farm.zone_name_required")).listRowBackground(Color.clear) }
            }
            .scrollContentBackground(.hidden).background(AppBackground())
            .navigationTitle(zone == nil ? tr("farm.add_zone") : tr("common.edit")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(tr("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button(tr("common.save")) { save() }.bold() }
            }
            .onAppear {
                if let z = zone { name = z.name ?? ""; lat = z.latitude; lon = z.longitude; radius = z.radius; geofence = z.geofenceEnabled; reminder = z.reminderText ?? "" }
                else { lat = location.coordinate.latitude; lon = location.coordinate.longitude; reminder = tr("geo.default_reminder") }
                recenter()
            }
        }
    }

    private func recenter() { camera = .region(MKCoordinateRegion(center: coord, latitudinalMeters: max(600, radius * 4), longitudinalMeters: max(600, radius * 4))) }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { error = true; return }
        FarmViewModel.saveZone(zone, in: farm, name: name, coordinate: coord, radius: radius, geofence: geofence, reminder: reminder)
        ToastCenter.shared.show(tr("common.saved")); dismiss()
    }
}

// MARK: - Zone detail

struct ZoneDetailView: View {
    @ObservedObject var zone: CDZone
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @State private var showEditor = false
    @State private var showCrop = false
    @State private var editingCrop: CDCrop?
    @State private var showMark = false
    @State private var confirmDelete = false
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDInfected.date, order: .reverse)]) private var infected: FetchedResults<CDInfected>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDScan.date, order: .reverse)]) private var scans: FetchedResults<CDScan>

    private var zoneInfected: [CDInfected] { infected.filter { $0.zoneID == zone.id } }
    private var zoneScans: [CDScan] { scans.filter { $0.zoneID == zone.id }.prefix(5).map { $0 } }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                map
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: tr("farm.crops"), actionTitle: tr("common.add")) { editingCrop = nil; showCrop = true }
                    if zone.cropList.isEmpty { Text(tr("farm.no_crops")).font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft) }
                    ForEach(zone.cropList) { c in
                        HStack(spacing: 12) {
                            IconBadge(icon: "carrot.fill", gradient: Theme.sunGradient, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(c.name ?? "") \(c.variety.map { "• \($0)" } ?? "")").font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.ink)
                                Text("\(c.plantCount) \(tr("farm.plants")) • \((c.plantedDate ?? Date()).formatted(date: .abbreviated, time: .omitted))").font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer()
                            Menu {
                                Button { editingCrop = c; showCrop = true } label: { Label(tr("common.edit"), systemImage: "pencil") }
                                Button(role: .destructive) { FarmViewModel.delete(c) } label: { Label(tr("common.delete"), systemImage: "trash") }
                            } label: { Image(systemName: "ellipsis").foregroundStyle(Theme.inkSoft).frame(width: 36, height: 36) }
                        }
                    }
                }.padding(18).softCard()

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: tr("farm.infected"), actionTitle: tr("farm.mark")) { showMark = true }
                    if zoneInfected.isEmpty { Text(tr("farm.no_infected")).font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft) }
                    ForEach(zoneInfected) { i in
                        HStack(spacing: 12) {
                            IconBadge(icon: "exclamationmark.triangle.fill", gradient: Theme.dangerGradient, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(i.diseaseLabel.flatMap(DiseaseCatalog.find)?.displayName ?? tr("farm.unknown")).font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.ink)
                                Text("\(i.note ?? "") • \((i.date ?? Date()).formatted(date: .abbreviated, time: .omitted))").font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer()
                            Button { i.resolved.toggle(); PersistenceController.shared.save() } label: {
                                Image(systemName: i.resolved ? "checkmark.circle.fill" : "circle").foregroundStyle(i.resolved ? Theme.leaf : Theme.inkSoft).font(.title3)
                            }.accessibilityLabel(tr("farm.resolved"))
                            Button(role: .destructive) { FarmViewModel.delete(i) } label: { Image(systemName: "trash").foregroundStyle(Theme.danger) }.accessibilityLabel(tr("common.delete"))
                        }
                    }
                }.padding(18).softCard()

                if !zoneScans.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: tr("farm.zone_scans"))
                        ForEach(zoneScans) { s in
                            NavigationLink { ScanResultView(scan: s) } label: {
                                HStack { StatusBadge(isHealthy: s.isHealthy); Text(s.disease?.displayName ?? "").font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(Theme.ink); Spacer()
                                    Text((s.date ?? Date()).formatted(date: .abbreviated, time: .omitted)).font(.rounded(.caption)).foregroundStyle(Theme.inkSoft) }
                            }.buttonStyle(.plain)
                        }
                    }.padding(18).softCard()
                }
            }.padding(20).readableWidth(900)
        }
        .background(AppBackground())
        .navigationTitle(zone.displayName).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu {
            Button { showEditor = true } label: { Label(tr("common.edit"), systemImage: "pencil") }
            Button(role: .destructive) { confirmDelete = true } label: { Label(tr("common.delete"), systemImage: "trash") }
        } label: { Image(systemName: "ellipsis.circle") } } }
        .sheet(isPresented: $showEditor) { if let f = zone.farm { ZoneEditor(farm: f, zone: zone) } }
        .sheet(isPresented: $showCrop) { CropEditor(zone: zone, crop: editingCrop) }
        .sheet(isPresented: $showMark) { InfectedMarkSheet(zone: zone) }
        .confirmationDialog(tr("common.delete_confirm"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(tr("common.delete"), role: .destructive) { FarmViewModel.deleteZone(zone); dismiss() }
        }
    }

    private var map: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: zone.coordinate, latitudinalMeters: max(500, zone.radius * 4), longitudinalMeters: max(500, zone.radius * 4)))) {
            UserAnnotation()
            MapCircle(center: zone.coordinate, radius: zone.radius).foregroundStyle(Theme.leaf.opacity(0.22)).stroke(Theme.leaf, lineWidth: 2)
            ForEach(zoneInfected) { i in
                Annotation(i.diseaseLabel.flatMap(DiseaseCatalog.find)?.displayName ?? "", coordinate: .init(latitude: i.latitude, longitude: i.longitude)) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.white).padding(7).background(i.resolved ? Theme.leaf : Theme.danger, in: Circle()).shadow(radius: 4)
                }
            }
        }
        .mapStyle(.hybrid).frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .topLeading) {
            if location.insideZoneIDs.contains(zone.id?.uuidString ?? "") { Chip(text: tr("geo.inside"), icon: "location.fill", color: Theme.leaf, filled: true).padding(12) }
        }
    }
}

struct CropEditor: View {
    let zone: CDZone; var crop: CDCrop?
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Tomato"; @State private var variety = ""; @State private var planted = Date(); @State private var count = 100
    var body: some View {
        NavigationStack {
            Form {
                TextField(tr("farm.crop_name"), text: $name)
                TextField(tr("farm.variety"), text: $variety)
                DatePicker(tr("farm.planted"), selection: $planted, in: ...Date(), displayedComponents: .date)
                Stepper("\(tr("farm.plants")): \(count)", value: $count, in: 1...100000, step: 10)
            }
            .scrollContentBackground(.hidden).background(AppBackground())
            .navigationTitle(tr("farm.crops")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(tr("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button(tr("common.save")) {
                    guard !name.isEmpty else { return }
                    FarmViewModel.saveCrop(crop, in: zone, name: name, variety: variety, planted: planted, count: count); ToastCenter.shared.show(tr("common.saved")); dismiss()
                }.bold() }
            }
            .onAppear { if let c = crop { name = c.name ?? ""; variety = c.variety ?? ""; planted = c.plantedDate ?? Date(); count = Int(c.plantCount) } }
        }.presentationDetents([.medium])
    }
}

/// Marks an infected plant's exact location: tap the map, or use the current GPS fix.
struct InfectedMarkSheet: View {
    let zone: CDZone
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @State private var disease: Disease = DiseaseCatalog.diseasesOnly[0]
    @State private var note = ""
    @State private var lat = 0.0; @State private var lon = 0.0
    private var coord: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

    var body: some View {
        NavigationStack {
            Form {
                Picker(tr("lib.title"), selection: $disease) { ForEach(DiseaseCatalog.diseasesOnly) { Text($0.displayName).tag($0) } }
                TextField(tr("farm.mark_note"), text: $note)
                Section(tr("farm.tap_map")) {
                    MapReader { proxy in
                        Map(initialPosition: .region(MKCoordinateRegion(center: zone.coordinate, latitudinalMeters: max(400, zone.radius * 3), longitudinalMeters: max(400, zone.radius * 3)))) {
                            UserAnnotation()
                            MapCircle(center: zone.coordinate, radius: zone.radius).foregroundStyle(Theme.leaf.opacity(0.2)).stroke(Theme.leaf, lineWidth: 2)
                            Marker(disease.displayName, systemImage: "exclamationmark.triangle.fill", coordinate: coord).tint(Theme.danger)
                        }
                        .mapStyle(.hybrid).frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .onTapGesture { p in if let c = proxy.convert(p, from: .local) { lat = c.latitude; lon = c.longitude } }
                    }.listRowInsets(EdgeInsets())
                    Button { lat = location.coordinate.latitude; lon = location.coordinate.longitude } label: { Label(tr("farm.use_location"), systemImage: "location.fill") }
                }
            }
            .scrollContentBackground(.hidden).background(AppBackground())
            .navigationTitle(tr("farm.mark")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(tr("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button(tr("common.save")) {
                    FarmViewModel.markInfected(disease: disease, coordinate: coord, note: note, zone: zone); ToastCenter.shared.show(tr("farm.marked")); dismiss()
                }.bold() }
            }
            .onAppear { lat = zone.latitude; lon = zone.longitude }
        }
    }
}
