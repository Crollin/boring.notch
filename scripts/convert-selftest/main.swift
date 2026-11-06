// Auto-test du convertisseur (pas de cible XCTest dans le projet).
// swiftc boringNotch/modules/Convert/FileConverter.swift boringNotch/modules/Convert/MarkdownConverter.swift scripts/convert-selftest/main.swift -o /tmp/convert-selftest && /tmp/convert-selftest

import AppKit
import ImageIO
import PDFKit

func check(_ cond: Bool, _ msg: String) { if !cond { print("FAIL: \(msg)"); exit(1) } }

let dir = FileManager.default.temporaryDirectory.appendingPathComponent("convert-selftest-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: dir) }

// PNG 5000×3000 semi-transparent, avec un GPS dans les métadonnées.
let png = dir.appendingPathComponent("photo.png")
do {
    let ctx = CGContext(data: nil, width: 5000, height: 3000, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
    ctx.fill(CGRect(x: 0, y: 0, width: 2500, height: 3000))
    let dest = CGImageDestinationCreateWithURL(png as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 48.85]] as CFDictionary)
    check(CGImageDestinationFinalize(dest), "fixture png")
}

let imageTargets = FileConverter.targets(for: png)
check(!imageTargets.contains(.png), "png ne propose pas png")
check(imageTargets.contains(.jpeg) && imageTargets.contains(.pdf), "png propose jpeg + pdf")

for target in imageTargets where target != .pdf {
    let data = try! FileConverter.convertImage(png, to: target)
    let src = CGImageSourceCreateWithData(data as CFData, nil)!
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
    check(props[kCGImagePropertyGPSDictionary] == nil, "\(target): GPS supprimé")
    check(props[kCGImagePropertyPixelWidth] as? Int == FileConverter.maxPixel, "\(target): plafonné à maxPixel")
    if target == .jpeg {
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(img, in: CGRect(x: -Double(img.width) + 1, y: 0, width: Double(img.width), height: Double(img.height)))
        let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
        check(px[0] > 240 && px[1] > 240, "jpeg: transparent → blanc, pas noir")
    }
    print("ok image → \(target.label) (\(data.count / 1024) Ko)")
}
check(PDFDocument(data: try! FileConverter.convertImage(png, to: .pdf))?.pageCount == 1, "image → pdf")
print("ok image → PDF")

// Documents
let txt = dir.appendingPathComponent("notes.txt")
try! String(repeating: "Ligne de texte assez longue pour remplir la page.\n", count: 300).write(to: txt, atomically: true, encoding: .utf8)
let rtf = dir.appendingPathComponent("doc.rtf")
let attr = NSAttributedString(string: "Titre en gras", attributes: [.font: NSFont.boldSystemFont(ofSize: 24)])
try! attr.rtf(from: NSRange(location: 0, length: attr.length))!.write(to: rtf)
let html = dir.appendingPathComponent("page.html")
try! "<img src='https://example.com/x.png'>".write(to: html, atomically: true, encoding: .utf8)

check(FileConverter.targets(for: txt) == [.pdf, .markdown], "txt → pdf, md")
check(FileConverter.targets(for: html).isEmpty, "html refusé (pas de WebKit / réseau)")

MainActor.assumeIsolated {
    let long = PDFDocument(data: try! FileConverter.convertDocument(txt))!
    check(long.pageCount > 1, "txt long → plusieurs pages (\(long.pageCount))")
    check(long.string?.contains("Ligne de texte") == true, "texte présent dans le pdf")
    let styled = PDFDocument(data: try! FileConverter.convertDocument(rtf))!
    check(styled.string?.contains("Titre en gras") == true, "rtf → pdf")
}
print("ok documents → PDF")

