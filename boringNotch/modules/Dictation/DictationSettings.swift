//
//  DictationSettings.swift
//  boringNotch
//

import Defaults
import KeyboardShortcuts
import SwiftUI

struct DictationSettings: View {
    @Default(.dictationLocale) private var locale
    @Default(.dictationHold) private var hold
    @Default(.dictationSubstitutions) private var substitutions
    @Default(.dictationSuggestions) private var suggestions
    @Default(.dictationHistory) private var history
    @Default(.dictationKeepHistory) private var keepHistory
    @State private var query = ""

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Raccourci :", name: .dictation)
                Picker("Mode", selection: $hold) {
                    Text("Maintenir pour parler").tag(true)
                    Text("Appuyer pour démarrer / arrêter").tag(false)
                }
                Picker("Langue", selection: $locale) {
                    Text("Français").tag("fr-FR")
                    Text("English (US)").tag("en-US")
                    Text("English (UK)").tag("en-GB")
                }
                Defaults.Toggle("Pastille autour de la notch", key: .activityDictation)
            } header: {
                Text("Dictée")
            } footer: {
                Text("Transcription sur le Mac (modèle Apple, téléchargé à la première utilisation de chaque langue). Le texte est collé dans l'app active. Tu peux dicter la ponctuation : « virgule », « point d'interrogation », « à la ligne ». Avec un texte sélectionné, une consigne (« raccourcis », « traduis en anglais », « reformule plus formel ») le réécrit ; sinon ce que tu dictes le remplace.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle("Nettoyer avec l'IA Apple", key: .dictationCleanup)
            } header: {
                Text("Nettoyage")
            } footer: {
                Text("Ponctuation, majuscules, « euh » retirés. Si le modèle n'est pas disponible, le texte brut est collé.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                TextEditor(text: $substitutions)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 110)
            } header: {
                Text("Substitutions")
            } footer: {
                Text("Une règle par ligne : « avant => après ». Mot entier, sans tenir compte des majuscules. Ex. : « boring notch => Boring Notch ».")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions, id: \.self) { rule in
                        HStack {
                            Text(rule).font(.system(.body, design: .monospaced))
                            Spacer()
                            Button("Accepter") {
                                substitutions += (substitutions.isEmpty || substitutions.hasSuffix("\n") ? "" : "\n") + rule + "\n"
                                suggestions.removeAll { $0 == rule }
                            }
                            Button("Ignorer", role: .destructive) { suggestions.removeAll { $0 == rule } }
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text("Suggestions apprises")
                } footer: {
                    Text("Sélectionne un mot mal transcrit, puis redicte-le : la correction apparaît ici. Les mots acceptés guident aussi la reconnaissance.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Defaults.Toggle("Conserver l'historique", key: .dictationKeepHistory)
                if keepHistory {
                    TextField("Rechercher", text: $query).textFieldStyle(.roundedBorder)
                    let shown = history.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }
                    if shown.isEmpty {
                        Text(history.isEmpty ? "Aucune dictée pour l'instant." : "Aucun résultat.").foregroundStyle(.secondary)
                    }
                    ForEach(shown.prefix(50)) { e in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(e.text).lineLimit(4).textSelection(.enabled)
                            HStack {
                                Text(e.date, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Copier") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(e.text, forType: .string) }
                                Button("Supprimer", role: .destructive) { history.removeAll { $0.id == e.id } }
                            }
                            .buttonStyle(.borderless).font(.caption)
                        }
                        .padding(.vertical, 2)
                    }
                    if !history.isEmpty { Button("Tout effacer", role: .destructive) { history = [] } }
                }
            } header: {
                Text("Historique")
            } footer: {
                Text("Stocké uniquement sur ce Mac (200 dictées maximum).").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Dictée")
    }
}
