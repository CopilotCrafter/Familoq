import Foundation

/// Fast in-memory lookup of a family's categories for rows, charts and pickers.
struct CategoryLookup {
    private let categoriesByID: [UUID: ExpenseCategory]
    private let subcategoriesByID: [UUID: ExpenseSubcategory]
    let categories: [ExpenseCategory]
    let subcategories: [ExpenseSubcategory]

    init(categories: [ExpenseCategory], subcategories: [ExpenseSubcategory]) {
        self.categories = categories.sorted { $0.sortOrder < $1.sortOrder }
        self.subcategories = subcategories.sorted { $0.sortOrder < $1.sortOrder }
        var c: [UUID: ExpenseCategory] = [:]
        for item in categories { c[item.id] = item }
        var s: [UUID: ExpenseSubcategory] = [:]
        for item in subcategories { s[item.id] = item }
        categoriesByID = c
        subcategoriesByID = s
    }

    func category(_ id: UUID?) -> ExpenseCategory? {
        id.flatMap { categoriesByID[$0] }
    }

    func subcategory(_ id: UUID?) -> ExpenseSubcategory? {
        id.flatMap { subcategoriesByID[$0] }
    }

    func activeCategories() -> [ExpenseCategory] {
        categories.filter { !$0.isArchived }
    }

    func activeSubcategories(of categoryID: UUID?) -> [ExpenseSubcategory] {
        guard let categoryID else { return [] }
        return subcategories.filter { $0.categoryID == categoryID && !$0.isArchived }
    }

    /// "Groceries › Fruits"
    func path(categoryID: UUID?, subcategoryID: UUID?) -> String {
        let cat = category(categoryID)?.name ?? "Uncategorized"
        if let sub = subcategory(subcategoryID)?.name {
            return "\(cat) › \(sub)"
        }
        return cat
    }
}
