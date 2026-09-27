import Foundation
import SwiftData
import FamiloqCore
import FamiloqBudget

/// Editable receipt shown on the confirmation screen. Nothing is saved until
/// the user taps Save (spec: never auto-save uncertain OCR data).
struct ReceiptDraft {
    var merchant: String
    var date: Date
    var currencyCode: String
    var totalText: String
    var categorizeWholeReceipt: Bool
    var wholeCategoryID: UUID?
    var wholeSubcategoryID: UUID?
    var items: [ReceiptDraftItem]
    var imageData: Data?
    var rawText: String
    var vatSummary: String
    var warnings: [String]

    var total: Decimal? { DecimalParser.parse(totalText) }

    var includedItemsSum: Decimal {
        items.filter(\.included).compactMap(\.amount).reduce(0, +)
    }

    /// total - sum of items (positive = items missing, negative = items too high)
    var difference: Decimal? {
        guard let total else { return nil }
        return total - includedItemsSum
    }
}

struct ReceiptDraftItem: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var amountText: String
    var categoryID: UUID?
    var subcategoryID: UUID?
    var included = true
    /// How sure the classifier was (0 = not recognised).
    var confidence: Double = 0

    var amount: Decimal? { DecimalParser.parse(amountText) }
}

enum ReceiptSaveError: LocalizedError {
    case missingTotal
    case missingCategory
    case noItems

    var errorDescription: String? {
        switch self {
        case .missingTotal: return "Enter the receipt total."
        case .missingCategory: return "Choose a category."
        case .noItems: return "Include at least one item with an amount, or categorize the entire receipt."
        }
    }
}

@MainActor
enum ReceiptDrafting {
    /// Builds the editable draft from OCR results, with category suggestions.
    static func draft(from parsed: ParsedReceipt, family: Family, lookup: CategoryLookup, rules: [MerchantRuleRecord], imageData: Data?, now: Date = Date()) -> ReceiptDraft {
        let groceriesID = lookup.categories.first { $0.systemKey == "groceries" }?.id
        let groceriesOtherID = lookup.subcategories.first { $0.systemKey == "groceries.other" }?.id
        func subID(_ key: String?) -> UUID? {
            guard let key else { return groceriesOtherID }
            return lookup.subcategories.first { $0.systemKey == key }?.id ?? groceriesOtherID
        }

        let merchant = parsed.merchant ?? ""
        let suggestion = CategorizationService.suggestion(for: merchant, rules: rules)
        let isGroceryMerchant = suggestion == nil || suggestion?.categoryID == groceriesID

        let items = parsed.items.map { item in
            ReceiptDraftItem(
                name: item.name,
                amountText: plain(item.amount),
                categoryID: groceriesID,
                subcategoryID: subID(item.suggestedSubcategoryKey),
                confidence: item.classificationConfidence
            )
        }

        let total = parsed.total ?? (parsed.items.isEmpty ? nil : parsed.itemsSum)
        let vat = parsed.vat.map { line in
            "\(plain(line.ratePercent)) %" + (line.taxAmount.map { ": \(plain($0))" } ?? "")
        }.joined(separator: ", ")

        return ReceiptDraft(
            merchant: merchant,
            date: parsed.date ?? now,
            currencyCode: parsed.currencyCode ?? family.baseCurrencyCode,
            totalText: total.map(plain) ?? "",
            // Item-level only makes sense for grocery-type receipts with items.
            categorizeWholeReceipt: items.isEmpty || !isGroceryMerchant,
            wholeCategoryID: suggestion?.categoryID ?? groceriesID,
            wholeSubcategoryID: suggestion?.subcategoryID,
            items: items,
            imageData: imageData,
            rawText: parsed.rawLines.joined(separator: "\n"),
            vatSummary: vat,
            warnings: parsed.warnings
        )
    }

