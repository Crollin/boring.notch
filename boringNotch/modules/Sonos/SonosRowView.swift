//
//  SonosRowView.swift
//  boringNotch
//
//  Ligne Sonos sous le lecteur + liste des pièces (affichée dans la notch,
//  pas en popover : un popover sort de la zone de survol et ferme la notch).
//

import Defaults
import SwiftUI

/// Ligne `[Cuisine ▾] 🔈 ───●─── 🔊`. Rien si Spotify ne joue pas sur une Sonos.
struct SonosRowView: View {
    @ObservedObject var store = SonosStore.shared
    private var pickerOpen: Bool { store.pickerOpen }

    var body: some View {
        if store.isActive {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.smooth(duration: 0.2)) { store.pickerOpen.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "hifispeaker.fill").font(.system(size: 9))
                        Text(store.label).lineLimit(1).fixedSize()
                        Image(systemName: pickerOpen ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(pickerOpen ? Color.green.opacity(0.85) : Color.white.opacity(0.12)))
                    .foregroundStyle(pickerOpen ? .black : .white)
                }
                .buttonStyle(.plain)

                Image(systemName: "speaker.fill").font(.system(size: 9)).foregroundStyle(.gray)
                SonosVolumeSlider(value: store.groupVolume) { v in await store.setGroupVolume(v) }
                    .frame(height: 8)
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 9)).foregroundStyle(.gray)
            }
            .frame(height: 18)
            .transition(.opacity)
        }
    }
}

/// Liste des pièces : favoris, « Revenir à », pièces (nom = déplacer, case = ajouter/retirer).
struct SonosPickerView: View {
    @ObservedObject var store = SonosStore.shared
    @Default(.sonosFavorites) private var favorites
    @Default(.sonosLastGroup) private var lastGroup
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(favorites) { fav in
                    row(icon: "star.fill", title: fav.name, detail: store.label(for: fav.roomIDs)) {
                        run { await store.apply(fav.roomIDs) }
                    }
                    .contextMenu {
                        Button("Supprimer", role: .destructive) { store.deleteFavorite(fav.id) }
                    }
                }
                if let last = lastGroup, let active = store.activeGroup, Set(last) != Set(active.memberIDs),
                   !store.label(for: last).isEmpty {
                    row(icon: "arrow.uturn.backward", title: "Revenir à : \(store.label(for: last))", detail: nil) {
                        run { await store.apply(last) }
                    }
                }
                if !favorites.isEmpty || lastGroup != nil { Divider().opacity(0.3).padding(.vertical, 2) }

                ForEach(store.rooms) { room in roomRow(room) }

                Divider().opacity(0.3).padding(.vertical, 2)
                if naming {
                    HStack {
                        TextField("Nom du favori", text: $newName)
                            .textFieldStyle(.plain).font(.system(size: 12))
                            .onSubmit(saveFavorite)
                        Button("OK", action: saveFavorite).buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                } else {
                    row(icon: "star", title: "Enregistrer ce groupe…", detail: nil) {
                        newName = store.label
                        naming = true
                    }
                }
            }
        }
    }

    private func roomRow(_ room: SonosRoom) -> some View {
        let members = store.activeGroup?.memberIDs ?? []
        let isMember = members.contains(room.id)
        return HStack(spacing: 8) {
            Button { Task { await store.toggle(room.id) } } label: {
                Image(systemName: isMember ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(isMember ? .green : .gray)
            }
            .buttonStyle(.plain)
            Button { run { await store.move(to: room.id) } } label: {
                Text(room.name).font(.system(size: 12, weight: isMember ? .semibold : .regular))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isMember && members.count > 1 {
                SonosVolumeSlider(value: store.roomVolumes[room.id] ?? 0) { v in await store.setRoomVolume(room.id, v) }
                    .frame(width: 90, height: 6)
                Text("\(store.roomVolumes[room.id] ?? 0)")
                    .font(.system(size: 10).monospacedDigit()).foregroundStyle(.gray).frame(width: 22, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func row(icon: String, title: String, detail: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.gray).frame(width: 14)
                Text(title).font(.system(size: 12)).lineLimit(1)
                if let detail { Text(detail).font(.system(size: 10)).foregroundStyle(.gray).lineLimit(1) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Changement de pièce : on referme la liste, comme un menu.
    private func run(_ action: @escaping () async -> Void) {
        withAnimation(.smooth(duration: 0.2)) { store.pickerOpen = false }
        Task { await action() }
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
