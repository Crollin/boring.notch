// Auto-test de la couche pure Spotify Connect.
// swiftc boringNotch/modules/Spotify/SpotifyConnect.swift scripts/spotify-selftest/main.swift -o "$TMPDIR/spotify-selftest" && "$TMPDIR/spotify-selftest"

import Foundation

func check(_ cond: Bool, _ msg: String) { if !cond { print("FAIL: \(msg)"); exit(1) } }

let json = """
{"devices":[
{"id":"a1","name":"MacBook de Côme","type":"Computer","is_active":true,"is_restricted":false},
{"id":"b2","name":"iPhone","type":"Smartphone","is_active":false,"is_restricted":false},
{"id":"c3","name":"Cuisine","type":"Speaker","is_active":false,"is_restricted":true},
{"id":null,"name":"Fantôme","type":"Speaker","is_active":false,"is_restricted":false}
]}
"""
let devices = SpotifyConnect.decode(Data(json.utf8))
check(devices?.count == 4, "decode")
check(SpotifyConnect.decode(Data("{}".utf8)) == nil, "decode {} -> nil")

let ctl = SpotifyConnect.controllable(devices!)
check(ctl.map(\.name) == ["MacBook de Côme", "iPhone"], "controllable")

check(SpotifyConnect.remoteActive(devices!, localName: "macbook de come") == nil, "local actif -> nil")
var onPhone = devices!
onPhone = onPhone.map { SpotifyDevice(id: $0.id, name: $0.name, type: $0.type, is_active: $0.name == "iPhone", is_restricted: $0.is_restricted) }
check(SpotifyConnect.remoteActive(onPhone, localName: "macbook de come")?.name == "iPhone", "iPhone distant")

check(SpotifyConnect.symbol(for: "Smartphone") == "iphone", "symbol phone")
check(SpotifyConnect.symbol(for: "TV") == "speaker.wave.2", "symbol default")
print("OK")
