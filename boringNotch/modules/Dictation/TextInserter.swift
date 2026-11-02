//
//  TextInserter.swift
//  boringNotch
//
//  Colle le texte dans l'app active : presse-papiers + ⌘V, puis restaure le presse-papiers.
//  Demande l'autorisation Accessibilité (déjà accordée au fork). Sans elle, le texte reste dans le presse-papiers.
//

import AppKit

enum TextInserter {
    /// Texte sélectionné dans l'app active (Accessibilité). nil si rien, champ protégé ou accès refusé.
    static func selectedText() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        var el: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &el) == .success,
              let el else { return nil }
        var sel: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el as! AXUIElement, kAXSelectedTextAttribute as CFString, &sel) == .success,
              let s = sel as? String, !s.isEmpty else { return nil }
        return s
    }

    @MainActor static func insert(_ text: String) async {
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string) // ponytail: seul le texte est restauré, pas images/fichiers
        pb.clearContents()
        pb.setString(text, forType: .string)
        // Convention des gestionnaires de presse-papiers : ne pas enregistrer ce contenu (dictée = texte privé).
        pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        guard AXIsProcessTrusted() else { return }

        try? await Task.sleep(for: .milliseconds(60))
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: down) // V
            e?.flags = .maskCommand
            e?.post(tap: .cghidEventTap)
        }
        try? await Task.sleep(for: .milliseconds(400))
        if let previous, pb.string(forType: .string) == text {
            pb.clearContents(); pb.setString(previous, forType: .string)
        }
    }
}
