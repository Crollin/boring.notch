//
//  WeatherStore.swift
//  boringNotch
//
//  Météo discrète dans l'en-tête du notch ouvert : icône + température, survol = min/max et pluie.
//  Position : CoreLocation (précision ~1 km, autorisation demandée une fois). Données : Open-Meteo (sans clé).
//

import AppKit
import CoreLocation
import Defaults
import OSLog
import SwiftUI

@MainActor
final class WeatherStore: NSObject, ObservableObject {
    static let shared = WeatherStore()

    struct Weather: Equatable {
        var temperature: Double
        var code: Int
        var isDay: Bool
        var min: Double
        var max: Double
        var rain: Int?          // probabilité max de pluie aujourd'hui, en %
    }

    @Published private(set) var weather: Weather?
    private let manager = CLLocationManager()
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        // App sans Dock : sans activation, macOS n'affiche pas toujours la demande d'autorisation.
        if manager.authorizationStatus == .notDetermined { NSApp.activate(ignoringOtherApps: true) }
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
        // ponytail: une mise à jour toutes les 30 min suffit pour une icône et une température.
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { _ in
            Task { @MainActor in WeatherStore.shared.manager.requestLocation() }
        }
    }

    private func fetch(_ c: CLLocationCoordinate2D) async {
        var u = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        u.queryItems = [
            .init(name: "latitude", value: String(format: "%.3f", c.latitude)),
            .init(name: "longitude", value: String(format: "%.3f", c.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "1"),
        ]
        guard let (data, _) = try? await URLSession.shared.data(from: u.url!),
              let r = try? JSONDecoder().decode(Response.self, from: data) else {
            // Réseau absent ou service saturé : nouvel essai dans 5 min plutôt qu'au prochain tour de 30 min.
            try? await Task.sleep(for: .seconds(300))
            manager.requestLocation()
            return
        }
        weather = Weather(temperature: r.current.temperature_2m, code: r.current.weather_code, isDay: r.current.is_day == 1,
                          min: r.daily.temperature_2m_min.first ?? r.current.temperature_2m,
                          max: r.daily.temperature_2m_max.first ?? r.current.temperature_2m,
                          rain: r.daily.precipitation_probability_max.first ?? nil)
    }

    private struct Response: Decodable {
        struct Current: Decodable { var temperature_2m: Double; var weather_code: Int; var is_day: Int }
        struct Daily: Decodable { var temperature_2m_max: [Double]; var temperature_2m_min: [Double]; var precipitation_probability_max: [Int?] }
        var current: Current
        var daily: Daily
    }
}

extension WeatherStore: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in await WeatherStore.shared.fetch(c) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger(subsystem: "theboringteam.boringnotch", category: "weather").error("localisation : \(error.localizedDescription, privacy: .public)")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Logger(subsystem: "theboringteam.boringnotch", category: "weather").info("autorisation : \(manager.authorizationStatus.rawValue)")
        switch manager.authorizationStatus {
        case .notDetermined, .denied, .restricted: break
        default: manager.requestLocation()
        }
    }
}

extension WeatherStore.Weather {
    /// Codes WMO d'Open-Meteo -> SF Symbol (rendu multicolore).
    var symbol: String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
    var help: String {
        "Min \(Int(min.rounded()))° · Max \(Int(max.rounded()))°" + (rain.map { " · Pluie \($0) %" } ?? "")
    }
}

/// Icône + température, à la hauteur des autres éléments de l'en-tête.
struct WeatherBadge: View {
    @ObservedObject private var store = WeatherStore.shared
    @Default(.showWeather) private var show

    var body: some View {
        if show, let w = store.weather {
            HStack(spacing: 4) {
                Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 12))
                Text("\(Int(w.temperature.rounded()))°").font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 6)
            .frame(height: 30)
            .help(w.help)
        }
    }
}
