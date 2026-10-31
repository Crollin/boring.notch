//
//  AgentsView.swift
//  boringNotch
//
//  Design inspiré de NotchNook : en-tête « Progression » + boutons ronds,
//  agent + statut en couleur d'accent, étapes cochées, carte d'activité à droite.
//

import SwiftUI

// MARK: - Style par agent / état

extension AgentState {
    var color: Color {
        switch self {
        case .thinking: .blue
        case .running: .green
        case .waiting: .orange
        case .done: .gray
        }
    }
    var label: String {
        switch self {
        case .thinking: "Réfléchit…"
        case .running(let tool): tool
        case .waiting: "Attend une approbation"
        case .done: "Terminé"
        }
    }
}

private func agentIcon(_ source: String) -> String {
    switch source {
    case "claude": "sparkle"
    case "codex": "chevron.left.forwardslash.chevron.right"
    case "cursor": "cursorarrow.rays"
    default: "terminal"
    }
}

private func accent(_ source: String) -> Color {
    switch source {
    case "claude": Color(red: 0.93, green: 0.50, blue: 0.27)
    case "codex": Color(red: 0.55, green: 0.68, blue: 1.0)
    default: .white
    }
}

private let secondary = Color.white.opacity(0.5)
private let cardFill = Color.white.opacity(0.07)
private let cardStroke = Color.white.opacity(0.10)

// MARK: - Onglet

struct AgentsView: View {
    private enum Mode { case progress, usage }

    @ObservedObject private var store = AgentStore.shared
    @State private var mode = Mode.progress
    @State private var selected: String?

