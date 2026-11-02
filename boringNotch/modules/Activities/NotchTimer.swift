//
//  NotchTimer.swift
//  boringNotch
//
//  Minuteur : compte à rebours en pastille autour de la notch (clic = arrêter), son + pastille
//  « Terminé » qui clignote à la fin. Menu de la barre des menus + raccourci, comme « Rester éveillé ».
//

import AppKit
import Defaults
import SwiftUI

@MainActor
final class NotchTimer: ObservableObject {
    static let shared = NotchTimer()
    static let presets = [5, 10, 15, 25, 45, 60]   // minutes

    @Published private(set) var end: Date?
    @Published private(set) var finishedAt: Date?
    private var task: Task<Void, Never>?

    var isOn: Bool { end != nil }

    func start(minutes: Int) {
        stop()
        let duration = TimeInterval(minutes * 60)
        end = Date().addingTimeInterval(duration)
        // Task.sleep suit l'horloge continue : la veille du Mac compte dans le temps écoulé.
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            if !Task.isCancelled { self?.finish() }
        }
    }

    func stop() {
        task?.cancel(); task = nil
        end = nil
        finishedAt = nil
    }

    func toggle() {
        isOn ? stop() : start(minutes: Defaults[.timerShortcutMinutes])
    }

    private func finish() {
        end = nil
        finishedAt = .now
        NSSound(named: "Glass")?.play()
        // La pastille « Terminé » reste une minute, sauf clic.
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            if !Task.isCancelled { self?.finishedAt = nil }
        }
    }

    func activity(now: Date, height: CGFloat) -> Activity? {
        if let end {
            return Activity(id: "timer", priority: 60, view: AnyView(
                ActivityPill(height: height, help: "Minuteur — cliquer pour arrêter", action: { NotchTimer.shared.stop() }) {
                    Image(systemName: "timer").foregroundStyle(.orange)
                    Text(activityDuration(end.timeIntervalSince(now).rounded(.up)))
                }
            ))
        }
        guard let finishedAt else { return nil }
        // Clignote une seconde sur deux (la vue est recalculée chaque seconde par ActivitySlots).
        let blink = Int(now.timeIntervalSince(finishedAt)) % 2 == 0
        return Activity(id: "timer", priority: 90, view: AnyView(
            ActivityPill(height: height, help: "Minuteur terminé — cliquer pour masquer", action: { NotchTimer.shared.stop() }) {
                Image(systemName: "timer").foregroundStyle(blink ? .orange : .white)
                Text("Terminé")
            }
        ))
    }
}

/// Entrées du menu de la barre des menus.
struct TimerMenu: View {
    @ObservedObject private var timer = NotchTimer.shared

    var body: some View {
        Menu("Minuteur") {
            ForEach(NotchTimer.presets, id: \.self) { m in
                Button("\(m) min") { timer.start(minutes: m) }
            }
            if timer.isOn {
                Divider()
                Button("Arrêter") { timer.stop() }
            }
        }
    }
}
