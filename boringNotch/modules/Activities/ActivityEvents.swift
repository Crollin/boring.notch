//
//  ActivityEvents.swift
//  boringNotch
//
//  Activités éphémères (quelques secondes) : commande terminal terminée, disque externe monté.
//  Casque connecté / déconnecté, batterie faible d'un accessoire : la notch fermée s'élargit (DeviceEventView).
//  Une seule à la fois : la plus récente remplace la précédente.
//

import AppKit
import CoreAudio
import Defaults
import SwiftUI

@MainActor
final class ActivityEvents: ObservableObject {
    static let shared = ActivityEvents()

    enum Event: Equatable {
        case command(name: String, ok: Bool, duration: TimeInterval, app: String?)
        case disk(name: String, url: URL)
    }

    @Published private(set) var event: Event?
    /// Événement d'appareil affiché pendant l'élargissement de la notch (DeviceEventView).
    struct DeviceEvent: Hashable {
        enum Kind: Hashable { case connected, disconnected, lowBattery(Int) }
        let name: String
        let kind: Kind
    }
    @Published private(set) var deviceEvent: DeviceEvent?

    func showDevice(_ e: DeviceEvent) {
        deviceEvent = e
        // value : 0 = déconnexion (élargissement plus court, cf. BoringViewCoordinator).
        BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .device, value: e.kind == .disconnected ? 0 : 1)
    }
    private var expires = Date.distantPast
    /// Casques présents et leur nom : à la déconnexion, CoreAudio ne connaît déjà plus le périphérique.
    private var knownHeadsets: [AudioObjectID: String] = [:]

    private func show(_ e: Event) {
        event = e
        expires = Date().addingTimeInterval(TimeInterval(Defaults[.activityEventSeconds]))
    }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { n in
            guard let url = n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            Task { @MainActor in ActivityEvents.shared.mounted(url) }
        }
        ws.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { n in
            let url = n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            Task { @MainActor in
                let e = ActivityEvents.shared
                if case .disk(_, let u)? = e.event, u == url { e.event = nil }
            }
        }

        knownHeadsets = Self.headsets
        var a = AudioHardware.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioHardware.system, &a, .main) { _, _ in
            Task { @MainActor in ActivityEvents.shared.devicesChanged() }
        }
    }

    // MARK: Sources

    /// Envoyé par scripts/cmd-hook.zsh via le socket des agents. Ignoré si le terminal est au premier plan.
    func commandFinished(_ env: AgentEnvelope) {
        guard Defaults[.activityCommands], let cmd = env.payload.command else { return }
        let app = env.app.flatMap { $0.isEmpty ? nil : $0 }
        // Le hook envoie dès 3 s (BN_MIN_SECONDS) ; le seuil réel se règle ici.
        guard (env.payload.duration ?? 0) >= Double(Defaults[.commandMinSeconds]) else { return }
        if !Defaults[.commandWhenFrontmost], let app, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app { return }
        let name = cmd.split(separator: " ").first.map(String.init) ?? cmd
        show(.command(name: name, ok: env.payload.exit_code == 0, duration: env.payload.duration ?? 0, app: app))
    }

    private func mounted(_ url: URL) {
        guard Defaults[.activityDisks],
              let v = try? url.resourceValues(forKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsLocalKey, .volumeLocalizedNameKey]),
              v.volumeIsLocal != false, v.volumeIsRemovable == true || v.volumeIsEjectable == true
        else { return }
        show(.disk(name: v.volumeLocalizedName ?? url.lastPathComponent, url: url))
    }

    /// Sorties audio Bluetooth (un casque expose une entrée et une sortie : on ne garde que la sortie).
    private static var headsets: [AudioObjectID: String] {
        Dictionary(uniqueKeysWithValues: AudioHardware.devices
            .filter { AudioHardware.isBluetooth($0) && AudioHardware.hasStreams($0, input: false) }
            .map { ($0, AudioHardware.string($0, kAudioObjectPropertyName) ?? "Casque") })
    }

    private func devicesChanged() {
        let now = Self.headsets
        let added = now.keys.first { knownHeadsets[$0] == nil }
        let removed = knownHeadsets.first { now[$0.key] == nil }
        knownHeadsets = now
        guard Defaults[.activityHeadsets] else { return }
        if let dev = added {
            showDevice(.init(name: now[dev] ?? "Casque", kind: .connected))
        } else if let (_, name) = removed {
            showDevice(.init(name: name, kind: .disconnected))
        }
    }

    // MARK: Pastille

    func activity(now: Date, height: CGFloat) -> Activity? {
        guard let event, now < expires else { return nil }
        switch event {
        case let .command(name, ok, duration, app):
            return Activity(id: "event-command", priority: 50, view: AnyView(
                ActivityPill(height: height, help: ok ? "Commande terminée" : "Commande en échec",
                             action: { if let app { Self.activate(app) } }) {
                    Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(ok ? .green : .red)
                    Text(name).lineLimit(1).frame(maxWidth: 80)
                    Text(activityDuration(duration)).foregroundStyle(.secondary)
                }
            ))
        case let .disk(name, url):
            return Activity(id: "event-disk", priority: 50, view: AnyView(
                ActivityPill(height: height, help: "Éjecter \(name)", action: { Self.eject(url) }) {
                    Image(systemName: "externaldrive.fill").foregroundStyle(.blue)
                    Text(name).lineLimit(1).frame(maxWidth: 80)
                    Image(systemName: "eject.fill").foregroundStyle(.secondary)
                }
            ))
        }
    }

    private static func eject(_ url: URL) {
        do { try NSWorkspace.shared.unmountAndEjectDevice(at: url) }
        catch { NSWorkspace.shared.activateFileViewerSelecting([url]) }   // sandbox ou disque occupé : le Finder prend le relais
    }

    private static func activate(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg)
    }
}
