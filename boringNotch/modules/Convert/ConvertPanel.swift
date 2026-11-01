//
//  ConvertPanel.swift
//  boringNotch
//
//  Conversion intégrée au Shelf : quand un seul fichier convertible est déposé, le panneau du Shelf
//  propose les formats. Le fichier est aussi ajouté au Shelf comme d'habitude. Résultat dans ~/Downloads.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ConvertStore: ObservableObject {
    static let shared = ConvertStore()

    enum Status: Equatable { case idle, working(ConvertTarget), done(URL), failed(String) }

    @Published private(set) var file: URL?
    @Published private(set) var status: Status = .idle
    /// Tuile « Convertir » visible pendant le glisser d'un fichier convertible.
    @Published private(set) var showDropTile = false
    private var hideTask: Task<Void, Never>?

    /// Suit le glisser au-dessus de la notch. Le masquage est différé : passer d'une zone de drop à l'autre
    /// fait brièvement retomber le ciblage à false, la tuile ne doit pas disparaître sous le curseur.
    func dragChanged(_ active: Bool) {
        hideTask?.cancel()
        if active {
            if !showDropTile { showDropTile = Self.draggedFileIsConvertible() }
            return
        }
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            showDropTile = false
        }
    }

    /// Lit seulement l'URL sur le pasteboard de drag (pas le contenu) : un seul fichier, d'un type convertible.
    private static func draggedFileIsConvertible() -> Bool {
        let urls = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.count == 1 && !FileConverter.targets(for: urls[0]).isEmpty
    }

    /// Drop sur la tuile : retourne false si ce n'est pas un fichier (le drop est refusé).
    func offer(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first,
              provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return false }
        hideTask?.cancel()
        showDropTile = false
        clear()
        Task {
            guard let url = await provider.extractFileURL(), !FileConverter.targets(for: url).isEmpty else { return }
            file = url
            status = .idle
        }
        return true
    }

    func clear() {
        file = nil
        status = .idle
    }

    func convert(to target: ConvertTarget) {
        guard let src = file, !isWorking else { return }
        status = .working(target)
        Task {
            let scoped = src.startAccessingSecurityScopedResource()
            defer { if scoped { src.stopAccessingSecurityScopedResource() } }
            do {
                let data: Data
                if FileConverter.documentType(of: src) != nil {
                    data = try FileConverter.convertDocument(src)
                } else {
                    data = try await Task.detached(priority: .userInitiated) {
                        try FileConverter.convertImage(src, to: target)
                    }.value
                }
                status = .done(try FileConverter.save(data, from: src, ext: target.fileExtension))
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    var isWorking: Bool {
        if case .working = status { return true }
        return false
    }
}

/// Contenu du panneau du Shelf pendant une proposition de conversion.
struct ConvertPanel: View {
    let file: URL
    @ObservedObject private var store = ConvertStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                    .resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
                    statusLine
                }
                Spacer()
                Button { store.clear() } label: {
                    Image(systemName: "xmark").padding(7).background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Revenir au Shelf")
            }

            HStack(spacing: 8) {
                ForEach(FileConverter.targets(for: file)) { target in
                    Button { store.convert(to: target) } label: {
                        VStack(spacing: 5) {
                            if store.status == .working(target) {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: target == .pdf ? "doc" : "photo")
                            }
                            Text(target.label).font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isWorking)
                }
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch store.status {
        case .done(let url):
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label("\(url.lastPathComponent) → Téléchargements", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.caption).lineLimit(1)
            }
            .buttonStyle(.plain)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
        default:
            Text(sizeText).font(.caption).foregroundStyle(.gray)
        }
    }

    private var sizeText: String {
        let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// Tuile qui apparaît à côté de LocalSend pendant le glisser d'un fichier convertible (même style que FileShareView).
struct ConvertDropZone: View {
    @EnvironmentObject private var vm: BoringViewModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [Color.black.opacity(0.35), Color.black.opacity(0.20)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(vm.convertDropTargeting ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.1),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10]))
                )
                .shadow(color: Color.black.opacity(0.6), radius: 6, x: 0, y: 2)

            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(vm.convertDropTargeting ? 0.11 : 0.09))
                        .frame(width: 55, height: 55)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(vm.convertDropTargeting ? Color.accentColor : Color.gray)
                        .scaleEffect(vm.convertDropTargeting ? 1.06 : 1.0)
                        .animation(.spring(response: 0.36, dampingFraction: 0.7), value: vm.convertDropTargeting)
                }
                Text("Convertir")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(18)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onDrop(of: [.fileURL], isTargeted: $vm.convertDropTargeting) { providers in
            guard ConvertStore.shared.offer(providers) else { return false }
            vm.dropEvent = true
            return true
        }
    }
}
