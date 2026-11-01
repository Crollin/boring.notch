//
//  StayAwake.swift
//  boringNotch
//
//  Empêche la mise en veille du Mac (l'écran peut s'éteindre). Menu de la barre des menus + raccourci ; clic = arrêter.
//

import Defaults
import IOKit.pwr_mgt
import SwiftUI

@MainActor
final class StayAwake: ObservableObject {
    static let shared = StayAwake()

    @Published private(set) var until: Date?      // .distantFuture = indéfiniment
    private var assertion = IOPMAssertionID(0)
    private var stopTask: Task<Void, Never>?

    var isOn: Bool { until != nil }

    /// `duration` nil = jusqu'à l'arrêt manuel.
    func start(for duration: TimeInterval?) {
        stop()
        guard IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                          IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                          "Boring Notch : rester éveillé" as CFString, &assertion) == kIOReturnSuccess
        else { return }
        until = duration.map { Date().addingTimeInterval($0) } ?? .distantFuture
        if let duration {
            stopTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                if !Task.isCancelled { self?.stop() }
            }
        }
    }

    func stop() {
        stopTask?.cancel(); stopTask = nil
        if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
        until = nil
    }

    func toggle() { isOn ? stop() : start(for: nil) }

    func activity(now: Date, height: CGFloat) -> Activity? {
        guard let until, Defaults[.activityStayAwake] else { return nil }
        return Activity(id: "awake", priority: 20, view: AnyView(
            ActivityPill(height: height, help: "Rester éveillé — cliquer pour arrêter", action: { StayAwake.shared.stop() }) {
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(.orange)
                if until != .distantFuture { Text(activityDuration(until.timeIntervalSince(now))) }
            }
        ))
    }
}

/// Entrées du menu de la barre des menus.
struct StayAwakeMenu: View {
    @ObservedObject private var awake = StayAwake.shared

    var body: some View {
        Menu("Rester éveillé") {
            Button("1 heure") { awake.start(for: 3600) }
            Button("2 heures") { awake.start(for: 7200) }
            Button("4 heures") { awake.start(for: 4 * 3600) }
            Button("Indéfiniment") { awake.start(for: nil) }
            if awake.isOn {
                Divider()
                Button("Arrêter") { awake.stop() }
            }
        }
    }
}
