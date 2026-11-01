//
//  FileConverter.swift
//  boringNotch
//
//  Conversion 100 % locale (ImageIO, PDFKit, AppKit) : images → JPEG/PNG/AVIF/PDF, documents → PDF.
//  Aucun réseau, aucun binaire externe (l'app est sandboxée).
//

import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum ConvertTarget: String, CaseIterable, Identifiable {
    case jpeg, png, avif, pdf

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        case .avif: return UTType("public.avif") ?? .image
        case .pdf: return .pdf
        }
    }
}

enum ConvertError: LocalizedError {
    case unreadable, encodingFailed

    var errorDescription: String? {
        switch self {
        case .unreadable: return "Fichier illisible."
        case .encodingFailed: return "Échec de l'encodage."
        }
    }
}

enum FileConverter {
    /// ponytail: plafond au décodage, borne la mémoire face aux images géantes. À monter si besoin d'exports plus grands.
    static let maxPixel = 4096
    static let jpegQuality = 0.82

    /// Types de documents lus par AppKit, avec leur type explicite.
    /// Le HTML est exclu volontairement : son import passe par WebKit et peut charger des ressources distantes.
    private static let documentTypes: [(UTType, NSAttributedString.DocumentType)] = [
        (.rtfd, .rtfd),
        (.rtf, .rtf),
        (UTType("org.openxmlformats.wordprocessingml.document"), .officeOpenXML),
        (UTType("com.microsoft.word.doc"), .docFormat),
        (UTType("org.oasis-open.opendocument.text"), .openDocument),
        (.plainText, .plain),
    ].compactMap { type, doc in type.map { ($0, doc) } }

    private static let writableImageTypes = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])

    static func contentType(of url: URL) -> UTType? {
        (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: url.pathExtension)
    }

    static func documentType(of url: URL) -> NSAttributedString.DocumentType? {
        guard let type = contentType(of: url) else { return nil }
        return documentTypes.first { type.conforms(to: $0.0) }?.1
    }

    static func targets(for url: URL) -> [ConvertTarget] {
        guard let type = contentType(of: url) else { return [] }
        if type.conforms(to: .image) {
            return ConvertTarget.allCases.filter { target in
                target.utType != type && (target == .pdf || writableImageTypes.contains(target.utType.identifier))
            }
        }
        return documentType(of: url) == nil ? [] : [.pdf]
    }

    // MARK: - Images (thread-safe, à appeler hors du main thread)

    static func convertImage(_ src: URL, to target: ConvertTarget) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ConvertError.unreadable
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // applique l'orientation EXIF
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ConvertError.unreadable
        }

        if target == .pdf {
            let doc = PDFDocument()
            guard let page = PDFPage(image: NSImage(cgImage: image, size: .zero)) else { throw ConvertError.encodingFailed }
            doc.insert(page, at: 0)
            guard let data = doc.dataRepresentation() else { throw ConvertError.encodingFailed }
            return data
        }

        if target == .jpeg, hasAlpha(image) {
            guard let flat = flattenedOnWhite(image) else { throw ConvertError.encodingFailed }
            image = flat
        }

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, target.utType.identifier as CFString, 1, nil) else {
            throw ConvertError.encodingFailed
        }
        // Aucune métadonnée source n'est recopiée : EXIF/GPS supprimés.
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ConvertError.encodingFailed }
        return data as Data
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
    }

    /// JPEG n'a pas de transparence : sans ça, les zones transparentes deviennent noires.
    private static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(.white)
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }

    // MARK: - Documents (AppKit : main thread)

    /// ponytail: rendu texte d'AppKit, fidèle pour du texte/styles/images, approximatif pour les mises en page Word complexes.
    @MainActor
    static func convertDocument(_ src: URL) throws -> Data {
        guard let docType = documentType(of: src) else { throw ConvertError.unreadable }
        let text = try NSAttributedString(url: src, options: [.documentType: docType], documentAttributes: nil)

        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 595, height: 842) // A4
        let margin: CGFloat = 56
        info.topMargin = margin; info.bottomMargin = margin
        info.leftMargin = margin; info.rightMargin = margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic

        let width = info.paperSize.width - 2 * margin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        view.isVerticallyResizable = true
        view.maxSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        view.textStorage?.setAttributedString(text)
        if let container = view.textContainer { view.layoutManager?.ensureLayout(for: container) }
        view.sizeToFit()

        // pdfOperation(with:inside:to:) ignore la pagination (une seule page géante) : on passe par une vraie impression vers fichier.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: tmp) }
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = tmp

        let op = NSPrintOperation(view: view, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run(), let data = try? Data(contentsOf: tmp), !data.isEmpty else { throw ConvertError.encodingFailed }
        return data
    }

    // MARK: - Sortie

    /// Écrit dans ~/Downloads sans jamais écraser : « nom.ext », puis « nom 2.ext », etc.
    static func save(_ data: Data, from src: URL, ext: String) throws -> URL {
        let dir = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let base = src.deletingPathExtension().lastPathComponent
        for n in 1...999 {
            let name = n == 1 ? "\(base).\(ext)" : "\(base) \(n).\(ext)"
            let url = dir.appendingPathComponent(name)
            do {
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}
