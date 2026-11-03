//
//  OpenLogi.swift
//  boringNotch
//
//  Batterie / charge des périphériques Logitech (MX Master, MX Keys…) via OpenLogi : sa CLI
//  `openlogi api devices` interroge l'agent déjà lancé et répond en JSON versionné.
//  macOS n'expose pas leur batterie autrement. Sans OpenLogi installé : liste vide, rien ne se passe.
//  Connexion : l'état « en ligne » est relevé toutes les 5 s (cf. LogiConnectionWatcher).
//

import Defaults
import Foundation

enum OpenLogi {
    struct Device {
        let name: String
        let online: Bool
        let percentage: Int?
        let charging: Bool
    }

    private struct Reply: Decodable {
        struct Data: Decodable {
            struct Dev: Decodable {
                struct Battery: Decodable { let percentage: Int?; let status: String? }
                let name: String
                let online: Bool
                let battery: Battery?
            }
            let devices: [Dev]
        }
        let ok: Bool
        let data: Data?
    }

    /// Appareils connus de l'agent OpenLogi. L'app est sandboxée : la CLI est lancée par le helper XPC.
    static func devices() async -> [Device] {
        guard let data = await XPCHelperClient.shared.openLogiDevicesJSON(),
              let r = try? JSONDecoder().decode(Reply.self, from: data), r.ok else { return [] }
        return (r.data?.devices ?? []).map {
            Device(name: $0.name, online: $0.online, percentage: $0.battery?.percentage,
                   charging: isCharging($0.battery?.status))
        }
    }

    /// « charging », « recharging »… mais pas « discharging ».
    private static func isCharging(_ status: String?) -> Bool {
        let s = status?.lowercased() ?? ""
        return s.contains("charging") && !s.hasPrefix("dis")
    }

}

/// Surveille l'état « en ligne » des appareils OpenLogi : un passage hors ligne → en ligne affiche la pastille avec la batterie.
/// ponytail: interrogation toutes les 5 s (le BLE n'émet pas de notification de connexion fiable) ; l'agent OpenLogi n'a pas d'abonnement.
@MainActor
final class LogiConnectionWatcher {
    static let shared = LogiConnectionWatcher()
    private var online: Set<String>?   // nil tant que le premier relevé n'est pas fait : pas de pastille au lancement
    private var timer: Timer?

    func start() {
        guard timer == nil, FileManager.default.fileExists(atPath: "/Applications/OpenLogi.app") else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in await LogiConnectionWatcher.shared.poll() }
        }
        Task { await poll() }
    }

    private func poll() async {
        let devices = await OpenLogi.devices()
        let now = Set(devices.filter(\.online).map(\.name))
        defer { online = now }
        guard let before = online, Defaults[.activityHeadsets] else { return }
        for d in devices where d.online && !before.contains(d.name) {
            ActivityEvents.shared.showDevice(.init(name: d.name, kind: .connected, battery: d.percentage, charging: d.charging))
        }
    }
}
