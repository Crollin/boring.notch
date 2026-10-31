//
//  SonosStore.swift
//  boringNotch
//
//  État Sonos : détecte la pièce où joue Spotify, pilote volume et groupes.
//  Toute erreur réseau ⇒ activeGroup = nil, silencieusement (hors maison = rien d'affiché).
//

import AppKit
import Defaults
import Foundation

extension SonosFavorite: Defaults.Serializable {}

@MainActor
final class SonosStore: ObservableObject {
    static let shared = SonosStore()

    @Published private(set) var rooms: [SonosRoom] = []
    @Published private(set) var activeGroup: SonosGroup?
    @Published private(set) var groupVolume: Int = 0
    @Published private(set) var roomVolumes: [String: Int] = [:]

    var isActive: Bool { activeGroup != nil }
    var label: String { activeGroup.map { SonosLogic.label(for: $0, rooms: rooms) } ?? "" }

    private let client = SonosClient()
    private let discovery = SonosDiscovery()
    private var groups: [SonosGroup] = []
    private var pollTask: Task<Void, Never>?
    private var lastLocalVolumeChange = Date.distantPast
    private var busy = false   // action de groupe en cours : pas de polling concurrent

    // ponytail: polling 3 s ; abonnements UPnP GENA si la latence gêne.
    private let pollInterval: Duration = .seconds(3)

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(3))
            }
        }
    }

    // MARK: - Rafraîchissement

    private enum Detection {
        case off                                   // désactivé, Spotify fermé/arrêté : inactif tout de suite
        case miss                                  // rien trouvé (réseau, changement de morceau…)
        case active(rooms: [SonosRoom], groups: [SonosGroup], group: SonosGroup)
    }

    private var generation = 0   // incrémenté par chaque action de groupe : invalide un refresh en vol
    private var misses = 0
    // ponytail: 2 ratés (~6 s) avant de rendre les touches au Mac ; évite le clignotement aux changements de morceau.
    private let missesBeforeInactive = 2

    func refresh() async {
        guard !busy else { return }
        let gen = generation
        let detection = await detect()
        guard gen == generation, !busy else { return }   // une action a changé les groupes entre-temps

        switch detection {
        case .off:
            misses = 0
            setInactive()
        case .miss:
            misses += 1
            if misses >= missesBeforeInactive { setInactive() }
        case .active(let newRooms, let newGroups, let group):
            misses = 0
            rooms = newRooms
            groups = newGroups
            if let old = activeGroup {
                let updated = SonosLogic.updatedHistory(previous: Defaults[.sonosLastGroup], old: old.memberIDs, new: group.memberIDs)
                if updated != Defaults[.sonosLastGroup] { Defaults[.sonosLastGroup] = updated }
            }
            activeGroup = group
            await refreshVolumes(group, generation: gen)
        }
    }

    private func detect() async -> Detection {
        guard Defaults[.enableSonos], let spotify = await Self.spotifyState() else { return .off }
        guard let host = await reachableHost(),
              let topo = try? await client.topology(host: host) else { return .miss }
        let sorted = topo.rooms.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        for group in topo.groups {
            guard let h = sorted.first(where: { $0.id == group.coordinatorID })?.host,
                  let state = try? await client.transportState(host: h),
                  SonosLogic.statesAgree(spotifyPlaying: spotify.playing, sonosState: state),
                  let track = try? await client.currentTrack(host: h),
                  SonosLogic.tracksMatch(track, spotify.track) else { continue }
            return .active(rooms: sorted, groups: topo.groups, group: group)
        }
        return .miss
    }

    private func refreshVolumes(_ group: SonosGroup, generation gen: Int) async {
        // Ne pas écraser un réglage local tout juste envoyé (curseur qui saute).
        guard Date().timeIntervalSince(lastLocalVolumeChange) > 2, let coord = ip(of: group.coordinatorID) else { return }
        let v = try? await client.groupVolume(coordinator: coord)
        var vols: [String: Int] = [:]
        if group.memberIDs.count > 1 {
            for id in group.memberIDs {
                if let h = ip(of: id), let rv = try? await client.volume(host: h) { vols[id] = rv }
            }
        }
        guard gen == generation, !busy, Date().timeIntervalSince(lastLocalVolumeChange) > 2 else { return }
        if let v { groupVolume = v }
        roomVolumes = vols
    }

    private func setInactive() {
        if activeGroup != nil { activeGroup = nil }
        if !roomVolumes.isEmpty { roomVolumes = [:] }
    }

    private var knownHost: String?

    private func reachableHost() async -> String? {
        if let h = knownHost ?? rooms.first?.host, (try? await client.transportState(host: h)) != nil {
            knownHost = h
            return h
        }
        knownHost = await discovery.firstHost()
        return knownHost
    }

    private func ip(of id: String) -> String? { rooms.first { $0.id == id }?.host }

    /// État Spotify si Spotify est lancé et en lecture/pause, sinon nil.
    private static func spotifyState() async -> (playing: Bool, track: SonosTrack)? {
        let script = """
        if application "Spotify" is running then
            tell application "Spotify"
                if player state is stopped then return ""
                return (player state as string) & linefeed & (id of current track) & linefeed & (name of current track) & linefeed & (artist of current track)
            end tell
        end if
        return ""
        """
        guard let out = try? await AppleScriptHelper.execute(script)?.stringValue, !out.isEmpty else { return nil }
        let p = out.components(separatedBy: "\n")
        guard p.count >= 3 else { return nil }
        return (p[0] == "playing",
                SonosTrack(title: p[2], artist: p.count > 3 ? p[3] : "", spotifyID: SonosParse.spotifyID(from: p[1])))
    }

    // MARK: - Groupes

    func move(to roomID: String) async { await apply([roomID]) }

    func toggle(_ roomID: String) async {
        guard let group = activeGroup, let members = SonosLogic.toggled(group, room: roomID) else { return }
        await apply(members)
    }

    /// Le groupe actif devient exactement `roomIDs` (pièces absentes ignorées).
    /// Le coordinateur actuel est gardé s'il reste dans la liste (aucune coupure).
    func apply(_ roomIDs: [String]) async {
        guard let group = activeGroup,
              let target = SonosLogic.plan(for: roomIDs, available: Set(rooms.map(\.id))),
              Set(target) != Set(group.memberIDs) || !target.contains(group.coordinatorID),
              !busy else { return }   // une action à la fois (taps rapides ignorés)
        busy = true
        generation += 1
        defer { busy = false }

        var coordinator = group.coordinatorID
        var members = Set(group.memberIDs)
        do {
            if !target.contains(coordinator) {
                let next = target[0]
                if !members.contains(next), let h = ip(of: next) {
                    try await client.join(host: h, coordinatorID: coordinator)
                    members.insert(next)
                    try await Task.sleep(for: .milliseconds(500))
                }
                if let h = ip(of: coordinator) {
                    try await client.delegate(coordinator: h, to: next)
                    coordinator = next
                    try await Task.sleep(for: .milliseconds(500))
                }
            }
            for id in target where !members.contains(id) {
                if let h = ip(of: id) { try await client.join(host: h, coordinatorID: coordinator) }
            }
            for id in members where !target.contains(id) {
                if let h = ip(of: id) { try await client.leave(host: h) }
            }
        } catch {
            // Silencieux : le prochain refresh montre l'état réel.
        }
        try? await Task.sleep(for: .milliseconds(800))
        busy = false
        await refresh()
    }

    // MARK: - Volume

    func setGroupVolume(_ v: Int) async {
        guard let group = activeGroup, let h = ip(of: group.coordinatorID) else { return }
        let v = min(100, max(0, v))
        groupVolume = v
        lastLocalVolumeChange = Date()
        try? await client.setGroupVolume(coordinator: h, v)
    }

    func adjustGroupVolume(by delta: Int) async {
        await setGroupVolume(groupVolume + delta)
    }

    func setRoomVolume(_ roomID: String, _ v: Int) async {
        guard let h = ip(of: roomID) else { return }
        let v = min(100, max(0, v))
        roomVolumes[roomID] = v
        lastLocalVolumeChange = Date()
        try? await client.setVolume(host: h, v)
        if let group = activeGroup, let c = ip(of: group.coordinatorID),
           let g = try? await client.groupVolume(coordinator: c) { groupVolume = g }
    }

    func toggleMute() async {
        guard let group = activeGroup, let h = ip(of: group.coordinatorID),
              let muted = try? await client.groupMute(coordinator: h) else { return }
        try? await client.setGroupMute(coordinator: h, !muted)
    }

    /// Icône du HUD volume quand il affiche la Sonos (les vues HUD y ajoutent `label`).
    static let hudIcon = "hifispeaker.fill"

    func showHUD() {
        BoringViewCoordinator.shared.toggleSneakPeek(
            status: true, type: .volume, value: CGFloat(groupVolume) / 100, icon: Self.hudIcon)
    }

    // MARK: - Favoris

    func saveFavorite(name: String) {
        guard let group = activeGroup else { return }
        let name = name.trimmingCharacters(in: .whitespaces)
        Defaults[.sonosFavorites].append(SonosFavorite(id: UUID(), name: name.isEmpty ? label : name, roomIDs: group.memberIDs))
    }

    func deleteFavorite(_ id: UUID) {
        Defaults[.sonosFavorites].removeAll { $0.id == id }
    }

    func label(for roomIDs: [String]) -> String {
        roomIDs.compactMap { id in rooms.first { $0.id == id }?.name }.joined(separator: " + ")
    }
}
