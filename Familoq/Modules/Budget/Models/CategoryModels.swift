import Foundation
import SwiftData

@Model
final class ExpenseCategory {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    /// Key of the built-in category (e.g. "groceries"); nil for custom ones.
    var systemKey: String? = nil
    var name: String = ""
    /// SF Symbol name.
    var icon: String = "tag.fill"
    var colorHex: String = "#9E9E9E"
    var sortOrder: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, systemKey: String? = nil, name: String, icon: String, colorHex: String, sortOrder: Int) {
        self.id = id
        self.familyID = familyID
        self.systemKey = systemKey
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.sortOrder = sortOrder
    }
}

@Model
final class ExpenseSubcategory {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var categoryID: UUID = UUID()
    /// Key of the built-in subcategory (e.g. "groceries.fruits").
    var systemKey: String? = nil
    var name: String = ""
    var sortOrder: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, categoryID: UUID, systemKey: String? = nil, name: String, sortOrder: Int) {
        self.id = id
        self.familyID = familyID
        self.categoryID = categoryID
        self.systemKey = systemKey
        self.name = name
        self.sortOrder = sortOrder
    }
}
