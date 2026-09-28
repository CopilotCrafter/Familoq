import Foundation
import SwiftData
import FamiloqCore
import FamiloqBudget

/// Editable receipt shown on the confirmation screen. Nothing is saved until
/// the user taps Save (spec: never auto-save uncertain OCR data).
struct ReceiptDraft: Equatable {
    var merchant: String
    var date: Date
    var currencyCode: String
    /// False until the currency is certain or the user chose it: receipts
    /// from other countries often show only "$", "kr", "¥" - or nothing.
    var currencyConfirmed: Bool = true
    /// Currencies offered first when asking (best guess first).
    var currencyCandidates: [String] = []
    var totalText: String
    var categorizeWholeReceipt: Bool
    var wholeCategoryID: UUID?
    var wholeSubcategoryID: UUID?
    var items: [ReceiptDraftItem]
    var imageData: Data?
    var rawText: String
    var vatSummary: String
    var warnings: [String]
    /// Items the family filed themselves before (ItemRuleKey -> category).
    var learned: [String: ItemTarget] = [:]

    var total: Decimal? { DecimalParser.parse(totalText) }

    /// Names of the fields that differ (diagnostics for the check screen).
    static func changedFields(from a: ReceiptDraft, to b: ReceiptDraft) -> String {
        var names: [String] = []
        if a.merchant != b.merchant { names.append("merchant") }
        if a.date != b.date { names.append("date \(a.date.timeIntervalSince1970)->\(b.date.timeIntervalSince1970)") }
        if a.currencyCode != b.currencyCode { names.append("currency") }
        if a.currencyConfirmed != b.currencyConfirmed { names.append("currencyConfirmed") }
        if a.totalText != b.totalText { names.append("total '\(a.totalText)'->'\(b.totalText)'") }
        if a.categorizeWholeReceipt != b.categorizeWholeReceipt { names.append("wholeReceipt") }
        if a.wholeCategoryID != b.wholeCategoryID { names.append("wholeCategory") }
        if a.wholeSubcategoryID != b.wholeSubcategoryID { names.append("wholeSubcategory") }
        if a.items != b.items { names.append("items") }
        if a.imageData != b.imageData { names.append("image") }
        if a.warnings != b.warnings { names.append("warnings") }
        return names.isEmpty ? "nothing" : names.joined(separator: ", ")
    }

    var includedItemsSum: Decimal {
        items.filter(\.included).compactMap(\.amount).reduce(0, +)
    }

    /// total - sum of items (positive = items missing, negative = items too high)
    var difference: Decimal? {
        guard let total else { return nil }
        return total - includedItemsSum
    }
}

struct ItemTarget: Equatable {
    var categoryID: UUID?
    var subcategoryID: UUID?
}

struct ReceiptDraftItem: Identifiable, Equatable {
    /// Where the suggested category came from (shown as a small icon).
    enum Source: Equatable {
        case keyword, learned, appleIntelligence, unknown
    }

    let id = UUID()
    var name: String
    var amountText: String
    var categoryID: UUID?
    var subcategoryID: UUID?
    var included = true
    /// How sure the classifier was (0 = not recognised).
    var confidence: Double = 0
    var source: Source = .unknown
    /// What Familoq suggested - a different choice on Save is remembered.
    var suggestedCategoryID: UUID?
    var suggestedSubcategoryID: UUID?

    var amount: Decimal? { DecimalParser.parse(amountText) }

