//
//  AppVolumeModule.swift
//  boringNotch
//
//  Onglet « Son » : volume par app + choix de la sortie audio.
//

import SwiftUI

struct AppVolumeModule: NotchModule {
    let id = "appvolume"
    let label = "Son"
    let icon = "slider.horizontal.3"

    func start() {
        if #available(macOS 14.2, *) { Task { @MainActor in AppVolumeStore.shared.startListening() } }
    }

    @MainActor func makeView() -> AnyView {
        if #available(macOS 14.2, *) { return AnyView(AppVolumeView()) }
        return AnyView(Text("Nécessite macOS 14.2").font(.system(size: 11)).foregroundStyle(.gray))
    }
}

@available(macOS 14.2, *)
private struct AppVolumeView: View {
    @ObservedObject var store = AppVolumeStore.shared
    @ObservedObject var sonos = SonosStore.shared
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            outputMenu
            if store.apps.isEmpty && !sonos.isActive {
                Text("Aucune app ne joue de son")
                    .font(.system(size: 11)).foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        if sonos.isActive {
                            VolumeBar(icon: Image(systemName: "hifispeaker.fill"), name: sonos.label.isEmpty ? "Sonos" : sonos.label,
                                      value: sonos.groupVolume) { v in Task { await sonos.setGroupVolume(v) } }
                        }
                        ForEach(store.apps) { app in
                            VolumeBar(icon: app.icon.map { Image(nsImage: $0) } ?? Image(systemName: "waveform"), name: app.name,
                                      value: Int((store.volume(app) * 100).rounded())) { v in store.setVolume(Float(v) / 100, for: app) }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .onAppear { store.refresh() }
        .onReceive(timer) { _ in store.refresh() }
    }

    private var outputMenu: some View {
        Menu {
            ForEach(store.outputs) { out in
                Button { store.selectOutput(out.id) } label: {
                    if out.id == store.currentOutput { Label(out.name, systemImage: "checkmark") } else { Text(out.name) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "hifispeaker.fill").font(.system(size: 9, weight: .semibold))
                Text(store.outputs.first { $0.id == store.currentOutput }?.name ?? "Sortie")
                    .font(.system(size: 11, weight: .medium)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(0.08)))
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Ligne = curseur : le fond se remplit selon le volume, on glisse ou on clique n'importe où.
/// Envois limités à ~10/s pendant le glisser (Sonos passe par le réseau), valeur finale au relâché.
private struct VolumeBar: View {
    let icon: Image
    let name: String
    let value: Int
    let onChange: (Int) -> Void
    @State private var local: Int?
    @State private var lastSent = Date.distantPast
    @State private var hovering = false

    var body: some View {
        let v = local ?? value
        let active = hovering || local != nil
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 9).fill(.white.opacity(active ? 0.09 : 0.06))
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(colors: [Color.effectiveAccent.opacity(0.22), Color.effectiveAccent.opacity(active ? 0.5 : 0.38)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geo.size.width * CGFloat(v) / 100, v > 0 ? 18 : 0))
                HStack(spacing: 8) {
                    icon.resizable().scaledToFit().frame(width: 16, height: 16)
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    Text(name).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(.white.opacity(v == 0 ? 0.45 : 0.95))
                    Spacer(minLength: 8)
                    if v == 0 {
                        Image(systemName: "speaker.slash.fill").font(.system(size: 9)).foregroundStyle(.red.opacity(0.8))
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text("\(v)%").font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(active ? .white : .gray)
                        .contentTransition(.numericText(value: Double(v)))
                }
                .padding(.horizontal, 9)
            }
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(active ? 0.12 : 0.04)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let nv = Self.percent(g.location.x, geo.size.width)
                    local = nv
                    if Date().timeIntervalSince(lastSent) > 0.1 { lastSent = Date(); onChange(nv) }
                }
                .onEnded { g in
                    onChange(Self.percent(g.location.x, geo.size.width))
                    local = nil
                })
        }
        .frame(height: 28)
        .scaleEffect(local != nil ? 1.015 : 1)
        .animation(.smooth(duration: 0.18), value: v)
        .animation(.smooth(duration: 0.18), value: active)
    }

    static func percent(_ x: CGFloat, _ width: CGFloat) -> Int {
        Int((min(max(x / max(width, 1), 0), 1) * 100).rounded())
    }
}
