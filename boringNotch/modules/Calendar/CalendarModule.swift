//
//  CalendarModule.swift
//  boringNotch
//
//  Calendrier dans son propre onglet : l'accueil laisse toute la largeur au lecteur.
//

import SwiftUI

struct CalendarModule: NotchModule {
    let id = "calendar"
    let label = "Calendrier"
    let icon = "calendar"

    func start() {}

    @MainActor func makeView() -> AnyView { AnyView(CalendarTab()) }
}

private struct CalendarTab: View {
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        CalendarView()
            .onHover { vm.isHoveringCalendar = $0 }
    }
}
