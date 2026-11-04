// Auto-test du rangement des copies (épingles).
// swiftc boringNotch/modules/Clipboard/Clip.swift scripts/clipboard-selftest/main.swift -o "$TMPDIR/clipboard-selftest" && "$TMPDIR/clipboard-selftest"

import Foundation

func check(_ cond: Bool, _ msg: String) { if !cond { print("FAIL: \(msg)"); exit(1) } }

let t0 = Date()
func clip(_ s: String, _ age: Double, pinned: Bool = false) -> Clip {
    var c = Clip(content: .text(s), date: t0.addingTimeInterval(-age)); c.pinned = pinned; return c
}
func texts(_ cs: [Clip]) -> [String] { cs.map(\.preview) }

var list = [clip("pin", 100, pinned: true), clip("a", 5), clip("b", 4), clip("c", 3), clip("d", 2)]
check(texts(list.arranged(limit: 5)) == ["pin", "d", "c", "b", "a"], "épinglée d'abord, récentes triées")
// Cinq nouvelles copies : l'épinglée reste, les anciennes sortent.
for (i, s) in ["e", "f", "g", "h", "i"].enumerated() { list = ([clip(s, -Double(i))] + list).arranged(limit: 5) }
check(texts(list) == ["pin", "i", "h", "g", "f"], "l'épinglée survit à 5 copies")
check(texts([clip("p1", 9, pinned: true), clip("p2", 1, pinned: true), clip("x", 0)].arranged(limit: 2)) == ["p1", "p2"], "épinglées jamais évincées")
print("OK")
