// Auto-test de l'ordre des onglets.
// swiftc boringNotch/modules/TabOrder.swift scripts/tab-order-selftest/main.swift -o "$TMPDIR/tab-order-selftest" && "$TMPDIR/tab-order-selftest"

import Foundation

func check(_ cond: Bool, _ msg: String) { if !cond { print("FAIL: \(msg)"); exit(1) } }

let ids = ["home", "shelf", "calendar", "focus", "agents"]
check(TabOrder.apply([], to: ids) == ids, "ordre par défaut")
check(TabOrder.apply(["focus", "home"], to: ids) == ["focus", "home", "shelf", "calendar", "agents"], "classés d'abord, nouveaux ensuite")
check(TabOrder.apply(["gone", "agents", "agents"], to: ids) == ["agents", "home", "shelf", "calendar", "focus"], "inconnus et doublons ignorés")
check(TabOrder.isShown("home", hidden: ["home"], showCalendar: false), "accueil toujours affiché")
check(!TabOrder.isShown("calendar", hidden: [], showCalendar: false), "calendrier suit showCalendar")
check(!TabOrder.isShown("focus", hidden: ["focus"], showCalendar: true), "onglet masqué")
check(TabOrder.move("focus", onto: "shelf", in: ids) == ["home", "focus", "shelf", "calendar", "agents"], "remonter")
check(TabOrder.move("shelf", onto: "focus", in: ids) == ["home", "calendar", "focus", "shelf", "agents"], "descendre")
check(TabOrder.move("texte quelconque", onto: "focus", in: ids) == ids, "glisser étranger ignoré")
print("OK")
