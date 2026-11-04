//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id: String
    let label: String
    let icon: String
    let view: NotchViews

    /// Tous les onglets, dans l'ordre choisi dans les réglages.
    static func ordered(_ order: [String]) -> [TabModel] {
        TabOrder.apply(order, to: tabs.map(\.id)).compactMap { id in tabs.first { $0.id == id } }
    }
}

let tabs = [
    TabModel(id: "home", label: "Accueil", icon: "house.fill", view: .home),
    TabModel(id: "shelf", label: "Étagère", icon: "tray.fill", view: .shelf)
] + NotchModules.all.map { TabModel(id: $0.id, label: $0.label, icon: $0.icon, view: .module($0.id)) }

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.showCalendar) private var showCalendar
    @Default(.tabOrder) private var order
    @Default(.hiddenTabs) private var hidden
    @Namespace var animation

    private var visible: [TabModel] {
        TabModel.ordered(order).filter { TabOrder.isShown($0.id, hidden: hidden, showCalendar: showCalendar) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visible) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
        .padding(.trailing, 8)   // un peu d'air avant l'encoche
        // Onglet courant masqué depuis les réglages : retour à l'accueil.
        .onChange(of: visible.map(\.id)) { _, ids in
            if let current = tabs.first(where: { $0.view == coordinator.currentView }), !ids.contains(current.id) {
                coordinator.currentView = .home
            }
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
