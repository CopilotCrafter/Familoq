import Foundation
import SwiftData
import FamiloqCore
import FamiloqBudget

/// The Budget space - the first Familoq module.
@MainActor
enum BudgetModule: FamiloqModule {
    static let space: FamiloqSpace = .budget

    static let models: [any PersistentModel.Type] = [
        ExpenseCategory.self,
        ExpenseSubcategory.self,
        Expense.self,
        Budget.self,
        MerchantRuleRecord.self,
        ExchangeRateCacheEntry.self,
        ReceiptRecord.self,
        ReceiptItemRecord.self
    ]

    static func seedDefaults(familyID: UUID, in context: ModelContext) {
        let ids = seedCategories(familyID: familyID, in: context)
        seedMerchantRules(familyID: familyID, categories: ids, in: context)
    }

    /// Returns maps from default keys to the created record IDs.
    @discardableResult
    static func seedCategories(familyID: UUID, in context: ModelContext) -> SeededCategoryIDs {
        var ids = SeededCategoryIDs()
        for (categoryIndex, def) in DefaultCategories.all.enumerated() {
            let category = ExpenseCategory(
                familyID: familyID,
                systemKey: def.key,
                name: def.name,
                icon: def.icon,
                colorHex: def.colorHex,
                sortOrder: categoryIndex
            )
            context.insert(category)
            ids.categories[def.key] = category.id
            for (subIndex, subDef) in def.subcategories.enumerated() {
                let sub = ExpenseSubcategory(
                    familyID: familyID,
                    categoryID: category.id,
                    systemKey: subDef.key,
                    name: subDef.name,
                    sortOrder: subIndex
                )
                context.insert(sub)
                ids.subcategories[subDef.key] = sub.id
            }
        }
        return ids
    }

    static func seedMerchantRules(familyID: UUID, categories: SeededCategoryIDs, in context: ModelContext) {
        for rule in DefaultMerchantRules.all {
            guard let categoryID = categories.categories[rule.categoryKey] else { continue }
            let subID = rule.subcategoryKey.flatMap { categories.subcategories[$0] }
            let record = MerchantRuleRecord(
                familyID: familyID,
                pattern: rule.pattern,
                displayMerchant: rule.pattern,
                categoryID: categoryID,
                subcategoryID: subID,
                isUserDefined: false
            )
            context.insert(record)
        }
    }
}

struct SeededCategoryIDs {
    var categories: [String: UUID] = [:]
    var subcategories: [String: UUID] = [:]
}
