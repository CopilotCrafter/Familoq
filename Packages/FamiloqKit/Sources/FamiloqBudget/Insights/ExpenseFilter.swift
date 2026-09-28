import Foundation
import FamiloqCore

/// The facts of one expense a filter looks at (keeps the filter independent
/// of the database model, so it is tested on Linux).
public struct ExpenseFacts: Sendable {
    public var merchant: String
    public var note: String
    /// "Groceries › Fruits"
    public var categoryPath: String
    public var categoryID: UUID?
    public var memberID: UUID?
    public var date: Date
    public var amount: Decimal
    public var currencyCode: String
    /// Amount in the family's base currency (nil while waiting for a rate).
    public var baseAmount: Decimal?
    /// "manual", "quick", "receipt", "scheduled"
    public var entryMethod: String

    public init(merchant: String, note: String, categoryPath: String, categoryID: UUID?, memberID: UUID?, date: Date,
                amount: Decimal, currencyCode: String, baseAmount: Decimal?, entryMethod: String) {
        self.merchant = merchant
        self.note = note
        self.categoryPath = categoryPath
        self.categoryID = categoryID
        self.memberID = memberID
        self.date = date
        self.amount = amount
        self.currencyCode = currencyCode
        self.baseAmount = baseAmount
        self.entryMethod = entryMethod
    }
}

/// Search & filters for the expense list. Empty sets / nil values = no filter.
public struct ExpenseFilter: Equatable, Sendable {
    public var text: String = ""
    public var from: Date?
    /// Exclusive.
    public var to: Date?
    public var categoryIDs: Set<UUID> = []
    public var memberIDs: Set<UUID> = []
    /// Compared with the base-currency amount (original amount if not converted yet).
    public var minAmount: Decimal?
    public var maxAmount: Decimal?
    public var entryMethods: Set<String> = []
    public var onlyForeignCurrency = false

    public init() {}

    public var isActive: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty || from != nil || to != nil || !categoryIDs.isEmpty
            || !memberIDs.isEmpty || minAmount != nil || maxAmount != nil || !entryMethods.isEmpty || onlyForeignCurrency
    }

    /// Number of active filters besides the search text (for a badge).
    public var activeFilterCount: Int {
        var n = 0
        if from != nil || to != nil { n += 1 }
        if !categoryIDs.isEmpty { n += 1 }
        if !memberIDs.isEmpty { n += 1 }
        if minAmount != nil || maxAmount != nil { n += 1 }
        if !entryMethods.isEmpty { n += 1 }
        if onlyForeignCurrency { n += 1 }
        return n
    }

    public func matches(_ e: ExpenseFacts, baseCurrency: String) -> Bool {
        if let from, e.date < from { return false }
        if let to, e.date >= to { return false }
        if !categoryIDs.isEmpty {
            guard let id = e.categoryID, categoryIDs.contains(id) else { return false }
        }
        if !memberIDs.isEmpty {
            guard let id = e.memberID, memberIDs.contains(id) else { return false }
        }
        let value = e.baseAmount ?? e.amount
        if let minAmount, value < minAmount { return false }
        if let maxAmount, value > maxAmount { return false }
        if !entryMethods.isEmpty && !entryMethods.contains(e.entryMethod) { return false }
        if onlyForeignCurrency && CurrencyInfo.normalize(e.currencyCode) == CurrencyInfo.normalize(baseCurrency) { return false }

        let query = TextNormalizer.normalize(text)
        guard !query.isEmpty else { return true }
        let haystack = TextNormalizer.normalize("\(e.merchant) \(e.note) \(e.categoryPath)")
        // Every word must appear somewhere ("rewe milk").
        let words = query.split(separator: " ")
        if words.allSatisfy({ haystack.contains($0) }) { return true }
        // Amount search: "12,50" or "12.50" matches 12.50.
        if let wanted = DecimalParser.parse(text), wanted == e.amount || wanted == e.baseAmount { return true }
        return false
    }
}
