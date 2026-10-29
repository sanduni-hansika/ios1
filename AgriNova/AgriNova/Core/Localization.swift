import Foundation

/// Runtime localisation (English / Sinhala / Tamil) so the language can be switched instantly
/// from onboarding or Settings without restarting the app.
/// `tr` reads `AppSettings.shared.language`, an @Observable property, so SwiftUI refreshes automatically.
func tr(_ key: String) -> String {
    let lang = AppSettings.shared.language
    guard let row = Strings.table[key] else { return key }
    let i = lang.index
    if i < row.count, !row[i].isEmpty { return row[i] }
    return row[0]
}

func tr(_ key: String, _ args: CVarArg...) -> String {
    String(format: tr(key), arguments: args)
}

extension Array where Element == String {
    /// Picks the en/si/ta variant from a 3-element array.
    var localized: String {
        let i = AppSettings.shared.language.index
        return i < count ? self[i] : (first ?? "")
    }
}
