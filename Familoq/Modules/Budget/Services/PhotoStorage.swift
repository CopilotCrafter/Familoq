import Foundation
import SwiftData
import UIKit
import FamiloqCore

/// Receipt photos: how much space they take, making them smaller, removing
/// old ones and archiving them. The receipt data itself always stays.
@MainActor
enum PhotoStorage {
    enum Retention: String, CaseIterable, Identifiable {
        case forever, twoYears, oneYear, sixMonths

        var id: String { rawValue }

        var title: String {
            switch self {
            case .forever: return "Forever"
            case .twoYears: return "2 years"
            case .oneYear: return "1 year"
            case .sixMonths: return "6 months"
            }
        }

        var months: Int? {
            switch self {
            case .forever: return nil
            case .twoYears: return 24
            case .oneYear: return 12
            case .sixMonths: return 6
            }
        }

        /// Photos of receipts before this date are removed (nil = never).
        func cutoff(now: Date = Date(), calendar: Calendar = FamiloqCalendar.make()) -> Date? {
            months.flatMap { calendar.date(byAdding: .month, value: -$0, to: calendar.startOfDay(for: now)) }
        }
    }

    enum Kind: String { case receipt, expense }

    struct Photo: Identifiable {
        let kind: Kind
        let id: UUID
        let date: Date
        let merchant: String
        let total: String
        let bytes: Int
        let keep: Bool
    }

    // MARK: Setting (on the owner's iPhone, per family)

    private static func key(_ familyID: UUID) -> String { "photos.retention.\(familyID.uuidString)" }

    static func retention(familyID: UUID) -> Retention {
        UserDefaults.standard.string(forKey: key(familyID)).flatMap(Retention.init(rawValue:)) ?? .forever
    }

    static func setRetention(_ value: Retention, familyID: UUID) {
        UserDefaults.standard.set(value.rawValue, forKey: key(familyID))
    }

    // MARK: Inventory

    /// Every photo of a family, measured (sizes are cached on the record).
    static func photos(familyID: UUID, context: ModelContext) -> [Photo] {
        let fid = familyID
        var result: [Photo] = []
        var measured = false
        let receipts = (try? context.fetch(FetchDescriptor<ReceiptRecord>(predicate: #Predicate { $0.familyID == fid && $0.photoBytes >= 0 }))) ?? []
        for receipt in receipts {
            if receipt.photoBytes == 0 {
                receipt.photoBytes = receipt.imageData?.count ?? -1
                measured = true
            }
            guard receipt.photoBytes > 0 else { continue }
            result.append(Photo(kind: .receipt, id: receipt.id, date: receipt.date, merchant: receipt.merchant,
                                total: receipt.total.currency(receipt.currencyCode), bytes: receipt.photoBytes, keep: receipt.keepPhoto))
        }
        let expenses = (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.familyID == fid && $0.photoBytes >= 0 }))) ?? []
        for expense in expenses {
            if expense.photoBytes == 0 {
                expense.photoBytes = expense.receiptImageData?.count ?? -1
                measured = true
            }
            guard expense.photoBytes > 0 else { continue }
            result.append(Photo(kind: .expense, id: expense.id, date: expense.date, merchant: expense.merchant,
                                total: expense.amount.currency(expense.currencyCode), bytes: expense.photoBytes, keep: expense.keepPhoto))
        }
        // Sizes are local only (not synced) - saving does not upload anything.
        if measured { try? context.save() }
        return result.sorted { $0.date > $1.date }
    }

    static func candidates(_ photos: [Photo], retention: Retention, now: Date = Date()) -> [Photo] {
        guard let cutoff = retention.cutoff(now: now) else { return [] }
        return photos.filter { !$0.keep && $0.date < cutoff }
    }

    // MARK: Changes (synced to every iPhone and iCloud)

