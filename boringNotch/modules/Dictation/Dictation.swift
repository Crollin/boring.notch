//
//  Dictation.swift
//  boringNotch
//
//  Dictée vocale 100 % locale : micro → SpeechAnalyzer (Apple) → nettoyage par segments → collage.
//  Chaque segment finalisé est nettoyé pendant que tu parles : à l'arrêt, il ne reste que le dernier à traiter.
//

import AVFoundation
import Defaults
import FoundationModels
import OSLog
import Speech
import SwiftUI

/// Niveau sonore lu par l'interface (écrit depuis le thread audio, lu depuis le MainActor).
final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var v: Float = 0
    var value: Float { lock.lock(); defer { lock.unlock() }; return v }
    func push(_ x: Float) { lock.lock(); v = max(x, v * 0.7); lock.unlock() } // attaque immédiate, retombée douce
    func reset() { lock.lock(); v = 0; lock.unlock() }
}

@available(macOS 26.0, *)
@MainActor
final class Dictation: ObservableObject {
    static let shared = Dictation()

    enum Phase { case idle, listening, processing }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var partial = ""
    @Published private(set) var error: String?
    @Published private(set) var justDone = false
    @Published private(set) var offer: String?   // règle apprise proposée dans la notch (reste dans les réglages après)
    private var offerTask: Task<Void, Never>?
    private(set) var startedAt = Date()
    let meter = LevelMeter()

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Error>?
    private var chunks: [Task<String, Never>] = []
    private var raws: [String] = []
    private var warm: LanguageModelSession?   // préchauffée pendant que tu parles
    private var flashTask: Task<Void, Never>?
    private var limitTask: Task<Void, Never>?
    private var selection: String?            // texte sélectionné au déclenchement : remplacé, ou transformé par une commande
    private var generation = 0                // invalide un start() resté en attente si l'utilisateur a relâché

    // MARK: raccourci

    func keyDown() {
        switch (Defaults[.dictationHold], phase) {
        case (_, .idle): Task { await start() }
        case (false, .listening): Task { await stop() }
        default: break
        }
    }

    func keyUp() {
        if Defaults[.dictationHold], phase == .listening { Task { await stop() } }
    }

    // MARK: cycle

