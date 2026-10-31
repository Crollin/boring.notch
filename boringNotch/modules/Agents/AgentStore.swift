//
//  AgentStore.swift
//  boringNotch
//

import AppKit

@MainActor
final class AgentStore: ObservableObject {
    static let shared = AgentStore()

    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var lastFinished: Date?   // dernier Stop, pour l'état « terminé » de la pastille
    @Published private(set) var usage: [String: UsageLimits] = [:]   // par source (claude, codex...)

    private static let key = "agentSessions"

    /// Sessions restaurées au lancement (état inconnu = terminé) pour ne pas perdre les conversations
    /// ouvertes quand l'app redémarre ; elles se remettent à jour à leur prochain événement.
    private struct Saved: Codable {
        var id, source: String
        var cwd, title, app: String?
        var startedAt, updatedAt: Date
    }

    init() {
        let saved = (UserDefaults.standard.data(forKey: Self.key)).flatMap { try? JSONDecoder().decode([Saved].self, from: $0) } ?? []
        sessions = saved.filter { Date().timeIntervalSince($0.updatedAt) < 24 * 3600 }.map {
            var s = AgentSession(id: $0.id, source: $0.source, cwd: $0.cwd, startedAt: $0.startedAt, updatedAt: $0.updatedAt)
            s.title = $0.title; s.app = $0.app; s.state = .done
            return s
        }
    }

