import SwiftUI
import CoreLocation
import CoreData

struct DashboardView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(LocationService.self) private var location
    @Environment(SyncService.self) private var sync
    @State private var vm = DashboardViewModel()

    @FetchRequest(sortDescriptors: [SortDescriptor(\CDScan.date, order: .reverse)]) private var scans: FetchedResults<CDScan>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDTask.sortOrder)], predicate: NSPredicate(format: "done == NO")) private var openTasks: FetchedResults<CDTask>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDOutbreak.createdAt, order: .reverse)]) private var outbreaks: FetchedResults<CDOutbreak>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDFarm.createdAt)]) private var farms: FetchedResults<CDFarm>

    private var nearby: [CDOutbreak] {
        let here = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        return outbreaks.filter { ($0.createdAt ?? .distantPast) >= cutoff && here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= 25_000 }
    }
    private var unhealthyCount: Int { scans.filter { !$0.isHealthy }.count }
    private var activeTreatments: Int { Set(openTasks.compactMap(\.scanID)).count }
    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 18, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if case .loaded(let w, _) = vm.weather, w.fungalRisk == .high {
                    Banner(kind: .warning, title: tr("risk.high_title"), message: tr("risk.high_body"))
                        .transition(.scale.combined(with: .opacity))
                }
                LazyVGrid(columns: columns, spacing: 18) {
                    weatherCard
                    statsGrid
                    quickActions
                    lastScanCard
                    pendingCard
                    outbreakCard
                }
            }
            .padding(20).readableWidth(1100)
        }
        .refreshable { await vm.load(location: location.coordinate); await sync.syncNow() }
        .task(id: location.hasFix) { await vm.load(location: location.coordinate) }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: scans.count)
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.rounded(.footnote, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                Text("\(tr("dash.hello")), \(settings.userName.isEmpty ? tr("dash.farmer") : settings.userName) 👋")
                    .font(.rounded(.title, weight: .bold)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                Text(farms.first?.displayName ?? tr("dash.no_farm")).font(.rounded(.subheadline)).foregroundStyle(Theme.leaf)
            }
            Spacer()
            NavigationLink { ProfileView() } label: { AvatarView(size: 52) }
                .buttonStyle(CardPressStyle()).accessibilityLabel(tr("prof.title"))
        }
    }

    // MARK: Weather
    @ViewBuilder private var weatherCard: some View {
        switch vm.weather {
        case .loading:
            SkeletonBlock(height: 200)
        case .failed(let msg):
            VStack(spacing: 10) {
                Banner(kind: .error, title: tr("weather.error"), message: msg)
                Button(tr("common.retry")) { Task { await vm.load(location: location.coordinate) } }.buttonStyle(PrimaryButtonStyle(compact: true))
            }.padding(16).softCard()
        case .loaded(let w, let stale):
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(tr("weather.title"), systemImage: "cloud.sun.fill").font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.inkSoft)
                    Spacer()
                    if stale { Chip(text: tr("common.cached"), icon: "arrow.triangle.2.circlepath", color: Theme.sun) }
                    else { Chip(text: "Open-Meteo", icon: "antenna.radiowaves.left.and.right", color: Theme.sky) }
                }
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 52))
                        .symbolEffect(.pulse, options: .repeating)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(w.temperature.rounded()))°C").font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                        Text("↑\(Int(w.tempMax))°  ↓\(Int(w.tempMin))°").font(.rounded(.footnote)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        metric("humidity", "\(Int(w.humidity))%", tr("weather.humidity"))
                        metric("cloud.rain.fill", "\(Int(w.rainChance))%", tr("weather.rain"))
                    }
                }
                HStack(spacing: 10) {
                    Image(systemName: w.fungalRisk.icon).foregroundStyle(w.fungalRisk.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(tr("weather.fungal_risk")): \(tr(w.fungalRisk.titleKey))").font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.ink)
                        Text(DashboardViewModel.sprayAdvice(w)).font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                }
                .padding(12).background(w.fungalRisk.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            .padding(18).softCard()
        }
    }

    private func metric(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(Theme.sky)
            Text(value).font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(label) \(value)")
    }

    // MARK: Stats
    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
            stat("camera.viewfinder", "\(scans.count)", tr("dash.scans"), Theme.heroGradient)
            stat("exclamationmark.triangle.fill", "\(unhealthyCount)", tr("dash.unhealthy"), Theme.dangerGradient)
            stat("cross.case.fill", "\(activeTreatments)", tr("dash.treatments"), Theme.sunGradient)
            stat("dot.radiowaves.left.and.right", "\(nearby.count)", tr("dash.nearby"), Theme.skyGradient)
        }
    }

    private func stat(_ icon: String, _ value: String, _ label: String, _ g: LinearGradient) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            IconBadge(icon: icon, gradient: g, size: 38)
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink).contentTransition(.numericText())
            Text(label).font(.rounded(.caption, weight: .semibold)).foregroundStyle(Theme.inkSoft).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16).softCard(radius: 22, depth: 8)
        .accessibilityElement(children: .ignore).accessibilityLabel("\(label): \(value)")
    }

    // MARK: Quick actions
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: tr("dash.quick"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                action(.scan, Theme.heroGradient); action(.treatments, Theme.sunGradient)
                action(.insights, Theme.skyGradient); action(.history, Theme.dangerGradient)
            }
        }.padding(18).softCard()
    }

    private func action(_ s: AppSection, _ g: LinearGradient) -> some View {
        Button { withAnimation(.spring) { router.go(s) } } label: {
            VStack(spacing: 8) {
                IconBadge(icon: s.icon, gradient: g, size: 52)
                Text(tr(s.titleKey)).font(.rounded(.caption2, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.6)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
    }

    // MARK: Last scan
    @ViewBuilder private var lastScanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: tr("dash.last_scan"), actionTitle: scans.isEmpty ? nil : tr("common.all")) { router.go(.history) }
            if let s = scans.first {
                NavigationLink { ScanResultView(scan: s) } label: {
                    HStack(spacing: 14) {
                        if let img = s.image { Image(uiImage: img).resizable().scaledToFill().frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)) }
                        VStack(alignment: .leading, spacing: 6) {
                            StatusBadge(isHealthy: s.isHealthy)
                            Text(s.disease?.displayName ?? "—").font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink)
                            Text("\(Int((s.confidence * 100).rounded()))% • \((s.date ?? Date()).formatted(.relative(presentation: .named)))").font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(Theme.inkSoft)
                    }
                }.buttonStyle(.plain)
            } else {
                EmptyStateView(icon: "camera.viewfinder", title: tr("dash.no_scans"), message: tr("dash.no_scans_msg"), actionTitle: tr("nav.scan")) { router.go(.scan) }
            }
        }.padding(18).softCard()
    }

    // MARK: Pending treatments
    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: tr("dash.pending"), actionTitle: openTasks.isEmpty ? nil : tr("common.all")) { router.go(.treatments) }
            if openTasks.isEmpty {
                Label(tr("dash.no_pending"), systemImage: "checkmark.circle.fill").font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft).padding(.vertical, 6)
            } else {
                ForEach(openTasks.prefix(3)) { t in
                    HStack(spacing: 10) {
                        Image(systemName: "circle").foregroundStyle(Theme.sun)
                        Text(t.title ?? "").font(.rounded(.subheadline)).foregroundStyle(Theme.ink).lineLimit(2)
                        Spacer()
                    }
                }
            }
        }.padding(18).softCard()
    }

    // MARK: Outbreaks
    private var outbreakCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: tr("dash.outbreaks"), actionTitle: tr("nav.radar")) { router.go(.radar) }
            if nearby.isEmpty {
                Label(tr("dash.no_outbreaks"), systemImage: "checkmark.shield.fill").font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft).padding(.vertical, 6)
            } else {
                ForEach(nearby.prefix(3)) { o in
                    HStack(spacing: 12) {
                        IconBadge(icon: o.disease?.pathogen.icon ?? "leaf.fill", gradient: o.severity >= 3 ? Theme.dangerGradient : Theme.sunGradient, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.disease?.displayName ?? "").font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.ink)
                            Text(String(format: "%.1f km • %@", CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude).distance(from: CLLocation(latitude: o.latitude, longitude: o.longitude)) / 1000, (o.createdAt ?? Date()).formatted(.relative(presentation: .named))))
                                .font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                    }
                }
            }
        }.padding(18).softCard()
    }
}
