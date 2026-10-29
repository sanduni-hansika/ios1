import Foundation
import Observation
import CoreLocation

@MainActor @Observable
final class DashboardViewModel {
    enum WeatherState { case loading, loaded(WeatherSnapshot, stale: Bool), failed(String) }
    var weather: WeatherState = .loading

    func load(location: CLLocationCoordinate2D) async {
        if let cached = WeatherService.cached() { weather = .loaded(cached, stale: true) }
        do {
            let w = try await WeatherService.fetch(latitude: location.latitude, longitude: location.longitude)
            weather = .loaded(w, stale: false)
            scheduleRiskAlertIfNeeded(w)
            WidgetUpdater.refresh()
        } catch {
            if WeatherService.cached() == nil { weather = .failed(error.localizedDescription) }
        }
    }

    /// Early warning – at most one weather-risk notification per day.
    private func scheduleRiskAlertIfNeeded(_ w: WeatherSnapshot) {
        guard w.fungalRisk == .high else { return }
        let key = "riskAlert.\(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        NotificationService.fireNow(title: "🌧️ \(tr("risk.high_title"))", body: tr("risk.high_body"), userInfo: ["route": "dashboard"])
    }

    static func sprayAdvice(_ w: WeatherSnapshot) -> String {
        if w.rainChance >= 60 { return tr("weather.advice_rain") }
        if let h = w.bestSprayHour { return tr("weather.advice_window", String(format: "%02d:00", h)) }
        return tr("weather.advice_morning")
    }
}
