//
//  AgentSession.swift
//  boringNotch
//

import Foundation

enum AgentState: Equatable {
    case thinking
    case running(tool: String)
    case waiting          // en attente d'une approbation
    case done
}

/// Une action d'outil de l'agent (Read, Edit, Run…), affichée dans la liste de progression.
struct AgentStep: Identifiable, Equatable {
    let id: String
    var tool: String
    var label: String
    var file: String?
    var started: Date
    var duration: TimeInterval?
    var done: Bool { duration != nil }
    var isEdit: Bool { ["Edit", "Write", "MultiEdit"].contains(tool) }
}

struct LineDiff: Equatable {
    var added = 0
    var removed = 0
}

struct AgentSession: Identifiable, Equatable {
    let id: String              // session_id de l'agent
    var source: String          // claude, codex, cursor...
    var cwd: String?
    var title: String?          // premier prompt de la session
    var app: String?            // bundle id du terminal / IDE, pour rouvrir la conversation
    var pending: String?        // action en attente de validation
    var awaitsReply = false     // le dernier message de l'agent appelle une réponse de l'utilisateur
    var state: AgentState = .thinking
    var file: String?
    var steps: [AgentStep] = []
    var diffs: [String: LineDiff] = [:]   // par fichier, cumulé sur la session
    var startedAt: Date
    var updatedAt: Date

    var project: String { cwd.map { ($0 as NSString).lastPathComponent } ?? "?" }
    /// Sans événement depuis 5 min (interruption par Échap, terminal fermé : aucun hook Stop), la session est considérée inactive.
    var isActive: Bool { state != .done && Date().timeIntervalSince(updatedAt) < 300 }
}

struct RateLimit: Equatable, Codable {
    var usedPercent: Double
    var resetsAt: Date?
}

struct UsageLimits: Equatable, Codable {
    var fiveHour: RateLimit?
    var sevenDay: RateLimit?
    var updatedAt = Date.distantPast

    /// Affichée seulement si l'app a émis récemment (= en cours d'utilisation).
    var isFresh: Bool { Date().timeIntervalSince(updatedAt) < 6 * 3600 }
}

/// Une ligne reçue des scripts : {"source":"claude","kind":"statusline"?,"payload":{...JSON de l'agent...}}
/// Les noms de champs suivent les payloads Claude Code ; Codex/Cursor seront ajoutés ici
/// (ponytail: un seul décodeur tolérant, pas un par agent).
struct AgentEnvelope: Decodable {
    struct Payload: Decodable {
        var session_id: String?
        var hook_event_name: String?
        var cwd: String?
        var prompt: String?
        var last_message: String?
        var last_assistant_message: String?
        var tool_name: String?
        var tool_use_id: String?
        var tool_input: ToolInput?
        var rate_limits: Limits?
        // Commande terminal terminée (scripts/cmd-hook.zsh, kind "command").
        var command: String?
        var exit_code: Int?
        var duration: Double?
    }
    struct ToolInput: Decodable {
        var file_path: String?
        var command: String?
        var description: String?
        var pattern: String?
        var old_string: String?
        var new_string: String?
        var content: String?
        var edits: [Edit]?
    }
    struct Edit: Decodable {
        var old_string: String?
        var new_string: String?
    }
    struct Limits: Decodable {
        var five_hour: Window?
        var seven_day: Window?
    }
    struct Window: Decodable {
        var used_percentage: Double?
        var resets_at: Reset?

        /// resets_at : epoch (secondes) ou date ISO 8601, selon la version de l'agent.
        struct Reset: Decodable {
            let date: Date?
            init(from d: Decoder) throws {
                let c = try d.singleValueContainer()
                if let n = try? c.decode(Double.self) {
                    date = Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n)
                } else if let s = try? c.decode(String.self) {
                    date = ISO8601DateFormatter().date(from: s)
                } else {
                    date = nil
                }
            }
        }
    }
    var source: String
    var kind: String?
    var app: String?
    var wait: Bool?          // le hook attend une décision (PermissionRequest)
    var payload: Payload
}
