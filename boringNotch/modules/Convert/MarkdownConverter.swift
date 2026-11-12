//
//  MarkdownConverter.swift
//  boringNotch
//
//  PDF et documents → Markdown, 100 % local (PDFKit, Vision, AppKit). But : un texte léger et éditable à donner
//  à une IA. Titres, listes et tableaux sont reconstruits par heuristique ; les images sont ignorées.
//

import AppKit
import PDFKit
import Vision

enum MarkdownConverter {
    enum Block: Equatable {
        case heading(Int, String)
        case paragraph(String)
        case listItem(String)
        case table([[String]])
    }

    // MARK: - PDF (thread-safe, à appeler hors du main thread)

    /// Caractère (ou phrase OCR) positionné sur la page, coordonnées de haut en bas.
    struct Item { var text: String; var rect: CGRect; var size: CGFloat; var bold: Bool }
    /// Morceau de ligne séparé des autres par un grand blanc horizontal : une cellule potentielle.
    struct Segment { var text: String; var x0: CGFloat; var x1: CGFloat; var size: CGFloat; var bold: Bool }
    struct Line {
        var segments: [Segment]
        var top: CGFloat
        var bottom: CGFloat
        var text: String { segments.map(\.text).joined(separator: " ") }
        var height: CGFloat { bottom - top }
    }

    static func pdf(_ url: URL) throws -> Data {
        guard let doc = PDFDocument(url: url), !doc.isLocked else { throw ConvertError.unreadable }
        let pages: [[Line]] = (0..<doc.pageCount).compactMap { doc.page(at: $0) }.map { page in
            let runs = textRuns(page)
            // ponytail: une page sans couche texte est considérée comme scannée → OCR. Seuil arbitraire.
            return lines(from: runs.joined().count >= 20 ? runs : ocrItems(page).map { [$0] })
        }
        var sizes: [CGFloat: Int] = [:]
        for line in pages.joined() {
            for s in line.segments { sizes[Typography.bucket(s.size), default: 0] += s.text.count }
        }
        let typo = Typography(sizes: sizes)
        let blocks = pages.flatMap { pageBlocks(stripPageNumbers($0), typo) }
        guard !blocks.isEmpty else { throw ConvertError.noText }
        return Data(render(blocks).utf8)
    }

    /// Caractères de la page, regroupés par ligne de texte PDFKit.
    private static func textRuns(_ page: PDFPage) -> [[Item]] {
        guard let attr = page.attributedString else { return [] }
        let ns = attr.string as NSString
        let top = page.bounds(for: .mediaBox).maxY
        var runs: [[Item]] = [[]]
        var i = 0
        while i < ns.length {
            let range = ns.rangeOfComposedCharacterSequence(at: i)
            i = NSMaxRange(range)
            let char = ns.substring(with: range)
            if char.rangeOfCharacter(from: .newlines) != nil { runs.append([]); continue }
            guard !char.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            // characterBounds(at:) se décale après les retours à la ligne ; la sélection reste alignée sur la chaîne.
            guard let b = page.selection(for: range)?.bounds(for: page), b.height > 0 else { continue }
            let font = attr.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            runs[runs.count - 1].append(Item(text: char, rect: CGRect(x: b.minX, y: top - b.maxY, width: b.width, height: b.height),
                                             size: font?.pointSize ?? b.height, bold: isBold(font)))
        }
        return runs.filter { !$0.isEmpty }
    }

    /// Page scannée : rendu à 144 dpi puis reconnaissance de texte Vision (fr + en).
    private static func ocrItems(_ page: PDFPage) -> [Item] {
        let box = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        guard box.width > 0, box.height > 0,
              let ctx = CGContext(data: nil, width: Int(box.width * scale), height: Int(box.height * scale), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return [] }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        guard let image = ctx.makeImage() else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["fr-FR", "en-US"]
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { obs in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            let b = obs.boundingBox // normalisé, origine en bas à gauche
            let rect = CGRect(x: b.minX * box.width, y: (1 - b.maxY) * box.height,
                              width: b.width * box.width, height: b.height * box.height)
            return Item(text: text, rect: rect, size: rect.height, bold: false)
        }
    }

