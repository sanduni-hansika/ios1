import SwiftUI
import CoreData
import CoreLocation

/// Result of a saved scan. Used embedded in the scanner and as a detail screen from history / dashboard.
struct ScanResultView: View {
    @ObservedObject var scan: CDScan
    var embedded = false
    var onRescan: (() -> Void)? = nil

    @Environment(\.managedObjectContext) private var ctx
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var showReport = false
    @State private var showOutbreak = false
    @State private var pdfURL: URL?
    @State private var showZonePicker = false
    @State private var navigateToTreatment = false
    @State private var markZone: CDZone?
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDZone.name)]) private var zones: FetchedResults<CDZone>

    private var disease: Disease? { scan.disease }
    private var lowConfidence: Bool { scan.needsRescan }
    private var weather: WeatherSnapshot? { WeatherService.cached() }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if hSize == .regular && !embedded { regularLayout } else { compactLayout }
            }
            .padding(embedded ? 0 : 20).readableWidth(1000)
        }
        .navigationTitle(embedded ? "" : tr("scan.result"))
        .navigationBarTitleDisplayMode(.inline)
        .background { if !embedded { AppBackground() } }
        .sheet(isPresented: $showOutbreak) { if let d = disease { ReportOutbreakSheet(disease: d, scan: scan) } }
        .sheet(isPresented: $showReport) { if let pdfURL { PDFViewerSheet(url: pdfURL) } }
        .navigationDestination(isPresented: $navigateToTreatment) { TreatmentDetailView(scan: scan) }
    }

    private var compactLayout: some View {
        VStack(spacing: 20) { hero; if lowConfidence { lowConfidencePanel } else { details }; actions }
    }

    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 20) { hero; actions }.frame(maxWidth: 420)
            VStack(spacing: 20) { if lowConfidence { lowConfidencePanel } else { details } }
        }
    }

    // MARK: Hero
    private var hero: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .bottomLeading) {
                if let img = scan.image {
                    Image(uiImage: img).resizable().scaledToFill().frame(height: 250).frame(maxWidth: .infinity).clipped()
                }
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 8) {
                    StatusBadge(isHealthy: scan.isHealthy, large: true)
                    Text(lowConfidence ? tr("scan.uncertain") : (disease?.displayName ?? "—"))
                        .font(.rounded(.title, weight: .bold)).foregroundStyle(.white)
                    if !lowConfidence, let d = disease, !d.isHealthy {
                        Text(d.scientific).font(.rounded(.footnote)).italic().foregroundStyle(.white.opacity(0.85))
                    }
                }.padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 16, y: 10)

            HStack(spacing: 18) {
                ConfidenceRing(value: scan.confidence, tint: lowConfidence ? Theme.sun : (scan.isHealthy ? Theme.leaf : Theme.danger))
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) { Chip(text: Species.tomatoName.localized, icon: "leaf.fill"); if let d = disease { Chip(text: tr(d.pathogen.titleKey), icon: d.pathogen.icon, color: d.pathogen.color) } }
                    if !lowConfidence && !scan.isHealthy {
                        HStack {
                            Text("\(Int(scan.affectedPercent))%").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(Theme.danger)
                            Text(tr("treat.affected")).font(.rounded(.footnote)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    Text((scan.date ?? Date()).formatted(date: .abbreviated, time: .shortened)).font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
            }.padding(18).softCard()
        }
    }

    // MARK: Low confidence
    private var lowConfidencePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Banner(kind: .warning, title: tr("scan.low_title", Int((scan.confidence * 100).rounded())), message: tr("scan.low_msg"))
            ForEach(["scan.tip1", "scan.tip2", "scan.tip3"], id: \.self) { k in
                Label(tr(k), systemImage: "arrow.right.circle.fill").font(.rounded(.subheadline)).foregroundStyle(Theme.ink)
            }
            if let onRescan {
                Button { onRescan() } label: { Label(tr("scan.rescan"), systemImage: "arrow.counterclockwise.camera.fill") }.buttonStyle(PrimaryButtonStyle(gradient: Theme.sunGradient))
            }
            predictionsList
        }.padding(18).softCard()
    }

    // MARK: Details
    @ViewBuilder private var details: some View {
        VStack(spacing: 20) {
            earlyWarning
            // Species introduction
            VStack(alignment: .leading, spacing: 10) {
                Label("\(tr("scan.species")): \(Species.tomatoName.localized)", systemImage: "leaf.fill").font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink)
                Text(Species.tomatoIntro.localized).font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18).softCard()

            if let d = disease {
                VStack(alignment: .leading, spacing: 12) {
                    Label(d.displayName, systemImage: d.pathogen.icon).font(.rounded(.headline, weight: .bold)).foregroundStyle(d.pathogen.color)
                    Text(d.displaySummary).font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft)
                    Divider()
                    Text(d.isHealthy ? tr("scan.healthy_signs") : tr("scan.matched_symptoms")).font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.ink)
                    ForEach(d.symptoms, id: \.self) { s in
                        Label { Text(s).font(.rounded(.subheadline)).foregroundStyle(Theme.ink) } icon: {
                            Image(systemName: d.isHealthy ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(d.isHealthy ? Theme.leaf : Theme.danger)
                        }
                    }
                    NavigationLink { DiseaseDetailView(disease: d) } label: {
                        HStack { Text(tr("scan.learn_more")); Spacer(); Image(systemName: "chevron.right") }
                            .font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(Theme.leaf)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18).softCard()
            }
            predictionsList.padding(18).softCard()
        }
    }

    @ViewBuilder private var earlyWarning: some View {
        if let w = weather, w.fungalRisk != .low {
            if let d = disease, d.isHealthy {
                Banner(kind: .info, title: tr("scan.warn_healthy_title"), message: tr("scan.warn_healthy_body", tr(w.fungalRisk.titleKey)))
            } else if let d = disease, d.isMoistureDriven {
                Banner(kind: w.fungalRisk == .high ? .error : .warning, title: tr("scan.warn_title"), message: tr("scan.warn_body", Int(w.avgHumidity72h), Int(w.maxRainChance72h)))
            }
        }
    }

    private var predictionsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("scan.top_matches")).font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.ink)
            ForEach(ScanStore.topPredictions(scan).prefix(3), id: \.label) { p in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(DiseaseCatalog.find(p.label)?.displayName ?? p.label).font(.rounded(.footnote)); Spacer(); Text("\(Int((p.confidence * 100).rounded()))%").font(.rounded(.footnote, weight: .bold)) }
                        .foregroundStyle(Theme.ink)
                    GeometryReader { g in
                        Capsule().fill(Theme.leaf.opacity(0.15)).overlay(alignment: .leading) { Capsule().fill(Theme.heroGradient).frame(width: g.size.width * p.confidence) }
                    }.frame(height: 7)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Actions
    private var actions: some View {
        VStack(spacing: 12) {
            if !lowConfidence, let d = disease, !d.isHealthy {
                Button {
                    TreatmentService.start(scan: scan, in: ctx)
                    ToastCenter.shared.show(tr("treat.started_toast"))
                    navigateToTreatment = true
                } label: { Label(scan.treatmentStarted ? tr("treat.open") : tr("treat.start"), systemImage: "cross.case.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                Button { showOutbreak = true } label: { Label(tr("radar.report"), systemImage: "megaphone.fill").frame(maxWidth: .infinity).padding(.vertical, 14) }
                    .buttonStyle(SoftButtonStyle(radius: 26)).foregroundStyle(Theme.danger)
            }
            if !lowConfidence, let d = disease, !d.isHealthy {
                Menu {
                    ForEach(zones) { z in Button(z.displayName) { markInfected(in: z) } }
                    Button(tr("common.none")) { markInfected(in: nil) }
                } label: { Label(tr("farm.mark_here"), systemImage: "mappin.and.ellipse").font(.rounded(.subheadline, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14) }
                    .buttonStyle(SoftButtonStyle(radius: 22))
            }
            HStack(spacing: 12) {
                if let img = scan.image {
                    ShareLink(item: Image(uiImage: img), subject: Text("AgriNova"), message: Text(shareText),
                              preview: SharePreview(disease?.displayName ?? "AgriNova", image: Image(uiImage: img))) {
                        Label(tr("common.share"), systemImage: "square.and.arrow.up").font(.rounded(.subheadline, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                    }.buttonStyle(SoftButtonStyle(radius: 22))
                }
                Button {
                    pdfURL = ReportService.scanReport(scan, in: ctx); showReport = true
                } label: { Label(tr("pdf.report"), systemImage: "doc.richtext.fill").font(.rounded(.subheadline, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14) }
                    .buttonStyle(SoftButtonStyle(radius: 22))
            }
            if embedded, let onRescan {
                Button { onRescan() } label: { Label(tr("scan.again"), systemImage: "camera.viewfinder").frame(maxWidth: .infinity).padding(.vertical, 14) }
                    .buttonStyle(SoftButtonStyle(radius: 22))
            }
        }
    }

    /// Drops an infected-plant marker at the scan's GPS fix (or the current location) – step 17 of the brief.
    private func markInfected(in zone: CDZone?) {
        let c = scan.hasLocation ? CLLocationCoordinate2D(latitude: scan.latitude, longitude: scan.longitude) : LocationService.shared.coordinate
        FarmViewModel.markInfected(disease: disease, coordinate: c, note: tr("farm.from_scan"), zone: zone)
        if let zone { scan.zoneID = zone.id; scan.zoneName = zone.name; PersistenceController.shared.save() }
        ToastCenter.shared.show(tr("farm.marked"))
    }

    private var shareText: String {
        let d = disease?.displayName ?? "?"
        let loc = scan.hasLocation ? String(format: " (%.4f, %.4f)", scan.latitude, scan.longitude) : ""
        return "AgriNova • \(Species.tomatoName.localized): \(scan.isHealthy ? tr("status.healthy") : tr("status.unhealthy")) – \(d) • \(Int((scan.confidence * 100).rounded()))%\(loc)"
    }
}
