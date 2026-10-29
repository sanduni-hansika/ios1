import SwiftUI

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Theme.heroGradient
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(compact ? .subheadline : .headline, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, compact ? 10 : 15)
            .padding(.horizontal, compact ? 16 : 22)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(gradient, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: Theme.leafDeep.opacity(configuration.isPressed ? 0.15 : 0.40),
                    radius: configuration.isPressed ? 4 : 12, y: configuration.isPressed ? 2 : 8)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct SoftButtonStyle: ButtonStyle {
    var radius: CGFloat = 18
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.ink)
            .softCard(radius: radius, depth: configuration.isPressed ? 3 : 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SoftCircleButton: View {
    let icon: String
    var tint: Color = Theme.leafDeep
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(SoftButtonStyle(radius: 22))
        .accessibilityLabel(label)
    }
}

// MARK: - Small building blocks

struct Chip: View {
    let text: String
    var icon: String? = nil
    var color: Color = Theme.leaf
    var filled = false
    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.caption.weight(.bold)) }
            Text(text).font(.rounded(.caption, weight: .semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .foregroundStyle(filled ? .white : color)
        .background(filled ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.14)), in: Capsule())
    }
}

/// Healthy / Unhealthy label – always icon + text so it never relies on colour alone.
struct StatusBadge: View {
    let isHealthy: Bool
    var large = false
    var body: some View {
        Label(isHealthy ? tr("status.healthy") : tr("status.unhealthy"),
              systemImage: isHealthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            .font(.rounded(large ? .headline : .caption, weight: .bold))
            .padding(.horizontal, large ? 16 : 10).padding(.vertical, large ? 10 : 6)
            .foregroundStyle(.white)
            .background(isHealthy ? Theme.heroGradient : Theme.dangerGradient, in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

struct ConfidenceRing: View {
    let value: Double          // 0...1
    var size: CGFloat = 92
    var tint: Color = Theme.leaf
    @State private var shown = 0.0
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: size * 0.12)
            Circle().trim(from: 0, to: shown)
                .stroke(AngularGradient(colors: [tint.opacity(0.6), tint], center: .center),
                        style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int((value * 100).rounded()))%").font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                Text(tr("scan.confidence")).font(.system(size: size * 0.11, weight: .medium, design: .rounded)).foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(.easeOut(duration: 1.0)) { shown = value } }
        .onChange(of: value) { _, v in withAnimation(.easeOut(duration: 0.8)) { shown = v } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tr("scan.confidence")) \(Int((value * 100).rounded())) %")
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack {
            Text(title).font(.rounded(.title3, weight: .bold)).foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(Theme.leaf)
            }
        }
    }
}

struct IconBadge: View {
    let icon: String
    var gradient: LinearGradient = Theme.heroGradient
    var size: CGFloat = 44
    var body: some View {
        Image(systemName: icon).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(gradient, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 4)
            .accessibilityHidden(true)
    }
}

// MARK: - Feedback states

enum BannerKind {
    case info, success, warning, error
    var color: Color { switch self { case .info: Theme.sky; case .success: Theme.leaf; case .warning: Theme.sun; case .error: Theme.danger } }
    var icon: String { switch self { case .info: "info.circle.fill"; case .success: "checkmark.circle.fill"; case .warning: "exclamationmark.triangle.fill"; case .error: "xmark.octagon.fill" } }
}

struct Banner: View {
    let kind: BannerKind
    let title: String
    var message: String? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind.icon).font(.title3).foregroundStyle(kind.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.ink)
                if let message { Text(message).font(.rounded(.footnote)).foregroundStyle(Theme.inkSoft) }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(kind.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(kind.color.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @State private var float = false
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 44, weight: .light)).foregroundStyle(Theme.leaf)
                .padding(26).softCard(radius: 40)
                .offset(y: float ? -4 : 4)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: float)
            Text(title).font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.ink)
            Text(message).font(.rounded(.subheadline)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(PrimaryButtonStyle(compact: true))
            }
        }
        .padding(24).frame(maxWidth: .infinity)
        .onAppear { float = true }
    }
}

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width * 1.6)
            }.clipped().allowsHitTesting(false)
        )
        .onAppear { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 } }
    }
}
extension View { func shimmer() -> some View { modifier(Shimmer()) } }

struct SkeletonBlock: View {
    var height: CGFloat = 100
    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.inkSoft.opacity(0.12))
            .frame(height: height).shimmer().accessibilityHidden(true)
    }
}

// MARK: - Toasts

@Observable
final class ToastCenter {
    static let shared = ToastCenter()
    struct Toast: Equatable { var kind: BannerKind; var text: String; var id = UUID()
        static func == (l: Toast, r: Toast) -> Bool { l.id == r.id } }
    var current: Toast?
    func show(_ text: String, kind: BannerKind = .success) {
        let t = Toast(kind: kind, text: text)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { current = t }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            if current == t { withAnimation(.easeInOut) { current = nil } }
        }
    }
}

struct ToastOverlay: ViewModifier {
    var center = ToastCenter.shared
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let t = center.current {
                HStack(spacing: 10) {
                    Image(systemName: t.kind.icon).foregroundStyle(t.kind.color)
                    Text(t.text).font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .sensoryFeedback(trigger: center.current) { _, new in
            guard let new else { return nil }
            return new.kind == .error ? .error : .success
        }
    }
}
extension View { func toastOverlay() -> some View { modifier(ToastOverlay()) } }

// MARK: - Logo

struct LeafLogo: View {
    var size: CGFloat = 96
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Theme.heroGradient)
                .shadow(color: Theme.leaf.opacity(0.5), radius: size * 0.25, y: size * 0.1)
            Image(systemName: "leaf.fill").font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.95)).rotationEffect(.degrees(-20))
            Image(systemName: "sparkle").font(.system(size: size * 0.2, weight: .bold))
                .foregroundStyle(Theme.lime).offset(x: size * 0.26, y: -size * 0.24)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("AgriNova")
    }
}

// MARK: - Image helper

struct DiseaseImage: View {
    let disease: Disease
    var body: some View {
        Image(disease.imageName).resizable().scaledToFill()
    }
}
