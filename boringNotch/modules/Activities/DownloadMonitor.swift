//
//  DownloadMonitor.swift
//  boringNotch
//
//  Téléchargements en cours dans ~/Downloads : anneau de progression, puis ✓ et ajout à l'étagère.
//  Safari : paquet .download (progression dans son Info.plist). Chrome/Arc/Brave : .crdownload. Firefox : .part.
//

import AppKit
import Defaults
import SwiftUI

@MainActor
final class DownloadMonitor: ObservableObject {
    static let shared = DownloadMonitor()

    static let tempExtensions = ["download", "crdownload", "part"]

    @Published private(set) var progress: [String: Double?] = [:]   // nom temporaire → fraction (nil = inconnue)
    @Published private(set) var finished: URL?
    private var finishedAt = Date.distantPast
    private var dir: URL?
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?

    func start() {
        guard let d = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.resolvingSymlinksInPath() else { return }
        dir = d
        let fd = open(d.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { Task { @MainActor in DownloadMonitor.shared.scan() } }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        scan()
    }

    /// Le dossier n'est notifié que quand une entrée apparaît/disparaît : pendant un téléchargement, on interroge chaque seconde.
    private func scan() {
        guard let dir, Defaults[.activityDownloads] else { progress = [:]; return }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var now: [String: Double?] = [:]
        for n in names where Self.tempExtensions.contains((n as NSString).pathExtension) && !n.hasPrefix(".") {
            now[n] = Self.fraction(dir.appendingPathComponent(n))
        }
        // Terminé : l'entrée temporaire a disparu et le fichier final existe.
        for gone in progress.keys where now[gone] == nil {
            let final = dir.appendingPathComponent((gone as NSString).deletingPathExtension)
            if FileManager.default.fileExists(atPath: final.path) { complete(final) }
        }
        if now != progress { progress = now }

        if progress.isEmpty {
            timer?.invalidate(); timer = nil
        } else if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in DownloadMonitor.shared.scan() }
            }
        }
    }

    private func complete(_ url: URL) {
        finished = url
        finishedAt = .now
        guard Defaults[.downloadsToShelf], let bookmark = try? Bookmark(url: url) else { return }
        ShelfStateViewModel.shared.add([ShelfItem(kind: .file(bookmark: bookmark.data), isTemporary: false)])
    }

    /// Safari seul expose la taille finale ; ailleurs la progression est inconnue.
    private static func fraction(_ url: URL) -> Double? {
        guard url.pathExtension == "download",
              let info = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")),
              let done = (info["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.doubleValue,
              let total = (info["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.doubleValue, total > 0
        else { return nil }
        return min(done / total, 1)
    }

    func activity(height: CGFloat) -> Activity? {
        if !progress.isEmpty {
            let known = progress.values.compactMap { $0 }
            let fraction: Double? = known.count == progress.count ? known.reduce(0, +) / Double(known.count) : nil
            let help = progress.keys.sorted().map { ($0 as NSString).deletingPathExtension }.joined(separator: "\n")
            return Activity(id: "download", priority: 60, view: AnyView(
                ActivityPill(height: height, help: help) {
                    DownloadRing(fraction: fraction)
                    if progress.count > 1 { Text("\(progress.count)") }
                    else if let fraction { Text("\(Int(fraction * 100)) %") }
                }
            ))
        }
        if let finished, Date().timeIntervalSince(finishedAt) < 4 {
            return Activity(id: "download-done", priority: 60, view: AnyView(
                ActivityPill(height: height, help: finished.lastPathComponent,
                             action: { NSWorkspace.shared.activateFileViewerSelecting([finished]) }) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(finished.lastPathComponent).lineLimit(1).truncationMode(.middle).frame(maxWidth: 90)
                }
            ))
        }
        return nil
    }
}

private struct DownloadRing: View {
    let fraction: Double?
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 2)
            Circle()
                .trim(from: 0, to: fraction ?? 0.25)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(fraction == nil && spin ? 270 : -90))
                .animation(fraction == nil ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: spin)
                .animation(.easeOut, value: fraction)
        }
        .frame(width: 12, height: 12)
        .onAppear { spin = true }
    }
}
