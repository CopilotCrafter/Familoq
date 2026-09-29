import Foundation
import FamiloqCore

/// Main protein of a dish.
public enum DishProtein: String, CaseIterable, Sendable {
    case vegan = "vg", vegetarian = "v", legumes = "l", egg = "e", fish = "f", shellfish = "sf"
    case poultry = "p", redMeat = "m", pork = "pk"
}

/// Carbohydrate base of a dish.
public enum DishBase: String, CaseIterable, Sendable {
    case rice = "r", pasta = "p", bread = "b", potato = "po", wholegrain = "w", dough = "d", none = "n"

    /// White rice, pasta, white bread and dough: rise blood sugar faster.
    public var isRefined: Bool { self == .rice || self == .pasta || self == .bread || self == .dough }
}

/// Tags of a dish (short codes in the catalogue text).
public enum DishFlag: String, CaseIterable, Sendable {
    case gluten = "g", dairy = "d", nuts = "n", soy = "sy"
    case highSalt = "hs", highSatFat = "hf", highSugar = "hg", purine = "pu", fried = "fr"
    case processedMeat = "pr", offal = "lv", raw = "raw", alcohol = "al", seaweed = "sea"
    case sweet = "sw", vegetableRich = "vv", kidFriendly = "k", lunchbox = "lb", lunchboxOnly = "lbo"
    case spicy1 = "s1", spicy2 = "s2", spicy3 = "s3"
}

public struct Dish: Identifiable, Hashable, Sendable {
    public let id: String
    public let cuisine: Cuisine
    public let regions: [String]
    /// Original name (Käsespätzle, Avial, Ribollita).
    public let name: String
    public let englishDescription: String
    public let germanDescription: String
    public let proteins: Set<DishProtein>
    public let base: DishBase
    public let minutes: Int
    public let flags: Set<DishFlag>
    /// Months (1-12) when it is in season; empty = all year.
    public let seasonMonths: Set<Int>
    /// For 4 people, in German shop terms ("500 g Spätzle").
    public let ingredients: [String]

    public static func == (a: Dish, b: Dish) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public func has(_ flag: DishFlag) -> Bool { flags.contains(flag) }

    public var isVegetarian: Bool { proteins.isSubset(of: [.vegan, .vegetarian, .legumes, .egg]) }
    public var isVegan: Bool { proteins.isSubset(of: [.vegan, .legumes]) && !has(.dairy) && !containsEgg }
    public var hasFish: Bool { proteins.contains(.fish) }
    public var hasLegumes: Bool { proteins.contains(.legumes) }
    public var hasRedMeat: Bool { proteins.contains(.redMeat) || proteins.contains(.pork) }

    public var spiceLevel: Int {
        if has(.spicy3) { return 3 }
        if has(.spicy2) { return 2 }
        if has(.spicy1) { return 1 }
        return 0
    }

    /// Egg as protein or in the ingredients (breading, Spätzle, fresh pasta).
    public var containsEgg: Bool {
        if proteins.contains(.egg) { return true }
        let words = ["eier", "ei", "eigelb", "spatzle", "spaetzle", "eiernudeln", "tagliatelle", "tortellini", "mayonnaise"]
        return ingredients.contains { line in
            let text = TextNormalizer.normalize(line, germanTransliteration: true)
            return text.split(separator: " ").contains { token in words.contains(String(token)) }
        }
    }

    /// Rough share of beans, wheat and onions (for IBS / low FODMAP).
    public var highFODMAP: Bool { hasLegumes || has(.gluten) }

    public func description(german: Bool) -> String { german ? germanDescription : englishDescription }

    public func isInSeason(month: Int) -> Bool { seasonMonths.isEmpty || seasonMonths.contains(month) }
}

public enum DishCatalogue {
    /// All dishes (parsed once).
    public static let all: [Dish] = DishCatalogueData.lines.compactMap(parse)

    public static let byID: [String: Dish] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    public static func dishes(for cuisine: Cuisine) -> [Dish] { all.filter { $0.cuisine == cuisine } }

