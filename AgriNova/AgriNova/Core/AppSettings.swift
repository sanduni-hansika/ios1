import SwiftUI
import Observation

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case en, si, ta
    var id: String { rawValue }
    var index: Int { switch self { case .en: 0; case .si: 1; case .ta: 2 } }
    var nativeName: String { switch self { case .en: "English"; case .si: "සිංහල"; case .ta: "தமிழ்" } }
    var flag: String { switch self { case .en: "🇬🇧"; case .si: "🇱🇰"; case .ta: "🇱🇰" } }
}

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
    var icon: String { switch self { case .system: "circle.lefthalf.filled"; case .light: "sun.max.fill"; case .dark: "moon.stars.fill" } }
}

/// App-wide user preferences. Observable so every view that reads a value (including through `tr(_:)`) refreshes.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var language: AppLanguage
    var theme: ThemeMode
    var notificationsEnabled: Bool
    var cloudSyncEnabled: Bool
    var hasOnboarded: Bool
    var isSignedIn: Bool
    var allowFaceID: Bool
    var allowTouchID: Bool
    var allowGoogle: Bool
    var allowApple: Bool
    var username: String
    var userPhone: String
    var userDistrict: String
    var authMethod: String          // password | google | apple
    var memberSince: Date?
    var avatarVersion: Int          // bumped when the profile photo changes so views refresh
    var userName: String
    var userEmail: String
    var confidenceThreshold: Double
    var extensionOfficerEmail: String

    init() {
        let d = UserDefaults.standard
        language = AppLanguage(rawValue: d.string(forKey: "lang") ?? "en") ?? .en
        theme = ThemeMode(rawValue: d.string(forKey: "theme") ?? "system") ?? .system
        notificationsEnabled = d.object(forKey: "notif") as? Bool ?? true
        cloudSyncEnabled = d.bool(forKey: "cloud")
        hasOnboarded = d.bool(forKey: "onboarded")
        isSignedIn = d.bool(forKey: "signedIn")
        allowFaceID = d.object(forKey: "allowFace") as? Bool ?? true
        allowTouchID = d.object(forKey: "allowTouch") as? Bool ?? true
        allowGoogle = d.object(forKey: "allowGoogle") as? Bool ?? true
        allowApple = d.object(forKey: "allowApple") as? Bool ?? true
        username = d.string(forKey: "username") ?? ""
        userPhone = d.string(forKey: "userPhone") ?? ""
        userDistrict = d.string(forKey: "userDistrict") ?? ""
        authMethod = d.string(forKey: "authMethod") ?? "password"
        memberSince = d.object(forKey: "memberSince") as? Date
        avatarVersion = 0
        userName = d.string(forKey: "userName") ?? ""
        userEmail = d.string(forKey: "userEmail") ?? ""
        let t = d.double(forKey: "threshold")
        confidenceThreshold = t == 0 ? 0.70 : t
        extensionOfficerEmail = d.string(forKey: "officerEmail") ?? "extension.officer@agrinova.example"
    }

    func persist() {
        let d = UserDefaults.standard
        d.set(language.rawValue, forKey: "lang")
        d.set(theme.rawValue, forKey: "theme")
        d.set(notificationsEnabled, forKey: "notif")
        d.set(cloudSyncEnabled, forKey: "cloud")
        d.set(hasOnboarded, forKey: "onboarded")
        d.set(isSignedIn, forKey: "signedIn")
        d.set(allowFaceID, forKey: "allowFace"); d.set(allowTouchID, forKey: "allowTouch")
        d.set(allowGoogle, forKey: "allowGoogle"); d.set(allowApple, forKey: "allowApple")
        d.set(username, forKey: "username"); d.set(userPhone, forKey: "userPhone"); d.set(userDistrict, forKey: "userDistrict")
        d.set(authMethod, forKey: "authMethod"); d.set(memberSince, forKey: "memberSince")
        d.set(userName, forKey: "userName")
        d.set(userEmail, forKey: "userEmail")
        d.set(confidenceThreshold, forKey: "threshold")
        d.set(extensionOfficerEmail, forKey: "officerEmail")
    }

    /// Wipes local preferences (not the Keychain credentials) – used by "Reset data".
    func resetPreferences() {
        let d = UserDefaults.standard
        let keep = (language, theme)
        for k in ["notif", "cloud", "onboarded", "threshold", "officerEmail"] { d.removeObject(forKey: k) }
        notificationsEnabled = true; cloudSyncEnabled = false
        confidenceThreshold = 0.70; hasOnboarded = false
        language = keep.0; theme = keep.1
        persist()
    }
}

/// Selected top-level section (shared by iPhone tab bar and iPad sidebar).
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, scan, library, treatments, farm, radar, insights, history, settings
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .dashboard: "nav.home"; case .scan: "nav.scan"; case .library: "nav.library"
        case .treatments: "nav.treatments"; case .farm: "nav.farm"; case .radar: "nav.radar"
        case .insights: "nav.insights"; case .history: "nav.history"; case .settings: "nav.settings"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: "house.fill"; case .scan: "camera.viewfinder"; case .library: "leaf.fill"
        case .treatments: "cross.case.fill"; case .farm: "tree.fill"; case .radar: "dot.radiowaves.left.and.right"
        case .insights: "chart.xyaxis.line"; case .history: "clock.arrow.circlepath"; case .settings: "gearshape.fill"
        }
    }
}

/// Lightweight navigation coordinator – lets Siri intents, widgets and in-app buttons jump between sections.
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var selected: AppSection = .dashboard
    /// Image handed to the scanner (e.g. a bundled sample leaf from the library).
    var pendingImage: UIImage?
    func go(_ s: AppSection) { selected = s }
}
