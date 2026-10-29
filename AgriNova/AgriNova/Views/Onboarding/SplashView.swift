import SwiftUI

struct LanguagePicker: View {
    @Environment(AppSettings.self) private var settings
    var body: some View {
        HStack(spacing: 10) {
            ForEach(AppLanguage.allCases) { lang in
                let selected = settings.language == lang
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { settings.language = lang }
                } label: {
                    HStack(spacing: 6) {
                        Text(lang.flag)
                        Text(lang.nativeName).font(.rounded(.subheadline, weight: .semibold))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .foregroundStyle(selected ? .white : Theme.ink)
                    .background {
                        if selected { Capsule().fill(Theme.heroGradient) }
                        else { Capsule().fill(Theme.surface)
                            .shadow(color: .black.opacity(0.12), radius: 5, x: 3, y: 3)
                            .shadow(color: .white.opacity(0.7), radius: 5, x: -3, y: -3) }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lang.nativeName)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: settings.language)
    }
}

/// Animated launch screen: leaf grows, logo pops, tagline fades in; language can be chosen right here.
struct SplashView: View {
    let onFinish: () -> Void
    @State private var appear = false
    @State private var pulse = false
    @State private var progress = 0.0

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                ForEach(0..<3) { i in
                    Circle().stroke(Theme.leaf.opacity(0.25 - Double(i) * 0.07), lineWidth: 2)
                        .frame(width: 150 + CGFloat(i) * 46, height: 150 + CGFloat(i) * 46)
                        .scaleEffect(pulse ? 1.08 : 0.92)
                        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(Double(i) * 0.2), value: pulse)
                }
                LeafLogo(size: 128).scaleEffect(appear ? 1 : 0.4).rotationEffect(.degrees(appear ? 0 : -25)).opacity(appear ? 1 : 0)
            }
            VStack(spacing: 8) {
                Text("AgriNova").font(.system(size: 42, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                Text(tr("splash.tagline")).font(.rounded(.headline)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
            }
            .offset(y: appear ? 0 : 20).opacity(appear ? 1 : 0)
            Spacer()
            VStack(spacing: 16) {
                LanguagePicker()
                ProgressView(value: progress).tint(Theme.leaf).frame(width: 160)
                    .accessibilityLabel(tr("common.loading"))
            }
            .padding(.bottom, 40).opacity(appear ? 1 : 0)
        }
        .padding(.horizontal, 24)
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.6)) { appear = true }
            pulse = true
            withAnimation(.linear(duration: 2.4)) { progress = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) { onFinish() }
        }
    }
}
