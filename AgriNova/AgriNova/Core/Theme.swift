import SwiftUI

// MARK: - Colour helpers

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
    /// Colour that adapts to light / dark appearance.
    init(light: Color, dark: Color) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}

/// Design tokens for AgriNova's "soft 3D" (neumorphic) + glass design language.
enum Theme {
    static let leaf      = Color(hex: 0x1E9E57)
    static let leafDeep  = Color(hex: 0x0E6B3B)
    static let lime      = Color(hex: 0xB7E86C)
    static let sun       = Color(hex: 0xFFB547)
    static let danger    = Color(hex: 0xE5484D)
    static let sky       = Color(hex: 0x3F9BFF)
    static let violet    = Color(hex: 0x8B6CFF)

    static let canvas  = Color(light: Color(hex: 0xE8F0E9), dark: Color(hex: 0x0E1511))
    static let surface = Color(light: Color(hex: 0xEDF4EE), dark: Color(hex: 0x16201A))
    static let ink     = Color(light: Color(hex: 0x12261A), dark: Color(hex: 0xEAF5EC))
    static let inkSoft = Color(light: Color(hex: 0x4B6455), dark: Color(hex: 0x9DB5A4))

    static let heroGradient = LinearGradient(colors: [Color(hex: 0x23B068), Color(hex: 0x0E6B3B)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
    static let sunGradient  = LinearGradient(colors: [Color(hex: 0xFFC65C), Color(hex: 0xFF8F3F)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
    static let dangerGradient = LinearGradient(colors: [Color(hex: 0xFF6B6F), Color(hex: 0xC9303A)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
    static let skyGradient  = LinearGradient(colors: [Color(hex: 0x6CB8FF), Color(hex: 0x2F6FE0)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Soft-3D surface

struct SoftSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat
    var depth: CGFloat

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        content.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: dark ? .black.opacity(0.60) : Color(hex: 0x9FB2A5).opacity(0.60),
                        radius: depth, x: depth * 0.6, y: depth * 0.6)
                .shadow(color: dark ? .white.opacity(0.05) : .white.opacity(0.95),
                        radius: depth, x: -depth * 0.5, y: -depth * 0.5)
        )
    }
}

extension View {
    /// Raised neumorphic card.
    func softCard(radius: CGFloat = 24, depth: CGFloat = 10) -> some View {
        modifier(SoftSurface(radius: radius, depth: depth))
    }
    /// Frosted glass card used over imagery.
    func glass(radius: CGFloat = 22) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }
    /// Constrains content width on iPad so layouts stay readable.
    func readableWidth(_ width: CGFloat = 760) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }
}

// MARK: - Typography

extension Font {
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

// MARK: - Backdrop

struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Theme.canvas
            Circle().fill(Theme.leaf.opacity(scheme == .dark ? 0.16 : 0.18))
                .frame(width: 360).blur(radius: 90).offset(x: -150, y: -280)
            Circle().fill(Theme.sky.opacity(scheme == .dark ? 0.10 : 0.12))
                .frame(width: 300).blur(radius: 90).offset(x: 170, y: 120)
            Circle().fill(Theme.sun.opacity(scheme == .dark ? 0.08 : 0.14))
                .frame(width: 260).blur(radius: 90).offset(x: -120, y: 420)
        }
        .ignoresSafeArea()
    }
}
