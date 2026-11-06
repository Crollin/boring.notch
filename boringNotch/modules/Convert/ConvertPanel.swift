//
//  ConvertPanel.swift
//  boringNotch
//
//  Conversion intégrée au Shelf : quand un ou plusieurs fichiers convertibles sont déposés sur la tuile « Convertir »,
//  le panneau du Shelf propose les formats communs. Résultat dans le dossier choisi, sinon ~/Downloads.
//

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ConvertStore: ObservableObject {
    static let shared = ConvertStore()

    enum Status: Equatable {
        case idle
        case working(ConvertTarget, done: Int)
        case done([URL], failed: Int)
        case failed(String)
    }

    @Published private(set) var files: [URL] = []
    @Published private(set) var status: Status = .idle
    /// Tuile « Convertir » visible pendant le glisser de fichiers convertibles.
    @Published private(set) var showDropTile = false
    @Published private(set) var outputFolder: URL?
    private var hideTask: Task<Void, Never>?

    init() {
        outputFolder = Self.resolveOutputFolder()
    }

    /// Suit le glisser au-dessus de la notch. Le masquage est différé : passer d'une zone de drop à l'autre
    /// fait brièvement retomber le ciblage à false, la tuile ne doit pas disparaître sous le curseur.
    func dragChanged(_ active: Bool) {
        hideTask?.cancel()
        if active {
            if !showDropTile { showDropTile = Self.draggedFilesAreConvertible() }
            return
        }
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            showDropTile = false
        }
    }

    /// Lit seulement les URL sur le pasteboard de drag (pas le contenu) : des fichiers ayant au moins un format commun.
    private static func draggedFilesAreConvertible() -> Bool {
        let urls = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return !FileConverter.targets(for: urls).isEmpty
    }

    /// Drop sur la tuile : retourne false si ce ne sont pas des fichiers (le drop est refusé).
    func offer(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        hideTask?.cancel()
        showDropTile = false
        clear()
        Task {
            var urls: [URL] = []
            for provider in fileProviders {
                if let url = await provider.extractFileURL() { urls.append(url) }
            }
            guard !FileConverter.targets(for: urls).isEmpty else { return }
            files = urls
            status = .idle
        }
        return true
    }

    func clear() {
        files = []
        status = .idle
    }

    /// Convertit le lot un fichier après l'autre ; un échec n'arrête pas les suivants.
    func convert(to target: ConvertTarget) {
        guard !files.isEmpty, !isWorking else { return }
        let batch = files
        status = .working(target, done: 0)
        Task {
            let (dir, scoped) = outputDirectory()
            defer { if scoped { dir?.stopAccessingSecurityScopedResource() } }
            guard let dir else { status = .failed("Dossier de sortie introuvable."); return }

            var outputs: [URL] = []
            var lastError: Error?
            for (i, src) in batch.enumerated() {
                status = .working(target, done: i)
                do {
                    outputs.append(try FileConverter.save(try await Self.convert(src, to: target),
                                                          from: src, ext: target.fileExtension, in: dir))
                } catch {
                    lastError = error
                }
            }
            if outputs.isEmpty, let lastError {
                status = .failed(lastError.localizedDescription)
            } else {
                status = .done(outputs, failed: batch.count - outputs.count)
            }
        }
    }

    private static func convert(_ src: URL, to target: ConvertTarget) async throws -> Data {
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        let isDocument = FileConverter.documentType(of: src) != nil
        switch target {
        case .markdown where isDocument:
            return try MarkdownConverter.document(src)
        case .markdown:
            return try await Task.detached(priority: .userInitiated) { try MarkdownConverter.pdf(src) }.value
        case _ where isDocument:
            return try FileConverter.convertDocument(src)
        default:
            return try await Task.detached(priority: .userInitiated) { try FileConverter.convertImage(src, to: target) }.value
        }
    }

    var isWorking: Bool {
        if case .working = status { return true }
        return false
    }

    // MARK: - Dossier de sortie

    /// Dossier choisi s'il existe encore (accès sandbox ouvert, à refermer), sinon Téléchargements.
    private func outputDirectory() -> (URL?, scoped: Bool) {
        if let folder = Self.resolveOutputFolder() {
            let scoped = folder.startAccessingSecurityScopedResource()
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue {
                return (folder, scoped)
            }
            if scoped { folder.stopAccessingSecurityScopedResource() }
        }
        outputFolder = nil
        return (try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false), false)
    }

    private static func resolveOutputFolder() -> URL? {
        guard let data = Defaults[.convertOutputFolder] else { return nil }
        let (url, refreshed) = Bookmark(data: data).resolve()
        if let refreshed { Defaults[.convertOutputFolder] = refreshed }
        return url
    }

    func chooseOutputFolder() {
        SharingStateManager.shared.beginInteraction() // garde la notch ouverte pendant le sélecteur
        defer { SharingStateManager.shared.endInteraction() }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choisir"
        panel.message = "Dossier où enregistrer les fichiers convertis"
        panel.directoryURL = outputFolder
        guard panel.runModal() == .OK, let url = panel.url, let bookmark = try? Bookmark(url: url) else { return }
        Defaults[.convertOutputFolder] = bookmark.data
        outputFolder = url
    }

    func resetOutputFolder() {
        Defaults[.convertOutputFolder] = nil
        outputFolder = nil
    }
}

/// Contenu du panneau du Shelf pendant une proposition de conversion.
struct ConvertPanel: View {
    let files: [URL]
    @ObservedObject private var store = ConvertStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: files.count == 1 ? NSWorkspace.shared.icon(forFile: files[0].path)
                                                : NSWorkspace.shared.icon(for: .folder))
                    .resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(files.count == 1 ? files[0].lastPathComponent : "\(files.count) fichiers")
                        .font(.headline).lineLimit(1).truncationMode(.middle)
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
                ForEach(FileConverter.targets(for: files)) { target in
                    Button { store.convert(to: target) } label: {
                        VStack(spacing: 5) {
                            if case .working(target, _) = store.status {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: target == .markdown ? "text.alignleft" : target == .pdf ? "doc" : "photo")
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

            destinationLine
        }
    }

    private var destinationLine: some View {
        HStack(spacing: 6) {
            Button { store.chooseOutputFolder() } label: {
                Label(store.outputFolder?.lastPathComponent ?? "Téléchargements", systemImage: "folder")
                    .font(.caption).lineLimit(1).truncationMode(.middle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.gray)
            .help("Choisir le dossier de sortie")
            if store.outputFolder != nil {
                Button { store.resetOutputFolder() } label: {
                    Image(systemName: "arrow.uturn.backward").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.gray)
                .help("Revenir à Téléchargements")
            }
        }
        .disabled(store.isWorking)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch store.status {
        case .working(_, let done) where files.count > 1:
            Text("Conversion \(done + 1)/\(files.count)…").font(.caption).foregroundStyle(.gray)
        case .done(let urls, let failed):
            Button {
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            } label: {
                Label(doneText(urls, failed), systemImage: failed == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(failed == 0 ? .green : .orange).font(.caption).lineLimit(1)
            }
            .buttonStyle(.plain)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
        default:
            Text(sizeText).font(.caption).foregroundStyle(.gray).lineLimit(1)
        }
    }

    private func doneText(_ urls: [URL], _ failed: Int) -> String {
        let folder = urls.first?.deletingLastPathComponent().lastPathComponent ?? ""
        let what = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) fichiers"
        return failed == 0 ? "\(what) → \(folder)" : "\(what) → \(folder), \(failed) échec\(failed > 1 ? "s" : "")"
    }

    private var sizeText: String {
        let bytes = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
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
