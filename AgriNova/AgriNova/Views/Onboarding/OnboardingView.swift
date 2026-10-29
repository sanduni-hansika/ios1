import SwiftUI

/// Single welcome screen that explains what happens in the app (language is chosen only on the splash screen).
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @State private var appear = false

    private struct Item: Identifiable { let id: Int; let icon: String; let gradient: LinearGradient; let title: String; let body: String }
    private var items: [Item] { [
        .init(id: 0, icon: "camera.viewfinder", gradient: Theme.heroGradient, title: tr("onb.1.title"), body: tr("onb.s1")),
        .init(id: 1, icon: "cross.case.fill", gradient: Theme.sunGradient, title: tr("onb.2.title"), body: tr("onb.s2")),
        .init(id: 2, icon: "map.fill", gradient: Theme.skyGradient, title: tr("onb.3.title"), body: tr("onb.s3")),
        .init(id: 3, icon: "wifi.slash", gradient: Theme.dangerGradient, title: tr("onb.4.title"), body: tr("onb.s4"))
    ] }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    LeafLogo(size: 84).scaleEffect(appear ? 1 : 0.6).opacity(appear ? 1 : 0)
                    Text(tr("onb.title")).font(.rounded(.title, weight: .bold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                    Text(tr("onb.sub")).font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                }.padding(.top, 36)

                VStack(spacing: 14) {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 14) {
                            IconBadge(icon: item.icon, gradient: item.gradient, size: 52)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink)
                                Text(item.body).font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(16).softCard(radius: 22)
                        .offset(y: appear ? 0 : 24).opacity(appear ? 1 : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1 * Double(item.id)), value: appear)
                        .accessibilityElement(children: .combine)
                    }
                }

                Button(tr("onb.start")) { finish() }.buttonStyle(PrimaryButtonStyle()).padding(.top, 6)
            }
            .padding(24).readableWidth(560)
        }
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) { appear = true } }
    }

    private func finish() {
        withAnimation { settings.hasOnboarded = true }
        settings.persist()
        Task { await NotificationService.requestAuthorization() }
    }
}
