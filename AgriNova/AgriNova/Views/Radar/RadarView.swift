import SwiftUI
import MapKit

/// Community Outbreak Radar – a live MapKit map driven by synced Core Data / backend reports.
/// Beyond pins it offers: zoom-based clustering, severity hotspots, map styles, farm-zone overlays,
/// a distance ring with local risk, a spread timeline replay, in-app driving routes (MKDirections),
/// nearby agri-service search (MKLocalSearch) and Look Around street views.
struct RadarView: View {
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDOutbreak.createdAt, order: .reverse)]) private var all: FetchedResults<CDOutbreak>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDZone.name)]) private var zones: FetchedResults<CDZone>
    @Environment(LocationService.self) private var location
    @Environment(SyncService.self) private var sync
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var vm = RadarViewModel()
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showReport = false
    @State private var showPicker = false
    @State private var reportDisease: Disease = DiseaseCatalog.diseasesOnly[0]
    @State private var playTask: Task<Void, Never>?

    private var reports: [CDOutbreak] { vm.filtered(Array(all)) }
    private var visibleReports: [CDOutbreak] { vm.visible(reports) }
    private var clusters: [ReportCluster] { RadarViewModel.clusters(visibleReports, cell: RadarViewModel.clusterCell(for: vm.span)) }
    private var ringReports: [CDOutbreak] { vm.ringKm > 0 ? RadarViewModel.nearby(visibleReports, to: location.coordinate, km: Double(vm.ringKm)) : [] }

    var body: some View {
        Group {
            if hSize == .regular {
                HStack(spacing: 0) { mapView; listPanel.frame(width: 360) }
            } else {
                ZStack(alignment: .bottom) { mapView; bottomPanel }
            }
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showPicker = true } label: { Image(systemName: "megaphone.fill") }.accessibilityLabel(tr("radar.report")) } }
        .sheet(isPresented: $showReport) { ReportOutbreakSheet(disease: reportDisease) }
        .sheet(isPresented: $showPicker) { DiseasePickerSheet { d in reportDisease = d; showReport = true } }
        .sheet(item: $vm.selected) { r in
            ReportDetailSheet(report: r) { Task { await showRoute(to: r) } }.presentationDetents([.medium, .large])
        }
        .task { await sync.syncNow() }
        .refreshable { await sync.syncNow() }
        .onChange(of: vm.showServices) { _, on in if on { Task { await vm.searchServices(near: location.coordinate) } } }
        .onDisappear { playTask?.cancel() }
    }

    // MARK: Map
    private var mapView: some View {
        Map(position: $camera) {
            UserAnnotation()
            if vm.showZones {
                ForEach(zones) { z in
                    MapCircle(center: z.coordinate, radius: z.radius).foregroundStyle(Theme.leaf.opacity(0.18)).stroke(Theme.leaf, lineWidth: 1.5)
                }
            }
            if vm.ringKm > 0 {
                MapCircle(center: location.coordinate, radius: Double(vm.ringKm) * 1000)
                    .foregroundStyle(Theme.sky.opacity(0.06)).stroke(Theme.sky, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            }
            ForEach(visibleReports) { r in
                MapCircle(center: r.coordinate, radius: RadarViewModel.hotspotRadius(severity: r.severity))
                    .foregroundStyle(color(Int(r.severity)).opacity(0.16)).stroke(color(Int(r.severity)).opacity(0.5), lineWidth: 1)
            }
            ForEach(clusters) { c in
                Annotation(c.reports.count == 1 ? (c.reports[0].disease?.displayName ?? "") : tr("radar.count", c.reports.count), coordinate: c.coordinate, anchor: .bottom) {
                    if c.reports.count == 1 {
                        Button { vm.selected = c.reports[0] } label: { pin(c.reports[0]) }.buttonStyle(.plain)
                    } else {
                        Button { zoom(into: c) } label: { clusterBubble(c) }.buttonStyle(.plain)
                    }
                }
            }
            if vm.showServices {
                ForEach(vm.services, id: \.self) { item in
                    Annotation(item.name ?? tr("radar.service"), coordinate: item.placemark.coordinate) { serviceBadge(item) }
                }
            }
            if let route = vm.route {
                MapPolyline(route.polyline).stroke(Theme.sky, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
        }
        .mapStyle(vm.mapStyle.style)
        .mapControls { MapUserLocationButton(); MapCompass(); MapScaleView() }
        .onMapCameraChange(frequency: .onEnd) { ctx in vm.span = ctx.region.span }
        .safeAreaInset(edge: .top) { filterBar }
    }

    private func color(_ severity: Int) -> Color { severity >= 3 ? Theme.danger : (severity == 2 ? Theme.sun : Theme.leaf) }

    private func pin(_ r: CDOutbreak) -> some View {
        VStack(spacing: 0) {
            Image(systemName: r.disease?.pathogen.icon ?? "leaf.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                .padding(9).background(color(Int(r.severity)), in: Circle()).overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .shadow(color: color(Int(r.severity)).opacity(0.6), radius: 6, y: 3)
            Image(systemName: "triangle.fill").font(.system(size: 8)).rotationEffect(.degrees(180)).foregroundStyle(color(Int(r.severity))).offset(y: -2)
        }
        .overlay(alignment: .topTrailing) { if !r.synced { Circle().fill(Theme.sun).frame(width: 10, height: 10).overlay(Circle().strokeBorder(.white, lineWidth: 1.5)) } }
        .accessibilityLabel("\(r.disease?.displayName ?? ""), \(tr("radar.sev.\(r.severity)"))")
    }

    private func clusterBubble(_ c: ReportCluster) -> some View {
        Text("\(c.reports.count)").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            .frame(width: 44, height: 44).background(color(c.maxSeverity), in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5)).background(Circle().fill(color(c.maxSeverity).opacity(0.25)).frame(width: 60, height: 60))
            .shadow(color: color(c.maxSeverity).opacity(0.5), radius: 8, y: 4)
            .accessibilityLabel(tr("radar.count", c.reports.count))
    }

    private func serviceBadge(_ item: MKMapItem) -> some View {
        Button { openInMaps(item) } label: {
            Image(systemName: "building.2.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .padding(8).background(Color.teal, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white, lineWidth: 2)).shadow(radius: 4)
        }.buttonStyle(.plain).accessibilityLabel(item.name ?? tr("radar.service")).accessibilityHint(tr("radar.open_maps"))
    }

    private func openInMaps(_ item: MKMapItem) { item.openInMaps() }

    private func zoom(into c: ReportCluster) {
        let cell = RadarViewModel.clusterCell(for: vm.span)
        let d = max(0.01, cell * 0.9)
        withAnimation(.easeInOut) { camera = .region(MKCoordinateRegion(center: c.coordinate, span: MKCoordinateSpan(latitudeDelta: d, longitudeDelta: d))) }
    }

    private func showRoute(to r: CDOutbreak) async {
        if let rect = await vm.buildRoute(to: r, from: location.coordinate) { withAnimation(.easeInOut) { camera = .rect(rect) } }
    }

    // MARK: Filters, layers & status
    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(RadarViewModel.Range.allCases, id: \.self) { rg in
                    Button { withAnimation(.spring) { vm.range = rg } } label: { Chip(text: tr(rg.titleKey), color: Theme.leafDeep, filled: vm.range == rg) }.buttonStyle(.plain)
                }
                Spacer()
                statusChip
                layersMenu
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { withAnimation(.spring) { vm.diseaseFilter = nil } } label: { Chip(text: tr("common.all"), icon: "square.grid.2x2.fill", color: Theme.sky, filled: vm.diseaseFilter == nil) }.buttonStyle(.plain)
                    ForEach(DiseaseCatalog.diseasesOnly) { d in
                        Button { withAnimation(.spring) { vm.diseaseFilter = d.id } } label: { Chip(text: d.displayName, color: d.pathogen.color, filled: vm.diseaseFilter == d.id) }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(.horizontal, 14).padding(.vertical, 10).background(.ultraThinMaterial)
    }

    /// Map layers & tools: style, zones, distance ring, agri services, spread timeline.
    private var layersMenu: some View {
        @Bindable var vm = vm
        return Menu {
            Picker(tr("radar.style"), selection: $vm.mapStyle) {
                ForEach(MapStyleChoice.allCases) { Text(tr($0.titleKey)).tag($0) }
            }
            Picker(tr("radar.ring"), selection: $vm.ringKm) {
                Text(tr("radar.ring_off")).tag(0); Text("5 km").tag(5); Text("10 km").tag(10); Text("25 km").tag(25)
            }
            Toggle(tr("radar.zones"), isOn: $vm.showZones)
            Toggle(tr("radar.services"), isOn: $vm.showServices)
            Toggle(tr("radar.timeline"), isOn: $vm.timelineOn.animation(.spring))
        } label: {
            Image(systemName: "square.3.layers.3d").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.leafDeep)
                .frame(width: 34, height: 30).background(Theme.leaf.opacity(0.15), in: Capsule())
        }.accessibilityLabel(tr("radar.layers"))
    }

    private var statusChip: some View {
        Group {
            if sync.isSyncing { Chip(text: tr("radar.syncing"), icon: "arrow.triangle.2.circlepath", color: Theme.sky, filled: true) }
            else if !sync.isOnline { Chip(text: tr("radar.offline"), icon: "wifi.slash", color: Theme.sun, filled: true) }
            else if sync.pendingCount > 0 { Chip(text: tr("radar.pending", sync.pendingCount), icon: "tray.and.arrow.up.fill", color: Theme.sun, filled: true) }
            else { Chip(text: tr("radar.live"), icon: "dot.radiowaves.left.and.right", color: Theme.leaf, filled: true) }
        }
    }

    // MARK: Info strips (ring risk, route, timeline)
    @ViewBuilder private var infoStrips: some View {
        if vm.ringKm > 0 {
            let risk = RadarViewModel.riskLevel(score: RadarViewModel.riskScore(ringReports))
            HStack(spacing: 8) {
                Image(systemName: risk.icon).foregroundStyle(risk.color)
                Text(tr("radar.ring_summary", ringReports.count, "\(vm.ringKm)")).font(.rounded(.footnote, weight: .bold)).foregroundStyle(Theme.ink)
                Spacer()
                Chip(text: "\(tr("radar.risk")): \(tr(risk.titleKey))", color: risk.color, filled: true)
            }.padding(.horizontal, 16)
        }
        if let route = vm.route {
            HStack(spacing: 8) {
                Image(systemName: "car.fill").foregroundStyle(Theme.sky)
                Text(tr("radar.route_summary", String(format: "%.1f", route.distance / 1000), "\(Int((route.expectedTravelTime / 60).rounded()))"))
                    .font(.rounded(.footnote, weight: .bold)).foregroundStyle(Theme.ink)
                Spacer()
                Button(tr("radar.clear_route")) { withAnimation { vm.clearRoute() } }.font(.rounded(.footnote, weight: .bold)).foregroundStyle(Theme.danger)
            }.padding(.horizontal, 16)
        }
        if vm.timelineOn { timelineControl }
        if vm.showServices && vm.isSearching { ProgressView(tr("radar.services")).font(.rounded(.caption)).padding(.horizontal, 16) }
    }

    private var timelineControl: some View {
        @Bindable var vm = vm
        let date = vm.timelineDate(reports)
        return HStack(spacing: 10) {
            Button { togglePlay() } label: {
                Image(systemName: playTask == nil ? "play.fill" : "pause.fill").foregroundStyle(.white).frame(width: 34, height: 34).background(Theme.heroGradient, in: Circle())
            }.accessibilityLabel(tr("radar.play"))
            VStack(alignment: .leading, spacing: 2) {
                Slider(value: $vm.timelineProgress, in: 0...1).tint(Theme.leaf).disabled(vm.dateRange(reports) == nil)
                Text(date.map { tr("radar.until", $0.formatted(date: .abbreviated, time: .omitted)) } ?? tr("radar.timeline_need")).font(.rounded(.caption2)).foregroundStyle(Theme.inkSoft)
            }
        }.padding(.horizontal, 16)
    }

    private func togglePlay() {
        if playTask != nil { playTask?.cancel(); playTask = nil; return }
        if vm.timelineProgress >= 1 { vm.timelineProgress = 0 }
        playTask = Task { @MainActor in
            while !Task.isCancelled && vm.timelineProgress < 1 {
                try? await Task.sleep(for: .milliseconds(80))
                vm.timelineProgress = min(1, vm.timelineProgress + 0.012)
            }
            playTask = nil
        }
    }

    // MARK: Lists
    private var nearbyList: [CDOutbreak] { visibleReports.sorted { RadarViewModel.distanceKm($0, from: location.coordinate) < RadarViewModel.distanceKm($1, from: location.coordinate) } }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tr("radar.count", visibleReports.count)).font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.ink)
                Spacer()
                Text(backendLine).font(.rounded(.caption2)).foregroundStyle(Theme.inkSoft)
            }.padding(.horizontal, 20)
            infoStrips
            if visibleReports.isEmpty {
                Text(tr("radar.none")).font(.rounded(.footnote)).foregroundStyle(Theme.inkSoft).padding(.horizontal, 20).padding(.bottom, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) { ForEach(nearbyList.prefix(12)) { r in reportCard(r).frame(width: 250) } }.padding(.horizontal, 20)
                }
            }
        }
        .padding(.vertical, 12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 10).padding(.bottom, 84)
    }

    private var listPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("radar.count", visibleReports.count)).font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink)
                Text(backendLine).font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
                VStack(alignment: .leading, spacing: 10) { infoStrips }.padding(.horizontal, -16)
                ForEach(nearbyList) { reportCard($0) }
            }.padding(16)
        }.background(Theme.canvas)
    }

    private var backendLine: String { "\(sync.backendName)" + (sync.lastSync.map { " • \($0.formatted(.relative(presentation: .named)))" } ?? "") }

    private func reportCard(_ r: CDOutbreak) -> some View {
        Button { vm.selected = r; withAnimation { camera = .camera(MapCamera(centerCoordinate: r.coordinate, distance: 6000)) } } label: {
            HStack(spacing: 10) {
                if let d = r.disease { Image(d.imageName).resizable().scaledToFill().frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.disease?.displayName ?? "").font(.rounded(.footnote, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(String(format: "%.1f km • %@", RadarViewModel.distanceKm(r, from: location.coordinate), tr("radar.sev.\(r.severity)"))).font(.rounded(.caption2)).foregroundStyle(Theme.inkSoft)
                    Text((r.createdAt ?? Date()).formatted(.relative(presentation: .named))).font(.rounded(.caption2)).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
                if !r.synced { Image(systemName: "tray.and.arrow.up.fill").foregroundStyle(Theme.sun) }
            }.padding(10).softCard(radius: 18, depth: 5)
        }.buttonStyle(.plain)
    }
}

struct ReportDetailSheet: View {
    let report: CDOutbreak
    var onRoute: () -> Void = {}
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var lookAround: MKLookAroundScene?
    @State private var lookChecked = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let d = report.disease {
                        Image(d.imageName).resizable().scaledToFill().frame(height: 160).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        Text(d.displayName).font(.rounded(.title2, weight: .bold)).foregroundStyle(Theme.ink)
                        HStack { Chip(text: tr("radar.sev.\(report.severity)"), icon: "gauge.medium", color: report.severity >= 3 ? Theme.danger : Theme.sun, filled: true)
                            Chip(text: report.synced ? tr("radar.synced") : tr("radar.not_synced"), icon: report.synced ? "checkmark.icloud.fill" : "tray.and.arrow.up.fill", color: report.synced ? Theme.leaf : Theme.sun)
                            if report.sharedWithExtension { Chip(text: tr("radar.extension"), icon: "person.badge.shield.checkmark.fill", color: Theme.violet) } }
                    }
                    Label("\(tr("radar.reporter")): \(report.reporter ?? "")", systemImage: "person.fill").font(.rounded(.subheadline)).foregroundStyle(Theme.ink)
                    Label(String(format: "%.1f km", RadarViewModel.distanceKm(report, from: location.coordinate)), systemImage: "location.fill").font(.rounded(.subheadline)).foregroundStyle(Theme.ink)
                    Label((report.createdAt ?? Date()).formatted(date: .abbreviated, time: .shortened), systemImage: "calendar").font(.rounded(.subheadline)).foregroundStyle(Theme.ink)
                    if let n = report.notes, !n.isEmpty { Text(n).font(.rounded(.body)).foregroundStyle(Theme.inkSoft).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Theme.inkSoft.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous)) }

                    // Look Around street-level preview (not available in every country)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("radar.lookaround")).font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink)
                        if let lookAround {
                            LookAroundPreview(initialScene: lookAround).frame(height: 170).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        } else if lookChecked {
                            Text(tr("radar.no_lookaround")).font(.rounded(.footnote)).foregroundStyle(Theme.inkSoft)
                        } else { SkeletonBlock(height: 120) }
                    }

                    VStack(spacing: 10) {
                        Button { dismiss(); onRoute() } label: { Label(tr("radar.route"), systemImage: "car.fill") }.buttonStyle(PrimaryButtonStyle())
                        HStack {
                            Button {
                                let item = MKMapItem(placemark: MKPlacemark(coordinate: report.coordinate)); item.name = report.disease?.displayName
                                item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                            } label: { Label(tr("radar.directions"), systemImage: "arrow.triangle.turn.up.right.diamond.fill") }.buttonStyle(.bordered)
                            ShareLink(item: "AgriNova • \(report.disease?.displayName ?? "") • \(String(format: "%.4f, %.4f", report.latitude, report.longitude))") { Label(tr("common.share"), systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                        }
                    }
                }.padding(20)
            }
            .navigationTitle(tr("radar.report_detail")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("common.done")) { dismiss() } } }
            .task {
                lookAround = try? await MKLookAroundSceneRequest(coordinate: report.coordinate).scene
                lookChecked = true
            }
        }
    }
}

struct DiseasePickerSheet: View {
    let onPick: (Disease) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(DiseaseCatalog.diseasesOnly) { d in
                Button { dismiss(); onPick(d) } label: {
                    HStack(spacing: 12) {
                        Image(d.imageName).resizable().scaledToFill().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text(d.displayName).font(.rounded(.body, weight: .semibold)).foregroundStyle(Theme.ink)
                    }
                }
            }
            .navigationTitle(tr("radar.pick")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button(tr("common.cancel")) { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}
