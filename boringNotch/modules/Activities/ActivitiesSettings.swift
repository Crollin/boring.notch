//
//  ActivitiesSettings.swift
//  boringNotch
//

import Defaults
import KeyboardShortcuts
import SwiftUI

struct ActivitiesSettings: View {
    private static let hookLine = "source ~/Projects/boring.notch/scripts/cmd-hook.zsh"

    var body: some View {
        Form {
            Section {
                Defaults.Toggle("Micro et caméra utilisés", key: .activityPrivacy)
                Defaults.Toggle("Agents de code", key: .activityAgents)
                Defaults.Toggle("Téléchargements", key: .activityDownloads)
                Defaults.Toggle("Ajouter les téléchargements terminés à l'étagère", key: .downloadsToShelf)
                Defaults.Toggle("Disque externe branché", key: .activityDisks)
                Defaults.Toggle("Casque Bluetooth connecté", key: .activityHeadsets)
            } header: {
                Text("Pastilles à côté de la notch")
            } footer: {
                Text("Deux pastilles au plus, les plus importantes d'abord. Le micro et la caméra passent toujours en premier.")
                    .foregroundStyle(.secondary).font(.caption)
            }
            Section {
                Defaults.Toggle("Afficher la pastille", key: .activityStayAwake)
                KeyboardShortcuts.Recorder("Activer / arrêter :", name: .toggleStayAwake)
            } header: {
                Text("Rester éveillé")
            } footer: {
                Text("Durées depuis le menu de l'icône de la barre des menus. Le Mac ne se met pas en veille ; l'écran peut s'éteindre.")
                    .foregroundStyle(.secondary).font(.caption)
            }
            Section {
                Defaults.Toggle("Commande terminal terminée", key: .activityCommands)
                HStack {
                    Text(Self.hookLine).font(.caption.monospaced()).textSelection(.enabled)
                    Spacer()
                    Button("Copier") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.hookLine, forType: .string)
                    }
                }
            } header: {
                Text("Terminal")
            } footer: {
                Text("Ajoutez cette ligne à ~/.zshrc : les commandes de plus de 30 s (BN_MIN_SECONDS) s'affichent à la fin, si le terminal n'est pas au premier plan.")
                    .foregroundStyle(.secondary).font(.caption)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Activités")
    }
}
