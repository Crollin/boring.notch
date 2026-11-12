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
        await withCheckedContinuation { cont in
            Search(timeout: timeout) { cont.resume(returning: $0) }.start()
        }
    }
}

/// Tout l'état vit sur `queue` (série) : d'où `@unchecked Sendable`.
private final class Search: @unchecked Sendable {
    private let queue = DispatchQueue(label: "sonos.discovery")
    private let browser = NWBrowser(for: .bonjour(type: "_sonos._tcp", domain: nil), using: .tcp)
    private var connections: [NWConnection] = []
    private var completion: ((String?) -> Void)?
    private let timeout: TimeInterval

    init(timeout: TimeInterval, completion: @escaping (String?) -> Void) {
        self.timeout = timeout
        self.completion = completion
    }

    func start() {
        browser.browseResultsChangedHandler = { [self] results, _ in
            results.forEach { resolve($0.endpoint) }
        }
        browser.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) { [self] in finish(nil) }
    }

    /// Résolution : on ouvre une connexion et on lit l'adresse distante.
    private func resolve(_ endpoint: NWEndpoint) {
        let params = NWParameters.tcp
        (params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let conn = NWConnection(to: endpoint, using: params)
        connections.append(conn)
        conn.stateUpdateHandler = { [self, conn] state in
            guard case .ready = state,
                  case .hostPort(let host, _)? = conn.currentPath?.remoteEndpoint else { return }
            var s = "\(host)"
            if let pct = s.firstIndex(of: "%") { s = String(s[..<pct]) } // retire l'interface (%en0)
            finish(s)
        }
        conn.start(queue: queue)
    }

    private func finish(_ host: String?) {
        guard let completion else { return }
        self.completion = nil
        browser.cancel()
        connections.forEach { $0.cancel() }
        completion(host)
    }
}
