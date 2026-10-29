import SwiftUI

/// Adaptive shell: floating tab bar on iPhone, sidebar (NavigationSplitView) on iPad / large screens.
struct MainShell: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(AppRouter.self) private var router
    @Environment(\.managedObjectContext) private var ctx
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        Group {
            if hSize == .regular { splitLayout } else { phoneLayout }
        }
        .task {
            LocationService.shared.requestPermission()
            LocationService.shared.start()
            LocationService.shared.syncGeofences(from: ctx)
        }
    }

    // MARK: iPad
    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: Binding(get: { Optional(router.selected) }, set: { if let v = $0 { router.selected = v } })) {
                Section {
                    HStack(spacing: 12) {
                        LeafLogo(size: 44)
                        VStack(alignment: .leading) {
                            Text("AgriNova").font(.rounded(.title3, weight: .bold))
                            Text(tr("splash.tagline_short")).font(.rounded(.caption)).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6).listRowBackground(Color.clear)
                }
                ForEach(AppSection.allCases) { s in
                    Label(tr(s.titleKey), systemImage: s.icon).tag(s).font(.rounded(.body, weight: .medium))
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 320)
        } detail: {
            SectionContainer(section: router.selected).id(router.selected)
        }
        .tint(Theme.leaf)
    }

    // MARK: iPhone
    private var phoneLayout: some View {
        ZStack(alignment: .bottom) {
            SectionContainer(section: router.selected).id(router.selected)
                .transition(.opacity)
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 78) }
            FloatingTabBar()
        }
        .ignoresSafeArea(.keyboard)
    }
}

/// One NavigationStack per section so each keeps a clean back-stack.
struct SectionContainer: View {
    let section: AppSection
    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                switch section {
                case .dashboard: DashboardView()
                case .scan: ScanView()
                case .library: LibraryView()
                case .treatments: TreatmentsView()
                case .farm: FarmListView()
                case .radar: RadarView()
                case .insights: InsightsView()
                case .history: HistoryView()
                case .settings: SettingsView()
                }
            }
            .navigationTitle(tr(section.titleKey))
            .navigationBarTitleDisplayMode(section == .dashboard ? .inline : .large)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .tint(Theme.leaf)
    }
}

struct FloatingTabBar: View {
    @Environment(AppRouter.self) private var router
    @Namespace private var ns
    private let items: [AppSection] = [.dashboard, .library, .scan, .farm, .radar]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                if item == .scan { scanButton } else { tab(item) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
        .padding(.horizontal, 18).padding(.bottom, 6)
        .sensoryFeedback(.selection, trigger: router.selected)
    }

    private func tab(_ s: AppSection) -> some View {
        let on = router.selected == s
        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { router.selected = s }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: s.icon).font(.system(size: 19, weight: .semibold))
                    .symbolEffect(.bounce, value: on)
                Text(tr(s.titleKey)).font(.system(size: 10, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(on ? Theme.leafDeep : Theme.inkSoft)
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background {
                if on { Capsule().fill(Theme.leaf.opacity(0.18)).matchedGeometryEffect(id: "pill", in: ns) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr(s.titleKey))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var scanButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { router.selected = .scan }
        } label: {
            Image(systemName: "camera.viewfinder").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                .frame(width: 62, height: 62).background(Theme.heroGradient, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
                .shadow(color: Theme.leaf.opacity(0.55), radius: 12, y: 6)
                .offset(y: -14)
        }
        .frame(maxWidth: .infinity).buttonStyle(.plain)
        .accessibilityLabel(tr("nav.scan"))
    }
}
