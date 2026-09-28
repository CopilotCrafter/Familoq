import Foundation
import FamiloqCore
import FamiloqBudget

/// One line typed into the shopping list, e.g. "2x Milch" or "Hack 500 g".
public struct ShoppingEntry: Equatable, Sendable {
    public var name: String
    /// "" when no amount was typed; otherwise e.g. "2", "500 g", "1,5 kg".
    public var quantity: String

    public init(name: String, quantity: String = "") {
        self.name = name
        self.quantity = quantity
    }
}

public enum ShoppingEntryParser {
    private static let units = "x|×|stk\\.?|stück|stueck|st\\.?|pcs|pc|kg|g|gr|l|ml|pck\\.?|pckg\\.?|pack|packs|pkg|dosen|dose|flaschen|flasche|bund|glas|becher|cans|can|bottles|bottle"
    private static let number = "(\\d+(?:[.,]\\d+)?)"

    private static let leading = try! NSRegularExpression(
        pattern: "^\\s*\(number)\\s*(\(units))?\\s+(.+?)\\s*$", options: [.caseInsensitive])
    private static let trailing = try! NSRegularExpression(
        pattern: "^\\s*(.+?)\\s+(?:x\\s*)?\(number)\\s*(\(units))?\\s*$", options: [.caseInsensitive])
    private static let bracket = try! NSRegularExpression(
        pattern: "^\\s*(.+?)\\s*\\(\\s*\(number)\\s*(\(units))?\\s*\\)\\s*$", options: [.caseInsensitive])

    /// Splits an amount off the name: "2x Milch" -> ("Milch", "2"),
    /// "500g Hackfleisch" -> ("Hackfleisch", "500 g"), "Eier 10" -> ("Eier", "10").
    public static func parse(_ text: String) -> ShoppingEntry {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        func group(_ match: NSTextCheckingResult, _ i: Int) -> String? {
            let r = match.range(at: i)
            guard r.location != NSNotFound, let swiftRange = Range(r, in: trimmed) else { return nil }
            return String(trimmed[swiftRange])
        }
        if let m = leading.firstMatch(in: trimmed, range: range), let amount = group(m, 1), let name = group(m, 3) {
            return ShoppingEntry(name: capitalized(name), quantity: quantity(amount, group(m, 2)))
        }
        if let m = bracket.firstMatch(in: trimmed, range: range), let name = group(m, 1), let amount = group(m, 2) {
            return ShoppingEntry(name: capitalized(name), quantity: quantity(amount, group(m, 3)))
        }
        if let m = trailing.firstMatch(in: trimmed, range: range), let name = group(m, 1), let amount = group(m, 2) {
            return ShoppingEntry(name: capitalized(name), quantity: quantity(amount, group(m, 3)))
        }
        return ShoppingEntry(name: capitalized(trimmed))
    }

    private static func quantity(_ amount: String, _ unit: String?) -> String {
        guard var unit = unit?.lowercased(), !unit.isEmpty, unit != "x", unit != "×" else { return amount }
        if unit.hasSuffix(".") { unit.removeLast() }
        return "\(amount) \(unit)"
    }

    private static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// Key used to spot the same item ("milch" == "Milch" == "MILCH").
    public static func key(_ name: String) -> String {
        TextNormalizer.normalize(name, germanTransliteration: true)
    }
}

/// Supermarket sections, in the order most shops are walked through.
public enum ShoppingAisles {
    public static let other = "groceries.other"

    public static let walkOrder: [String] = [
        "groceries.fruits", "groceries.vegetables", "groceries.bakery", "groceries.meat", "groceries.fish",
        "groceries.dairy", "groceries.eggs", "groceries.grains", "groceries.canned", "groceries.condiments",
        "groceries.snacks", "groceries.coffee", "groceries.beverages", "groceries.frozen",
        "groceries.household", "groceries.cleaning", "groceries.pet", other
    ]

    /// Section for an item name, from the same classifier receipts use.
    public static func aisleKey(for name: String) -> String {
        guard let key = GroceryItemClassifier.classify(name)?.subcategoryKey, walkOrder.contains(key) else { return other }
        return key
    }

    public static func order(of key: String) -> Int {
        walkOrder.firstIndex(of: key) ?? walkOrder.count
    }

    /// English section name (the app translates it).
    public static func name(of key: String) -> String {
        if key == other { return "Other" }
        return DefaultCategories.subcategory(forKey: key)?.subcategory.name ?? "Other"
    }
}

/// Ticks off shopping list items that appear on a scanned receipt.
public enum ShoppingReceiptMatcher {
    private static let ignored: Set<String> = ["bio", "und", "and", "the", "der", "die", "das", "von", "mit", "for", "fur", "frische", "frisch", "fresh"]

    static func tokens(_ text: String, minLength: Int) -> [String] {
        ShoppingEntryParser.key(text).split(separator: " ").map(String.init)
            .filter { $0.count >= minLength && !ignored.contains($0) && !$0.allSatisfy(\.isNumber) }
    }

    /// Does a word from the list match a word on the receipt?
    /// Plurals ("Banane"/"BANANEN"), cut-off receipt words ("KARTOFF."), and
    /// German compounds whose last part is the item ("Vollmilch" is milk,
    /// but "Milchschokolade" is not).
    static func matches(list l: String, receipt r: String) -> Bool {
        if l == r { return true }
        if l.count >= 4, r.hasPrefix(l), r.count - l.count <= 2 { return true }
        if r.count >= 4, l.hasPrefix(r), l.count - r.count <= 2 { return true }
        if r.count >= 5, l.hasPrefix(r) { return true }
        if l.count >= 4, r.hasSuffix(l) { return true }
        if r.count >= 4, l.hasSuffix(r) { return true }
        return false
    }

    /// IDs of open list items that were bought on this receipt. Each receipt
    /// line ticks off at most one item.
    public static func boughtItems(open candidates: [(id: UUID, name: String)], receiptLines: [String]) -> [UUID] {
        var lines = receiptLines.map { tokens($0, minLength: 2) }
        var result: [UUID] = []
        for item in candidates {
            let wanted = tokens(item.name, minLength: 3)
            guard !wanted.isEmpty else { continue }
            if let index = lines.indices.first(where: { i in
                wanted.allSatisfy { w in lines[i].contains { matches(list: w, receipt: $0) } }
            }) {
                result.append(item.id)
                lines[index] = []
            }
        }
        return result
    }
}

/// "Buy again" suggestions from what the family bought before.
public enum ShoppingSuggestions {
    public static func frequent(history: [(name: String, date: Date)], excludingOpen openNames: [String], prefix: String = "", limit: Int = 12) -> [String] {
        let openKeys = Set(openNames.map { ShoppingEntryParser.key($0) })
        let typed = ShoppingEntryParser.key(prefix)
        var stats: [String: (name: String, count: Int, last: Date)] = [:]
        for entry in history {
            let key = ShoppingEntryParser.key(entry.name)
            guard !key.isEmpty, !openKeys.contains(key) else { continue }
            if !typed.isEmpty, !key.split(separator: " ").contains(where: { $0.hasPrefix(typed) }), !key.hasPrefix(typed) { continue }
            if var s = stats[key] {
                s.count += 1
                if entry.date > s.last { s.last = entry.date; s.name = entry.name }
                stats[key] = s
            } else {
                stats[key] = (entry.name, 1, entry.date)
            }
        }
        return stats.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.last > $1.last }
            .prefix(limit)
            .map(\.name)
    }
}