    private static func setPhoto(_ data: Data?, kind: Kind, id: UUID, context: ModelContext) {
        let target = id
        switch kind {
        case .receipt:
            var d = FetchDescriptor<ReceiptRecord>(predicate: #Predicate { $0.id == target })
            d.fetchLimit = 1
            if let receipt = try? context.fetch(d).first {
                receipt.syncImage = data
                receipt.photoRevision += 1
            }
        case .expense:
            var d = FetchDescriptor<Expense>(predicate: #Predicate { $0.id == target })
            d.fetchLimit = 1
            if let expense = try? context.fetch(d).first {
                expense.syncImage = data
                expense.photoRevision += 1
                expense.updatedAt = Date()
            }
        }
    }

    /// Removes the photos (the receipts and expenses stay). Returns bytes freed.
    @discardableResult
    static func remove(_ photos: [Photo], context: ModelContext) -> Int {
        for photo in photos where !photo.keep {
            setPhoto(nil, kind: photo.kind, id: photo.id, context: context)
        }
        try? context.save()
        return photos.filter { !$0.keep }.map(\.bytes).reduce(0, +)
    }

    /// Runs the family's "Keep receipt photos" setting (owner's iPhone).
    @discardableResult
    static func applyRetention(familyID: UUID, context: ModelContext) -> Int {
        let retention = retention(familyID: familyID)
        guard retention != .forever else { return 0 }
        let old = candidates(photos(familyID: familyID, context: context), retention: retention)
        guard !old.isEmpty else { return 0 }
        return remove(old, context: context)
    }

    private static func loadData(_ photo: Photo, context: ModelContext) -> Data? {
        let target = photo.id
        switch photo.kind {
        case .receipt:
            var d = FetchDescriptor<ReceiptRecord>(predicate: #Predicate { $0.id == target })
            d.fetchLimit = 1
            return (try? context.fetch(d).first)?.imageData
        case .expense:
            var d = FetchDescriptor<Expense>(predicate: #Predicate { $0.id == target })
            d.fetchLimit = 1
            return (try? context.fetch(d).first)?.receiptImageData
        }
    }

    /// Re-saves larger photos as small grayscale JPEGs. Returns bytes saved.
    static func makeSmaller(_ photos: [Photo], context: ModelContext, progress: (Int) -> Void) async -> Int {
        var saved = 0
        for (index, photo) in photos.enumerated() where photo.bytes > 220_000 {
            guard let data = loadData(photo, context: context) else { continue }
            let smaller: Data? = await Task.detached(priority: .utility) {
                guard let image = UIImage(data: data) else { return nil }
                return ReceiptOCRService.storageJPEG(from: image)
            }.value
            if let smaller, smaller.count < data.count * 9 / 10 {
                setPhoto(smaller, kind: photo.kind, id: photo.id, context: context)
                saved += data.count - smaller.count
            }
            progress(index + 1)
            if index % 10 == 9 { try? context.save() }
        }
        try? context.save()
        return saved
    }

    // MARK: Archive (PDF / ZIP)

    enum ArchiveFormat: String, CaseIterable, Identifiable {
        case pdf, zip
        var id: String { rawValue }
        var title: String { self == .pdf ? "PDF (one page per receipt)" : "ZIP (photos)" }
    }

    static func fileName(_ photo: Photo, index: Int) -> String {
        let day = photo.date.formatted(.iso8601.year().month().day())
        let shop = BackupService.safeFileName(photo.merchant)
        return "\(day) \(shop) \(index + 1).jpg"
    }

    /// Writes the photos of one year to a temporary file for Save to Files / share.
    static func archive(_ photos: [Photo], year: Int, familyName: String, format: ArchiveFormat, context: ModelContext) throws -> URL {
        let base = "Familoq-Receipts-\(BackupService.safeFileName(familyName))-\(year)"
        let temp = FileManager.default.temporaryDirectory
        // Read the photos first (the PDF/ZIP writers run outside the main actor's view of the data).
        let items: [(photo: Photo, data: Data)] = photos.sorted { $0.date < $1.date }.compactMap { photo in
            loadData(photo, context: context).map { (photo, $0) }
        }
        switch format {
        case .pdf:
            let url = temp.appendingPathComponent(base + ".pdf")
            let page = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
            let renderer = UIGraphicsPDFRenderer(bounds: page)
            try renderer.writePDF(to: url) { pdf in
                for item in items {
                    let photo = item.photo
                    autoreleasepool {
                        guard let image = UIImage(data: item.data) else { return }
                        pdf.beginPage()
                        let title = "\(photo.merchant) · \(photo.date.formatted(date: .abbreviated, time: .shortened)) · \(photo.total)"
                        (title as NSString).draw(at: CGPoint(x: 36, y: 30), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 13)])
                        let box = CGRect(x: 36, y: 56, width: page.width - 72, height: page.height - 92)
                        let scale = min(box.width / image.size.width, box.height / image.size.height)
                        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                        image.draw(in: CGRect(x: box.midX - size.width / 2, y: box.minY, width: size.width, height: size.height))
                    }
                }
            }
            return url
        case .zip:
            let folder = temp.appendingPathComponent(base, isDirectory: true)
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (index, item) in items.enumerated() {
                try item.data.write(to: folder.appendingPathComponent(fileName(item.photo, index: index)))
            }
            // The system zips a folder when it is read "for uploading".
            let zipURL = temp.appendingPathComponent(base + ".zip")
            try? FileManager.default.removeItem(at: zipURL)
            var coordinatorError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &coordinatorError) { zipped in
                do { try FileManager.default.copyItem(at: zipped, to: zipURL) } catch { copyError = error }
            }
            try? FileManager.default.removeItem(at: folder)
            if let error = coordinatorError ?? copyError { throw error }
            return zipURL
        }
    }

    // MARK: Sizes on this iPhone

    /// Everything Familoq stores on this iPhone (database, photos, caches).
    static func localBytes() -> Int {
        let manager = FileManager.default
        var total = 0
        let roots = [manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
                     manager.urls(for: .documentDirectory, in: .userDomainMask).first,
                     manager.urls(for: .cachesDirectory, in: .userDomainMask).first].compactMap { $0 }
        for root in roots {
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { continue }
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true { total += values?.totalFileAllocatedSize ?? 0 }
            }
        }
        return total
    }

    static func format(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
