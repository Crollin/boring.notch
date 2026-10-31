//
//  SonosModels.swift
//  boringNotch
//
//  Couche pure (Foundation seulement) : modèles, parsing UPnP, logique de groupes.
//  Testée par scripts/sonos-selftest.swift.
//

import Foundation

struct SonosRoom: Codable, Hashable, Identifiable {
    let id: String      // RINCON_…
    let name: String
    let host: String    // "192.168.1.20"
}

struct SonosGroup: Hashable {
    let coordinatorID: String
    let memberIDs: [String]
}

struct SonosFavorite: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var roomIDs: [String]
}

struct SonosTrack: Equatable {
    let title: String
    let artist: String
    var spotifyID: String? = nil   // id Spotify (22 car.) quand connu : prime sur le titre
}

// MARK: - Parsing

enum SonosParse {
    /// GetZoneGroupState (réponse SOAP complète). Ignore les membres `Invisible="1"` (subs, satellites).
    static func topology(_ soapResponse: String) -> (rooms: [SonosRoom], groups: [SonosGroup]) {
        let inner = value("ZoneGroupState", in: soapResponse) ?? soapResponse
        let collector = ElementCollector()
        _ = collector.parse(inner)
        var rooms: [SonosRoom] = []
        var groups: [SonosGroup] = []
        var current: (coordinator: String, members: [String])?
        for event in collector.events {
            switch event {
            case .start(let name, let attrs) where name == "ZoneGroup":
                current = (attrs["Coordinator"] ?? "", [])
            case .start(let name, let attrs) where name == "ZoneGroupMember":
                guard attrs["Invisible"] != "1", let id = attrs["UUID"],
                      let host = attrs["Location"].flatMap({ URL(string: $0)?.host }) else { continue }
                rooms.append(SonosRoom(id: id, name: attrs["ZoneName"] ?? id, host: host))
                current?.members.append(id)
            case .end(let name) where name == "ZoneGroup":
                if let c = current, !c.members.isEmpty {
                    groups.append(SonosGroup(coordinatorID: c.coordinator, memberIDs: c.members))
                }
                current = nil
            default: break
            }
        }
        return (rooms, groups)
    }

    /// Texte (déséchappé) du premier élément `tag`, préfixe de namespace ignoré.
    static func value(_ tag: String, in xml: String) -> String? {
        let collector = ElementCollector(textFor: tag)
        _ = collector.parse(xml)
        return collector.text
    }

    /// dc:title / dc:creator d'un TrackMetaData DIDL-Lite.
    static func track(fromDIDL didl: String) -> SonosTrack? {
        guard let title = value("title", in: didl), !title.isEmpty else { return nil }
        return SonosTrack(title: title, artist: value("creator", in: didl) ?? "",
                          spotifyID: value("res", in: didl).flatMap(spotifyID(from:)))
    }

    /// "…spotify:track:<id>?…" (ou "spotify%3atrack%3a<id>") → <id>.
    static func spotifyID(from uri: String) -> String? {
        let s = uri.removingPercentEncoding ?? uri
        guard let r = s.range(of: "spotify:track:") else { return nil }
        let id = s[r.upperBound...].prefix { $0.isLetter || $0.isNumber }
        return id.isEmpty ? nil : String(id)
    }
}

private final class ElementCollector: NSObject, XMLParserDelegate {
    enum Event { case start(String, [String: String]), end(String) }
    private let wanted: String?
    private var capturing = false
    private var buffer = ""
    private(set) var events: [Event] = []
    private(set) var text: String?

    init(textFor tag: String? = nil) { wanted = tag }

    func parse(_ xml: String) -> Bool {
        let p = XMLParser(data: Data(xml.utf8))
        p.delegate = self
        return p.parse()
    }

    private func local(_ name: String) -> String { name.split(separator: ":").last.map(String.init) ?? name }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        events.append(.start(local(name), attributes))
        if text == nil, let wanted, local(name) == wanted { capturing = true; buffer = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { if capturing { buffer += string } }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        events.append(.end(local(name)))
        if capturing, local(name) == wanted { text = buffer; capturing = false }
    }
}

// MARK: - SOAP

enum SonosSOAP {
    static func envelope(service: String, action: String, args: [(String, String)]) -> String {
        let body = args.map { "<\($0.0)>\(escape($0.1))</\($0.0)>" }.joined()
        return """
        <?xml version="1.0" encoding="utf-8"?>\
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
        <s:Body><u:\(action) xmlns:u="urn:schemas-upnp-org:service:\(service):1">\(body)</u:\(action)></s:Body></s:Envelope>
        """
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - Logique de groupes

enum SonosLogic {
    /// Titre : sans casse/accents, coupé à " - " et " (" (Remastered, feat.). Artiste : l'un contient l'autre.
    static func tracksMatch(_ a: SonosTrack, _ b: SonosTrack) -> Bool {
        if let x = a.spotifyID, let y = b.spotifyID { return x == y }
        func norm(_ s: String) -> String {
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespaces)
        }
        func title(_ s: String) -> String {
            var t = norm(s)
            for sep in [" - ", " ("] { if let r = t.range(of: sep) { t = String(t[..<r.lowerBound]) } }
            return t
        }
        guard title(a.title) == title(b.title) else { return false }
        let (x, y) = (norm(a.artist), norm(b.artist))
        return x.isEmpty || y.isEmpty || x.contains(y) || y.contains(x)
    }

    /// Spotify en lecture ⇔ Sonos en lecture ; Spotify en pause ⇔ Sonos en pause.
    /// Évite qu'une Sonos en pause sur le même morceau capte les touches quand Spotify joue sur le Mac.
    static func statesAgree(spotifyPlaying: Bool, sonosState: String) -> Bool {
        spotifyPlaying ? ["PLAYING", "TRANSITIONING"].contains(sonosState) : sonosState == "PAUSED_PLAYBACK"
    }

    /// Nouveaux membres après tap sur la case `room` ; nil si on retirerait la dernière pièce.
    static func toggled(_ group: SonosGroup, room: String) -> [String]? {
        if group.memberIDs.contains(room) {
            let rest = group.memberIDs.filter { $0 != room }
            return rest.isEmpty ? nil : rest
        }
        return group.memberIDs + [room]
    }

    /// Membres cibles encore présents (favori avec pièce débranchée) ; nil si aucun.
    static func plan(for target: [String], available: Set<String>) -> [String]? {
        let present = target.filter(available.contains)
        return present.isEmpty ? nil : present
    }

    /// « Revenir à » : l'ancien groupe dès que les membres changent (ordre ignoré).
    static func updatedHistory(previous: [String]?, old: [String], new: [String]) -> [String]? {
        Set(old) == Set(new) ? previous : old
    }

    static func label(for group: SonosGroup, rooms: [SonosRoom]) -> String {
        let ordered = [group.coordinatorID] + group.memberIDs.filter { $0 != group.coordinatorID }
        return ordered.compactMap { id in rooms.first { $0.id == id }?.name }.joined(separator: " + ")
    }
}
