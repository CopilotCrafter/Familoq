import Foundation
import SwiftData
import UIKit
import PDFKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import FamiloqCore
import FamiloqBudget

/// A page to add: a photo (JPEG) or a single PDF page, and which side it is.
struct NewPage {
    var format: String
    var data: Data
    var side: PageSide = .none
}

@MainActor
enum DocumentService {
    static func pages(of documentID: UUID, context: ModelContext) -> [DocumentPage] {
        let did = documentID
        return (try? context.fetch(FetchDescriptor<DocumentPage>(predicate: #Predicate { $0.documentID == did },
                                                                 sortBy: [SortDescriptor(\DocumentPage.sortOrder)]))) ?? []
    }

    /// Adds pages after the existing ones.
    static func addPages(_ items: [NewPage], to document: FamilyDocument, context: ModelContext) {
        var order = (pages(of: document.id, context: context).map(\.sortOrder).max() ?? -1) + 1
        for item in items {
            let page = DocumentPage(familyID: document.familyID, documentID: document.id, format: item.format, data: item.data, sortOrder: order)
            page.isPrivate = document.isPrivate
            page.side = item.side
            context.insert(page)
            order += 1
        }
        document.updatedAt = Date()
    }

    /// Scanned photos as pages. Cards: first photo = front, second = back.
    static func pages(from images: [UIImage], twoSided: Bool, firstSide: PageSide = .front) -> [NewPage] {
        images.enumerated().compactMap { index, image in
            guard let data = storageJPEG(image) else { return nil }
            var side = PageSide.none
            if twoSided && index < 2 {
                side = index == 0 ? firstSide : (firstSide == .front ? .back : .front)
            }
            return NewPage(format: "jpg", data: data, side: side)
        }
    }

    /// An imported PDF becomes one page per PDF page (so pages can be moved,
    /// rotated, split and read one by one).
    static func pages(fromPDF data: Data) -> [NewPage] {
        guard let source = PDFDocument(data: data), source.pageCount > 0 else { return [] }
        if source.isEncrypted && source.isLocked { return [NewPage(format: "pdf", data: data)] }
        var result: [NewPage] = []
        for index in 0..<source.pageCount {
            guard let page = source.page(at: index) else { continue }
            let single = PDFDocument()
            single.insert(page, at: 0)
            if let bytes = single.dataRepresentation() { result.append(NewPage(format: "pdf", data: bytes)) }
        }
        return result.isEmpty ? [NewPage(format: "pdf", data: data)] : result
    }

    /// Keeps the pages' privacy in step with the document.
    static func setPrivate(_ document: FamilyDocument, _ value: Bool, context: ModelContext) {
        document.isPrivate = value
        document.updatedAt = Date()
        for page in pages(of: document.id, context: context) { page.isPrivate = value }
    }