    /// The user has not changed the suggestion.
    var isUntouched: Bool { categoryID == suggestedCategoryID && subcategoryID == suggestedSubcategoryID }
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
    static func draft(from parsed: ParsedReceipt, family: Family, lookup: CategoryLookup, rules: [MerchantRuleRecord], imageData: Data?,
                      itemRules: [ItemCategoryRule] = [], now: Date = Date()) -> ReceiptDraft {
        let groceriesID = lookup.categories.first { $0.systemKey == "groceries" }?.id

        let merchant = parsed.merchant ?? ""
        let suggestion = CategorizationService.suggestion(for: merchant, rules: rules)
        let isGroceryMerchant = suggestion == nil || suggestion?.categoryID == groceriesID

        let learned = learnedTargets(itemRules)
        let items = draftItems(from: parsed, lookup: lookup, learned: learned)

        let total = parsed.total ?? (parsed.items.isEmpty ? nil : parsed.itemsSum)
        let vat = parsed.vat.map { line in
            "\(plain(line.ratePercent)) %" + (line.taxAmount.map { ": \(plain($0))" } ?? "")
        }.joined(separator: ", ")

        return ReceiptDraft(
            merchant: merchant,
            // Whole minutes: the date picker shows minutes only and would
            // otherwise "correct" the seconds while the screen is built.
            date: Date(timeIntervalSince1970: ((parsed.date ?? now).timeIntervalSince1970 / 60).rounded(.down) * 60),
            currencyCode: parsed.currencyCode ?? family.baseCurrencyCode,
            currencyConfirmed: !parsed.currency.needsConfirmation,
            currencyCandidates: currencyCandidates(for: parsed.currency, baseCurrency: family.baseCurrencyCode),
            totalText: total.map(plain) ?? "",
            // Item-level only makes sense for grocery-type receipts with items.
            categorizeWholeReceipt: items.isEmpty || !isGroceryMerchant,
            wholeCategoryID: suggestion?.categoryID ?? groceriesID,
            wholeSubcategoryID: suggestion?.subcategoryID,
            items: items,
            imageData: imageData,
            rawText: parsed.rawLines.joined(separator: "\n"),
            vatSummary: vat,
            warnings: parsed.warnings,
            learned: learned
        )
    }

    static func learnedTargets(_ rules: [ItemCategoryRule]) -> [String: ItemTarget] {
        Dictionary(rules.map { ($0.key, ItemTarget(categoryID: $0.categoryID, subcategoryID: $0.subcategoryID)) },
                   uniquingKeysWith: { a, _ in a })
    }

    /// Order: what the family taught Familoq, then the built-in keywords,
    /// then "Other groceries" (Apple Intelligence may fill that in later).
    static func draftItems(from parsed: ParsedReceipt, lookup: CategoryLookup, learned: [String: ItemTarget] = [:]) -> [ReceiptDraftItem] {
        let groceriesID = lookup.categories.first { $0.systemKey == "groceries" }?.id
        let groceriesOtherID = lookup.subcategories.first { $0.systemKey == "groceries.other" }?.id
        return parsed.items.map { item in
            if let target = learned[ItemRuleKey.make(item.name)],
               lookup.category(target.categoryID) != nil {
                return ReceiptDraftItem(
                    name: item.name, amountText: plain(item.amount),
                    categoryID: target.categoryID, subcategoryID: target.subcategoryID,
                    confidence: 1, source: .learned,
                    suggestedCategoryID: target.categoryID, suggestedSubcategoryID: target.subcategoryID)
            }
            let key = item.suggestedSubcategoryKey
            let subID = key.flatMap { k in lookup.subcategories.first { $0.systemKey == k }?.id } ?? groceriesOtherID
            return ReceiptDraftItem(
                name: item.name,
                amountText: plain(item.amount),
                categoryID: groceriesID,
                subcategoryID: subID,
                confidence: item.classificationConfidence,
                source: key == nil ? .unknown : .keyword,
                suggestedCategoryID: groceriesID,
                suggestedSubcategoryID: subID
            )
        }
    }

