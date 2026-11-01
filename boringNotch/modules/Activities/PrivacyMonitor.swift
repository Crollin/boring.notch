//
//  PrivacyMonitor.swift
//  boringNotch
//
//  Micro / caméra utilisés : point rouge / vert + durée depuis l'activation. Priorité maximale.
//

import AppKit
import CoreMediaIO
import Defaults
import SwiftUI

@MainActor
final class PrivacyMonitor: ObservableObject {
    static let shared = PrivacyMonitor()

    @Published private(set) var mic = false
    @Published private(set) var camera = false
    @Published private(set) var micApps: [String] = []   // noms d'apps
    private(set) var since: Date?
    private var timer: Timer?

    // ponytail: interrogation toutes les 2 s (quelques lectures de propriétés) ; listeners CoreAudio/CMIO si la latence gêne.
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in PrivacyMonitor.shared.poll() }
        }
        poll()
    }

    private func poll() {
        guard Defaults[.activityPrivacy] else { mic = false; camera = false; since = nil; return }
        let m = AudioHardware.micInUse
        // Le miroir de la notch utilise la caméra : ce n'est pas un usage à signaler.
        let c = Self.cameraInUse && !WebcamManager.shared.isSessionRunning
        if (m || c) && since == nil { since = .now }
        if !m && !c { since = nil }
        let apps = m ? Self.appNames(AudioHardware.micApps) : []
        if m != mic { mic = m }
        if c != camera { camera = c }
        if apps != micApps { micApps = apps }
    }

    private static func appNames(_ ids: [String]) -> [String] {
        let own = Bundle.main.bundleIdentifier
        var names: [String] = []
        for id in ids where id != own {
            let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
                .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    private static var cameraInUse: Bool {
        var a = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                          mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                          mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let sys = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(sys, &a, 0, nil, &size) == noErr, size > 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        guard CMIOObjectGetPropertyData(sys, &a, 0, nil, size, &size, &ids) == noErr else { return false }
        a.mSelector = CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)
        return ids.contains { id in
            var running: UInt32 = 0
            var s = UInt32(MemoryLayout<UInt32>.size)
            return CMIOObjectGetPropertyData(id, &a, 0, nil, s, &s, &running) == noErr && running != 0
        }
    }

    func activity(now: Date, height: CGFloat) -> Activity? {
        guard mic || camera, let since else { return nil }
        let help = [mic ? "Micro" + (micApps.isEmpty ? "" : " : " + micApps.joined(separator: ", ")) : nil,
                    camera ? "Caméra" : nil].compactMap { $0 }.joined(separator: "\n")
        return Activity(id: "privacy", priority: 100, view: AnyView(
            ActivityPill(height: height, help: help) {
                if mic { Image(systemName: "mic.fill").foregroundStyle(.red) }
                if camera { Image(systemName: "video.fill").foregroundStyle(.green) }
                Text(activityDuration(now.timeIntervalSince(since)))
            }
        ))
    }
}
