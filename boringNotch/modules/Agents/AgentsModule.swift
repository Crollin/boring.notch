//
//  AgentsModule.swift
//  boringNotch
//

import SwiftUI

struct AgentsModule: NotchModule {
    let id = "agents"
    let label = "Agents"
    let icon = "sparkles"

    private static let server = AgentSocketServer()

    func start() { Self.server.start() }

    @MainActor func makeView() -> AnyView { AnyView(AgentsView()) }
}