    /// Edit a saved receipt: the check screen filled from what was stored.
    static func draft(editing receipt: ReceiptRecord, items: [ReceiptItemRecord], lookup: CategoryLookup, itemRules: [ItemCategoryRule] = []) -> ReceiptDraft {
        let real = items.filter { $0.name != ReceiptSaver.differenceItemName }.sorted { $0.sortOrder < $1.sortOrder }
        let targets = Set(real.map { "\($0.categoryID?.uuidString ?? "-")|\($0.subcategoryID?.uuidString ?? "-")" })
        // One category for everything = it was saved as a whole receipt.
        let whole = targets.count <= 1
        let first = real.first
        return ReceiptDraft(
            merchant: receipt.merchant,
            date: receipt.date,
            currencyCode: receipt.currencyCode,
            currencyConfirmed: true,
            currencyCandidates: [],
            totalText: plain(receipt.total),
            categorizeWholeReceipt: whole,
            wholeCategoryID: first?.categoryID ?? lookup.categories.first { $0.systemKey == "groceries" }?.id,
            wholeSubcategoryID: first?.subcategoryID,
            items: real.map { item in
                ReceiptDraftItem(name: item.name, amountText: plain(item.amount),
                                 categoryID: item.categoryID, subcategoryID: item.subcategoryID,
                                 confidence: 1, source: .keyword,
                                 suggestedCategoryID: item.categoryID, suggestedSubcategoryID: item.subcategoryID)
            },
            imageData: receipt.imageData,
            rawText: receipt.rawText,
            vatSummary: receipt.vatSummary,
            warnings: [],
            learned: learnedTargets(itemRules)
        )
    }

    /// Detected candidates first, then the family's base currency, the
    /// iPhone's region currency and a few common ones.
    static func currencyCandidates(for detection: CurrencyDetection, baseCurrency: String) -> [String] {
        var result: [String] = []
        let regional = Locale.current.currency?.identifier
        for code in detection.candidates + [baseCurrency, regional].compactMap({ $0 }) + ["EUR", "USD", "GBP", "CHF"] {
            let c = CurrencyInfo.normalize(code)
            if CurrencyInfo.isValidCode(c) && !result.contains(c) { result.append(c) }
        }
        return Array(result.prefix(6))
    }

