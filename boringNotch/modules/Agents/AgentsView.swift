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

extension AgentStep {
    var symbol: String {
        switch tool {
        case "Bash": "terminal"
        case "Read": "doc.text"
        case "Edit", "Write", "MultiEdit": "pencil"
        case "Grep", "Glob": "magnifyingglass"
        case "Task", "Agent": "person.2"
        case "WebFetch", "WebSearch": "globe"
        default: "wrench.adjustable"
        }
    }
    var kind: String {
        switch tool {
        case "Bash": "Commande"
        case "Read": "Lecture"
        case "Edit", "Write", "MultiEdit": "Édition"
        case "Grep", "Glob": "Recherche"
        case "Task", "Agent": "Sous-agent"
        case "WebFetch", "WebSearch": "Web"
        default: tool
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

extension AgentSession {
    /// Même code couleur que la bulle : rouge = validation, orange = travail, vert = repos.
    var tint: Color { state == .waiting ? .red : isActive ? .orange : awaitsReply ? .blue : .green }
    var stateText: String {
        switch state {
        case .waiting: "Validation requise"
        case .thinking where isActive: "Réfléchit…"
        case .running where isActive: "Au travail"
        default: awaitsReply ? "Attend votre réponse" : "Au repos"
        }
    }
}

private let secondary = Color.white.opacity(0.5)
private let cardFill = Color.white.opacity(0.07)
private let cardStroke = Color.white.opacity(0.10)

/// Liquid Glass (macOS 26+) teinté ; repli sur un fond translucide + liseré avant.
private extension View {
    @ViewBuilder func glass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            self.background(shape.fill(.white.opacity(0.04)))
                .glassEffect(interactive ? .regular.tint(tint?.opacity(0.35)).interactive() : .regular.tint(tint?.opacity(0.35)), in: shape)
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
        // Hauteur du notch ouvert fixe (190) : on ne déborde jamais, sinon la mise en page remonte hors de l'écran.
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 8) {
            Label(mode == .progress ? "Progression" : "Forfait",
                  systemImage: mode == .progress ? "checklist" : "gauge.with.dots.needle.50percent")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(secondary)
            Spacer()
            if mode == .progress, store.sessions.count > 1 {
                ForEach(store.sessions.filter { $0.cwd != nil }.prefix(4)) { chip($0) }
            }
            roundButton("checklist", active: mode == .progress) { mode = .progress }
            roundButton("gauge.with.dots.needle.50percent", active: mode == .usage) { mode = .usage }
        }
    }

    private func chip(_ s: AgentSession) -> some View {
        let on = s.id == session?.id
        return Button { selected = s.id } label: {
            HStack(spacing: 5) {
                Circle().fill(s.tint).frame(width: 6, height: 6)
                Text(s.project).lineLimit(1)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(on ? .white : secondary)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .glass(Capsule(), tint: on ? s.tint : nil, interactive: true)
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
        Button { AgentStore.shared.openTerminal(s) } label: { agentHeaderContent(s) }
            .buttonStyle(.plain)
            .help("Ouvrir le terminal")
    }

    private func agentHeaderContent(_ s: AgentSession) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(.black)
                Circle().stroke(s.tint.opacity(0.55), lineWidth: 1.5)
                if s.source == "claude" {
                    Mascot(color: s.tint).scaleEffect(0.8)
                } else {
                    Image(systemName: agentIcon(s.source)).font(.system(size: 12)).foregroundStyle(s.tint)
                }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title ?? s.project)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 5) {
                    Text(s.source.capitalized + " · " + s.project).foregroundStyle(secondary)
                    Text(s.stateText).foregroundStyle(s.tint)
                }
                .font(.system(size: 10.5, weight: .medium)).lineLimit(1)
            }
            Image(systemName: "arrow.up.forward.app").font(.system(size: 10)).foregroundStyle(secondary)
        }
        .contentShape(Rectangle())
    }

    private func stepList(_ s: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if s.steps.isEmpty {
                Text(s.isActive ? s.state.label : "En attente d'un prompt")
                    .font(.system(size: 12)).foregroundStyle(secondary)
            }
            let steps = Array(s.steps.suffix(3))
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                HStack(spacing: 9) {
                    ZStack {
                        // fil de la timeline
                        Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
                            .padding(.top, i == 0 ? 10 : 0).padding(.bottom, i == steps.count - 1 ? 10 : 0)
                        Circle().fill(.black).frame(width: 14, height: 14)
                        Image(systemName: step.done ? step.symbol : "circle.dotted")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(step.done ? secondary : s.tint)
                    }
                    .frame(width: 14, height: 20)
                    Text(step.label).font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(step.done ? 0.65 : 1)).lineLimit(1)
                    Spacer(minLength: 6)
                    if let d = step.duration {
                        Text(String(format: "%.1fs", d)).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.white.opacity(0.3))
                    }
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
    private var waiting: Bool { session.state == .waiting }
    private var running: Bool { session.isActive && (step.map { !$0.done } ?? false) }
    private var tint: Color { session.tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: waiting ? "exclamationmark.shield.fill" : (step?.symbol ?? "folder.fill"))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.16)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                    Text(status).font(.system(size: 10.5, weight: .medium)).foregroundStyle(waiting || running ? tint : secondary)
                }
                Spacer(minLength: 4)
                if step?.isEdit == true, let f = step?.file, let d = session.diffs[f] {
                    Text("+\(d.added)").foregroundStyle(.green)
                    Text("−\(d.removed)").foregroundStyle(.red)
                }
            }
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            if let detail {
                Text(detail).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2).truncationMode(.middle)
            }
            if waiting {
                HStack(spacing: 8) {
                    decisionButton("Refuser", tint: nil) { AgentStore.shared.decide(session.id, allow: false) }
                    decisionButton("Autoriser", tint: .red) { AgentStore.shared.decide(session.id, allow: true) }
                }
            } else if running {
                ProgressLine(running: true, color: tint)
            }
        }
        .padding(11)
        .glass(RoundedRectangle(cornerRadius: 16, style: .continuous), tint: waiting ? .red : nil)
    }

    private func decisionButton(_ label: String, tint: Color?, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .glass(Capsule(), tint: tint, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        if waiting { return "Validation requise" }
        if let f = step?.file { return (f as NSString).lastPathComponent }
        return step?.kind ?? session.project
    }

    private var status: String {
        if waiting { return "En attente de votre accord" }
        guard let step else { return session.stateText }
        if let d = step.duration { return String(format: "Terminé · %.1f s", d) }
        return step.isEdit ? "Écriture…" : "En cours…"
    }

    private var detail: String? {
        if waiting { return session.pending }
        guard let step, step.file == nil else { return nil }
        return step.label
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

/// Bulle détachée à côté du notch (à la Droppy) : la mascotte pixel de l'agent, sans texte.
/// - travail : mascotte orange qui « marche » (deux images de pattes en alternance)
/// - validation : mascotte rouge qui se agite + liseré rouge qui pulse
/// - réponse attendue : mascotte bleue qui sautille + « ? » (une conversation attend votre suite)
/// - repos : bulle réduite, mascotte verte atténuée et immobile
private struct AgentBubble: View {
    enum Kind { case working, attention, reply, idle }
    let kind: Kind
    var badge = false      // une autre conversation attend une réponse
    let height: CGFloat
    @State private var pulse = false

    private var tint: Color { kind == .attention ? .red : kind == .idle ? .green : kind == .reply ? .blue : .orange }
    private var diameter: CGFloat { max(height - 4, 20) * (kind == .idle ? 0.78 : 1) }

    var body: some View {
        ZStack {
            Circle().fill(.black)
            if kind == .attention {
                Circle().stroke(tint.opacity(pulse ? 0.9 : 0.25), lineWidth: 1.5)
                    .animation(.easeInOut(duration: 0.7).repeatForever(), value: pulse)
            }
            PixelMascot(color: tint, walking: kind == .working)
                .scaleEffect(kind == .idle ? 0.8 : 1)
                .offset(y: kind == .reply && pulse ? -1.5 : 0)
                .animation(kind == .reply ? .easeInOut(duration: 0.55).repeatForever() : .default, value: pulse)
                .opacity(kind == .idle ? 0.6 : 1)
                .rotationEffect(.degrees(kind == .attention ? (pulse ? 7 : -7) : 0))
                .animation(kind == .attention ? .easeInOut(duration: 0.16).repeatForever() : .default, value: pulse)
        }
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .topTrailing) {
            if kind == .reply || badge {
                Text("?").font(.system(size: 7, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 11, height: 11).background(Circle().fill(Color.blue))
                    .overlay(Circle().stroke(.black, lineWidth: 1.5))
                    .offset(x: 3, y: -2).transition(.scale)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: kind)
        .onAppear { pulse = true }
    }
}

private struct PixelMascot: View {
    let color: Color
    let walking: Bool
    private static let body = [".#.....#.", "#########", "##.###.##", "#########"]
    private static let legsA = [".#.#.#.#.", "#.#...#.#"]
    private static let legsB = ["#.#.#.#.#", ".#.....#."]
    private let px: CGFloat = 2.1

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.32)) { t in
            let alt = walking && Int(t.date.timeIntervalSinceReferenceDate / 0.32) % 2 == 1
            let rows = Self.body + (alt ? Self.legsB : Self.legsA)
            Canvas { ctx, _ in
                for (y, row) in rows.enumerated() {
                    for (x, c) in row.enumerated() where c == "#" {
                        ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px)), with: .color(color))
                    }
                }
            }
            .frame(width: px * 9, height: px * 6)
        }
    }
}

/// Bulle à gauche du notch fermé.
/// Visible tant qu'une conversation est ouverte ; priorité : validation > travail > repos.
struct AgentsPill: View {
    var height: CGFloat = 32
    var onTap: () -> Void = {}
    @ObservedObject private var store = AgentStore.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let open = store.sessions.contains { ctx.date.timeIntervalSince($0.updatedAt) < 4 * 3600 }
            let kind: AgentBubble.Kind? = store.needsAttention ? .attention
                : store.activeCount > 0 ? .working : store.needsReply ? .reply : open ? .idle : nil
            if let kind {
                Button(action: onTap) {
                    AgentBubble(kind: kind, badge: store.needsReply, height: height).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .trailing)))
                .help("Ouvrir l'onglet Agents")
            }
        }
    }
}
