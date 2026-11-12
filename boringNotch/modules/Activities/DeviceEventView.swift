//
//  DeviceEventView.swift
//  boringNotch
//
//  Événement d'appareil dans la notch fermée élargie (même mécanique que la charge) :
//  Même langage que les pastilles commande / dictée : rond noir, fin anneau coloré qui porte l'information.
//  - connexion : l'anneau se remplit à hauteur de la batterie (vert / orange / rouge), éclair en charge ;
//  - déconnexion : anneau éteint, icône atténuée ;
//  - batterie faible : anneau rouge qui pulse.
//

import SwiftUI

struct DeviceEventView: View {
    static let sideWidth: CGFloat = 120

    let notchWidth: CGFloat
    let height: CGFloat
    @ObservedObject private var events = ActivityEvents.shared

    var body: some View {
        if let e = events.deviceEvent {
            // id : un nouvel événement pendant l'affichage rejoue l'animation au lieu de muter l'état en place.
            Content(event: e, notchWidth: notchWidth, height: height).id(e)
        }
    }

    // ponytail: forme devinée d'après le nom ; macOS déclare casques, écouteurs et enceintes en « Headset ».
    static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if ["keys", "keyboard", "clavier"].contains(where: n.contains) { return "keyboard" }
        if ["mouse", "souris", "master", "anywhere"].contains(where: n.contains) { return "computermouse" }
        if n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if ["ear", "buds", "pods"].contains(where: n.contains) { return "earbuds" }
        if ["boom", "speaker", "soundlink", "jbl", "flip", "charge"].contains(where: n.contains) { return "hifispeaker.fill" }
        return "headphones"
    }
}

private struct Content: View {
    let event: ActivityEvents.DeviceEvent
    let notchWidth: CGFloat
    let height: CGFloat
    @State private var shown = false

    private var disconnected: Bool { event.kind == .disconnected }
    private var low: Int? { if case .lowBattery(let l) = event.kind { l } else { nil } }
    /// Niveau connu : batterie lue à la connexion, ou alerte de batterie faible.
    private var level: Int? { low ?? event.battery }
    private var diameter: CGFloat { max(height - 8, 18) }

    private var tint: Color {
        if disconnected { return .white.opacity(0.35) }
        guard let l = level else { return .green }
        return event.charging || l > 30 ? .green : l > 15 ? .orange : .red
    }

    private var status: String {
        switch event.kind {
        case .disconnected: "Déconnecté"
        case .lowBattery: "Batterie faible"
        case .connected: "Connecté"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            badge
                .padding(.leading, 6)
                .frame(width: DeviceEventView.sideWidth, alignment: .leading)

            Rectangle().fill(.black).frame(width: notchWidth + 10)

            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: 3) {
                    Text(status).foregroundStyle(low != nil ? Color.red.opacity(0.9) : .white.opacity(0.6))
                    if let l = level {
                        if event.charging { Image(systemName: "bolt.fill").foregroundStyle(tint) }
                        Text("\(l) %").foregroundStyle(tint)
                    }
                }
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : -6)
                Text(event.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(disconnected ? 0.6 : 1))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 8)
                    .animation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.12), value: shown)
            }
            .padding(.trailing, 4)
            .frame(width: DeviceEventView.sideWidth, alignment: .trailing)
        }
        .frame(height: height)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.55).delay(0.08)) { shown = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.name), \(status)\(level.map { ", \($0) %" } ?? "")")
    }

    /// Rond noir + anneau : l'arc est la batterie (anneau plein si elle est inconnue). Alerte : l'anneau pulse.
    private var badge: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: low == nil)) { ctx in
            let pulse = low != nil ? 0.55 + 0.45 * abs(sin(ctx.date.timeIntervalSinceReferenceDate * 3)) : 1
            ZStack {
                Circle().fill(.black)
                Circle().stroke(tint.opacity(0.25), lineWidth: 1.8)
                Circle().trim(from: 0, to: shown && !disconnected ? CGFloat(level ?? 100) / 100 : 0)
                    .stroke(tint.opacity(pulse), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8).delay(0.2), value: shown)
                Image(systemName: DeviceEventView.symbol(for: event.name))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(disconnected ? 0.5 : 1))
                    .symbolEffect(.bounce, value: shown)
            }
            .frame(width: diameter, height: diameter)
            .overlay(alignment: .topTrailing) {   // y ≥ 0 : le haut de la notch rogne ce qui dépasse
                if event.charging && !disconnected {
                    Image(systemName: "bolt.fill").font(.system(size: 6, weight: .heavy)).foregroundStyle(.black)
                        .frame(width: 11, height: 11).background(Circle().fill(Color.green))
                        .overlay(Circle().stroke(.black, lineWidth: 1.5)).offset(x: 3, y: 1)
                }
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        .scaleEffect(shown ? 1 : (disconnected ? 0.8 : 0.2))
        .rotationEffect(.degrees(shown || disconnected ? 0 : -25))
    }
}
