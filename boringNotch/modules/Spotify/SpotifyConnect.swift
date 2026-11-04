//
//  SpotifyConnect.swift
//  boringNotch
//
//  Appareils Spotify Connect : décodage et choix (couche pure, testée par scripts/spotify-selftest).
//

import Foundation

struct SpotifyDevice: Decodable, Equatable, Identifiable {
    let id: String?
    let name: String
    let type: String  // "Computer", "Smartphone", "Speaker"…
    let is_active: Bool
    let is_restricted: Bool
}

enum SpotifyConnect {
    private struct Response: Decodable { let devices: [SpotifyDevice] }

    static func decode(_ data: Data) -> [SpotifyDevice]? {
        (try? JSONDecoder().decode(Response.self, from: data))?.devices
    }

    /// Appareils vers lesquels on peut transférer la lecture.
    static func controllable(_ d: [SpotifyDevice]) -> [SpotifyDevice] {
        d.filter { $0.id != nil && !$0.is_restricted }
    }

    static func sameName(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// L'appareil actif quand ce n'est pas ce Mac.
    static func remoteActive(_ d: [SpotifyDevice], localName: String) -> SpotifyDevice? {
        d.first { $0.is_active && !sameName($0.name, localName) }
    }

    static func symbol(for type: String) -> String {
        switch type {
        case "Smartphone": "iphone"
        case "Speaker": "hifispeaker"
        case "Computer": "laptopcomputer"
        default: "speaker.wave.2"
        }
    }
}
