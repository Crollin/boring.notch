//
//  SonosDiscovery.swift
//  boringNotch
//
//  Trouve une Sonos via Bonjour (_sonos._tcp). Une seule suffit :
//  GetZoneGroupState donne ensuite toutes les pièces et leurs IP.
//

import Foundation
import Network

final class SonosDiscovery {
    /// IPv4 d'une Sonos, ou nil après `timeout` (hors maison, autorisation refusée…).
    func firstHost(timeout: TimeInterval = 3) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let queue = DispatchQueue(label: "sonos.discovery")
            let browser = NWBrowser(for: .bonjour(type: "_sonos._tcp", domain: nil), using: .tcp)
            var connections: [NWConnection] = []
            var done = false

            func finish(_ host: String?) {
                guard !done else { return }
                done = true
                browser.cancel()
                connections.forEach { $0.cancel() }
                cont.resume(returning: host)
            }

            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    // Résolution : on ouvre une connexion et on lit l'adresse distante.
                    let params = NWParameters.tcp
                    if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                        ip.version = .v4
                    }
                    let conn = NWConnection(to: result.endpoint, using: params)
                    connections.append(conn)
                    conn.stateUpdateHandler = { state in
                        guard case .ready = state,
                              case .hostPort(let host, _)? = conn.currentPath?.remoteEndpoint else { return }
                        var s = "\(host)"
                        if let pct = s.firstIndex(of: "%") { s = String(s[..<pct]) } // retire l'interface (%en0)
                        finish(s)
                    }
                    conn.start(queue: queue)
                }
            }
            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }
}