    static func delete(_ document: FamilyDocument, context: ModelContext) {
        for page in pages(of: document.id, context: context) { context.delete(page) }
        let did: UUID? = document.id
        for reminder in (try? context.fetch(FetchDescriptor<FamilyReminder>(predicate: #Predicate { $0.documentID == did }))) ?? [] {
            reminder.documentID = nil
            reminder.updatedAt = Date()
        }
        context.delete(document)
        try? context.save()
        Task { await PlannerNotifications.reschedule(context: context) }
    }

    /// Moves the pages from `index` on into a new document of the same kind
    /// and person ("Split here").
    @discardableResult
    static func split(_ document: FamilyDocument, at index: Int, context: ModelContext) -> FamilyDocument? {
        let all = pages(of: document.id, context: context)
        guard index > 0, index < all.count else { return nil }
        let copy = FamilyDocument(familyID: document.familyID, title: document.displayTitle + " (2)")
        copy.kind = document.kind
        copy.memberID = document.memberID
        copy.personName = document.personName
        copy.carID = document.carID
        copy.tagsRaw = document.tagsRaw
        copy.tripIDsRaw = document.tripIDsRaw
        copy.isPrivate = document.isPrivate
        copy.remind = false
        copy.createdByMemberID = document.createdByMemberID
        context.insert(copy)
        for (order, page) in all[index...].enumerated() {
            page.documentID = copy.id
            page.sortOrder = order
        }
        document.updatedAt = Date()
        try? context.save()
        return copy
    }

    /// Saves a new page order.
    static func reorder(_ pages: [DocumentPage]) {
        for (index, page) in pages.enumerated() where page.sortOrder != index {
            page.sortOrder = index
        }
    }

    /// Stores a photo as a sharp but small colour JPEG (documents need
    /// colour and must stay readable when printed).
    static func storageJPEG(_ image: UIImage, maxSide: CGFloat = 2200, quality: CGFloat = 0.72) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// Removes exported copies (they are only needed while sharing).
    static func clearExports() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FamiloqExport", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
    }

    /// A safe file name ("Reisepass - Anna.pdf").
    static func fileName(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_()"))
        let cleaned = String(text.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Document" : String(cleaned.prefix(80))
    }
}

// MARK: - Page images

enum PageImage {
    /// The page as it is shown: photo turned by its quarter turns, or a PDF
    /// page rendered (about 200 dpi on A4).
    static func image(format: String, data: Data, quarterTurns: Int, width: CGFloat = 1654) -> UIImage? {
        if format == "pdf" {
            guard let doc = PDFDocument(data: data), let page = doc.page(at: 0) else { return nil }
            page.rotation = (page.rotation + quarterTurns * 90) % 360
            let bounds = page.bounds(for: .mediaBox)
            let turned = page.rotation % 180 != 0
            let w = turned ? bounds.height : bounds.width
            let h = turned ? bounds.width : bounds.height
            guard w > 0, h > 0 else { return nil }
            return page.thumbnail(of: CGSize(width: width, height: width * h / w), for: .mediaBox)
        }
        guard let image = UIImage(data: data) else { return nil }
        return rotated(image, quarterTurns: quarterTurns)
    }

    static func rotated(_ image: UIImage, quarterTurns: Int) -> UIImage {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 else { return image }
        let size = image.size
        let target = turns % 2 == 0 ? size : CGSize(width: size.height, height: size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: target, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: target.width / 2, y: target.height / 2)
            cg.rotate(by: CGFloat(turns) * .pi / 2)
            image.draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}

// MARK: - Reading text (search)

/// Reads the words on a page on this iPhone (Vision, no internet) - only
/// used to find documents by searching.
@MainActor
enum DocumentText {
    private static var running = false

    /// Reads pages that were not read yet (a few at a time).
    static func readMissing(familyID: UUID, context: ModelContext) async {
        guard !running else { return }
        running = true
        defer { running = false }
        let fid = familyID
        var descriptor = FetchDescriptor<DocumentPage>(predicate: #Predicate { $0.familyID == fid && $0.textScanned == false })
        descriptor.fetchLimit = 12
        let pages = (try? context.fetch(descriptor)) ?? []
        var changed = false
        for page in pages {
            guard let data = page.data else { continue }
            let format = page.format
            let turns = page.quarterTurns
            let text = await Task.detached(priority: .utility) { DocumentText.read(format: format, data: data, quarterTurns: turns) }.value
            if page.isDeleted { continue }
            page.text = String(text.prefix(20_000))
            page.textScanned = true
            changed = true
        }
        if changed { try? context.save() }
    }

    nonisolated static func read(format: String, data: Data, quarterTurns: Int) -> String {
        if format == "pdf", let doc = PDFDocument(data: data) {
            let embedded = (doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if embedded.count > 20 { return embedded }
        }
        guard let image = PageImage.image(format: format, data: data, quarterTurns: quarterTurns, width: 1400),
              let cgImage = image.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["de-DE", "en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

// MARK: - Export

struct ExportOptions {
    var name: String
    var twoSidesOnOnePage = false
    /// Two unlabeled photos of a card count as front and back.
    var pairUnlabeled = false
    var smaller = false
    var blackAndWhite = false
    var stamp = false
    var stampLanguage: CopyStamp.Language = .german
    var stampPurpose = ""
    var password = ""
    /// Blacked-out areas per page (0-1 of the page as shown).
    var redactions: [UUID: [CGRect]] = [:]
}

/// One page of the export (a copy of the stored page's content).
struct ExportPage: Identifiable {
    let id: UUID
    let format: String
    let data: Data
    let quarterTurns: Int
    let side: PageSide

    var isImage: Bool { format != "pdf" }
}

enum DocumentExporter {
    static let a4 = CGSize(width: 595, height: 842)

    @MainActor
    static func exportPages(_ pages: [DocumentPage]) -> [ExportPage] {
        pages.compactMap { page in
            guard let data = page.data else { return nil }
            return ExportPage(id: page.id, format: page.format, data: data, quarterTurns: page.quarterTurns, side: page.side)
        }
    }

    /// The finished PDF (password-protected when a password is set).
    static func pdf(_ pages: [ExportPage], options: ExportOptions) -> Data? {
        guard !pages.isEmpty else { return nil }
        let result = PDFDocument()
        // Pages keep a reference to their document - keep those alive.
        var sources: [PDFDocument] = []
        let groups: [[Int]] = options.twoSidesOnOnePage
            ? DocumentLayout.pairs(sides: pages.map(\.side), isImage: pages.map(\.isImage), pairUnlabeled: options.pairUnlabeled)
            : pages.indices.map { [$0] }
        for group in groups {
            if group.count == 2 {
                let images = group.compactMap { processedImage(pages[$0], options: options) }
                if let doc = renderPage(size: a4, options: options, draw: { rect in drawPair(images, in: rect) }),
                   let page = doc.page(at: 0) {
                    sources.append(doc)
                    result.insert(page, at: result.pageCount)
                }
                continue
            }
            let item = pages[group[0]]
            if !item.isImage && !needsRaster(item, options: options),
               let doc = PDFDocument(data: item.data) {
                // Unchanged PDF page: stays sharp text.
                sources.append(doc)
                for index in 0..<doc.pageCount {
                    guard let page = doc.page(at: index) else { continue }
                    page.rotation = (page.rotation + item.quarterTurns * 90) % 360
                    result.insert(page, at: result.pageCount)
                }
                continue
            }
            guard let image = processedImage(item, options: options) else { continue }
            let landscape = image.size.width > image.size.height
            let size = landscape ? CGSize(width: a4.height, height: a4.width) : a4
            if let doc = renderPage(size: size, options: options, draw: { rect in
                image.draw(in: fit(image.size, in: rect.insetBy(dx: 18, dy: 18)))
            }), let page = doc.page(at: 0) {
                sources.append(doc)
                result.insert(page, at: result.pageCount)
            }
        }
        guard result.pageCount > 0 else { return nil }
        defer { sources.removeAll() }
        let password = options.password.trimmingCharacters(in: .whitespaces)
        if password.isEmpty { return result.dataRepresentation() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let ok = result.write(to: url, withOptions: [.userPasswordOption: password, .ownerPasswordOption: password])
        return ok ? try? Data(contentsOf: url) : nil
    }

    /// Writes the PDF as a file named after the document(s).
    static func file(_ pages: [ExportPage], options: ExportOptions) -> URL? {
        guard let data = pdf(pages, options: options) else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FamiloqExport", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(options.name + ".pdf")
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }

    static func needsRaster(_ page: ExportPage, options: ExportOptions) -> Bool {
        options.smaller || options.blackAndWhite || options.stamp || !(options.redactions[page.id] ?? []).isEmpty
    }

    /// Turned, blacked out, grey and compressed as chosen - always a JPEG
    /// underneath, so the PDF stays small.
    static func processedImage(_ page: ExportPage, options: ExportOptions) -> UIImage? {
        guard var image = PageImage.image(format: page.format, data: page.data, quarterTurns: page.quarterTurns,
                                          width: options.smaller ? 1240 : 1654) else { return nil }
        let boxes = options.redactions[page.id] ?? []
        if !boxes.isEmpty {
            let size = image.size
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            let source = image
            image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                source.draw(at: .zero)
                UIColor.black.setFill()
                for box in boxes {
                    UIRectFill(CGRect(x: box.minX * size.width, y: box.minY * size.height,
                                      width: box.width * size.width, height: box.height * size.height))
                }
            }
        }
        if options.blackAndWhite, let grey = greyscale(image) { image = grey }
        let maxSide: CGFloat = options.smaller ? 1400 : 2200
        guard let jpeg = DocumentService.storageJPEGNonisolated(image, maxSide: maxSide, quality: options.smaller ? 0.5 : 0.8) else { return image }
        return UIImage(data: jpeg)
    }

    static func greyscale(_ image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        let filter = CIFilter.colorControls()
        filter.inputImage = input
        filter.saturation = 0
        filter.contrast = 1.15
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg, scale: image.scale, orientation: .up)
    }

    static func fit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    /// Front on the top half, back on the bottom half (like a copy shop).
    static func drawPair(_ images: [UIImage], in rect: CGRect) {
        let half = rect.height / 2
        for (index, image) in images.prefix(2).enumerated() {
            let box = CGRect(x: rect.minX, y: rect.minY + CGFloat(index) * half, width: rect.width, height: half)
                .insetBy(dx: 60, dy: 40)
            // Cards stay about 1.5 times their real size.
            let capped = CGRect(x: box.minX, y: box.minY, width: min(box.width, 380), height: box.height)
            let target = fit(image.size, in: capped)
            image.draw(in: target.offsetBy(dx: box.midX - target.midX, dy: 0))
        }
    }

    /// One page drawn with UIKit, the copy stamp on top.
    static func renderPage(size: CGSize, options: ExportOptions, draw: (CGRect) -> Void) -> PDFDocument? {
        let rect = CGRect(origin: .zero, size: size)
        let data = UIGraphicsPDFRenderer(bounds: rect).pdfData { ctx in
            ctx.beginPage()
            UIColor.white.setFill()
            UIRectFill(rect)
            draw(rect)
            if options.stamp {
                drawStamp(CopyStamp.text(language: options.stampLanguage, purpose: options.stampPurpose,
                                         date: Date(), calendar: FamiloqCalendar.make()),
                          in: rect, context: ctx.cgContext)
            }
        }
        return PDFDocument(data: data)
    }

    static func drawStamp(_ text: String, in rect: CGRect, context: CGContext) {
        let fontSize = max(14, min(rect.width, rect.height) / 22)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: UIColor.systemRed.withAlphaComponent(0.45)
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: -.pi / 6)
        for offset in [-1.0, 0.0, 1.0] {
            let y = CGFloat(offset) * rect.height / 3.2 - textSize.height / 2
            string.draw(at: CGPoint(x: -textSize.width / 2, y: y))
        }
        context.restoreGState()
    }
}

extension DocumentService {
    /// Same as `storageJPEG`, usable off the main actor.
    nonisolated static func storageJPEGNonisolated(_ image: UIImage, maxSide: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
