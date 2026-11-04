//
//  FocusModule.swift
//  boringNotch
//
//  Onglet « Focus » : minuteur, Pomodoro et « Rester éveillé » réglables depuis le notch.
//

import Defaults
import SwiftUI

struct FocusModule: NotchModule {
    let id = "focus"
    let label = "Focus"
    let icon = "timer"

    func start() {}

    @MainActor func makeView() -> AnyView { AnyView(FocusView()) }
}

private struct FocusView: View {
    @ObservedObject private var timer = NotchTimer.shared
    @ObservedObject private var awake = StayAwake.shared
    @State private var minutes = 25.0

    var body: some View {
        // Une seconde de résolution pour les temps restants.
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 8) {
                timerBlock(now: ctx.date)
                Divider()
                pomodoroBlock
                Divider()
                awakeBlock(now: ctx.date)
            }
        }
        .padding(.horizontal, 4)
        .font(.system(size: 12))
    }

    private func timerBlock(now: Date) -> some View {
        HStack(spacing: 6) {
            Label("Minuteur", systemImage: "timer").frame(width: 110, alignment: .leading)
            if let end = timer.end, timer.phase == nil {
                Text(activityDuration(end.timeIntervalSince(now).rounded(.up))).monospacedDigit()
                Spacer()
                Button("Arrêter") { timer.stop() }
            } else {
                ForEach(NotchTimer.presets, id: \.self) { m in
                    Button("\(m)") { timer.start(minutes: m) }.buttonStyle(.bordered).controlSize(.small)
                }
                Slider(value: $minutes, in: 1...120, step: 1)
                Text("\(Int(minutes)) min").monospacedDigit().frame(width: 50, alignment: .trailing)
                Button("Lancer") { timer.start(minutes: Int(minutes)) }
            }
        }
    }

    private var pomodoroBlock: some View {
        HStack(spacing: 6) {
            Label("Pomodoro", systemImage: "brain.head.profile").frame(width: 110, alignment: .leading)
            if let phase = timer.phase {
                Text(phaseText(phase))
                Spacer()
                Button("Arrêter") { timer.stop() }
            } else {
                Text("\(Defaults[.pomodoroFocusMinutes]) min de focus, \(Defaults[.pomodoroShortMinutes]) min de pause").foregroundStyle(.secondary)
                Spacer()
                Button("Démarrer") { timer.startPomodoro() }
            }
        }
    }

    private func phaseText(_ p: FocusPhase) -> String {
        let total = Defaults[.pomodoroLongEvery]
        switch p {
        case .focus(let r): return "Focus \(r)/\(total)"
        case .shortBreak(let r): return "Pause \(r)/\(total)"
        case .longBreak: return "Pause longue"
        }
    }

    private func awakeBlock(now: Date) -> some View {
        HStack(spacing: 6) {
            Label("Rester éveillé", systemImage: "cup.and.saucer").frame(width: 110, alignment: .leading)
            if let until = awake.until {
                Text(until == .distantFuture ? "Indéfiniment" : activityDuration(until.timeIntervalSince(now))).monospacedDigit()
                Spacer()
                Button("Arrêter") { awake.stop() }
            } else {
                Button("1 h") { awake.start(for: 3600) }.buttonStyle(.bordered).controlSize(.small)
                Button("2 h") { awake.start(for: 7200) }.buttonStyle(.bordered).controlSize(.small)
                Button("4 h") { awake.start(for: 4 * 3600) }.buttonStyle(.bordered).controlSize(.small)
                Button("Indéfiniment") { awake.start(for: nil) }.buttonStyle(.bordered).controlSize(.small)
                Spacer()
                Defaults.Toggle("Garder l'écran allumé", key: .stayAwakeDisplay)
            }
        }
    }
}