    private func start() async {
        guard phase == .idle else { return }
        phase = .listening; partial = ""; error = nil; justDone = false
        startedAt = .now; meter.reset(); chunks = []; raws = []
        generation += 1
        let g = generation
        let stale = { [self] in generation != g || phase != .listening }
        selection = await TextInserter.selectedText().map { String($0.prefix(4000)) }
        if stale() { return }
        if Defaults[.dictationCleanup] { warm = TextCleanup.warmSession() } // charge le modèle pendant la prise de parole
        do {
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw DictationError.micDenied }

            let wanted = Locale(identifier: Defaults[.dictationLocale])
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) else { throw DictationError.unsupported }
            let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
            // Première utilisation : télécharge le modèle de la langue (géré par le système).
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) { try await req.downloadAndInstall() }
            if stale() { return } // relâché pendant le téléchargement : stop() a déjà tout remis à zéro

            // whileInUse : le modèle de reconnaissance est libéré dès la fin de la dictée (pas de RAM résiduelle).
            let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .whileInUse))
            // Vocabulaire perso (cibles des substitutions) : la reconnaissance les privilégie.
            let vocab = TextCleanup.vocabulary()
            if !vocab.isEmpty { let ctx = AnalysisContext(); ctx.contextualStrings[.general] = vocab; try? await analyzer.setContext(ctx) }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { throw DictationError.unsupported }
            if stale() { return }
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            self.analyzer = analyzer; input = continuation

            results = Task { [weak self] in
                var done = ""
                for try await r in transcriber.results {
                    let s = String(r.text.characters)
                    if r.isFinal { done += s; await self?.finalized(s, partial: done) } else { await self?.setPartial(done + s) }
                }
            }
            try await analyzer.start(inputSequence: stream)
            if stale() { continuation.finish(); await analyzer.cancelAndFinishNow(); return }
            try Self.startCapture(engine, to: format, continuation, meter)
            // Garde-fou : un micro oublié en mode « basculer » s'arrête seul.
            // ponytail: 3 min en dur.
            limitTask = Task { try? await Task.sleep(for: .seconds(180)); if !Task.isCancelled { await stop() } }
        } catch {
            await fail(error)
        }
    }

    /// Un segment est figé : on le nettoie tout de suite, en série, pendant que la suite est dictée.
    private func finalized(_ s: String, partial p: String) {
        partial = p
        raws.append(s)
        let session = warm ?? (Defaults[.dictationCleanup] ? TextCleanup.warmSession() : nil)
        warm = nil
        let prev = chunks.last
        let locale = Defaults[.dictationLocale]
        chunks.append(Task { _ = await prev?.value; return await TextCleanup.cleanChunk(s, session: session, locale: locale) })
    }

    private func stop() async {
        guard phase == .listening else { return }
        phase = .processing
        generation += 1; limitTask?.cancel(); limitTask = nil
        let g = generation
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        input?.finish(); input = nil

        // Chaque attente est bornée : la dictée ne reste jamais bloquée sur « traitement ».
        let a = analyzer, r = results
        let finished = await withDeadline(6) { () async -> Bool? in
            do { try await a?.finalizeAndFinishThroughEndOfInput(); try await r?.value; return true } catch { return false }
        }
        guard generation == g else { return }          // annulée par un clic pendant l'attente
        if finished != true { r?.cancel(); await a?.cancelAndFinishNow() }
        analyzer = nil; results = nil

        let all = chunks
        let parts = await withDeadline(12) { () async -> [String]? in
            var out: [String] = []
            for c in all { out.append(await c.value) }
            return out
        }
        guard generation == g else { return }
        // Délai dépassé ou erreur : on colle ce qui a été entendu (texte partiel, règles seulement) plutôt que rien.
        var text = TextCleanup.finish(parts ?? [TextCleanup.spoken(TextCleanup.removeFillers(partial), locale: Defaults[.dictationLocale])])
        let sel = selection; selection = nil
        if let sel, !text.isEmpty {
            Logger(subsystem: "theboringteam.boringnotch", category: "dictation")
                .info("sélection \(sel.count) car., premier mot « \(text.split(separator: " ").first.map(String.init) ?? "", privacy: .public) », commande : \(TextCleanup.isCommand(text))")
            if TextCleanup.isCommand(text) {
                // Commande vocale sur la sélection (« raccourcis », « traduis en anglais »…) : le modèle réécrit la sélection.
                let out = await TextCleanup.command(text, on: sel)
                guard generation == g else { return }
                guard let out else { await fail(DictationError.commandFailed); return }
                text = out
            } else {
                if let rule = TextCleanup.learn(from: sel, to: text) { propose(rule) } // mot sélectionné puis redicté
            }
        }
        if !text.isEmpty {
            await TextInserter.insert(text)
            if Defaults[.dictationKeepHistory] {
                var h = Defaults[.dictationHistory]
                h.insert(DictationEntry(text: text, raw: raws.joined(separator: " ")), at: 0)
                Defaults[.dictationHistory] = Array(h.prefix(200))
            }
            flash()
        }
        guard generation == g else { return }
        phase = .idle; partial = ""; chunks = []; raws = []; warm = nil
    }

    /// Abandonne tout (clic pendant le traitement) : rien n'est collé.
    func cancel() {
        generation += 1; limitTask?.cancel(); limitTask = nil
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        input?.finish(); input = nil; results?.cancel(); results = nil
        chunks.forEach { $0.cancel() }; chunks = []; raws = []; warm = nil; selection = nil
        let a = analyzer; analyzer = nil
        Task { await a?.cancelAndFinishNow() }
        phase = .idle; partial = ""
    }

    private func propose(_ rule: String) {
        offer = rule
        offerTask?.cancel()
        // ponytail: 12 s dans la notch ; ensuite la règle reste dans Réglages > Dictée.
        offerTask = Task { try? await Task.sleep(for: .seconds(12)); if !Task.isCancelled { offer = nil } }
    }

    func answerOffer(accept: Bool) {
        guard let rule = offer else { return }
        accept ? TextCleanup.accept(rule) : TextCleanup.dismiss(rule)
        offerTask?.cancel(); offer = nil
    }

    private func flash() {
        justDone = true
        flashTask?.cancel()
        flashTask = Task { try? await Task.sleep(for: .seconds(1.2)); if !Task.isCancelled { justDone = false } }
    }

    private func fail(_ e: Error) async {
        generation += 1; limitTask?.cancel(); limitTask = nil
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        input?.finish(); input = nil; results?.cancel(); results = nil
        chunks.forEach { $0.cancel() }; chunks = []; raws = []; warm = nil; selection = nil
        await analyzer?.cancelAndFinishNow(); analyzer = nil
        error = (e as? DictationError)?.message ?? e.localizedDescription
        phase = .idle; partial = ""
        flashTask?.cancel()
        flashTask = Task { try? await Task.sleep(for: .seconds(4)); if !Task.isCancelled { error = nil } }
    }

    /// Clic sur la bulle : terminer la dictée en cours.
    func stopNow() {
        switch phase { case .listening: Task { await stop() }; case .processing: cancel(); default: break }
    }

    fileprivate func setPartial(_ s: String) { partial = s }

    // nonisolated : le tap tourne sur le thread audio, il ne doit pas hériter du MainActor.
    private nonisolated static func startCapture(_ engine: AVAudioEngine, to format: AVAudioFormat,
                                                 _ out: AsyncStream<AnalyzerInput>.Continuation,
                                                 _ meter: LevelMeter) throws {
        let node = engine.inputNode
        let inFormat = node.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inFormat, to: format) else { throw DictationError.unsupported }
        node.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { buffer, _ in
            if let ch = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                var sum: Float = 0
                for i in 0..<Int(buffer.frameLength) { sum += ch[i] * ch[i] }
                meter.push(min(1, (sum / Float(buffer.frameLength)).squareRoot() * 6)) // RMS, gain visuel
            }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / inFormat.sampleRate) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var fed = false
            converter.convert(to: converted, error: nil) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return buffer
            }
            if converted.frameLength > 0 { out.yield(AnalyzerInput(buffer: converted)) }
        }
        engine.prepare()
        try engine.start()
    }
}

