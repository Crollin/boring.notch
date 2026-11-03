//
//  DeviceEventView.swift
//  boringNotch
//
//  Événement d'appareil dans la notch fermée élargie (même mécanique que la charge) :
//  - connexion : pastille d'accent qui « pop », ondes qui s'échappent, nom qui glisse en place ;
//  - déconnexion : pastille éteinte, ondes qui se resserrent vers l'icône ;
//  - batterie faible : pastille rouge, ondes lentes, pourcentage.
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
    @State private var ripple = false

    private var connected: Bool { event.kind == .connected }
    private var disconnected: Bool { event.kind == .disconnected }
    private var battery: Int? { if case .lowBattery(let l) = event.kind { l } else { nil } }

    private var accent: Color {
        switch event.kind {
        case .connected: .effectiveAccent
        case .disconnected: .white.opacity(0.35)
        case .lowBattery: .red
        }
    }

    private var status: String {
        switch event.kind {
        case .connected: "Connecté"
        case .disconnected: "Déconnecté"
        case .lowBattery(let l): "Batterie faible · \(l) %"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            badge
                .padding(.leading, 6)
                .frame(width: DeviceEventView.sideWidth, alignment: .leading)

            Rectangle().fill(.black).frame(width: notchWidth + 10)

            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: 4) {
                    let dot: Color = disconnected ? .white.opacity(0.35) : (battery != nil ? .red : .green)
                    Circle().fill(dot).frame(width: 5, height: 5)
                        .scaleEffect(!disconnected && !ripple ? 1.8 : 1)
                        .shadow(color: dot.opacity(!disconnected && !ripple ? 0.9 : 0), radius: 4)
                    Text(status)
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(battery != nil ? Color.red.opacity(0.9) : .white.opacity(0.6))
                }
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
            withAnimation(disconnected ? .smooth(duration: 0.3).delay(0.05)
                                       : .spring(response: 0.42, dampingFraction: 0.55).delay(0.08)) { shown = true }
            withAnimation(.easeOut(duration: 1.2).delay(0.3)) { ripple = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.name), \(status)")
    }

    /// Ondes : vers l'extérieur (signal qui s'établit, alerte), vers l'icône à la déconnexion (signal qui se perd).
    private var badge: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .stroke(accent, lineWidth: 1.5)
                    .scaleEffect(disconnected ? (ripple ? 0.9 : 1.9) : (ripple ? 1.9 : 1))
                    .opacity(ripple ? 0 : (disconnected ? 0.6 : 0.7))
                    .animation(.easeOut(duration: disconnected ? 0.8 : (battery != nil ? 1.5 : 1.1))
                                .delay(0.3 + Double(i) * (battery != nil ? 0.45 : 0.28)), value: ripple)
            }
            Circle()
                .fill(disconnected
                      ? AnyShapeStyle(.white.opacity(0.14))
                      : AnyShapeStyle(LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.55)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                .shadow(color: disconnected ? .clear : accent.opacity(0.6), radius: shown ? 6 : 0)
            Image(systemName: DeviceEventView.symbol(for: event.name))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(disconnected ? 0.6 : 1))
                .symbolEffect(disconnected ? .bounce.down : .bounce.up, value: ripple)
        }
        .frame(width: 24, height: 24)
        .scaleEffect(shown ? 1 : (disconnected ? 0.8 : 0.2))
        .rotationEffect(.degrees(shown || disconnected ? 0 : -25))
    }
}
