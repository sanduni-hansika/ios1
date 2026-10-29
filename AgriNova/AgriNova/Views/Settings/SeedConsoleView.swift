import SwiftUI

/// Developer console for the demo / viva. Seed data flows through Apple SDKs (Vision, Core ML, Core Location,
/// UserNotifications) before it reaches app logic – see SeedService.
struct SeedConsoleView: View {
    @Environment(LocationService.self) private var location
    @Environment(\.managedObjectContext) private var ctx
    @State private var log: [String] = []
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Banner(kind: .info, title: tr("seed.rule_title"), message: tr("seed.rule"))

                card(tr("seed.farm"), "tree.fill") {
                    Text(tr("seed.farm_desc")).font(.rounded(.footnote)).foregroundStyle(Theme.inkSoft)
                    action(tr("seed.farm_btn"), "plus.circle.fill") { SeedService.seedDemoFarm(); append("✅ Demo farm + 3 zones, crops, workers saved to Core Data; geofences armed (\(location.monitored.count))") }
                }
                card(tr("seed.ml"), "brain.head.profile") {
                    Text(tr("seed.ml_desc")).font(.rounded(.footnote)).foregroundStyle(Theme.inkSoft)
                    if !LeafClassifier.shared.isModelAvailable { Banner(kind: .warning, title: tr("err.model_missing_title"), message: tr("err.model_missing")) }
                    action(tr("seed.ml_all"), "photo.stack.fill") { await runAll() }
                    ForEach(DiseaseCatalog.all) { d in
                        Button { Task { await runOne(d) } } label: {
                            HStack(spacing: 12) {
                                Image(d.imageName).resizable().scaledToFill().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text(d.displayName).font(.rounded(.subheadline)).foregroundStyle(Theme.ink)
                                Spacer(); Image(systemName: "play.circle.fill").foregroundStyle(Theme.leaf)
                            }
                        }.buttonStyle(.plain).disabled(busy)
                    }
                }
                card(tr("seed.outbreaks"), "megaphone.fill") {
                    Text(tr("seed.outbreaks_desc")).font(.rounded(.footnote)).foregroundStyle(Theme.inkSoft)
                    action(tr("seed.outbreaks_btn"), "tray.and.arrow.up.fill") { SeedService.seedOutbreaks(); append("✅ 5 outbreak reports queued → outbox → backend (\(SyncService.shared.backendName))") }
                }
                card(tr("seed.geo"), "location.circle.fill") {
                    Text(tr("seed.geo_desc")).font(.rounded(.footnote)).foregroundStyle(Theme.inkSoft)
                    infoRow(tr("seed.auth_status"), location.hasAlways ? "Always" : (location.isAuthorized ? "When in use" : "Not granted"))
                    infoRow(tr("seed.regions"), "\(location.monitored.count) / \(LocationService.maxRegions)")
                    infoRow(tr("seed.inside"), "\(location.insideZoneIDs.count)")
                    infoRow(tr("seed.last_event"), location.lastEvent.isEmpty ? "—" : location.lastEvent)
                    action(tr("seed.request_loc"), "location.fill") { location.requestPermission(); location.start() }
                    action(tr("seed.rearm"), "arrow.triangle.2.circlepath") { location.syncGeofences(from: ctx); append("Re-armed \(location.monitored.count) geofence(s)") }
                }
                card(tr("seed.notif"), "bell.fill") {
                    action(tr("seed.notif_btn"), "bell.badge.fill") {
                        await NotificationService.requestAuthorization()
                        NotificationService.fireNow(title: "AgriNova", body: tr("set.notif_test_body")); append("🔔 Local notification scheduled (1 s)")
                    }
                    action(tr("seed.recheck_btn"), "clock.badge.checkmark") {
                        await NotificationService.requestAuthorization()
                        NotificationService.schedule(id: "demo-recheck", title: "\(tr("notif.recheck_title")) – Early Blight", body: tr("notif.recheck_body", 7), after: 10, userInfo: ["route": "treatments"])
                        append("⏰ Re-check reminder scheduled in 10 s (lock the phone or go Home to see it)")
                    }
                    action(tr("seed.weather_btn"), "cloud.sun.fill") {
                        do { let w = try await WeatherService.fetch(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude); append("☁️ Open-Meteo: \(Int(w.temperature))°C, \(Int(w.humidity))% RH, risk \(w.fungalRisk.rawValue)") }
                        catch { append("❌ Weather: \(error.localizedDescription)") }
                    }
                    action(tr("seed.widget_btn"), "rectangle.on.rectangle") { WidgetUpdater.refresh(); append("🧩 Widget timelines reloaded") }
                }
                if !log.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("seed.log")).font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink)
                        ForEach(Array(log.enumerated().reversed()), id: \.offset) { _, l in Text(l).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.inkSoft) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18).softCard()
                }
            }.padding(20).readableWidth(720)
        }
        .background(AppBackground())
        .navigationTitle(tr("seed.title")).navigationBarTitleDisplayMode(.inline)
    }

    private func append(_ s: String) { log.append(s) }

    private func runOne(_ d: Disease) async {
        busy = true; defer { busy = false }
        do {
            let s = try await SeedService.classifySample(d)
            append("🔬 \(d.name[0]) → predicted \(s.disease?.name[0] ?? "?") (\(Int(s.confidence * 100))%)")
        } catch { append("❌ \(d.name[0]): \(error.localizedDescription)") }
    }
    private func runAll() async { for d in DiseaseCatalog.all { await runOne(d) } }

    private func card<C: View>(_ t: String, _ icon: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { Label(t, systemImage: icon).font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink); c() }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18).softCard()
    }
    private func action(_ title: String, _ icon: String, _ run: @escaping () async -> Void) -> some View {
        Button { Task { busy = true; await run(); busy = false } } label: { Label(title, systemImage: icon) }.buttonStyle(PrimaryButtonStyle(compact: true)).disabled(busy)
    }
    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack { Text(k).font(.rounded(.footnote)).foregroundStyle(Theme.inkSoft); Spacer(); Text(v).font(.rounded(.footnote, weight: .semibold)).foregroundStyle(Theme.ink) }
    }
}
