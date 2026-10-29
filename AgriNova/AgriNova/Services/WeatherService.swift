import Foundation
import SwiftUI

enum FungalRisk: String, Codable {
    case low, moderate, high
    var titleKey: String { "risk.\(rawValue)" }
    var color: Color { switch self { case .low: Theme.leaf; case .moderate: Theme.sun; case .high: Theme.danger } }
    var icon: String { switch self { case .low: "checkmark.shield.fill"; case .moderate: "exclamationmark.shield.fill"; case .high: "flame.fill" } }
    var level: Double { switch self { case .low: 0.25; case .moderate: 0.6; case .high: 0.95 } }
}

struct WeatherSnapshot: Codable, Equatable {
    var temperature: Double
    var humidity: Double
    var rainChance: Double          // today's max precipitation probability, %
    var tempMax: Double
    var tempMin: Double
    var windSpeed: Double
    var weatherCode: Int
    var avgHumidity72h: Double
    var avgTemp72h: Double
    var maxRainChance72h: Double
    var bestSprayHour: Int?         // next dry, calm hour (0–23)
    var fetchedAt: Date
    var latitude: Double
    var longitude: Double

    var fungalRisk: FungalRisk { WeatherService.fungalRisk(avgHumidity: avgHumidity72h, avgTemp: avgTemp72h, rainChance: maxRainChance72h) }
    var symbol: String {
        switch weatherCode {
        case 0: "sun.max.fill"; case 1, 2: "cloud.sun.fill"; case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"; case 51...67: "cloud.drizzle.fill"; case 80...82: "cloud.heavyrain.fill"
        case 95...99: "cloud.bolt.rain.fill"; default: "cloud.sun.fill"
        }
    }
}

/// Open-Meteo integration – free, key-less REST API (https://open-meteo.com).
enum WeatherService {
    private struct Response: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let relative_humidity_2m: Double; let weather_code: Int; let wind_speed_10m: Double }
        struct Hourly: Decodable { let time: [String]; let relative_humidity_2m: [Double?]; let temperature_2m: [Double?]; let precipitation_probability: [Double?]; let wind_speed_10m: [Double?] }
        struct Daily: Decodable { let precipitation_probability_max: [Double?]; let temperature_2m_max: [Double?]; let temperature_2m_min: [Double?] }
        let current: Current; let hourly: Hourly; let daily: Daily
    }

    static let cacheKey = "weather.cache"

    static func fetch(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", latitude)),
            .init(name: "longitude", value: String(format: "%.4f", longitude)),
            .init(name: "current", value: "temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m"),
            .init(name: "hourly", value: "relative_humidity_2m,temperature_2m,precipitation_probability,wind_speed_10m"),
            .init(name: "daily", value: "precipitation_probability_max,temperature_2m_max,temperature_2m_min"),
            .init(name: "forecast_days", value: "3"),
            .init(name: "timezone", value: "auto")
        ]
        var req = URLRequest(url: c.url!); req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let r = try JSONDecoder().decode(Response.self, from: data)

        let hum = r.hourly.relative_humidity_2m.prefix(72).compactMap { $0 }
        let tmp = r.hourly.temperature_2m.prefix(72).compactMap { $0 }
        let rain = r.hourly.precipitation_probability.prefix(72).compactMap { $0 }
        let avg: ([Double]) -> Double = { $0.isEmpty ? 0 : $0.reduce(0, +) / Double($0.count) }

        // Treatment timing: first of the next 24 hours that is dry (<25 % rain), calm (<15 km/h) and daylight (5–18 h).
        let hourNow = Calendar.current.component(.hour, from: Date())
        var best: Int?
        for offset in 1...24 {
            let idx = hourNow + offset
            guard idx < r.hourly.time.count else { break }
            let h = (hourNow + offset) % 24
            let p = r.hourly.precipitation_probability[idx] ?? 100
            let w = r.hourly.wind_speed_10m[idx] ?? 99
            if p < 25, w < 15, (5...18).contains(h) { best = h; break }
        }
        let snap = WeatherSnapshot(
            temperature: r.current.temperature_2m, humidity: r.current.relative_humidity_2m,
            rainChance: r.daily.precipitation_probability_max.first.flatMap { $0 } ?? 0,
            tempMax: r.daily.temperature_2m_max.first.flatMap { $0 } ?? r.current.temperature_2m,
            tempMin: r.daily.temperature_2m_min.first.flatMap { $0 } ?? r.current.temperature_2m,
            windSpeed: r.current.wind_speed_10m, weatherCode: r.current.weather_code,
            avgHumidity72h: avg(hum), avgTemp72h: avg(tmp), maxRainChance72h: rain.max() ?? 0,
            bestSprayHour: best, fetchedAt: Date(), latitude: latitude, longitude: longitude)
        cache(snap)
        return snap
    }

    /// Fungal / bacterial infection risk from the next 72 h of humidity, temperature and rain probability.
    static func fungalRisk(avgHumidity: Double, avgTemp: Double, rainChance: Double) -> FungalRisk {
        var score = 0
        if avgHumidity >= 85 { score += 2 } else if avgHumidity >= 75 { score += 1 }
        if (18...30).contains(avgTemp) { score += 1 }
        if rainChance >= 60 { score += 2 } else if rainChance >= 40 { score += 1 }
        return score >= 4 ? .high : (score >= 2 ? .moderate : .low)
    }

    static func cache(_ s: WeatherSnapshot) {
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: cacheKey) }
    }
    static func cached() -> WeatherSnapshot? {
        UserDefaults.standard.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(WeatherSnapshot.self, from: $0) }
    }
}