    /// The user chose the currency: confirm it and, when it changes how
    /// amounts are written (whole yen/forint vs. cents), read the receipt
    /// text again in that currency's style.
    static func applyCurrency(_ code: String, to draft: inout ReceiptDraft, lookup: CategoryLookup) {
        let new = CurrencyInfo.normalize(code)
        let old = draft.currencyCode
        draft.currencyCode = new
        draft.currencyConfirmed = true
        draft.warnings.removeAll { $0.localizedCaseInsensitiveContains("currency") }
        guard CurrencyDetector.usesWholeAmounts(new) != CurrencyDetector.usesWholeAmounts(old),
              !draft.rawText.isEmpty else { return }
        let reparsed = ReceiptParser.parse(lines: draft.rawText.components(separatedBy: "\n"), currency: new)
        draft.items = draftItems(from: reparsed, lookup: lookup, learned: draft.learned)
        if let total = reparsed.total ?? (reparsed.items.isEmpty ? nil : reparsed.itemsSum) {
            draft.totalText = plain(total)
        }
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
    static let differenceItemName = "Difference to receipt total"

    /// - Parameter replacing: a saved receipt being edited - its items and
    ///   expenses are replaced (the person it was booked for stays).
    @discardableResult
    static func save(_ draft: ReceiptDraft, family: Family, member: FamilyMember?, lookup: CategoryLookup, context: ModelContext,
                     replacing existing: ReceiptRecord? = nil) throws -> [Expense] {
        guard let total = draft.total, total > 0 else { throw ReceiptSaveError.missingTotal }
        let merchant = draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Receipt" : draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let currency = CurrencyInfo.normalize(draft.currencyCode)
        let repository = FamilyRepository(context: context, familyID: family.id)

        let receipt: ReceiptRecord
        /// Editing: expenses of the receipt, reused where the group still exists.
        var reusable: [Expense] = []
        var bookedFor: UUID? = member?.id
        var createdBy: UUID? = member?.id
        if let existing {
            // Validate everything before deleting anything.
            if !draft.categorizeWholeReceipt {
                let included = draft.items.filter { $0.included && ($0.amount ?? 0) != 0 }
                guard !included.isEmpty else { throw ReceiptSaveError.noItems }
                guard included.allSatisfy({ $0.categoryID != nil }) else { throw ReceiptSaveError.missingCategory }
            } else if draft.wholeCategoryID == nil {
                throw ReceiptSaveError.missingCategory
            }
            receipt = existing
            let rid = existing.id
            let oldExpenses = try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.receiptID == rid }))
            bookedFor = oldExpenses.first?.memberID ?? bookedFor
            createdBy = oldExpenses.first?.createdByMemberID ?? existing.createdByMemberID ?? createdBy
            reusable = oldExpenses
            for item in try context.fetch(FetchDescriptor<ReceiptItemRecord>(predicate: #Predicate { $0.receiptID == rid })) {
                context.delete(item)
            }
            receipt.merchant = merchant
            receipt.date = draft.date
            receipt.totalValue = FixedPoint.storage(from: total)
            receipt.currencyCode = currency
        } else {
            receipt = ReceiptRecord(familyID: family.id, merchant: merchant, date: draft.date, total: total, currencyCode: currency)
            receipt.syncImage = draft.imageData
            receipt.rawText = draft.rawText
            receipt.vatSummary = draft.vatSummary
            receipt.createdByMemberID = member?.id
        }

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
                itemRecords.append(ReceiptItemRecord(familyID: family.id, receiptID: receipt.id, name: differenceItemName, amount: difference,
                                                     categoryID: groups[largest].categoryID, subcategoryID: groups[largest].subcategoryID,
                                                     sortOrder: itemRecords.count))
            }
        }

        if existing == nil { context.insert(receipt) }
        itemRecords.forEach { context.insert($0) }
        if !draft.categorizeWholeReceipt {
            learn(from: draft.items, familyID: family.id, context: context)
        }

        var expenses: [Expense] = []
        for group in groups where group.amount > 0 {
            if let index = reusable.firstIndex(where: { $0.categoryID == group.categoryID && $0.subcategoryID == group.subcategoryID }) {
                let expense = reusable.remove(at: index)
                expense.amount = group.amount
                expense.currencyCode = currency
                expense.baseCurrencyCode = family.baseCurrencyCode
                expense.merchant = merchant
                expense.date = draft.date
                expense.note = summary(of: group.names)
                expense.resetConversion()
                expense.updatedAt = Date()
                expenses.append(expense)
                continue
            }
            let expense = Expense(familyID: family.id, amount: group.amount, currencyCode: currency,
                                  baseCurrencyCode: family.baseCurrencyCode, merchant: merchant, date: draft.date)
            expense.categoryID = group.categoryID
            expense.subcategoryID = group.subcategoryID
            expense.memberID = bookedFor
            expense.createdByMemberID = createdBy
            expense.entryMethod = .receipt
            expense.receiptID = receipt.id
            expense.note = summary(of: group.names)
            expense.resetConversion()
            try repository.insert(expense)
            expenses.append(expense)
        }
        for leftover in reusable { context.delete(leftover) }
        try context.save()
        return expenses
    }

    /// Every item the user filed differently from the suggestion is
    /// remembered for the whole family (next receipt: filed the same way).
    static func learn(from items: [ReceiptDraftItem], familyID: UUID, context: ModelContext) {
        for item in items where item.included && !item.isUntouched {
            guard let categoryID = item.categoryID else { continue }
            let key = ItemRuleKey.make(item.name)
            guard key.count >= 3 else { continue }
            let id = ItemCategoryRule.ruleID(familyID: familyID, key: key)
            var descriptor = FetchDescriptor<ItemCategoryRule>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let rule = try? context.fetch(descriptor).first {
                rule.categoryID = categoryID
                rule.subcategoryID = item.subcategoryID
                rule.displayName = item.name
                rule.updatedAt = Date()
            } else {
                context.insert(ItemCategoryRule(id: id, familyID: familyID, key: key, displayName: item.name,
                                                categoryID: categoryID, subcategoryID: item.subcategoryID))
            }
        }
    }

    private static func summary(of names: [String]) -> String {
        guard !names.isEmpty else { return "" }
        let shown = names.prefix(3).joined(separator: ", ")
        return names.count > 3 ? "\(shown) +\(names.count - 3) more" : shown
    }
}
