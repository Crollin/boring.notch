//
//  SonosPanelView.swift
//  boringNotch
//
//  Panneau Sonos à droite du lecteur (style widgets) : groupe actif, volume, pièces, favoris.
//  Hors du drawingGroup du lecteur : ScrollView et TextField ne s'y dessinent pas.
//

import Defaults
import SwiftUI

struct SonosPanelView: View {
    @ObservedObject var store = SonosStore.shared
    @Default(.sonosFavorites) private var favorites
    @Default(.sonosLastGroup) private var lastGroup
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hifispeaker.fill").font(.system(size: 11)).foregroundStyle(.gray)
                Text(store.label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            HStack(spacing: 8) {
                Button { Task { await store.toggleMute() } } label: {
                    Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
                SonosVolumeSlider(value: store.groupVolume) { v in await store.setGroupVolume(v) }
                    .frame(height: 6)
                Text("\(store.groupVolume)")
                    .font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(.gray)
                    .frame(width: 20, alignment: .trailing)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(store.rooms) { room in roomRow(room) }
                    Divider().opacity(0.2).padding(.vertical, 3)
                    ForEach(favorites) { fav in
                        row(icon: "star.fill", title: fav.name) { Task { await store.apply(fav.roomIDs) } }
                            .contextMenu {
                                Button("Supprimer", role: .destructive) { store.deleteFavorite(fav.id) }
                            }
                    }
                    if let last = lastGroup, let active = store.activeGroup, Set(last) != Set(active.memberIDs),
                       !store.label(for: last).isEmpty {
                        row(icon: "arrow.uturn.backward", title: store.label(for: last)) { Task { await store.apply(last) } }
                    }
                    if naming {
                        TextField("Nom du favori", text: $newName)
                            .textFieldStyle(.plain).font(.system(size: 12))
                            .onSubmit(saveFavorite)
                            .padding(.vertical, 3)
                    } else {
                        row(icon: "star", title: "Enregistrer le groupe") {
                            newName = store.label
                            naming = true
                        }
                    }
                }
            }
        }
    }

    private func roomRow(_ room: SonosRoom) -> some View {
        let members = store.activeGroup?.memberIDs ?? []
        let isMember = members.contains(room.id)
        return HStack(spacing: 6) {
            Button { Task { await store.toggle(room.id) } } label: {
                Image(systemName: isMember ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isMember ? Color.effectiveAccent : .gray)
            }
            .buttonStyle(.plain)
            Button { Task { await store.move(to: room.id) } } label: {
                Text(room.name).font(.system(size: 12, weight: isMember ? .medium : .regular))
                    .foregroundStyle(isMember ? .white : .gray)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isMember && members.count > 1 {
                SonosVolumeSlider(value: store.roomVolumes[room.id] ?? 0) { v in await store.setRoomVolume(room.id, v) }
                    .frame(width: 50, height: 5)
            }
        }
        .padding(.vertical, 3)
    }

    private func row(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10)).foregroundStyle(.gray).frame(width: 12)
                Text(title).font(.system(size: 12)).foregroundStyle(.gray).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func saveFavorite() {
        store.saveFavorite(name: newName)
        naming = false
    }
}

/// Curseur 0–100 ; envoi throttlé (~150 ms) pendant le glisser, valeur finale au relâché.
struct SonosVolumeSlider: View {
    let value: Int
    let onChange: (Int) async -> Void
    @State private var local: Double = 0
    @State private var dragging = false
    @State private var lastSent = Date.distantPast

    var body: some View {
        CustomSlider(
            value: $local,
            range: 0...100,
            color: .white,
            dragging: $dragging,
            lastDragged: .constant(.distantPast),
            onValueChange: { v in Task { await onChange(Int(v.rounded())) } },
            onDragChange: { v in
                guard Date().timeIntervalSince(lastSent) > 0.15 else { return }
                lastSent = Date()
                Task { await onChange(Int(v.rounded())) }
            }
        )
        .onAppear { local = Double(value) }
        .onChange(of: value) { _, v in if !dragging { local = Double(v) } }
    }
}
