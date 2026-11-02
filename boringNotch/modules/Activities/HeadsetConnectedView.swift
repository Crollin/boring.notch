//
//  HeadsetConnectedView.swift
//  boringNotch
//
//  Casque Bluetooth connecté / déconnecté : la notch fermée s'élargit quelques secondes (même mécanique que la charge).
//  Connexion : pastille d'accent qui « pop », ondes qui s'échappent, nom qui glisse en place.
//  Déconnexion : pastille éteinte, ondes qui se resserrent vers l'icône.
//

import SwiftUI

struct HeadsetConnectedView: View {
    static let sideWidth: CGFloat = 120

    let notchWidth: CGFloat
    let height: CGFloat
    @ObservedObject private var events = ActivityEvents.shared

    var body: some View {
        let h = events.headset
        let connected = h?.connected ?? true
        // id : une déconnexion pendant l'affichage rejoue l'animation au lieu de muter l'état en place.
        Content(name: h?.name ?? "Casque", connected: connected, notchWidth: notchWidth, height: height)
            .id(connected)
    }

    // ponytail: forme devinée d'après le nom ; macOS déclare casques, écouteurs et enceintes en « Headset ».
    static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if ["ear", "buds", "pods"].contains(where: n.contains) { return "earbuds" }
        if ["boom", "speaker", "soundlink", "jbl", "flip", "charge"].contains(where: n.contains) { return "hifispeaker.fill" }
        return "headphones"
    }
}

private struct Content: View {
    let name: String
    let connected: Bool
    let notchWidth: CGFloat
    let height: CGFloat
    @State private var shown = false
    @State private var ripple = false

    private var accent: Color { connected ? .effectiveAccent : .white.opacity(0.35) }

    var body: some View {
        HStack(spacing: 0) {
            badge
                .padding(.leading, 6)
                .frame(width: HeadsetConnectedView.sideWidth, alignment: .leading)

            Rectangle().fill(.black).frame(width: notchWidth + 10)

            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: 4) {
                    Circle().fill(connected ? Color.green : .white.opacity(0.35)).frame(width: 5, height: 5)
                        .scaleEffect(connected && !ripple ? 1.8 : 1)
                        .shadow(color: .green.opacity(connected && !ripple ? 0.9 : 0), radius: 4)
                    Text(connected ? "Connecté" : "Déconnecté")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : -6)
                Text(name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(connected ? 1 : 0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 8)
                    .animation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.12), value: shown)
            }
            .padding(.trailing, 4)
            .frame(width: HeadsetConnectedView.sideWidth, alignment: .trailing)
        }
        .frame(height: height)
        .onAppear {
            withAnimation(connected ? .spring(response: 0.42, dampingFraction: 0.55).delay(0.08)
                                    : .smooth(duration: 0.3).delay(0.05)) { shown = true }
            withAnimation(.easeOut(duration: 1.2).delay(0.3)) { ripple = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(connected ? "connecté" : "déconnecté")")
    }

    /// Ondes : vers l'extérieur à la connexion (le signal s'établit), vers l'icône à la déconnexion (il se perd).
    private var badge: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .stroke(accent, lineWidth: 1.5)
                    .scaleEffect(connected ? (ripple ? 1.9 : 1) : (ripple ? 0.9 : 1.9))
                    .opacity(connected ? (ripple ? 0 : 0.7) : (ripple ? 0 : 0.6))
                    .animation(.easeOut(duration: connected ? 1.1 : 0.8).delay(0.3 + Double(i) * 0.28), value: ripple)
            }
            Circle()
                .fill(connected
                      ? AnyShapeStyle(LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.55)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(.white.opacity(0.14)))
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                .shadow(color: connected ? accent.opacity(0.6) : .clear, radius: shown ? 6 : 0)
            Image(systemName: HeadsetConnectedView.symbol(for: name))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(connected ? 1 : 0.6))
                .symbolEffect(connected ? .bounce.up : .bounce.down, value: ripple)
        }
        .frame(width: 24, height: 24)
        .scaleEffect(shown ? 1 : (connected ? 0.2 : 0.8))
        .rotationEffect(.degrees(shown || !connected ? 0 : -25))
    }
}
