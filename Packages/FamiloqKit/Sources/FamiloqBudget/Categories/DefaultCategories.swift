import Foundation
import FamiloqCore

public struct DefaultSubcategory: Equatable, Sendable {
    /// Stable identifier, independent of the (renamable) display name.
    public let key: String
    public let name: String
}

public struct DefaultCategory: Equatable, Sendable {
    public let key: String
    public let name: String
    /// SF Symbol name.
    public let icon: String
    public let colorHex: String
    public let subcategories: [DefaultSubcategory]
}

/// The default category tree seeded into every new family.
/// Owners can rename, add and archive categories afterwards; the `key`
/// fields let the app keep recognising built-in categories after renames.
public enum DefaultCategories {
    public static let all: [DefaultCategory] = [
        make("groceries", "Groceries", "cart.fill", "#34A853", [
            ("meat", "Meat & Poultry"),
            ("fish", "Fish & Seafood"),
            ("dairy", "Milk & Dairy"),
            ("eggs", "Eggs"),
            ("vegetables", "Vegetables"),
            ("fruits", "Fruits"),
            ("bakery", "Bread & Bakery"),
            ("grains", "Rice, Pasta & Grains"),
            ("canned", "Canned & Packaged Food"),
            ("snacks", "Snacks & Sweets"),
            ("beverages", "Beverages"),
            ("coffee", "Coffee & Tea"),
            ("condiments", "Spices, Sauces & Condiments"),
            ("frozen", "Frozen Food"),
            ("household", "Household Supplies"),
            ("cleaning", "Cleaning Products"),
            ("pet", "Pet Supplies"),
            ("other", "Other Groceries")
        ]),
        make("transport", "Transport", "car.fill", "#4285F4", [
            ("fuel", "Fuel"),
            ("public", "Public Transport"),
            ("parking", "Parking"),
            ("tolls", "Tolls"),
            ("maintenance", "Car Maintenance"),
            ("insurance", "Car Insurance"),
            ("wash", "Car Wash"),
            ("other", "Other")
        ]),
        make("housing", "Housing & Utilities", "house.fill", "#8E6C4A", [
            ("rent", "Rent"),
            ("electricity", "Electricity"),
            ("heating", "Heating"),
            ("water", "Water"),
            ("internet", "Internet"),
            ("mobile", "Mobile"),
            ("household", "Household"),
            ("other", "Other")
        ]),
        make("restaurants", "Restaurants & Food", "fork.knife", "#EA4335", [
            ("restaurant", "Restaurant"),
            ("fastfood", "Fast Food"),
            ("cafe", "Café"),
            ("takeaway", "Takeaway"),
            ("delivery", "Delivery"),
            ("other", "Other")
        ]),
        make("shopping", "Shopping", "bag.fill", "#A142F4", [
            ("clothing", "Clothing"),
            ("electronics", "Electronics"),
            ("home", "Home & Furniture"),
            ("personalcare", "Personal Care"),
            ("gifts", "Gifts"),
            ("other", "Other")
        ]),
        make("travel", "Travel", "airplane", "#00ACC1", [
            ("flights", "Flights"),
            ("hotels", "Hotels"),
            ("train", "Train"),
            ("carrental", "Car Rental"),
            ("activities", "Activities"),
            ("food", "Travel Food"),
            ("other", "Other")
        ]),
        make("health", "Health", "cross.case.fill", "#E91E63", [
            ("pharmacy", "Pharmacy"),
            ("doctor", "Doctor"),
            ("dental", "Dental"),
            ("insurance", "Insurance"),
            ("other", "Other")
        ]),
        make("entertainment", "Entertainment", "theatermasks.fill", "#FB8C00", [
            ("cinema", "Cinema"),
            ("events", "Events"),
            ("games", "Games"),
            ("hobbies", "Hobbies"),
            ("other", "Other")
        ]),
        make("subscriptions", "Subscriptions", "repeat.circle.fill", "#5C6BC0", [
            ("streaming", "Streaming"),
            ("software", "Software"),
            ("cloud", "Cloud Storage"),
            ("memberships", "Memberships"),
            ("other", "Other")
        ]),
        make("education", "Education", "book.fill", "#43A047", [
            ("courses", "Courses"),
            ("books", "Books"),
            ("school", "School"),
            ("other", "Other")
        ]),
        make("insurance", "Insurance", "shield.fill", "#546E7A", [
            ("car", "Car"),
            ("home", "Home"),
            ("health", "Health"),
            ("other", "Other")
        ]),
        make("personal", "Personal", "person.fill", "#D81B60", [
            ("hairdresser", "Hairdresser"),
            ("beauty", "Beauty"),
            ("personalcare", "Personal Care"),
            ("other", "Other")
        ]),
        make("savings", "Savings", "banknote.fill", "#2E7D32", [
            ("emergency", "Emergency Fund"),
            ("investments", "Investments"),
            ("other", "Other")
        ]),
        make("other", "Other", "ellipsis.circle.fill", "#9E9E9E", [
            ("other", "Other")
        ])
    ]

    public static func category(forKey key: String) -> DefaultCategory? {
        all.first { $0.key == key }
    }

    /// Looks up e.g. "groceries.fruits".
    public static func subcategory(forKey key: String) -> (category: DefaultCategory, subcategory: DefaultSubcategory)? {
        for category in all {
            if let sub = category.subcategories.first(where: { $0.key == key }) {
                return (category, sub)
            }
        }
        return nil
    }

    private static func make(_ key: String, _ name: String, _ icon: String, _ color: String, _ subs: [(String, String)]) -> DefaultCategory {
        DefaultCategory(
            key: key,
            name: name,
            icon: icon,
            colorHex: color,
            subcategories: subs.map { DefaultSubcategory(key: "\(key).\($0.0)", name: $0.1) }
        )
    }
}
