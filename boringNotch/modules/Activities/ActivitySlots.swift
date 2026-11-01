//
//  ActivitySlots.swift
//  boringNotch
//
//  Activités autour de la notch fermée : deux emplacements (gauche, droite), les deux plus prioritaires s'affichent.
//  Ajouter une activité = une source qui renvoie une `Activity?` et une ligne dans `ActivitySlots.items`.
//

import Defaults
import SwiftUI

struct Activity: Identifiable {
    let id: String
    let priority: Int      // plus grand = plus important (micro/caméra 100, jamais masqués)
    let view: AnyView
}

struct ActivitySlots: View {
    let height: CGFloat
    let notchWidth: CGFloat
    let openAgents: () -> Void

    @ObservedObject private var agents = AgentStore.shared
    @ObservedObject private var privacy = PrivacyMonitor.shared
    @ObservedObject private var downloads = DownloadMonitor.shared
    @ObservedObject private var awake = StayAwake.shared
    @ObservedObject private var events = ActivityEvents.shared
    @Default(.activityAgents) private var showAgents

    // ponytail: tout est recalculé chaque seconde (durées, expirations) ; un tick par source si ça coûte un jour.
    private func items(_ now: Date) -> [Activity] {
        [
            privacy.activity(now: now, height: height),
            showAgents ? agents.activity(now: now, height: height, onTap: openAgents) : nil,
            downloads.activity(height: height),
            events.activity(now: now, height: height),
            awake.activity(now: now, height: height),
        ]
        .compactMap { $0 }
        .sorted { $0.priority > $1.priority }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let shown = Array(items(ctx.date).prefix(2))
            HStack(spacing: 0) {
                HStack { Spacer(minLength: 0); slot(shown.first, anchor: .trailing) }
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, notchWidth / 2 + 6)
                HStack { slot(shown.dropFirst().first, anchor: .leading); Spacer(minLength: 0) }
                    .frame(maxWidth: .infinity)
                    .padding(.leading, notchWidth / 2 + 6)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: shown.map(\.id))
        }
        .frame(height: height)
    }

    @ViewBuilder private func slot(_ a: Activity?, anchor: UnitPoint) -> some View {
        if let a {
            a.view
                .id(a.id)
                .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: anchor)))
        }
    }
}

/// Fond commun des pastilles : capsule noire à la hauteur de la notch fermée.
struct ActivityPill<Content: View>: View {
    let height: CGFloat
    var help: String = ""
    var action: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        let pill = HStack(spacing: 5) { content }
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: max(height - 4, 20))
            .background(Capsule().fill(.black))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .help(help)
        if let action {
            Button(action: action) { pill.contentShape(Capsule()) }.buttonStyle(.plain)
        } else {
            pill
        }
    }
}

/// 75 s → « 1:15 », 3 725 s → « 1:02:05 ».
func activityDuration(_ t: TimeInterval) -> String {
    let s = max(0, Int(t))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                     : String(format: "%d:%02d", s / 60, s % 60)
}
