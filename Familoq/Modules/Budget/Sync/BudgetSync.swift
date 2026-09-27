import Foundation
import SwiftData
import FamiloqCore

// Budget records shared with the family through iCloud.
// ExchangeRateCacheEntry is NOT synced (public data, cached per iPhone).

extension BudgetModule {
    static var syncHandlers: [SyncHandler] {
        [
            .of(ExpenseCategory.self,
                inFamily: { fid in #Predicate<ExpenseCategory> { $0.familyID == fid } },
                withID: { id in #Predicate<ExpenseCategory> { $0.id == id } },
                make: { id, fid in ExpenseCategory(id: id, familyID: fid, name: "", icon: "tag.fill", colorHex: "#9E9E9E", sortOrder: 0) }),
            .of(ExpenseSubcategory.self,
                inFamily: { fid in #Predicate<ExpenseSubcategory> { $0.familyID == fid } },
                withID: { id in #Predicate<ExpenseSubcategory> { $0.id == id } },
                make: { id, fid in ExpenseSubcategory(id: id, familyID: fid, categoryID: UUID(), name: "", sortOrder: 0) }),
            .of(MerchantRuleRecord.self,
                inFamily: { fid in #Predicate<MerchantRuleRecord> { $0.familyID == fid } },
                withID: { id in #Predicate<MerchantRuleRecord> { $0.id == id } },
                make: { id, fid in
                    let rule = MerchantRuleRecord(familyID: fid, pattern: "", displayMerchant: "", categoryID: UUID(), subcategoryID: nil, isUserDefined: false)
                    rule.id = id
                    return rule
                }),
            .of(Budget.self,
                inFamily: { fid in #Predicate<Budget> { $0.familyID == fid } },
                withID: { id in #Predicate<Budget> { $0.id == id } },
                make: { id, fid in
                    let budget = Budget(familyID: fid, period: .monthly, scope: .overall, amount: 0, currencyCode: "EUR")
                    budget.id = id
                    return budget
                }),
            .of(ReceiptRecord.self, hasImage: true,
                inFamily: { fid in #Predicate<ReceiptRecord> { $0.familyID == fid } },
                withID: { id in #Predicate<ReceiptRecord> { $0.id == id } },
                make: { id, fid in
                    let receipt = ReceiptRecord(familyID: fid, merchant: "", date: Date(), total: 0, currencyCode: "EUR")
                    receipt.id = id
                    return receipt
                }),
            .of(ReceiptItemRecord.self,
                inFamily: { fid in #Predicate<ReceiptItemRecord> { $0.familyID == fid } },
                withID: { id in #Predicate<ReceiptItemRecord> { $0.id == id } },
                make: { id, fid in
                    let item = ReceiptItemRecord(familyID: fid, receiptID: UUID(), name: "", amount: 0, categoryID: nil, subcategoryID: nil, sortOrder: 0)
                    item.id = id
                    return item
                }),
            .of(Expense.self, hasImage: true,
                inFamily: { fid in #Predicate<Expense> { $0.familyID == fid } },
                withID: { id in #Predicate<Expense> { $0.id == id } },
                make: { id, fid in
                    let expense = Expense(familyID: fid, amount: 0, currencyCode: "EUR", baseCurrencyCode: "EUR", merchant: "", date: Date())
                    expense.id = id
                    return expense
                })
        ]
    }
}

extension ExpenseCategory: SyncableRecord {
    static var syncKind: SyncKind { .category }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("systemKey", systemKey)
        p.set("name", name)
        p.set("icon", icon)
        p.set("colorHex", colorHex)
        p.set("sortOrder", sortOrder)
        p.set("isArchived", isArchived)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        systemKey = p.optionalString("systemKey")
        name = p.string("name")
        icon = p.string("icon", default: "tag.fill")
        colorHex = p.string("colorHex", default: "#9E9E9E")
        sortOrder = p.int("sortOrder")
        isArchived = p.bool("isArchived")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
    }
}

extension ExpenseSubcategory: SyncableRecord {
    static var syncKind: SyncKind { .subcategory }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("categoryID", categoryID)
        p.set("systemKey", systemKey)
        p.set("name", name)
        p.set("sortOrder", sortOrder)
        p.set("isArchived", isArchived)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        categoryID = p.uuid("categoryID") ?? categoryID
        systemKey = p.optionalString("systemKey")
        name = p.string("name")
        sortOrder = p.int("sortOrder")
        isArchived = p.bool("isArchived")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
    }
}

extension MerchantRuleRecord: SyncableRecord {
    static var syncKind: SyncKind { .rule }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("pattern", pattern)
        p.set("displayMerchant", displayMerchant)
        p.set("categoryID", categoryID)
        p.set("subcategoryID", subcategoryID)
        p.set("isUserDefined", isUserDefined)
        p.set("createdAt", createdAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        pattern = p.string("pattern")
        displayMerchant = p.string("displayMerchant")
        categoryID = p.uuid("categoryID") ?? categoryID
        subcategoryID = p.uuid("subcategoryID")
        isUserDefined = p.bool("isUserDefined")
        createdAt = p.date("createdAt", default: createdAt)
    }
}

extension Budget: SyncableRecord {
    static var syncKind: SyncKind { .budget }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("periodRaw", periodRaw)
        p.set("scopeRaw", scopeRaw)
        p.set("categoryID", categoryID)
        p.set("subcategoryID", subcategoryID)
        p.set("amountValue", amountValue)
        p.set("currencyCode", currencyCode)
        p.set("isActive", isActive)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        periodRaw = p.string("periodRaw", default: "monthly")
        scopeRaw = p.string("scopeRaw", default: "overall")
        categoryID = p.uuid("categoryID")
        subcategoryID = p.uuid("subcategoryID")
        amountValue = p.int64("amountValue")
        currencyCode = p.string("currencyCode", default: "EUR")
        isActive = p.bool("isActive", default: true)
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
    }
}

extension ReceiptRecord: SyncableRecord {
    static var syncKind: SyncKind { .receipt }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("merchant", merchant)
        p.set("date", date)
        p.set("totalValue", totalValue)
        p.set("currencyCode", currencyCode)
        p.set("rawText", rawText)
        p.set("vatSummary", vatSummary)
        p.set("createdAt", createdAt)
        p.set("createdByMemberID", createdByMemberID)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        merchant = p.string("merchant")
        date = p.date("date", default: date)
        totalValue = p.int64("totalValue")
        currencyCode = p.string("currencyCode", default: "EUR")
        rawText = p.string("rawText")
        vatSummary = p.string("vatSummary")
        createdAt = p.date("createdAt", default: createdAt)
        createdByMemberID = p.uuid("createdByMemberID")
    }

    var syncImage: Data? {
        get { imageData }
        set { imageData = newValue }
    }
}

extension ReceiptItemRecord: SyncableRecord {
    static var syncKind: SyncKind { .receiptItem }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("receiptID", receiptID)
        p.set("name", name)
        p.set("amountValue", amountValue)
        p.set("quantityText", quantityText)
        p.set("categoryID", categoryID)
        p.set("subcategoryID", subcategoryID)
        p.set("sortOrder", sortOrder)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        receiptID = p.uuid("receiptID") ?? receiptID
        name = p.string("name")
        amountValue = p.int64("amountValue")
        quantityText = p.optionalString("quantityText")
        categoryID = p.uuid("categoryID")
        subcategoryID = p.uuid("subcategoryID")
        sortOrder = p.int("sortOrder")
    }
}

extension Expense: SyncableRecord {
    static var syncKind: SyncKind { .expense }
    var syncID: UUID { id }

    /// The photo itself is not part of the fingerprint (reading every photo
    /// on each check would be slow); it is sent whenever the expense is.
    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("amountValue", amountValue)
        p.set("currencyCode", currencyCode)
        p.set("baseAmountValue", baseAmountValue)
        p.set("baseCurrencyCode", baseCurrencyCode)
        p.set("exchangeRateText", exchangeRateText)
        p.set("exchangeRateDateKey", exchangeRateDateKey)
        p.set("exchangeRateSource", exchangeRateSource)
        p.set("conversionStatusRaw", conversionStatusRaw)
        p.set("merchant", merchant)
        p.set("date", date)
        p.set("categoryID", categoryID)
        p.set("subcategoryID", subcategoryID)
        p.set("memberID", memberID)
        p.set("createdByMemberID", createdByMemberID)
        p.set("paymentMethodRaw", paymentMethodRaw)
        p.set("note", note)
        p.set("entryMethodRaw", entryMethodRaw)
        p.set("receiptID", receiptID)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        amountValue = p.int64("amountValue")
        currencyCode = p.string("currencyCode", default: "EUR")
        baseAmountValue = p.optionalInt64("baseAmountValue")
        baseCurrencyCode = p.string("baseCurrencyCode", default: "EUR")
        exchangeRateText = p.optionalString("exchangeRateText")
        exchangeRateDateKey = p.optionalString("exchangeRateDateKey")
        exchangeRateSource = p.optionalString("exchangeRateSource")
        conversionStatusRaw = p.string("conversionStatusRaw", default: "notNeeded")
        merchant = p.string("merchant")
        date = p.date("date", default: date)
        categoryID = p.uuid("categoryID")
        subcategoryID = p.uuid("subcategoryID")
        memberID = p.uuid("memberID")
        createdByMemberID = p.uuid("createdByMemberID")
        paymentMethodRaw = p.string("paymentMethodRaw", default: "debitCard")
        note = p.string("note")
        entryMethodRaw = p.string("entryMethodRaw", default: "manual")
        receiptID = p.uuid("receiptID")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
    }

    var syncImage: Data? {
        get { receiptImageData }
        set { receiptImageData = newValue }
    }
}
