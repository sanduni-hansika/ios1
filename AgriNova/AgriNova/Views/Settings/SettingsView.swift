import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SyncService.self) private var sync
    @Environment(\.managedObjectContext) private var ctx
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var confirmReset = false
    @State private var confirmSignOut = false

    var body: some View {
        @Bindable var s = settings
        ScrollView {
            VStack(spacing: 18) {
                profileCard
                section(tr("set.language"), "globe") { LanguagePicker().frame(maxWidth: .infinity, alignment: .leading) }
                section(tr("set.appearance"), "paintbrush.fill") {
                    Picker("", selection: $s.theme) {
                        ForEach(ThemeMode.allCases) { m in Label(tr("set.theme.\(m.rawValue)"), systemImage: m.icon).tag(m) }
                    }.pickerStyle(.segmented)
                }
                section(tr("set.notifications"), "bell.badge.fill") {
                    Toggle(tr("set.notif_toggle"), isOn: $s.notificationsEnabled).tint(Theme.leaf)
                    if notifStatus == .denied { Banner(kind: .warning, title: tr("set.notif_denied")); Button(tr("set.open_settings")) { openSystemSettings() }.font(.rounded(.subheadline, weight: .semibold)) }
                    Button { Task { await NotificationService.requestAuthorization(); NotificationService.fireNow(title: "AgriNova", body: tr("set.notif_test_body")); await refreshStatus() } } label: { Label(tr("set.notif_test"), systemImage: "bell.and.waves.left.and.right") }
                        .font(.rounded(.subheadline, weight: .semibold))
                }
                section(tr("set.sync"), "arrow.triangle.2.circlepath.icloud.fill") {
                    Toggle(tr("set.icloud"), isOn: $s.cloudSyncEnabled).tint(Theme.leaf)
                    Text(tr("set.icloud_note")).font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
                    Divider()
                    infoRow(tr("set.backend"), sync.backendName)
                    infoRow(tr("set.network"), sync.isOnline ? tr("set.online") : tr("set.offline_mode"))
                    infoRow(tr("set.queue"), "\(sync.pendingCount)")
                    infoRow(tr("set.last_sync"), sync.lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    if let e = sync.lastError { Text(e).font(.rounded(.caption)).foregroundStyle(Theme.danger) }
                    Button { Task { await sync.syncNow(); ToastCenter.shared.show(tr("set.synced")) } } label: { Label(sync.isSyncing ? tr("radar.syncing") : tr("set.sync_now"), systemImage: "arrow.clockwise") }
                        .buttonStyle(PrimaryButtonStyle(compact: true)).disabled(sync.isSyncing)
                }
                section(tr("set.quick"), "lock.shield.fill") {
                    Text(tr("set.quick_note")).font(.rounded(.footnote)).foregroundStyle(Theme.inkSoft)
                    Toggle(isOn: $s.allowFaceID) { Label("Face ID", systemImage: "faceid") }.tint(Theme.leaf)
                    Toggle(isOn: $s.allowTouchID) { Label("Touch ID", systemImage: "touchid") }.tint(Theme.leaf)
                    Toggle(isOn: $s.allowGoogle) { Label("Google", systemImage: "g.circle.fill") }.tint(Theme.leaf)
                    Toggle(isOn: $s.allowApple) { Label("Apple ID", systemImage: "apple.logo") }.tint(Theme.leaf)
                    infoRow(tr("set.device_bio"), AuthService.biometryType == .faceID ? "Face ID" : (AuthService.biometryType == .touchID ? "Touch ID" : tr("set.none_available")))
                }
                section(tr("set.detection"), "dial.medium.fill") {
                    VStack(alignment: .leading) {
                        Text("\(tr("set.threshold")): \(Int(settings.confidenceThreshold * 100))%").font(.rounded(.subheadline, weight: .semibold))
                        Slider(value: $s.confidenceThreshold, in: 0.5...0.9, step: 0.05).tint(Theme.leaf)
                        Text(tr("set.threshold_note")).font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
                    }
                }
                section(tr("set.data"), "externaldrive.fill") {
                    NavigationLink { SeedConsoleView() } label: { rowLabel(tr("seed.title"), "wand.and.stars") }
                    Button(role: .destructive) { confirmReset = true } label: { Label(tr("set.reset"), systemImage: "trash.fill").font(.rounded(.subheadline, weight: .semibold)) }
                }
                section(tr("set.about"), "info.circle.fill") {
                    infoRow(tr("set.version"), "1.0 (1)")
                    Text(tr("set.about_text")).font(.rounded(.caption)).foregroundStyle(Theme.inkSoft)
                }
                Button(role: .destructive) { confirmSignOut = true } label: { Label(tr("set.sign_out"), systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity).padding(.vertical, 14) }
                    .buttonStyle(SoftButtonStyle(radius: 22))
            }.padding(20).readableWidth(720)
        }
        .task { await refreshStatus() }
        .confirmationDialog(tr("set.reset_confirm"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(tr("set.reset"), role: .destructive) { resetAll() }
        } message: { Text(tr("set.reset_msg")) }
        .confirmationDialog(tr("set.sign_out"), isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(tr("set.sign_out"), role: .destructive) { AuthService.signOut() }
        }
    }

    private var profileCard: some View {
        NavigationLink { ProfileView() } label: {
            HStack(spacing: 16) {
                AvatarView(size: 70)
                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.userName.isEmpty ? tr("dash.farmer") : settings.userName).font(.rounded(.title3, weight: .bold)).foregroundStyle(Theme.ink)
                    Text("@\(settings.username)").font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft)
                    Text(tr("prof.view")).font(.rounded(.caption, weight: .semibold)).foregroundStyle(Theme.leaf)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.inkSoft)
            }.padding(18).softCard()
        }.buttonStyle(CardPressStyle())
    }

    private func section<C: View>(_ title: String, _ icon: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).softCard()
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack { Text(k).font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft); Spacer(); Text(v).font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing) }
            .accessibilityElement(children: .combine)
    }
    private func rowLabel(_ t: String, _ icon: String) -> some View {
        HStack { Label(t, systemImage: icon).font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(Theme.ink); Spacer(); Image(systemName: "chevron.right").foregroundStyle(Theme.inkSoft) }
    }

    private func refreshStatus() async { notifStatus = await NotificationService.status() }
    private func openSystemSettings() { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }

    private func resetAll() {
        NotificationService.cancelAll()
        PersistenceController.shared.wipeAll()
        UserDefaults.standard.removeObject(forKey: WeatherService.cacheKey)
        try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent("demo_backend.json"))
        LocationService.shared.apply([])
        settings.resetPreferences()
        SyncService.shared.refreshPending()
        WidgetUpdater.refresh()
        ToastCenter.shared.show(tr("set.reset_done"))
    }
}