    private var session: AgentSession? {
        store.sessions.first { $0.id == selected } ?? store.sessions.first
    }
    private var freshUsage: [(source: String, limits: UsageLimits)] {
        store.usage.filter { $0.value.isFresh }.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            switch mode {
            case .progress: progress
            case .usage: usagePage
            }
        }
        .padding(.horizontal, 6)
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 8) {
            Label(mode == .progress ? "Progression" : "Forfait",
                  systemImage: mode == .progress ? "checklist" : "gauge.with.dots.needle.50percent")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(secondary)
            Spacer()
            if mode == .progress, store.sessions.count > 1 {
                ForEach(store.sessions.prefix(4)) { chip($0) }
            }
            roundButton("checklist", active: mode == .progress) { mode = .progress }
            roundButton("gauge.with.dots.needle.50percent", active: mode == .usage) { mode = .usage }
        }
    }

    private func chip(_ s: AgentSession) -> some View {
        let on = s.id == session?.id
        return Button { selected = s.id } label: {
            HStack(spacing: 4) {
                Image(systemName: agentIcon(s.source)).font(.system(size: 8))
                Text(s.project).lineLimit(1)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(on ? accent(s.source) : secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(on ? accent(s.source).opacity(0.18) : .white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func roundButton(_ icon: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Color.green : secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(active ? Color.green.opacity(0.22) : .white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Progression

    @ViewBuilder private var progress: some View {
        if let s = session {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    agentHeader(s)
                    stepList(s)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                ActivityCard(session: s).frame(width: 220)
            }
        } else {
            VStack(spacing: 6) {
                Mascot(color: secondary)
                Text("Aucune session en cours").font(.system(size: 11)).foregroundStyle(secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func agentHeader(_ s: AgentSession) -> some View {
        Button { openTerminal(s) } label: { agentHeaderContent(s) }
            .buttonStyle(.plain)
            .help("Ouvrir le terminal")
    }

    /// Ramène au premier plan le terminal / l'IDE qui héberge la conversation.
    /// ponytail: active l'app seulement ; sélectionner l'onglet exact demanderait AppleScript par terminal.
    private func openTerminal(_ s: AgentSession) {
        // ponytail: Termix par défaut quand l'app n'est pas connue ; à rendre configurable si besoin.
        let id = s.app ?? "com.karmaa.termix"
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id }) {
            app.activate(options: [.activateAllWindows])
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    private func agentHeaderContent(_ s: AgentSession) -> some View {
        HStack(spacing: 8) {
            if s.source == "claude" {
                Mascot(color: accent(s.source))
            } else {
                Image(systemName: agentIcon(s.source)).font(.system(size: 14)).foregroundStyle(accent(s.source))
            }
            Text(s.source.capitalized).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            Circle().fill(s.state == .waiting ? .orange : accent(s.source)).frame(width: 6, height: 6)
            Text(s.title ?? s.project)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(accent(s.source)).lineLimit(1)
            do {
                Image(systemName: "arrow.up.forward.app").font(.system(size: 10)).foregroundStyle(secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func stepList(_ s: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if s.steps.isEmpty {
                Text(s.state == .done ? "En attente d'un prompt" : s.state.label)
                    .font(.system(size: 12)).foregroundStyle(secondary)
            }
            ForEach(s.steps.suffix(3)) { step in
                HStack(spacing: 8) {
                    Image(systemName: step.done ? "checkmark" : "play.fill")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(accent(s.source)).frame(width: 12)
                    Text(step.label).font(.system(size: 12))
                        .foregroundStyle(.white.opacity(step.done ? 0.8 : 1)).lineLimit(1)
                }
            }
        }
    }

    // MARK: Forfait

    @ViewBuilder private var usagePage: some View {
        if freshUsage.isEmpty {
            Text("Aucune limite disponible : lancez une session Claude Code ou Codex.")
                .font(.system(size: 11)).foregroundStyle(secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 10) {
                ForEach(freshUsage, id: \.source) { UsageBlock(source: $0.source, limits: $0.limits) }
            }
        }
    }
}

// MARK: - Carte d'activité

private struct ActivityCard: View {
    let session: AgentSession

    private var step: AgentStep? { session.steps.last }
    private var color: Color { accent(session.source) }

    private var waiting: Bool { session.state == .waiting }
    private var icon: String {
        if waiting { return "exclamationmark.shield.fill" }
        if step == nil { return "folder.fill" }
        return step?.isEdit == true ? "doc.text.fill" : "hammer.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if step?.isEdit == true, let f = step?.file, let d = session.diffs[f] {
                    Text("+\(d.added)").foregroundStyle(.green)
                    Text("−\(d.removed)").foregroundStyle(.red)
                }
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(waiting ? Color.orange : color)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(secondary).lineLimit(2)
            ProgressLine(running: waiting || (step.map { !$0.done } ?? false && session.isActive), color: waiting ? .orange : color)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(waiting ? Color.orange.opacity(0.12) : cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(waiting ? Color.orange.opacity(0.5) : cardStroke))
    }

    private var title: String {
        if waiting { return "Validation requise" }
        if let f = step?.file { return (f as NSString).lastPathComponent }
        return step?.label ?? session.project
    }

    private var subtitle: String {
        if waiting { return session.pending ?? "Une action attend votre accord" }
        guard let step, session.isActive else { return session.isActive ? session.state.label : "Terminé" }
        if let d = step.duration { return String(format: "%.2f s", d) }
        return step.isEdit ? "Enregistrement…" : "En cours…"
    }
}

/// Trait fin : segment qui glisse tant que l'étape tourne, plein sinon.
private struct ProgressLine: View {
    let running: Bool
    let color: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                if running {
                    TimelineView(.animation) { t in
                        let phase = t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        Capsule().fill(color)
                            .frame(width: g.size.width * 0.3)
                            .offset(x: (g.size.width * 0.7) * phase)
                    }
                } else {
                    Capsule().fill(color)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 3)
    }
}

// MARK: - Limites d'usage

private struct UsageBlock: View {
    let source: String
    let limits: UsageLimits

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: agentIcon(source)).font(.system(size: 11))
                Text(source.capitalized).font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(accent(source))
            if let w = limits.fiveHour { UsageLine(title: "5 h", limit: w) }
            if let w = limits.sevenDay { UsageLine(title: "7 j", limit: w) }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(cardStroke))
    }
}

/// « 5 h ▬▬▬▬ 4 % 2 h 10 » sur une seule ligne.
private struct UsageLine: View {
    let title: String
    let limit: RateLimit

    private var color: Color { limit.usedPercent >= 90 ? .red : limit.usedPercent >= 70 ? .orange : .green }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 18, alignment: .leading).foregroundStyle(secondary)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(color).frame(width: g.size.width * min(max(limit.usedPercent, 0), 100) / 100)
                }
            }
            .frame(height: 4)
            Text("\(Int(limit.usedPercent.rounded())) %").monospacedDigit().frame(width: 34, alignment: .trailing)
            Text(limit.resetsAt.map(Self.remaining) ?? "").frame(width: 44, alignment: .trailing).foregroundStyle(secondary)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white)
    }

    static func remaining(_ date: Date) -> String {
        let m = max(0, Int(date.timeIntervalSinceNow / 60))
        if m >= 2880 { return "\(m / 1440) j" }
        if m >= 60 { return "\(m / 60) h \(String(format: "%02d", m % 60))" }
        return "\(m) min"
    }
}

// MARK: - Mascotte, point d'état et island

/// Petite mascotte en pixel art (clin d'œil à NotchNook).
private struct Mascot: View {
    let color: Color
    private static let rows = [".#.....#.", "#########", "##.###.##", "#########", ".#.#.#.#.", "#.#...#.#"]

    var body: some View {
        Canvas { ctx, _ in
            for (y, row) in Self.rows.enumerated() {
                for (x, c) in row.enumerated() where c == "#" {
                    ctx.fill(Path(CGRect(x: CGFloat(x) * 2.5, y: CGFloat(y) * 2.5, width: 2.5, height: 2.5)), with: .color(color))
                }
            }
        }
        .frame(width: 22.5, height: 15)
    }
}

/// Point d'état ; pulse tant que l'agent travaille.
struct StateDot: View {
    let state: AgentState
    @State private var pulse = false

    private var animated: Bool { state != .done }

    var body: some View {
        Circle().fill(state.color)
            .frame(width: 7, height: 7)
            .opacity(animated && pulse ? 0.35 : 1)
            .animation(animated ? .easeInOut(duration: 0.8).repeatForever() : .default, value: pulse)
            .onAppear { pulse = true }
    }
}

/// Island à gauche du notch fermé : même langage visuel que le notch / la live activity Spotify
/// (bord haut droit collé en haut, coins arrondis uniquement en bas).
struct AgentsPill: View {
    var height: CGFloat = 32
    @ObservedObject private var store = AgentStore.shared

    var body: some View {
        if store.activeCount > 0 {
            HStack(spacing: 6) {
                StateDot(state: store.needsAttention ? .waiting : .running(tool: ""))
                Text(store.needsAttention ? "Validation" : "\(store.activeCount)")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(store.needsAttention ? Color.orange : .white)
            }
            .padding(.horizontal, 16)
            .frame(height: height)
            .background(.black)
            .clipShape(NotchShape(topCornerRadius: 6, bottomCornerRadius: 12))
            .fixedSize()
            .transition(.opacity)
        }
    }
}
