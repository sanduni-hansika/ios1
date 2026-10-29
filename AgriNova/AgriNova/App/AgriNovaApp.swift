import SwiftUI

@main
struct AgriNovaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = AppSettings.shared
    @Environment(\.scenePhase) private var phase
    private let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .environment(settings)
                .environment(SyncService.shared)
                .environment(LocationService.shared)
                .environment(AppRouter.shared)
                .preferredColorScheme(settings.theme.colorScheme)
                .toastOverlay()
                .onOpenURL { AuthService.handle(url: $0) }
                .onChange(of: phase) { _, new in
                    if new == .active {
                        SyncService.shared.appBecameActive()
                        LocationService.shared.start()
                        LocationService.shared.syncGeofences(from: persistence.viewContext)
                        WidgetUpdater.refresh()
                    }
                }
                .onChange(of: settings.language) { _, _ in settings.persist(); WidgetUpdater.refresh() }
                .onChange(of: settings.theme) { _, _ in settings.persist() }
                .onChange(of: settings.notificationsEnabled) { _, _ in settings.persist() }
                .onChange(of: settings.cloudSyncEnabled) { _, _ in settings.persist() }
                .onChange(of: settings.allowFaceID) { _, _ in settings.persist() }
                .onChange(of: settings.allowTouchID) { _, _ in settings.persist() }
                .onChange(of: settings.allowGoogle) { _, _ in settings.persist() }
                .onChange(of: settings.allowApple) { _, _ in settings.persist() }
                .onChange(of: settings.confidenceThreshold) { _, _ in settings.persist() }
                .onChange(of: settings.userName) { _, _ in settings.persist() }
        }
    }
}

/// Splash → Onboarding → Sign-in → Main app.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @State private var splashDone = false

    var body: some View {
        ZStack {
            AppBackground()
            if !splashDone {
                SplashView { withAnimation(.easeInOut(duration: 0.6)) { splashDone = true } }
                    .transition(.opacity)
            } else if !settings.hasOnboarded {
                OnboardingView().transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            } else if !settings.isSignedIn {
                AuthView().transition(.opacity)
            } else {
                MainShell().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: settings.hasOnboarded)
        .animation(.easeInOut(duration: 0.45), value: settings.isSignedIn)
    }
}
