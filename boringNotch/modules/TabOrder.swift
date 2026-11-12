//
//  TabOrder.swift
//  boringNotch
//
//  Ordre des onglets (Foundation seulement, testé par scripts/tab-order-selftest).
//

import Foundation

enum TabOrder {
    /// Ordre enregistré d'abord (ids inconnus et doublons ignorés), puis les onglets jamais classés, dans l'ordre par défaut.
    static func apply(_ saved: [String], to ids: [String]) -> [String] {
        var seen = Set<String>()
        return (saved.filter(ids.contains) + ids).filter { seen.insert($0).inserted }
    }

    /// Glisser-déposer : `id` prend la place de `target` (les autres se décalent). Ids inconnus : ordre inchangé.
    static func move(_ id: String, onto target: String, in ids: [String]) -> [String] {
        guard let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target), from != to else { return ids }
        var out = ids
        out.remove(at: from)
        out.insert(id, at: to)
        return out
    }

    /// Affiché ou non : l'accueil toujours, le calendrier selon son propre réglage, les autres selon la liste masquée.
    static func isShown(_ id: String, hidden: [String], showCalendar: Bool) -> Bool {
        switch id {
        case "home": true
        case "calendar": showCalendar
        default: !hidden.contains(id)
        }
    }
}