enum DictationError: Error {
    case micDenied, unsupported, commandFailed
    var message: String {
        switch self {
        case .micDenied: "Accès au micro refusé (Réglages Système > Confidentialité)"
        case .unsupported: "Langue non prise en charge par la dictée Apple"
        case .commandFailed: "Commande impossible (modèle indisponible ou trop lent)"
        }
    }
}

struct DictationEntry: Codable, Identifiable, Hashable, Defaults.Serializable {
    var id = UUID()
    var date = Date()
    var text: String
    var raw: String
}

// MARK: pastille autour de la notch fermée

@available(macOS 26.0, *)
extension Dictation {
    func activity(height: CGFloat) -> Activity? {
        guard Defaults[.activityDictation] else { return nil }
        if error != nil || phase != .idle || justDone {
            return Activity(id: "dictation", priority: 100, view: AnyView(DictationPill(height: height)))
        }
        if let offer { return Activity(id: "dictation-offer", priority: 90, view: AnyView(DictationOffer(height: height, rule: offer))) }
        return nil
    }
}

/// Bulle ronde (comme celle des agents) : un petit personnage dont la bouche suit ta voix.
/// - écoute : anneau rouge qui pulse avec le niveau + point « REC », il cligne des yeux
/// - traitement : il regarde à gauche et à droite, anneau orange qui tourne
/// - fini : sourire vert qui rebondit
/// - erreur : jaune, « ! »
/// Un clic termine l'écoute, ou abandonne le traitement s'il traîne.
/// Remplace la pastille « micro utilisé » le temps de la dictée (voir PrivacyMonitor).
@available(macOS 26.0, *)
struct DictationPill: View {
    let height: CGFloat
    @ObservedObject private var d = Dictation.shared

    private enum Mood { case listening, thinking, happy, oops }
    private var mood: Mood { d.error != nil ? .oops : d.phase == .listening ? .listening : d.phase == .processing ? .thinking : .happy }
    private var tint: Color {
        switch mood { case .listening: .white; case .thinking: .orange; case .happy: .green; case .oops: .yellow }
    }
    private var diameter: CGFloat { max(height - 8, 18) }

    var body: some View {
        Button { d.stopNow() } label: {
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let level = CGFloat(d.meter.value)
                ZStack {
                    Circle().fill(.black)
                    ring(t: t, level: level)
                    Face(mood: mood == .listening ? .listening(level: level) : mood == .thinking ? .thinking
                         : mood == .happy ? .happy : .oops, color: tint, t: t)
                }
                .frame(width: diameter, height: diameter)
                .scaleEffect(mood == .happy ? 1.12 : 1)
                .overlay(alignment: .topTrailing) { badge(t: t) }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: mood)
        .help(d.error ?? (d.phase == .listening ? "Dictée en cours — cliquer pour terminer" : d.phase == .processing ? "Traitement — cliquer pour annuler" : "Dictée"))
    }

