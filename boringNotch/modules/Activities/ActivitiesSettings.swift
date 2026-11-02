//
//  ActivitiesSettings.swift
//  boringNotch
//

import Defaults
import KeyboardShortcuts
import SwiftUI

struct ActivitiesSettings: View {
    private static let hookLine = "source ~/Projects/boring.notch/scripts/cmd-hook.zsh"

    @Default(.activityMaxPills) private var maxPills
    @Default(.activityEventSeconds) private var eventSeconds
    @Default(.commandMinSeconds) private var commandMin
    @Default(.stayAwakeShortcutMinutes) private var shortcutMinutes
    @Default(.timerShortcutMinutes) private var timerMinutes
    @Default(.activityDownloads) private var downloads
    @Default(.activityCommands) private var commands

    var body: some View {
        Form {
            Section {
                Picker("Pastilles affichées", selection: $maxPills) {
                    Text("Une (à gauche)").tag(1)
                    Text("Deux (gauche et droite)").tag(2)
                }
                Stepper(value: $eventSeconds, in: 2...30) {
                    LabeledContent("Durée des notifications", value: "\(eventSeconds) s")
                }
            } header: {
                Text("Général")
            } footer: {
                note("Les plus importantes d'abord : micro et caméra, agents, téléchargements, notifications, minuteur, rester éveillé. La durée s'applique aux commandes, disques, casques et téléchargements terminés.")
            }

            Section {
                Defaults.Toggle("Micro utilisé", key: .activityMic)
                Defaults.Toggle("Caméra utilisée", key: .activityCamera)
            } header: {
                Text("Micro et caméra")
            } footer: {
                note("Point rouge (micro) ou vert (caméra) avec la durée ; survoler la pastille affiche les apps qui écoutent. Le miroir de la notch n'est pas compté.")
            }

            Section {
                Defaults.Toggle("Agents de code", key: .activityAgents)
            } header: {
                Text("Agents")
            }

            Section {
                Defaults.Toggle("Téléchargements en cours", key: .activityDownloads)
                Defaults.Toggle("Ajouter les fichiers terminés à l'étagère", key: .downloadsToShelf)
                    .disabled(!downloads)
            } header: {
                Text("Téléchargements")
            } footer: {
                note("Dossier Téléchargements. Progression exacte pour Safari ; Chrome, Arc et Firefox affichent un anneau tournant.")
            }

            Section {
                Defaults.Toggle("Commande terminée", key: .activityCommands)
                Stepper(value: $commandMin, in: 5...600, step: 5) {
                    LabeledContent("Seulement si elle a duré plus de", value: "\(commandMin) s")
                }
                .disabled(!commands)
                Defaults.Toggle("Même quand le terminal est au premier plan", key: .commandWhenFrontmost)
                    .disabled(!commands)
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
                note("Nécessite cette ligne dans ~/.zshrc (nouveaux terminaux). Un clic sur la pastille ramène le terminal.")
            }

            Section {
                Defaults.Toggle("Disque externe branché (bouton éjecter)", key: .activityDisks)
                Defaults.Toggle("Casque Bluetooth connecté", key: .activityHeadsets)
            } header: {
                Text("Appareils")
            } footer: {
                note("Un clic sur la pastille du casque en fait la sortie audio.")
            }

            Section {
                Defaults.Toggle("Afficher la pastille", key: .activityStayAwake)
                Defaults.Toggle("Garder aussi l'écran allumé", key: .stayAwakeDisplay)
                KeyboardShortcuts.Recorder("Raccourci activer / arrêter :", name: .toggleStayAwake)
                Picker("Durée avec le raccourci", selection: $shortcutMinutes) {
                    Text("Indéfiniment").tag(0)
                    Text("1 heure").tag(60)
                    Text("2 heures").tag(120)
                    Text("4 heures").tag(240)
                }
            } header: {
                Text("Rester éveillé")
            } footer: {
                note("Aussi depuis le menu de l'icône de la barre des menus. Un clic sur la pastille arrête. Le réglage de l'écran s'applique à la prochaine activation.")
            }

            Section {
                KeyboardShortcuts.Recorder("Raccourci lancer / arrêter :", name: .toggleTimer)
                Picker("Durée avec le raccourci", selection: $timerMinutes) {
                    ForEach(NotchTimer.presets, id: \.self) { Text("\($0) min").tag($0) }
                }
            } header: {
                Text("Minuteur")
            } footer: {
                note("Aussi depuis le menu de l'icône de la barre des menus. Un clic sur la pastille arrête ; à la fin, un son et une pastille « Terminé » pendant une minute.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Activités")
    }

    private func note(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).font(.caption)
    }
}
