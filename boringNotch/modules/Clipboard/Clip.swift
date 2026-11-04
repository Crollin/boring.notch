//
//  Clip.swift
//  boringNotch
//
//  Une copie de l'onglet « Copies » et la règle de rangement (testée par scripts/clipboard-selftest).
//

import AppKit

struct Clip: Identifiable {
    enum Content {
        case text(String)
        case image(NSImage)
        case files([URL])
    }
    let id = UUID()
    let content: Content
    let date: Date
    var pinned = false

    var preview: String {
        switch content {
        case .text(let s): s.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? ""
        case .image(let i): "Image \(Int(i.size.width))×\(Int(i.size.height))"
        case .files(let u): u.map(\.lastPathComponent).joined(separator: ", ")
        }
    }
    var symbol: String {
        switch content {
        case .text: "text.alignleft"
        case .image: "photo"
        case .files: "doc"
        }
    }
    /// Même contenu (pour ne pas empiler deux fois la même copie).
    func same(as other: Content) -> Bool {
        switch (content, other) {
        case let (.text(a), .text(b)): a == b
        case let (.files(a), .files(b)): a == b
        case let (.image(a), .image(b)): a.tiffRepresentation == b.tiffRepresentation
        default: false
        }
    }
}

extension Array where Element == Clip {
    /// Épinglées d'abord (dans l'ordre où on les a épinglées), puis les plus récentes jusqu'à `limit` cartes au total :
    /// une épinglée n'est jamais évincée par de nouvelles copies.
    func arranged(limit: Int) -> [Clip] {
        let pinned = filter(\.pinned)
        let recent = filter { !$0.pinned }.sorted { $0.date > $1.date }
        return pinned + recent.prefix(Swift.max(0, limit - pinned.count))
    }
}
