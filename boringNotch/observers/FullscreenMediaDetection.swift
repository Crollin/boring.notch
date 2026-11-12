//
//  FullscreenMediaDetection.swift
//  boringNotch
//
//  Created by Richard Kunkli on 06/09/2024.
//

import AppKit
import Combine
import Defaults
import MacroVisionKit

@MainActor
final class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()
    
    @Published var fullscreenStatus: [String: Bool] = [:]
    
    private var monitorTask: Task<Void, Never>?
    private var windowMonitorTask: Task<Void, Never>?
    private var spaces: [FullScreenMonitor.SpaceInfo] = []
    private var cancellables: Set<AnyCancellable> = []
    
    private init() {
        // The old default depended on Now Playing, which streaming services do not always publish.
        if !Defaults[.didMigrateFullscreenHiding] {
            if Defaults[.hideNotchOption] == .nowPlayingOnly {
                Defaults[.hideNotchOption] = .always
            }
            Defaults[.didMigrateFullscreenHiding] = true
        }

        Publishers.CombineLatest(
            Defaults.publisher(.hideNotchOption).map(\.newValue),
            MusicManager.shared.$bundleIdentifier
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.updateStatus() }
        .store(in: &cancellables)

        startMonitoring()
    }
    
    deinit {
        monitorTask?.cancel()
        windowMonitorTask?.cancel()
    }
    
    private func startMonitoring() {
        monitorTask = Task { @MainActor [weak self] in
            let stream = await FullScreenMonitor.shared.spaceChanges()
            for await spaces in stream {
                guard let self else { return }
                self.spaces = spaces
                self.updateStatus()
            }
        }

        // Some video players use a borderless window without creating a macOS fullscreen Space.
        // Window geometry is available without recording the screen or requesting Accessibility.
        windowMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.updateStatus()
                do {
                    try await Task.sleep(for: .milliseconds(750))
                } catch {
                    return
                }
            }
        }
    }
    
    private func updateStatus() {
        var newStatus: [String: Bool] = [:]

        guard Defaults[.hideNotchOption] != .never else {
            if !fullscreenStatus.isEmpty { fullscreenStatus = [:] }
            return
        }
        
        for space in spaces {
            if let uuid = space.screenUUID {
                let shouldDetect: Bool
                if Defaults[.hideNotchOption] == .nowPlayingOnly, let musicSourceBundle = MusicManager.shared.bundleIdentifier  {
                    shouldDetect = space.runningApps.contains(musicSourceBundle)
                } else {
                    shouldDetect = true
                }
                newStatus[uuid] = (newStatus[uuid] ?? false) || shouldDetect
            }
        }

        for uuid in borderlessFullscreenScreens() {
            newStatus[uuid] = true
        }
        
        if fullscreenStatus != newStatus { fullscreenStatus = newStatus }
    }

    private func borderlessFullscreenScreens() -> Set<String> {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              Defaults[.hideNotchOption] != .nowPlayingOnly
                || MusicManager.shared.bundleIdentifier == nil
                || MusicManager.shared.bundleIdentifier == app.bundleIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }

        let appWindows = windows.filter {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier
                && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
                && (($0[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0) > 0
        }

        return Set(NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = screen.displayUUID else { return nil }
            // CGWindow bounds and CGDisplayBounds share a top-left origin, including secondary displays.
            let displayBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            let coversDisplay = appWindows.contains { window in
                guard let dictionary = window[kCGWindowBounds as String] as? [String: Any],
                      let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return false }
                let tolerance: CGFloat = 1
                return abs(bounds.minX - displayBounds.minX) <= tolerance
                    && abs(bounds.minY - displayBounds.minY) <= tolerance
                    && abs(bounds.width - displayBounds.width) <= tolerance
                    && abs(bounds.height - displayBounds.height) <= tolerance
            }
            return coversDisplay ? uuid : nil
        })
    }
}

