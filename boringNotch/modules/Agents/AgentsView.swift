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

/// Liquid Glass (macOS 26+) teinté ; repli sur un fond translucide + liseré avant.
private extension View {
    @ViewBuilder func glass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(interactive ? .regular.tint(tint?.opacity(0.35)).interactive() : .regular.tint(tint?.opacity(0.35)), in: shape)
        } else {
            self.background(shape.fill(tint?.opacity(0.18) ?? cardFill)).overlay(shape.stroke(cardStroke))
        }
    }
}

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
            .glass(Capsule(), tint: on ? accent(s.source) : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func roundButton(_ icon: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Color.green : secondary)
                .frame(width: 26, height: 26)
                .glass(Circle(), tint: active ? .green : nil, interactive: true)
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

    private func openTerminal(_ s: AgentSession) { AgentStore.shared.openTerminal(s) }

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
            if waiting {
                HStack(spacing: 8) {
                    decisionButton("Refuser", tint: nil, text: .white) { AgentStore.shared.decide(session.id, allow: false) }
                    decisionButton("Autoriser", tint: .orange, text: .white) { AgentStore.shared.decide(session.id, allow: true) }
                }
                .padding(.top, 2)
            }
            ProgressLine(running: waiting || (step.map { !$0.done } ?? false && session.isActive), color: waiting ? .orange : color)
        }
        .padding(10)
        .glass(RoundedRectangle(cornerRadius: 16, style: .continuous), tint: waiting ? .orange : nil)
    }

    private func decisionButton(_ label: String, tint: Color?, text: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(text)
                .frame(maxWidth: .infinity).padding(.vertical, 5)
                .glass(Capsule(), tint: tint, interactive: true)
        }
        .buttonStyle(.plain)
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
        .glass(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

/// Indicateur de la pastille : anneau orange qui tourne (travail), point d'exclamation rouge (validation), coche verte (terminé).
private struct StatusRing: View {
    enum Kind { case working, attention, done }
    let kind: Kind
    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            switch kind {
            case .working:
                Circle().stroke(Color.orange.opacity(0.25), lineWidth: 2)
                Circle().trim(from: 0, to: 0.7).stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
            case .attention:
                Circle().fill(Color.red.opacity(pulse ? 0.9 : 0.5))
                    .animation(.easeInOut(duration: 0.6).repeatForever(), value: pulse)
                Text("!").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
            case .done:
                Circle().fill(Color.green)
                Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.black)
            }
        }
        .frame(width: 14, height: 14)
        .onAppear { spin = true; pulse = true }
    }
}

/// Island à gauche du notch fermé : même langage visuel que le notch / la live activity Spotify
/// (bord haut droit collé en haut, coins arrondis uniquement en bas).
/// États : validation requise (rouge) > au travail (orange + anneau) > terminé (vert, 10 s).
struct AgentsPill: View {
    var height: CGFloat = 32
    var onTap: () -> Void = {}
    @ObservedObject private var store = AgentStore.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let justDone = store.lastFinished.map { ctx.date.timeIntervalSince($0) < 10 } ?? false
            let kind: StatusRing.Kind? = store.needsAttention ? .attention
                : store.activeCount > 0 ? .working : justDone ? .done : nil
            if let kind {
                let tint: Color = kind == .attention ? Color.red : kind == .done ? Color.green : Color.orange
                Button(action: onTap) {
                    StatusRing(kind: kind).id(kind)
                        .padding(.horizontal, 14)
                        .frame(height: height)
                    .background(LinearGradient(colors: [.black, tint.opacity(0.28)], startPoint: .top, endPoint: .bottom))
                    .background(.black)
                    .clipShape(NotchShape(topCornerRadius: 6, bottomCornerRadius: 12))
                    .overlay(NotchShape(topCornerRadius: 6, bottomCornerRadius: 12).stroke(tint.opacity(0.4), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .shadow(color: tint.opacity(kind == .done ? 0.25 : 0.4), radius: 8, y: 2)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: kind)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
                .help("Ouvrir l'onglet Agents")
            }
        }
    }
}