    private static func plain(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}

@MainActor
enum ReceiptSaver {
    /// Saves the confirmed receipt: one ReceiptRecord, its items, and one
    /// expense per (category, subcategory) group - e.g. "Lidl · Fruits €4.40".
    /// Any difference between items and total is added to the largest group,
    /// so the expenses always add up to what was actually paid.
    @discardableResult
    static func save(_ draft: ReceiptDraft, family: Family, member: FamilyMember?, lookup: CategoryLookup, context: ModelContext) throws -> [Expense] {
        guard let total = draft.total, total > 0 else { throw ReceiptSaveError.missingTotal }
        let merchant = draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Receipt" : draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let currency = CurrencyInfo.normalize(draft.currencyCode)
        let repository = FamilyRepository(context: context, familyID: family.id)

        let receipt = ReceiptRecord(familyID: family.id, merchant: merchant, date: draft.date, total: total, currencyCode: currency)
        receipt.imageData = draft.imageData
        receipt.rawText = draft.rawText
        receipt.vatSummary = draft.vatSummary
        receipt.createdByMemberID = member?.id

        struct Group {
            var categoryID: UUID
            var subcategoryID: UUID?
            var amount: Decimal
            var names: [String]
        }
        var groups: [Group] = []
        var itemRecords: [ReceiptItemRecord] = []

        if draft.categorizeWholeReceipt {
            guard let categoryID = draft.wholeCategoryID else { throw ReceiptSaveError.missingCategory }
            groups.append(Group(categoryID: categoryID, subcategoryID: draft.wholeSubcategoryID, amount: total, names: []))
            for (index, item) in draft.items.enumerated() where item.included {
                guard let amount = item.amount else { continue }
                itemRecords.append(ReceiptItemRecord(familyID: family.id, receiptID: receipt.id, name: item.name, amount: amount,
                                                     categoryID: categoryID, subcategoryID: draft.wholeSubcategoryID, sortOrder: index))
            }
        } else {
            let included = draft.items.enumerated().filter { $0.element.included && ($0.element.amount ?? 0) != 0 }
            guard !included.isEmpty else { throw ReceiptSaveError.noItems }
            for (index, item) in included {
                guard let amount = item.amount, let categoryID = item.categoryID else { throw ReceiptSaveError.missingCategory }
                itemRecords.append(ReceiptItemRecord(familyID: family.id, receiptID: receipt.id, name: item.name, amount: amount,
                                                     categoryID: categoryID, subcategoryID: item.subcategoryID, sortOrder: index))
                if let g = groups.firstIndex(where: { $0.categoryID == categoryID && $0.subcategoryID == item.subcategoryID }) {
                    groups[g].amount += amount
                    groups[g].names.append(item.name)
                } else {
                    groups.append(Group(categoryID: categoryID, subcategoryID: item.subcategoryID, amount: amount, names: [item.name]))
                }
            }
            let difference = total - groups.reduce(0) { $0 + $1.amount }
            if difference != 0, let largest = groups.indices.max(by: { groups[$0].amount < groups[$1].amount }),
               groups[largest].amount + difference > 0 {
                groups[largest].amount += difference
                itemRecords.append(ReceiptItemRecord(familyID: family.id, receiptID: receipt.id, name: "Difference to receipt total", amount: difference,
                                                     categoryID: groups[largest].categoryID, subcategoryID: groups[largest].subcategoryID,
                                                     sortOrder: itemRecords.count))
            }
        }

        context.insert(receipt)
        itemRecords.forEach { context.insert($0) }

        var expenses: [Expense] = []
        for group in groups where group.amount > 0 {
            let expense = Expense(familyID: family.id, amount: group.amount, currencyCode: currency,
                                  baseCurrencyCode: family.baseCurrencyCode, merchant: merchant, date: draft.date)
            expense.categoryID = group.categoryID
            expense.subcategoryID = group.subcategoryID
            expense.memberID = member?.id
            expense.createdByMemberID = member?.id
            expense.entryMethod = .receipt
            expense.receiptID = receipt.id
            expense.note = summary(of: group.names)
            expense.resetConversion()
            try repository.insert(expense)
            expenses.append(expense)
        }
        try context.save()
        return expenses
    }

    private static func summary(of names: [String]) -> String {
        guard !names.isEmpty else { return "" }
        let shown = names.prefix(3).joined(separator: ", ")
        return names.count > 3 ? "\(shown) +\(names.count - 3) more" : shown
    }
}