// PDF → Markdown : titre, paragraphe, puces, tableau ; puis la même page scannée (OCR).
func drawSample(in ctx: CGContext, height: CGFloat) {
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    func put(_ s: String, _ x: CGFloat, _ y: CGFloat, _ font: NSFont) {
        NSAttributedString(string: s, attributes: [.font: font]).draw(at: NSPoint(x: x, y: height - y))
    }
    let body = NSFont(name: "Helvetica", size: 12)!, bold = NSFont(name: "Helvetica-Bold", size: 12)!
    put("Rapport annuel", 72, 80, NSFont(name: "Helvetica-Bold", size: 24)!)
    put("Ce document présente les résultats de l'année écoulée pour", 72, 120, body)
    put("l'ensemble des magasins du réseau.", 72, 136, body)
    put("• Premier point important", 72, 170, body)
    put("• Second point", 72, 186, body)
    for (i, row) in [["Produit", "Prix", "Stock"], ["Pommes", "2,50 €", "120"], ["Poires", "3,10 €", "80"], ["Cerises", "7,00 €", "15"]].enumerated() {
        for (j, cell) in row.enumerated() { put(cell, [72, 260, 400][j], 230 + CGFloat(i) * 20, i == 0 ? bold : body) }
    }
    put("Fin du rapport.", 72, 330, body)
    NSGraphicsContext.current = nil
}
let a4 = CGRect(x: 0, y: 0, width: 595, height: 842)
let textPDF = dir.appendingPathComponent("rapport.pdf")
do {
    var box = a4
    let ctx = CGContext(textPDF as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil); drawSample(in: ctx, height: a4.height); ctx.endPDFPage(); ctx.closePDF()
}
let scanPDF = dir.appendingPathComponent("scan.pdf")
do {
    let ctx = CGContext(data: nil, width: 1190, height: 1684, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: 1190, height: 1684)); ctx.scaleBy(x: 2, y: 2)
    drawSample(in: ctx, height: a4.height)
    let doc = PDFDocument()
    doc.insert(PDFPage(image: NSImage(cgImage: ctx.makeImage()!, size: a4.size))!, at: 0)
    check(doc.write(to: scanPDF), "fixture scan")
}
check(FileConverter.targets(for: textPDF) == [.markdown], "pdf → md")
check(FileConverter.targets(for: [textPDF, txt]) == [.markdown], "lot pdf + txt → md seul")
check(FileConverter.targets(for: [textPDF, png]).isEmpty, "lot pdf + image → rien")
for (name, url) in [("texte", textPDF), ("scan", scanPDF)] {
    let md = String(decoding: try! MarkdownConverter.pdf(url), as: UTF8.self)
    print("--- \(name)\n\(md)")
    check(md.contains("# Rapport annuel"), "\(name) : titre")
    check(md.contains("pour l'ensemble des magasins"), "\(name) : paragraphe recollé")
    check(md.contains("- Premier point important\n- Second point"), "\(name) : puces")
    check(md.contains("| Produit | Prix | Stock |\n| --- | --- | --- |\n| Pommes | 2,50 € | 120 |"), "\(name) : tableau")
    check(md.contains("| Cerises | 7,00 € | 15 |\n\nFin du rapport."), "\(name) : fin du tableau")
}
print("ok PDF → Markdown")

// DOCX → Markdown : vrai document Word (le writer docx d'AppKit perd les tableaux, on écrit le XML à la main).
do {
    let pkg = dir.appendingPathComponent("docx")
    func file(_ path: String, _ xml: String) {
        let url = pkg.appendingPathComponent(path)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" + xml).write(to: url, atomically: true, encoding: .utf8)
    }
    file("[Content_Types].xml", #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>"#)
    file("_rels/.rels", #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>"#)
    func p(_ runs: String) -> String { "<w:p>\(runs)</w:p>" }
    func r(_ t: String, _ props: String = "") -> String { "<w:r><w:rPr>\(props)<w:sz w:val=\"24\"/></w:rPr><w:t xml:space=\"preserve\">\(t)</w:t></w:r>" }
    func row(_ cells: [String]) -> String { "<w:tr>" + cells.map { "<w:tc>\(p(r($0)))</w:tc>" }.joined() + "</w:tr>" }
    file("word/document.xml", #"<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>"#
        + p("<w:r><w:rPr><w:b/><w:sz w:val=\"40\"/></w:rPr><w:t>Devis</w:t></w:r>")
        + p(r("Voici le ") + r("détail", "<w:b/>") + r(" :"))
        + p(r("• Pose")) + p(r("• Fourniture"))
        + "<w:tbl><w:tblGrid><w:gridCol w:w=\"3000\"/><w:gridCol w:w=\"3000\"/></w:tblGrid>"
        + row(["Article", "Montant"]) + row(["Pose", "400 €"]) + "</w:tbl>"
        + p(r("Merci.")) + "</w:body></w:document>")
    let docx = dir.appendingPathComponent("devis.docx")
    let zip = Process()
    zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    zip.currentDirectoryURL = pkg
    zip.arguments = ["-qr", docx.path, "[Content_Types].xml", "_rels", "word"]
    try! zip.run(); zip.waitUntilExit()

    MainActor.assumeIsolated {
        let md = String(decoding: try! MarkdownConverter.document(docx), as: UTF8.self)
        print("--- docx\n\(md)")
        check(md.contains("# Devis"), "docx : titre")
        check(md.contains("Voici le **détail** :"), "docx : gras")
        check(md.contains("- Pose\n- Fourniture"), "docx : liste")
        check(md.contains("| Article | Montant |\n| --- | --- |\n| Pose | 400 € |\n\nMerci."), "docx : tableau")
    }
}
print("ok DOCX → Markdown")
print("ALL OK")