    @ViewBuilder private func ring(t: Double, level: CGFloat) -> some View {
        switch mood {
        case .listening:
            Circle().stroke(Color.red.opacity(0.45 + 0.55 * level), lineWidth: 1.2 + 1.8 * level)
        case .thinking:
            Circle().trim(from: 0, to: 0.3).stroke(Color.orange, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(t * 360 * 1.4))
        case .happy:
            Circle().stroke(Color.green.opacity(0.7), lineWidth: 1.5)
        case .oops:
            Circle().stroke(Color.yellow.opacity(0.8), lineWidth: 1.5)
        }
    }

    @ViewBuilder private func badge(t: Double) -> some View {
        // y ≥ 0 : le haut de la notch rogne tout ce qui dépasse.
        switch mood {
        case .listening:
            Circle().fill(Color.red).frame(width: 7, height: 7)
                .opacity(0.6 + 0.4 * abs(sin(t * 3)))
                .overlay(Circle().stroke(.black, lineWidth: 1.2)).offset(x: 2, y: 1)
        case .oops:
            Text("!").font(.system(size: 7, weight: .heavy)).foregroundStyle(.black)
                .frame(width: 11, height: 11).background(Circle().fill(Color.yellow))
                .overlay(Circle().stroke(.black, lineWidth: 1.5)).offset(x: 3, y: 1)
        default: EmptyView()
        }
    }

    /// Visage en pixels, dans le style de la mascotte des agents.
    private struct Face: View {
        enum Kind { case listening(level: CGFloat), thinking, happy, oops }
        let mood: Kind, color: Color, t: Double
        private let px: CGFloat = 2.1

        // Grille 9 × 7 ; (colonne, ligne)
        private var pixels: [(Int, Int)] {
            var p: [(Int, Int)] = []
            func rect(_ c: ClosedRange<Int>, _ r: ClosedRange<Int>) { for y in r { for x in c { p.append((x, y)) } } }
            switch mood {
            case .listening(let level):
                let blink = t.truncatingRemainder(dividingBy: 3.4) < 0.12
                blink ? rect(2...2, 2...2) : rect(2...2, 1...2)
                blink ? rect(6...6, 2...2) : rect(6...6, 1...2)
                switch level {                         // la bouche s'ouvre avec la voix
                case ..<0.10: rect(3...5, 5...5)
                case ..<0.28: rect(3...5, 4...5)
                case ..<0.55: rect(2...6, 4...5)
                default:      rect(2...6, 4...6)
                }
            case .thinking:
                let look = Int(t / 0.4) % 2 == 0 ? 0 : 2   // regarde à gauche, puis à droite
                rect((1 + look)...(1 + look), 1...2); rect((5 + look)...(5 + look), 1...2)
                rect(4...4, 5...5)
            case .happy:
                p += [(1, 2), (2, 1), (3, 2), (5, 2), (6, 1), (7, 2)]   // yeux ^ ^
                p += [(2, 4), (6, 4)]; rect(3...5, 5...5)                // sourire
            case .oops:
                rect(2...2, 1...2); rect(6...6, 1...2)
                p += [(2, 5), (3, 4), (4, 5), (5, 4), (6, 5)]            // bouche ondulée
            }
            return p
        }

        var body: some View {
            Canvas { ctx, _ in
                for (x, y) in pixels {
                    ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px)), with: .color(color))
                }
            }
            .frame(width: px * 9, height: px * 7)
        }
    }
}

/// Règle apprise, sur deux lignes (avant / après) avec une pastille verte (valider) et une rouge (ignorer).
@available(macOS 26.0, *)
struct DictationOffer: View {
    let height: CGFloat
    let rule: String
    private var parts: (String, String) {
        let p = rule.components(separatedBy: " => ")
        return (p.first ?? rule, p.count > 1 ? p[1] : "")
    }
    var body: some View {
        let h = max(height - 8, 24)
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(parts.0).font(.system(size: 8.5, weight: .medium)).foregroundStyle(.white.opacity(0.55)).strikethrough()
                Text(parts.1).font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white)
            }
            .lineLimit(1).truncationMode(.middle).frame(maxWidth: 120, alignment: .leading)
            tile("checkmark", .green, accept: true)
            tile("xmark", .red, accept: false)
        }
        .padding(.leading, 9).padding(.trailing, 3)
        .frame(height: h)
        .background(Capsule().fill(.black))
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        .help("Règle apprise : l'ajouter aux substitutions ?")
    }

    private func tile(_ icon: String, _ color: Color, accept: Bool) -> some View {
        Button { Dictation.shared.answerOffer(accept: accept) } label: {
            Image(systemName: icon).font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 19, height: 19).background(Circle().fill(color))
        }
        .buttonStyle(.plain)
    }
}