    private func save() {
        let saved = sessions.map { Saved(id: $0.id, source: $0.source, cwd: $0.cwd, title: $0.title, app: $0.app,
                                         startedAt: $0.startedAt, updatedAt: $0.updatedAt) }
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Self.key)
    }

    var activeCount: Int { sessions.filter(\.isActive).count }
    var needsAttention: Bool { sessions.contains { $0.state == .waiting && Date().timeIntervalSince($0.updatedAt) < 600 } }

    /// Session vers laquelle ramène la pastille : validation en attente > au travail > la plus récente.
    var focusSession: AgentSession? {
        sessions.first { $0.state == .waiting } ?? sessions.first { $0.isActive } ?? sessions.first
    }

    /// Ramène au premier plan le terminal / l'IDE qui héberge la conversation.
    /// ponytail: active l'app seulement ; sélectionner l'onglet exact demanderait AppleScript par terminal.
    func openTerminal(_ s: AgentSession) {
        // ponytail: Termix par défaut quand l'app n'est pas connue ; à rendre configurable si besoin.
        let id = s.app ?? "com.karmaa.termix"
        // openApplication active aussi une app déjà lancée ; NSRunningApplication.activate est ignoré depuis une app non active.
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg)
    }

    /// Réponses en attente d'une décision, par session (hook PermissionRequest bloquant).
    private var responders: [String: (String?) -> Void] = [:]

    /// Autoriser / refuser depuis le notch : renvoie la décision au hook, qui la transmet à l'agent.
    func decide(_ sid: String, allow: Bool) {
        guard let r = responders.removeValue(forKey: sid) else { return }
        let decision = allow ? "{\"behavior\":\"allow\"}" : "{\"behavior\":\"deny\",\"message\":\"Refusé depuis Boring Notch\"}"
        r("{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":\(decision)}}")
        guard var s = sessions.first(where: { $0.id == sid }) else { return }
        s.pending = nil; s.state = .thinking
        upsert(s)
    }

    func apply(_ env: AgentEnvelope, reply: ((String?) -> Void)? = nil) {
        let p = env.payload
        if let l = p.rate_limits { applyUsage(l, source: env.source) }
        guard let sid = p.session_id else { return }

        // Une nouvelle session vue via la status line est inactive (état .done) jusqu'à son prochain événement.
        var s = sessions.first { $0.id == sid }
            ?? AgentSession(id: sid, source: env.source, cwd: p.cwd, state: .done, startedAt: .now, updatedAt: .now)
        s.cwd = p.cwd ?? s.cwd
        s.app = env.app.flatMap { $0.isEmpty ? nil : $0 } ?? s.app
        if env.kind == "statusline" { upsert(s); return }
        if let f = p.tool_input?.file_path { s.file = f }
        let wasWaiting = s.state == .waiting
        s.pending = nil
        // Une autre activité de la session = la validation a été traitée ailleurs (terminal) : on libère le hook.
        if p.hook_event_name != "PermissionRequest" { responders.removeValue(forKey: sid)?(nil) }

        switch p.hook_event_name {
        case "UserPromptSubmit":
            if s.title == nil, let t = p.prompt?.split(whereSeparator: \.isNewline).first { s.title = String(t) }
            s.state = .thinking
        case "PreToolUse":
            s.state = .running(tool: p.tool_name ?? "…")
            startStep(&s, p)
        case "PostToolUse":
            s.state = .thinking
            finishStep(&s, p)
        case "PermissionRequest":
            s.state = .waiting
            if let reply { responders.removeValue(forKey: sid)?(nil); responders[sid] = reply }
            s.pending = Self.label(p.tool_name ?? "…", p.tool_input)
            if !wasWaiting { NSSound(named: "Glass")?.play() }
        case "Stop":
            s.state = .done
            lastFinished = .now
            for i in s.steps.indices where !s.steps[i].done { s.steps[i].duration = Date().timeIntervalSince(s.steps[i].started) }
        case "SessionEnd":
            sessions.removeAll { $0.id == sid }
            save()
            return
        default: break
        }
        s.updatedAt = .now
        upsert(s)
    }

    /// Met la session en tête de liste (ou la crée) sans toucher à son état.
    private func upsert(_ s: AgentSession) {
        var s = s
        if sessions.first(where: { $0.id == s.id }) != nil, s.state == .done { s.updatedAt = .now }
        sessions.removeAll { $0.id == s.id }
        sessions.insert(s, at: 0)
        save()
    }

    // MARK: Étapes

    private func startStep(_ s: inout AgentSession, _ p: AgentEnvelope.Payload) {
        let tool = p.tool_name ?? "…"
        let input = p.tool_input
        let file = input?.file_path
        s.steps.append(AgentStep(id: p.tool_use_id ?? UUID().uuidString, tool: tool,
                                 label: Self.label(tool, input), file: file, started: .now))
        if s.steps.count > 30 { s.steps.removeFirst(s.steps.count - 30) }

        // Lignes modifiées : estimation à partir des chaînes de l'outil (ponytail: pas un vrai diff).
        guard let file, ["Edit", "Write", "MultiEdit"].contains(tool) else { return }
        func lines(_ t: String?) -> Int { t.map { $0.split(separator: "\n", omittingEmptySubsequences: false).count } ?? 0 }
        var d = s.diffs[file] ?? LineDiff()
        for e in input?.edits ?? [] { d.added += lines(e.new_string); d.removed += lines(e.old_string) }
        d.added += lines(input?.new_string) + lines(input?.content)
        d.removed += lines(input?.old_string)
        s.diffs[file] = d
    }

    private func finishStep(_ s: inout AgentSession, _ p: AgentEnvelope.Payload) {
        let i = s.steps.lastIndex { p.tool_use_id != nil ? $0.id == p.tool_use_id : ($0.tool == p.tool_name && !$0.done) }
        if let i { s.steps[i].duration = Date().timeIntervalSince(s.steps[i].started) }
    }

    private static func label(_ tool: String, _ i: AgentEnvelope.ToolInput?) -> String {
        if let f = i?.file_path { return "\(tool) \((f as NSString).lastPathComponent)" }
        let text = i?.description ?? i?.command?.split(whereSeparator: \.isNewline).first.map(String.init)
        if tool == "Bash", let text { return "Run \(text.prefix(40))" }
        if let q = i?.pattern ?? text { return "\(tool) \(q.prefix(40))" }
        return tool
    }

    // MARK: Limites

    private func applyUsage(_ l: AgentEnvelope.Limits, source: String) {
        func map(_ w: AgentEnvelope.Window?) -> RateLimit? {
            w?.used_percentage.map { RateLimit(usedPercent: $0, resetsAt: w?.resets_at?.date) }
        }
        let old = usage[source]
        usage[source] = UsageLimits(fiveHour: map(l.five_hour) ?? old?.fiveHour,
                                    sevenDay: map(l.seven_day) ?? old?.sevenDay,
                                    updatedAt: .now)
    }
}
