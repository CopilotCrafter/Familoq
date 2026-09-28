import Foundation
import SwiftData
import FamiloqCore

/// A scanned receipt: image, recognised text and the confirmed header data.
/// Expenses created from it reference it via `Expense.receiptID`.
@Model
final class ReceiptRecord {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var merchant: String = ""
    /// Purchase date and time printed on the receipt (confirmed by the user).
    var date: Date = Date()
    var totalValue: Int64 = 0
    var currencyCode: String = "EUR"
    /// Recognised text, kept for later corrections and search.
    var rawText: String = ""
    @Attribute(.externalStorage) var imageData: Data? = nil
    var vatSummary: String = ""
    var createdAt: Date = Date()
    var createdByMemberID: UUID? = nil
    /// "Keep this photo" (warranty/tax): never removed by the photo cleanup.
    var keepPhoto: Bool = false
    /// Raised when the photo is replaced, made smaller or removed, so the
    /// change is sent to iCloud (the photo itself is not fingerprinted).
    var photoRevision: Int = 0
    /// Size of the photo in bytes (this iPhone only): 0 = not measured yet, -1 = no photo.
    var photoBytes: Int = 0

    init(familyID: UUID, merchant: String, date: Date, total: Decimal, currencyCode: String) {
        self.familyID = familyID
        self.merchant = merchant
        self.date = date
        self.totalValue = FixedPoint.storage(from: total)
        self.currencyCode = currencyCode
    }

    var total: Decimal {
        get { FixedPoint.decimal(from: totalValue) }
        set { totalValue = FixedPoint.storage(from: newValue) }
    }
}

/// One confirmed line of a receipt with its category (item-level grocery tracking).
@Model
final class ReceiptItemRecord {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var receiptID: UUID = UUID()
    var name: String = ""
    var amountValue: Int64 = 0
    var quantityText: String? = nil
    var categoryID: UUID? = nil
    var subcategoryID: UUID? = nil
    var sortOrder: Int = 0

    init(familyID: UUID, receiptID: UUID, name: String, amount: Decimal, categoryID: UUID?, subcategoryID: UUID?, sortOrder: Int) {
        self.familyID = familyID
        self.receiptID = receiptID
        self.name = name
        self.amountValue = FixedPoint.storage(from: amount)
        self.categoryID = categoryID
        self.subcategoryID = subcategoryID
        self.sortOrder = sortOrder
    }

    var amount: Decimal {
        get { FixedPoint.decimal(from: amountValue) }
        set { amountValue = FixedPoint.storage(from: newValue) }
    }
}
