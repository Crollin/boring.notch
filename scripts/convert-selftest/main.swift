// Auto-test du convertisseur (pas de cible XCTest dans le projet).
// swiftc boringNotch/modules/Convert/FileConverter.swift scripts/convert-selftest/main.swift -o /tmp/convert-selftest && /tmp/convert-selftest

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

check(FileConverter.targets(for: txt) == [.pdf], "txt → pdf")
check(FileConverter.targets(for: html).isEmpty, "html refusé (pas de WebKit / réseau)")

MainActor.assumeIsolated {
    let long = PDFDocument(data: try! FileConverter.convertDocument(txt))!
    check(long.pageCount > 1, "txt long → plusieurs pages (\(long.pageCount))")
    check(long.string?.contains("Ligne de texte") == true, "texte présent dans le pdf")
    let styled = PDFDocument(data: try! FileConverter.convertDocument(rtf))!
    check(styled.string?.contains("Titre en gras") == true, "rtf → pdf")
}
print("ok documents → PDF")
print("ALL OK")
