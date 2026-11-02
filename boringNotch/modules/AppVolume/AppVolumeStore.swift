//
//  AppVolumeStore.swift
//  boringNotch
//
//  Apps qui jouent du son (regroupées par .app : les helpers Firefox/Chrome comptent
//  pour leur app), leur volume, et la sortie audio du Mac.
//

import AppKit
import CoreAudio
import Darwin

@available(macOS 14.2, *)
@MainActor
final class AppVolumeStore: ObservableObject {
    static let shared = AppVolumeStore()

    struct App: Identifiable, Equatable {
        let id: String // chemin du .app, ou nom du processus
        let name: String
        let icon: NSImage?
        let processes: [AudioObjectID]
    }

    struct Output: Identifiable, Equatable {
        let id: AudioObjectID
        let name: String
    }

    @Published private(set) var apps: [App] = []
    @Published private(set) var volumes: [String: Float] = [:] // seulement les apps réglées (≠ 100 %)
    @Published private(set) var outputs: [Output] = []
    @Published private(set) var currentOutput: AudioObjectID = 0

    private var taps: [String: AppAudioTap] = [:]
    private var listening = false

    func volume(_ app: App) -> Float { volumes[app.id] ?? 1 }

    func setVolume(_ v: Float, for app: App) {
        if v >= 0.995 {
            volumes[app.id] = nil
            taps[app.id] = nil
        } else {
            volumes[app.id] = v
            if let tap = taps[app.id] { tap.volume = v } else { taps[app.id] = makeTap(app.processes, v) }
        }
    }

    func selectOutput(_ id: AudioObjectID) {
        AudioHardware.setDefaultOutput(id)
        refresh()
    }

    /// Le changement de sortie est suivi même onglet fermé : les taps doivent suivre.
    func startListening() {
        guard !listening else { return }
        listening = true
        var a = AudioHardware.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioHardware.system, &a, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.rebuildTaps() }
        }
    }

    func refresh() {
        let me = getpid()
        var groups: [String: (name: String, path: String?, procs: [AudioObjectID])] = [:]
        var playing = Set<String>()
        for proc in AudioHardware.ids(AudioHardware.system, kAudioHardwarePropertyProcessObjectList) {
            let pid = pid_t(bitPattern: AudioHardware.uint(proc, kAudioProcessPropertyPID))
            guard pid > 0, pid != me else { continue }
            let (key, name, path) = Self.identify(pid: pid, proc: proc)
            groups[key, default: (name, path, [])].procs.append(proc)
            if AudioHardware.uint(proc, kAudioProcessPropertyIsRunningOutput) != 0 { playing.insert(key) }
        }

        // Affichées : celles qui jouent, plus celles réglées dont un processus existe encore.
        apps = groups.filter { playing.contains($0.key) || volumes[$0.key] != nil }
            .map { key, g in
                App(id: key, name: g.name, icon: g.path.map { NSWorkspace.shared.icon(forFile: $0) }, processes: g.procs.sorted())
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        for (key, tap) in taps {
            guard let procs = groups[key]?.procs.sorted() else { taps[key] = nil; volumes[key] = nil; continue }
            if procs != tap.processes { taps[key] = makeTap(procs, tap.volume) } // nouvel helper (nouvel onglet…)
        }

        outputs = AudioHardware.devices.filter { AudioHardware.hasStreams($0, input: false) }
            .compactMap { dev in AudioHardware.string(dev, kAudioObjectPropertyName).map { Output(id: dev, name: $0) } }
            .filter { !$0.name.hasPrefix("Boring Notch") && !$0.name.hasPrefix("CADefaultDeviceAggregate") }
        currentOutput = AudioHardware.uint(AudioHardware.system, kAudioHardwarePropertyDefaultOutputDevice)
    }

    private func rebuildTaps() {
        for (key, tap) in taps { taps[key] = makeTap(tap.processes, tap.volume) }
        refresh()
    }

    private func makeTap(_ procs: [AudioObjectID], _ v: Float) -> AppAudioTap? {
        let out = AudioHardware.uint(AudioHardware.system, kAudioHardwarePropertyDefaultOutputDevice)
        guard let uid = AudioHardware.string(out, kAudioDevicePropertyDeviceUID) else { return nil }
        return AppAudioTap(processes: procs, outputUID: uid, volume: v)
    }

    /// Clé de regroupement = le .app le plus externe du chemin de l'exécutable.
    nonisolated static func identify(pid: pid_t, proc: AudioObjectID) -> (key: String, name: String, path: String?) {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let exe = proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : ""
        if let app = outermostApp(exe) {
            return (app, FileManager.default.displayName(atPath: app), app)
        }
        let name = exe.isEmpty ? (AudioHardware.string(proc, kAudioProcessPropertyBundleID) ?? "PID \(pid)") : (exe as NSString).lastPathComponent
        return (name, name, nil)
    }

    nonisolated static func outermostApp(_ path: String) -> String? {
        guard let r = path.range(of: ".app/") else { return nil }
        return String(path[..<r.lowerBound]) + ".app"
    }
}