    /// "de|by,bw|Käsespätzle|en|de|v|d|35|g,d|4-6|500 g Spätzle; 250 g Käse"
    static func parse(_ line: String) -> Dish? {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
        guard f.count == 11, let cuisine = Cuisine(rawValue: f[0]), let base = DishBase(rawValue: f[6]), let minutes = Int(f[7]) else { return nil }
        let proteins = Set(f[5].split(separator: ",").compactMap { DishProtein(rawValue: String($0)) })
        let flags = Set(f[8].split(separator: ",").compactMap { DishFlag(rawValue: String($0)) })
        return Dish(id: cuisine.rawValue + "." + slug(f[2]), cuisine: cuisine,
                    regions: f[1].split(separator: ",").map(String.init), name: f[2],
                    englishDescription: f[3], germanDescription: f[4], proteins: proteins, base: base,
                    minutes: minutes, flags: flags, seasonMonths: months(f[9]),
                    ingredients: f[10].split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    static func slug(_ name: String) -> String {
        TextNormalizer.normalize(name, germanTransliteration: true)
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, c in
                if c == "-" && (result.isEmpty || result.hasSuffix("-")) { return }
                result.append(c)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// "4-6" -> {4,5,6}; "11-2" wraps over the new year.
    static func months(_ text: String) -> Set<Int> {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[0]), (1...12).contains(parts[1]) else { return [] }
        var result: Set<Int> = []
        var m = parts[0]
        while true {
            result.insert(m)
            if m == parts[1] { break }
            m = m % 12 + 1
        }
        return result
    }

    /// Finds a catalogue dish by (roughly) its name, e.g. for a typed meal.
    public static func match(title: String) -> Dish? {
        let key = slug(title)
        guard !key.isEmpty else { return nil }
        return all.first { slug($0.name) == key } ?? all.first { key.count >= 6 && slug($0.name).hasPrefix(key) }
    }
}

/// Rough carbohydrates per portion from the ingredient amounts.
public enum CarbEstimate {
    /// grams of carbohydrate per 100 g (dry where it is bought dry).
    static let perHundredGrams: [(String, Double)] = [
        ("reisnudeln", 80), ("glasnudeln", 85), ("basmatireis", 78), ("jasminreis", 78), ("klebreis", 80), ("sushireis", 78),
        ("risottoreis", 78), ("paellareis", 78), ("naturreis", 72), ("reismehl", 80), ("reis", 78), ("poha", 77),
        ("spatzle", 30), ("spaghetti", 71), ("nudeln", 71), ("tagliatelle", 68), ("rigatoni", 71), ("orecchiette", 71),
        ("trofie", 70), ("tortellini", 45), ("lasagneplatten", 70), ("ramennudeln", 65), ("eiernudeln", 68),
        ("mehl", 72), ("atta", 65), ("buchweizenmehl", 70), ("maismehl", 75), ("kichererbsenmehl", 55), ("ragi-mehl", 72),
        ("bulgur", 70), ("couscous", 70), ("polenta", 75), ("haferflocken", 60), ("quinoa", 64),
        ("kartoffeln", 16), ("susskartoffeln", 20), ("linsen", 50), ("dal", 55), ("kichererbsen", 45),
        ("kidneybohnen", 15), ("bohnen", 15), ("erbsen", 10), ("mais", 16)
    ]

    /// Typical carbohydrate per piece.
    static let perPiece: [(String, Double)] = [
        ("brotchen", 28), ("brezn", 40), ("naan", 50), ("pitabrot", 35), ("fladenbrot", 120), ("tortilla", 15),
        ("wrap", 30), ("chapati", 20), ("roti", 20), ("knodel", 22), ("kartoffelklo", 22), ("klo", 22), ("baguette", 150),
        ("ciabatta", 130), ("vollkornbrot", 250), ("apfel", 15), ("birne", 20), ("kochbanane", 45), ("kartoffel", 20),
        ("wantan-blatter", 5)
    ]

    public static func perPortion(ingredients: [String], servings: Int) -> Int? {
        guard servings > 0 else { return nil }
        var total = 0.0
        var found = false
        for line in ingredients {
            let text = TextNormalizer.normalize(line, germanTransliteration: true)
            let tokens = text.split(separator: " ").map(String.init)
            guard let first = tokens.first, let number = Double(first.replacingOccurrences(of: ",", with: ".")) else { continue }
            let unit = tokens.count > 1 ? tokens[1] : ""
            let rest = tokens.dropFirst(unit == "g" || unit == "kg" ? 2 : 1).joined(separator: " ")
            if unit == "g" || unit == "kg" {
                let grams = unit == "kg" ? number * 1000 : number
                if let density = perHundredGrams.first(where: { rest.contains($0.0) })?.1 {
                    total += grams * density / 100
                    found = true
                }
            } else if unit == "dosen" || unit == "dose" {
                if let density = perHundredGrams.first(where: { rest.contains($0.0) })?.1, density <= 20 {
                    total += number * 240 * density / 100
                    found = true
                }
            } else if let carbs = perPiece.first(where: { text.contains($0.0) })?.1 {
                total += number * carbs
                found = true
            }
        }
        guard found else { return nil }
        return Int((total / Double(servings) / 5).rounded()) * 5
    }
}
