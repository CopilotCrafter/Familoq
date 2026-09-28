import Foundation
import SwiftData
import FamiloqBudget

/// Built-in category names follow the app language (German/English).
/// Names are family data (synced), so only the family's owner renames them,
/// and only names nobody has changed yet ("Groceries" -> "Lebensmittel").
@MainActor
enum CategoryNameLocalizer {
    /// The built-in English name in the app's current language.
    static func localized(_ english: String) -> String {
        NSLocalizedString(english, comment: "Built-in category name")
    }

    @discardableResult
    static func apply(familyID: UUID, context: ModelContext) -> Int {
        let fid = familyID
        var renamed = 0
        let categories = (try? context.fetch(FetchDescriptor<ExpenseCategory>(predicate: #Predicate { $0.familyID == fid }))) ?? []
        for category in categories {
            guard let key = category.systemKey, let english = DefaultCategories.category(forKey: key)?.name else { continue }
            let target = localized(english)
            if category.name != target && isUntouchedDefault(category.name, english: english) {
                category.name = target
                category.updatedAt = Date()
                renamed += 1
            }
        }
        let subcategories = (try? context.fetch(FetchDescriptor<ExpenseSubcategory>(predicate: #Predicate { $0.familyID == fid }))) ?? []
        let defaults = Dictionary(DefaultCategories.all.flatMap(\.subcategories).map { ($0.key, $0.name) }, uniquingKeysWith: { first, _ in first })
        for sub in subcategories {
            guard let key = sub.systemKey, let english = defaults[key] else { continue }
            let target = localized(english)
            if sub.name != target && isUntouchedDefault(sub.name, english: english) {
                sub.name = target
                sub.updatedAt = Date()
                renamed += 1
            }
        }
        if renamed > 0 { try? context.save() }
        return renamed
    }

    /// Still the English or the translated default (never a user's own name).
    private static func isUntouchedDefault(_ name: String, english: String) -> Bool {
        name == english || name == localized(english)
    }
}
