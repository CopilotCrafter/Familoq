import Foundation
import SwiftData
import FamiloqCore

/// Full family backup (JSON) and restore. Uses the same record fields as the
/// iCloud sync, so every synced model is included automatically.
@MainActor
enum BackupService {
    static func makeBackup(family: Family, context: ModelContext, includePhotos: Bool) throws -> FamilyBackup {
        var records: [FamilyBackup.Record] = []
        for handler in SyncRegistry.handlers {
            for record in try handler.all(context, family.id) {
                let image = (includePhotos && handler.hasImage) ? record.syncImage?.base64EncodedString() : nil
                records.append(FamilyBackup.Record(kind: handler.kind.rawValue, id: record.syncID,
                                                   fields: record.syncPayload().values, image: image))
            }
        }
        return FamilyBackup(familyID: family.id, familyName: family.name, baseCurrency: family.baseCurrencyCode, records: records)
    }

    /// Writes the backup to a temporary file for the share sheet / Files.
    static func writeFile(_ backup: FamilyBackup) throws -> URL {
        let day = backup.exportedAt.formatted(.iso8601.year().month().day())
        let name = "Familoq-Backup-\(safeFileName(backup.familyName))-\(day).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try backup.encoded().write(to: url, options: .atomic)
        return url
    }

    struct RestoreSummary: Equatable {
        var added = 0
        var updated = 0
        var skipped = 0
    }

    /// Adds the backup's records to `family`; records that already exist in
    /// this family are updated. Records of OTHER families are never touched
    /// (family isolation), and the family's own name/currency stay as they are.
    static func restore(_ backup: FamilyBackup, into family: Family, context: ModelContext, currentUserRecordName: String) throws -> RestoreSummary {
        var summary = RestoreSummary()
        let ownNames = Set(try SyncRegistry.currentFingerprints(familyID: family.id, context: context).keys)
        // Parents first (categories before expenses), in registry order.
        let order = Dictionary(uniqueKeysWithValues: SyncRegistry.handlers.enumerated().map { ($0.element.kind.rawValue, $0.offset) })
        let sorted = backup.records.sorted { (order[$0.kind] ?? 99) < (order[$1.kind] ?? 99) }
        for record in sorted {
            guard let kind = SyncKind(rawValue: record.kind), kind != .family,
                  let handler = SyncRegistry.handler(for: kind) else {
                summary.skipped += 1
                continue
            }
            let payload = SyncPayload(values: record.fields)
            let object: any SyncableRecord
            if let existing = try handler.find(context, record.id) {
                guard ownNames.contains(kind.recordName(for: record.id)) else {
                    summary.skipped += 1 // belongs to another family on this iPhone
                    continue
                }
                object = existing
                summary.updated += 1
            } else {
                object = handler.make(context, record.id, family.id)
                summary.added += 1
            }
            object.applySyncPayload(payload)
            if handler.hasImage, let base64 = record.image {
                object.syncImage = Data(base64Encoded: base64)
            }
            if let member = object as? FamilyMember {
                member.isCurrentUser = !member.cloudUserRecordName.isEmpty && member.cloudUserRecordName == currentUserRecordName
            }
        }
        try context.save()
        return summary
    }

    static func safeFileName(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = text.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let result = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "Family" : result
    }
}

/// Expenses as CSV for Excel / Numbers.
@MainActor
enum CSVExport {
    static func expenses(_ expenses: [Expense], lookup: CategoryLookup, members: [FamilyMember], baseCurrency: String, locale: Locale = .current) -> Data {
        let csv = CSVWriter(locale: locale)
        let header = ["Date", "Time", "Merchant", "Category", "Subcategory", "Amount", "Currency",
                      "Amount (\(baseCurrency))", "Exchange rate", "Rate date", "Member", "Payment", "Note", "Entered as", "Receipt"]
        let dayFormat = Date.ISO8601FormatStyle().year().month().day()
        let rows: [[String]] = expenses.sorted { $0.date < $1.date }.map { e in
            let time = e.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            return [
                e.date.formatted(dayFormat),
                time,
                e.merchant,
                lookup.category(e.categoryID)?.name ?? "",
                lookup.subcategory(e.subcategoryID)?.name ?? "",
                csv.number(e.amount, places: CurrencyInfo.minorUnits(for: e.currencyCode)),
                e.currencyCode,
                csv.number(e.baseAmount, places: CurrencyInfo.minorUnits(for: baseCurrency)),
                e.exchangeRate.map { csv.number($0, places: 6) } ?? "",
                e.exchangeRateDateKey ?? "",
                members.first { $0.id == e.memberID }?.displayName ?? "",
                e.paymentMethod.displayName,
                e.note,
                e.entryMethod.displayName,
                e.receiptID == nil ? "" : "yes"
            ]
        }
        return csv.document(header: header, rows: rows)
    }

    static func writeFile(_ data: Data, familyName: String, label: String) throws -> URL {
        let name = "Familoq-\(BackupService.safeFileName(familyName))-\(BackupService.safeFileName(label)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