    /// Fusionne les lignes de texte qui se chevauchent en hauteur (cellules d'une même rangée),
    /// puis découpe chaque rangée en segments sur les grands blancs.
    static func lines(from runs: [[Item]]) -> [Line] {
        let boxes = runs.map { run in (box: run.map(\.rect).reduce(run[0].rect) { $0.union($1) }, items: run) }
        var groups: [(box: CGRect, items: [Item])] = []
        for run in boxes.sorted(by: { $0.box.midY < $1.box.midY }) {
            if let g = groups.last,
               min(g.box.maxY, run.box.maxY) - max(g.box.minY, run.box.minY) > min(g.box.height, run.box.height) * 0.5 {
                groups[groups.count - 1].items += run.items
            } else {
                groups.append(run)
            }
        }
        return groups.map { group in
            var segs: [Segment] = []
            var last: Item?
            for it in group.items.sorted(by: { $0.rect.minX < $1.rect.minX }) {
                // Faux gras : certains PDF dessinent le même texte deux fois avec un léger décalage.
                if let l = last, l.text == it.text, abs(l.rect.minX - it.rect.minX) < 1 { continue }
                last = it
                let em = max(it.size, 1)
                let gap = it.rect.minX - (segs.last?.x1 ?? -.infinity)
                // ponytail: blanc ≥ 1 em = changement de cellule ; des colonnes plus serrées restent collées.
                if gap < em, !segs.isEmpty {
                    let n = segs.count - 1
                    segs[n].text += (gap > em * 0.15 ? " " : "") + it.text
                    segs[n].x1 = max(segs[n].x1, it.rect.maxX)
                    segs[n].bold = segs[n].bold && it.bold
                } else {
                    segs.append(Segment(text: it.text, x0: it.rect.minX, x1: it.rect.maxX, size: it.size, bold: it.bold))
                }
            }
            // Puce ou numéro détaché de son texte par un retrait : ce n'est pas une colonne.
            if segs.count >= 2, segs[0].text.wholeMatch(of: #/[•◦▪●○■□➢►▶✓✔\-–—*]|\d{1,3}[.)]|[a-z][.)]/#) != nil {
                segs[1].text = segs[0].text + " " + segs[1].text
                segs[1].x0 = segs[0].x0
                segs.removeFirst()
            }
            return Line(segments: segs,
                        top: group.items.map(\.rect.minY).min() ?? 0,
                        bottom: group.items.map(\.rect.maxY).max() ?? 0)
        }
    }

