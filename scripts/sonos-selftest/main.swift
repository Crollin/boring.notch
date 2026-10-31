// Auto-test de la couche pure Sonos (pas de cible XCTest dans le projet).
// swiftc boringNotch/modules/Sonos/SonosModels.swift [boringNotch/modules/Sonos/SonosClient.swift] scripts/sonos-selftest/main.swift -o /tmp/sonos-selftest && /tmp/sonos-selftest

import Foundation

func check(_ cond: Bool, _ msg: String) { if !cond { print("FAIL: \(msg)"); exit(1) } }

// topology
let zgs = """
<ZoneGroupState><ZoneGroups>\
<ZoneGroup Coordinator="RINCON_A" ID="RINCON_A:1">\
<ZoneGroupMember UUID="RINCON_A" Location="http://192.168.1.20:1400/xml/device_description.xml" ZoneName="Cuisine"/>\
<ZoneGroupMember UUID="RINCON_B" Location="http://192.168.1.21:1400/xml/device_description.xml" ZoneName="Bureau"/>\
<ZoneGroupMember UUID="RINCON_X" Location="http://192.168.1.29:1400/xml/device_description.xml" ZoneName="Sub" Invisible="1"/>\
</ZoneGroup>\
<ZoneGroup Coordinator="RINCON_C" ID="RINCON_C:2">\
<ZoneGroupMember UUID="RINCON_C" Location="http://192.168.1.22:1400/xml/device_description.xml" ZoneName="Salon"/>\
</ZoneGroup></ZoneGroups></ZoneGroupState>
"""
let escaped = zgs.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
let soapTopo = "<s:Envelope><s:Body><u:GetZoneGroupStateResponse><ZoneGroupState>\(escaped)</ZoneGroupState></u:GetZoneGroupStateResponse></s:Body></s:Envelope>"
let topo = SonosParse.topology(soapTopo)
check(topo.rooms.count == 3, "3 rooms, got \(topo.rooms.count)")
check(topo.groups.count == 2, "2 groups")
check(topo.rooms.first { $0.id == "RINCON_A" }?.host == "192.168.1.20", "host")
check(topo.groups.first { $0.coordinatorID == "RINCON_A" }?.memberIDs == ["RINCON_A", "RINCON_B"], "members")

// value
check(SonosParse.value("CurrentVolume", in: "<s:Envelope><s:Body><u:GetVolumeResponse><CurrentVolume>45</CurrentVolume></u:GetVolumeResponse></s:Body></s:Envelope>") == "45", "value")

// track
let didl = "<DIDL-Lite xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><item><dc:title>Été Indien - Remastered 2004</dc:title><dc:creator>Joe Dassin</dc:creator></item></DIDL-Lite>"
let didlEsc = didl.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
let posInfo = "<s:Envelope><s:Body><u:GetPositionInfoResponse><TrackMetaData>\(didlEsc)</TrackMetaData></u:GetPositionInfoResponse></s:Body></s:Envelope>"
check(SonosParse.track(fromDIDL: SonosParse.value("TrackMetaData", in: posInfo) ?? "") == SonosTrack(title: "Été Indien - Remastered 2004", artist: "Joe Dassin"), "track")

// tracksMatch
check(SonosLogic.tracksMatch(SonosTrack(title: "Été Indien - Remastered 2004", artist: "Joe Dassin"), SonosTrack(title: "ete indien", artist: "JOE DASSIN")), "match accents/suffix")
check(SonosLogic.tracksMatch(SonosTrack(title: "Song (feat. X)", artist: "A, X"), SonosTrack(title: "Song", artist: "A")), "match feat")
check(!SonosLogic.tracksMatch(SonosTrack(title: "Autre", artist: "Joe Dassin"), SonosTrack(title: "ete indien", artist: "Joe Dassin")), "no match")

// toggled
check(SonosLogic.toggled(SonosGroup(coordinatorID: "A", memberIDs: ["A"]), room: "A") == nil, "last room refused")
check(SonosLogic.toggled(SonosGroup(coordinatorID: "A", memberIDs: ["A", "B"]), room: "B") == ["A"], "remove")
check(SonosLogic.toggled(SonosGroup(coordinatorID: "A", memberIDs: ["A"]), room: "C") == ["A", "C"], "add")

// plan
check(SonosLogic.plan(for: ["A", "Z"], available: ["A", "B"]) == ["A"], "plan partial")
check(SonosLogic.plan(for: ["Z"], available: ["A"]) == nil, "plan empty")

// history
check(SonosLogic.updatedHistory(previous: nil, old: ["A"], new: ["A", "B"]) == ["A"], "history change")
check(SonosLogic.updatedHistory(previous: ["A"], old: ["A", "B"], new: ["B", "A"]) == ["A"], "history unchanged (order)")

// label
let rooms = topo.rooms
check(SonosLogic.label(for: SonosGroup(coordinatorID: "RINCON_A", memberIDs: ["RINCON_A"]), rooms: rooms) == "Cuisine", "label 1")
check(SonosLogic.label(for: SonosGroup(coordinatorID: "RINCON_B", memberIDs: ["RINCON_A", "RINCON_B"]), rooms: rooms) == "Bureau + Cuisine", "label coordinator first")

// envelope
let env = SonosSOAP.envelope(service: "RenderingControl", action: "SetVolume", args: [("InstanceID", "0"), ("Channel", "Master"), ("DesiredVolume", "30"), ("X", "a&b")])
check(env.contains("<u:SetVolume xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\">"), "envelope action")
check(env.contains("<DesiredVolume>30</DesiredVolume>"), "envelope arg")
check(env.contains("<X>a&amp;b</X>"), "envelope escape")

#if SONOS_NET
if let host = ProcessInfo.processInfo.environment["SONOS_HOST"] {
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            let t = try await SonosClient().topology(host: host)
            check(!t.rooms.isEmpty, "network topology")
            print("rooms:", t.rooms.map(\.name).joined(separator: ", "))
            for g in t.groups {
                if let h = t.rooms.first(where: { $0.id == g.coordinatorID })?.host {
                    let s = try await SonosClient().transportState(host: h)
                    let v = try await SonosClient().groupVolume(coordinator: h)
                    let tr = try await SonosClient().currentTrack(host: h)
                    print(SonosLogic.label(for: g, rooms: t.rooms), s, v, tr.map { "\($0.title) — \($0.artist)" } ?? "-")
                }
            }
        } catch { check(false, "network: \(error)") }
        sem.signal()
    }
    sem.wait()
}
#endif

print("OK")