    /// Numéro de page seul en haut ou en bas de page : du bruit pour une IA.
    private static func stripPageNumbers(_ lines: [Line]) -> [Line] {
        var lines = lines
        let isNumber = { (l: Line) in
            l.text.wholeMatch(of: #/(?i)(page\s*)?\d{1,4}(\s*(\/|sur|of)\s*\d{1,4})?/#) != nil
        }
        if let l = lines.last, isNumber(l) { lines.removeLast() }
        if let l = lines.first, isNumber(l) { lines.removeFirst() }
        return lines
    }

    static func pageBlocks(_ lines: [Line], _ typo: Typography) -> [Block] {
        var blocks: [Block] = []
        var prose: [Line] = []
        var i = 0
        while i < lines.count {
            guard let (end, columns) = tableRun(in: lines, from: i) else {
                prose.append(lines[i])
                i += 1
                continue
            }
            blocks += proseBlocks(prose, typo)
            prose = []
            let run = lines[i..<end]
            let raw = run.map { cells($0, columns) }
            let filled = raw.joined().filter { !$0.isEmpty }
            let avg = filled.map(\.count).reduce(0, +) / max(filled.count, 1)
            // ponytail: mise en page sur deux colonnes de texte (longues lignes, nombreuses) ≠ tableau. Heuristique.
            if columns.count == 2, run.count >= 5, avg > 40 {
                for c in 0..<2 {
                    let column = run.compactMap { line -> Line? in
                        let segs = line.segments.filter { columnIndex($0, columns) == c }
                        return segs.isEmpty ? nil : Line(segments: segs, top: line.top, bottom: line.bottom)
                    }
                    blocks += proseBlocks(column, typo)
                }
            } else {
                var rows: [[String]] = []
                for row in raw {
                    // Première cellule vide = suite d'une cellule écrite sur plusieurs lignes.
                    if row[0].isEmpty, !rows.isEmpty {
                        for c in row.indices where !row[c].isEmpty {
                            rows[rows.count - 1][c] = join(rows[rows.count - 1][c], row[c])
                        }
                    } else {
                        rows.append(row)
                    }
                }
                blocks.append(.table(rows))
            }
            i = end
        }
        return blocks + proseBlocks(prose, typo)
    }

    /// Lignes consécutives à plusieurs segments dont les colonnes s'alignent. Retourne la fin (exclue) et les colonnes.
    static func tableRun(in lines: [Line], from start: Int) -> (end: Int, columns: [ClosedRange<CGFloat>])? {
        guard lines[start].segments.count >= 2 else { return nil }
        func close(_ a: Int, _ b: Int) -> Bool {
            lines[b].top - lines[a].bottom < max(lines[a].height, lines[b].height) * 2
        }
        var end = start + 1
        while end < lines.count, close(end - 1, end) {
            // Lignes à une seule cellule (voisines vides, ou cellule sur plusieurs lignes) : gardées si le tableau reprend après.
            var next = end
            while next < lines.count, lines[next].segments.count == 1, close(next - 1, next) { next += 1 }
            guard next < lines.count, lines[next].segments.count >= 2, close(next - 1, next) else { break }
            end = next + 1
        }
        guard var cols = columns(of: lines[start..<end]) else { return nil }
        // Une ligne qui déborde sur plusieurs colonnes (titre, paragraphe) termine le tableau.
        if let cut = (start..<end).first(where: { k in
            lines[k].segments.count == 1 && cols.filter { $0.overlaps(lines[k].segments[0].x0...lines[k].segments[0].x1) }.count > 1
        }) {
            end = cut
            guard let c = columns(of: lines[start..<end]) else { return nil }
            cols = c
        }
        return (end, cols)
    }

    /// Colonnes = union des intervalles horizontaux des segments, sur les lignes à plusieurs cellules.
    private static func columns(of lines: ArraySlice<Line>) -> [ClosedRange<CGFloat>]? {
        let multi = lines.filter { $0.segments.count >= 2 }
        guard multi.count >= 2 else { return nil }
        var columns: [ClosedRange<CGFloat>] = []
        for s in multi.flatMap(\.segments).sorted(by: { $0.x0 < $1.x0 }) {
            if let last = columns.last, s.x0 <= last.upperBound + 2 {
                columns[columns.count - 1] = last.lowerBound...max(last.upperBound, s.x1)
            } else {
                columns.append(s.x0...s.x1)
            }
        }
        return columns.count >= 2 ? columns : nil
    }

    private static func columnIndex(_ s: Segment, _ columns: [ClosedRange<CGFloat>]) -> Int {
        if let c = columns.firstIndex(where: { $0.overlaps(s.x0...s.x1) }) { return c }
        let mid = (s.x0 + s.x1) / 2
        return columns.indices.min { abs((columns[$0].lowerBound + columns[$0].upperBound) / 2 - mid)
            < abs((columns[$1].lowerBound + columns[$1].upperBound) / 2 - mid) } ?? 0
    }

    private static func cells(_ line: Line, _ columns: [ClosedRange<CGFloat>]) -> [String] {
        var row = Array(repeating: "", count: columns.count)
        for s in line.segments {
            let c = columnIndex(s, columns)
            row[c] = row[c].isEmpty ? s.text : row[c] + " " + s.text
        }
        return row
    }

    static func proseBlocks(_ lines: [Line], _ typo: Typography) -> [Block] {
        var blocks: [Block] = []
        var previous: Line?
        for line in lines {
            defer { previous = line }
            let text = line.text
            // ponytail: interligne < 0,6 ligne = même paragraphe. Les paragraphes sans espacement (retrait seul) fusionnent.
            let tight = previous.map { line.top - $0.bottom < min(line.height, $0.height) * 0.6 } ?? false
            let size = line.segments.map(\.size).max() ?? typo.body
            if let level = typo.headingLevel(size: size, bold: line.segments.allSatisfy(\.bold), text: text) {
                if tight, case .heading(level, let prev)? = blocks.last {
                    blocks[blocks.count - 1] = .heading(level, prev + " " + text)
                } else {
                    blocks.append(.heading(level, text))
                }
                continue
            }
            if let item = listItem(text) {
                blocks.append(.listItem(item))
                continue
            }
            if tight, let last = blocks.last {
                switch last {
                case .paragraph(let p): blocks[blocks.count - 1] = .paragraph(join(p, text)); continue
                case .listItem(let p): blocks[blocks.count - 1] = .listItem(join(p, text)); continue
                default: break
                }
            }
            blocks.append(.paragraph(text))
        }
        return blocks
    }

    /// Recolle deux lignes ; une césure en fin de ligne (« inter- » + « face ») est supprimée.
    static func join(_ a: String, _ b: String) -> String {
        if a.hasSuffix("-"), a.dropLast().last?.isLetter == true, b.first?.isLowercase == true {
            return String(a.dropLast()) + b
        }
        return a + " " + b
    }

    // MARK: - Documents Word / RTF / ODT (AppKit : main thread)

    @MainActor
    static func document(_ src: URL) throws -> Data {
        guard let type = FileConverter.documentType(of: src) else { throw ConvertError.unreadable }
        let text = try NSAttributedString(url: src, options: [.documentType: type], documentAttributes: nil)
        let blocks = blocks(from: text)
        guard !blocks.isEmpty else { throw ConvertError.noText }
        return Data(render(blocks).utf8)
    }

    static func blocks(from text: NSAttributedString) -> [Block] {
        let ns = text.string as NSString
        let all = NSRange(location: 0, length: ns.length)
        var sizes: [CGFloat: Int] = [:]
        text.enumerateAttribute(.font, in: all) { value, range, _ in
            if let font = value as? NSFont { sizes[Typography.bucket(font.pointSize), default: 0] += range.length }
        }
        let typo = Typography(sizes: sizes)

        var blocks: [Block] = []
        var table: (id: NSTextTable, cells: [Int: [Int: String]])?
        func flushTable() {
            guard let t = table else { return }
            let width = (t.cells.values.flatMap(\.keys).max() ?? 0) + 1
            blocks.append(.table(t.cells.keys.sorted().map { r in (0..<width).map { t.cells[r]?[$0] ?? "" } }))
            table = nil
        }

        ns.enumerateSubstrings(in: all, options: [.byParagraphs, .substringNotRequired]) { _, range, enclosing, _ in
            guard enclosing.length > 0 else { return }
            let style = text.attribute(.paragraphStyle, at: enclosing.location, effectiveRange: nil) as? NSParagraphStyle
            let content = inline(text.attributedSubstring(from: range))

            if let cell = style?.textBlocks.compactMap({ $0 as? NSTextTableBlock }).last {
                if table?.id !== cell.table {
                    flushTable()
                    table = (cell.table, [:])
                }
                let old = table?.cells[cell.startingRow]?[cell.startingColumn] ?? ""
                table?.cells[cell.startingRow, default: [:]][cell.startingColumn] =
                    old.isEmpty || content.isEmpty ? old + content : old + " " + content
                return
            }
            flushTable()
            guard !content.isEmpty else { return }

            let plain = clean(ns.substring(with: range))
            var allBold = true
            text.enumerateAttribute(.font, in: range) { value, r, _ in
                if !isBold(value as? NSFont), !clean(ns.substring(with: r)).isEmpty { allBold = false }
            }
            let size = (text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)?.pointSize ?? typo.body
            if let level = typo.headingLevel(size: size, bold: allBold, text: plain) {
                blocks.append(.heading(level, plain))
            } else if let lists = style?.textLists, let list = lists.last {
                let indent = String(repeating: "  ", count: lists.count - 1)
                if let item = listItem(plain) {
                    blocks.append(.listItem(indent + item))
                } else {
                    let ordered = list.markerFormat.rawValue.contains("decimal")
                    let marker = ordered ? "\(text.itemNumber(in: list, at: range.location))." : "-"
                    blocks.append(.listItem(indent + marker + " " + content))
                }
            } else if let item = listItem(plain) {
                blocks.append(.listItem(item))
            } else {
                blocks.append(.paragraph(content))
            }
        }
        flushTable()
        return blocks
    }

    /// Gras / italique en Markdown, sur une seule ligne.
    private static func inline(_ s: NSAttributedString) -> String {
        let ns = s.string as NSString
        var out = ""
        s.enumerateAttribute(.font, in: NSRange(location: 0, length: s.length)) { value, range, _ in
            let raw = ns.substring(with: range)
            let font = value as? NSFont
            let mark = (isBold(font) ? "**" : "") + (font?.fontDescriptor.symbolicTraits.contains(.italic) == true ? "*" : "")
            let core = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !mark.isEmpty, !core.isEmpty else { out += raw; return }
            let lead = raw.prefix { $0.isWhitespace }
            let trail = raw.reversed().prefix { $0.isWhitespace }
            out += lead + mark + core + String(mark.reversed()) + String(trail.reversed())
        }
        // Deux passages gras collés : « **a****b** » → « **ab** ».
        return clean(out.replacingOccurrences(of: "******", with: "").replacingOccurrences(of: "****", with: ""))
    }

    /// Une seule ligne, sans le caractère des pièces jointes (images ignorées).
    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{FFFC}", with: "")
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Commun

    struct Typography {
        let body: CGFloat
        let headings: [CGFloat]

        init(sizes: [CGFloat: Int]) {
            let body = sizes.max { $0.value < $1.value }?.key ?? 12
            self.body = body
            headings = sizes.keys.filter { $0 >= body * 1.15 }.sorted(by: >)
        }

        static func bucket(_ size: CGFloat) -> CGFloat { (size * 2).rounded() / 2 }

        /// Plus grand que le texte courant → # / ## / ### ; ligne courte entièrement en gras → niveau suivant.
        func headingLevel(size: CGFloat, bold: Bool, text: String) -> Int? {
            guard !text.isEmpty, text.count <= 120 else { return nil }
            if let i = headings.firstIndex(of: Self.bucket(size)) { return min(i + 1, 3) }
            if bold, text.count <= 80, !text.hasSuffix("."), text.contains(where: \.isLetter) {
                return min(headings.count + 1, 4)
            }
            return nil
        }
    }

    static func isBold(_ font: NSFont?) -> Bool {
        guard let font else { return false }
        return font.fontDescriptor.symbolicTraits.contains(.bold)
            || font.fontName.range(of: "bold|black|heavy|semibold", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// « • texte », « - texte », « 1. texte » → item de liste Markdown.
    static func listItem(_ text: String) -> String? {
        if let m = text.wholeMatch(of: #/[•◦▪●○■□➢►▶✓✔]\s*(.+)/#) { return "- " + m.1 }
        if let m = text.wholeMatch(of: #/[\-–—*]\s+(.+)/#) { return "- " + m.1 }
        if let m = text.wholeMatch(of: #/(\d{1,3})[.)]\s+(.+)/#) { return "\(m.1). " + m.2 }
        return nil
    }

    static func render(_ blocks: [Block]) -> String {
        var out = ""
        var previous: Block?
        for block in blocks {
            if let previous {
                if case .listItem = previous, case .listItem = block { out += "\n" } else { out += "\n\n" }
            }
            switch block {
            case .heading(let level, let text): out += String(repeating: "#", count: level) + " " + text
            case .paragraph(let text), .listItem(let text): out += text
            case .table(let rows): out += renderTable(rows)
            }
            previous = block
        }
        return out + "\n"
    }

    private static func renderTable(_ rows: [[String]]) -> String {
        let width = rows.map(\.count).max() ?? 0
        guard width > 0 else { return "" }
        let lines = rows.map { row in
            let cells = (row + Array(repeating: "", count: width - row.count)).map {
                clean($0).replacingOccurrences(of: "|", with: "\\|")
            }
            return "| " + cells.joined(separator: " | ") + " |"
        }
        return ([lines[0], "|" + String(repeating: " --- |", count: width)] + lines.dropFirst()).joined(separator: "\n")
    }
}
