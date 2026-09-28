import Foundation
import FamiloqCore

// "Healthy basket": how balanced the family's food shopping is.
//
// Honest limits (shown in the app): it is estimated from WHAT WAS BOUGHT and
// WHAT IT COST - not from what was eaten, portion sizes or nutrition labels.
// It is a friendly nudge, not medical or dietary advice. No calorie or
// weight targets are ever computed.

public enum FoodGroup: String, CaseIterable, Sendable {
    case vegetables, fruits, wholeGrains, grains, legumesNuts, dairy, eggs, meat, fish
    case processedMeat, sweetsSnacks, sugaryDrinks, alcohol, readyMeals
    case drinks, fatsCondiments, nonFood, other

    public var title: String {
        switch self {
        case .vegetables: return "Vegetables"
        case .fruits: return "Fruit"
        case .wholeGrains: return "Wholegrain"
        case .grains: return "Bread, pasta & rice"
        case .legumesNuts: return "Pulses & nuts"
        case .dairy: return "Dairy"
        case .eggs: return "Eggs"
        case .meat: return "Meat"
        case .fish: return "Fish"
        case .processedMeat: return "Sausage & cold cuts"
        case .sweetsSnacks: return "Sweets & snacks"
        case .sugaryDrinks: return "Soft drinks & juices"
        case .alcohol: return "Alcohol"
        case .readyMeals: return "Ready meals & fast food"
        case .drinks: return "Water, coffee & tea"
        case .fatsCondiments: return "Oils, sauces & spices"
        case .nonFood: return "Non-food"
        case .other: return "Other food"
        }
    }

    public var icon: String {
        switch self {
        case .vegetables: return "carrot.fill"
        case .fruits: return "apple.logo"
        case .wholeGrains: return "leaf.fill"
        case .grains: return "birthday.cake.fill"
        case .legumesNuts: return "circle.grid.3x3.fill"
        case .dairy: return "cup.and.saucer.fill"
        case .eggs: return "oval.portrait.fill"
        case .meat: return "fork.knife"
        case .fish: return "fish.fill"
        case .processedMeat: return "exclamationmark.triangle.fill"
        case .sweetsSnacks: return "birthday.cake"
        case .sugaryDrinks: return "waterbottle.fill"
        case .alcohol: return "wineglass.fill"
        case .readyMeals: return "takeoutbag.and.cup.and.straw.fill"
        case .drinks: return "drop.fill"
        case .fatsCondiments: return "flame.fill"
        case .nonFood: return "bag.fill"
        case .other: return "cart.fill"
        }
    }

    public var colorHex: String {
        switch self {
        case .vegetables: return "#2E7D32"
        case .fruits: return "#66BB6A"
        case .wholeGrains: return "#8D6E63"
        case .grains: return "#BCAAA4"
        case .legumesNuts: return "#795548"
        case .dairy: return "#42A5F5"
        case .eggs: return "#FFCA28"
        case .meat: return "#E57373"
        case .fish: return "#26C6DA"
        case .processedMeat, .sweetsSnacks, .sugaryDrinks, .alcohol, .readyMeals: return "#FB8C00"
        case .drinks: return "#90CAF9"
        case .fatsCondiments: return "#FFB74D"
        case .nonFood: return "#9E9E9E"
        case .other: return "#B0BEC5"
        }
    }

    /// Better bought less often.
    public var isLessHealthy: Bool {
        switch self {
        case .processedMeat, .sweetsSnacks, .sugaryDrinks, .alcohol, .readyMeals: return true
        default: return false
        }
    }

    public var isFood: Bool { self != .nonFood }
}

public struct FoodPurchase: Sendable {
    public var name: String
    /// In the family's base currency.
    public var amount: Decimal
    /// Stored subcategory, e.g. "groceries.dairy" (nil for custom ones).
    public var subcategoryKey: String?
    public var date: Date

    public init(name: String, amount: Decimal, subcategoryKey: String?, date: Date) {
        self.name = name
        self.amount = amount
        self.subcategoryKey = subcategoryKey
        self.date = date
    }
}

public enum FoodGroupClassifier {
    /// Checked on the item name first - they override the subcategory
    /// (salami is "Meat & Poultry" in the budget but processed meat here).
    static let keywords: [(FoodGroup, [String])] = [
        (.nonFood, ["pfand", "leergut", "knotenbeutel", "tragetasche", "tute", "beutel", "kuchenrolle", "mullbeutel"]),
        // Look-alikes that must not be read as wine, juice or cake.
        (.fruits, ["nektarine", "weintraube", "wassermelone"]),
        (.meat, ["schwein", "rumpsteak"]),
        (.fatsCondiments, ["weinessig", "essig"]),
        (.alcohol, ["bier", "pils", "radler", "wein", "rotwein", "weisswein", "rosewein", "sekt", "prosecco", "vodka", "wodka", "whisky", "gin", "rum", "likor", "schnaps", "aperol", "beer", "wine"]),
        (.sugaryDrinks, ["cola", "fanta", "sprite", "limo", "limonade", "eistee", "ice tea", "energy", "red bull", "saft", "direktsa", "nektar", "juice", "smoothie", "schorle", "sirup", "mezzo", "spezi"]),
        (.processedMeat, ["wurst", "wurstchen", "wiener", "salami", "schinken", "speck", "bacon", "leberkas", "leberwurst", "mortadella", "lyoner", "aufschnitt", "kabanos", "chorizo", "kassler", "bratwurst", "hot dog"]),
        (.readyMeals, ["pizza", "fertiggericht", "pommes", "nuggets", "burger", "lasagne", "tiefkuhlgericht", "instant", "5 minuten", "doner", "ravioli", "currywurst"]),
        (.sweetsSnacks, ["schoko", "chocolate", "chips", "crisps", "keks", "cookie", "gummi", "haribo", "bonbon", "riegel", "praline", "nutella", "eiscreme", "ice cream", "kuchen", "torte", "donut", "croissant", "waffel", "popcorn", "milka", "ritter sport"]),
        (.legumesNuts, ["linsen", "kichererbsen", "bohnen", "erbsen", "tofu", "hummus", "nuss", "nusse", "mandel", "walnuss", "haselnuss", "cashew", "erdnuss", "pistazie", "leinsamen", "chiasamen", "kerne"]),
        (.wholeGrains, ["vollkorn", "haferflocken", "hafer", "dinkel", "roggen", "quinoa", "naturreis", "vollkornreis", "musli", "knackebrot", "buchweizen", "hirse", "bulgur"]),
        (.fish, ["lachs", "hering", "makrele", "thunfisch", "forelle", "sardine", "kabeljau", "seelachs", "fisch", "garnele", "salmon", "tuna"]),
        (.eggs, ["eier", "egg"]),
        (.drinks, ["wasser", "water", "mineral", "sprudel", "kaffee", "kaffeebohnen", "coffee", "tee", "teebeutel", "tea", "espresso"])
    ]

    static func matches(_ word: String, in text: String) -> Bool {
        // Short keywords must start a word ("tee" not in "Blätterteig").
        if word.count <= 4 {
            return text.split(separator: " ").contains { $0.hasPrefix(word) }
        }
        return text.contains(word)
    }

    public static func group(name: String, subcategoryKey: String?) -> FoodGroup {
        let text = TextNormalizer.normalize(name, germanTransliteration: true)
        // Longest keyword wins across all groups ("milchschokolade" -> sweets).
        var best: (FoodGroup, Int)?
        for (group, words) in keywords {
            for word in words {
                let key = TextNormalizer.normalize(word, germanTransliteration: true)
                if matches(key, in: text), key.count > (best?.1 ?? 0) { best = (group, key.count) }
            }
        }
        if let best { return best.0 }

        let key = (subcategoryKey == nil || subcategoryKey == "groceries.other")
            ? (GroceryItemClassifier.classify(name)?.subcategoryKey ?? subcategoryKey)
            : subcategoryKey
        switch key {
        case "groceries.vegetables": return .vegetables
        case "groceries.fruits": return .fruits
        case "groceries.bakery", "groceries.grains": return .grains
        case "groceries.meat": return .meat
        case "groceries.fish": return .fish
        case "groceries.dairy": return .dairy
        case "groceries.eggs": return .eggs
        case "groceries.snacks": return .sweetsSnacks
        case "groceries.beverages": return .drinks
        case "groceries.coffee": return .drinks
        case "groceries.condiments": return .fatsCondiments
        case "groceries.frozen": return .readyMeals
        case "groceries.canned": return .other
        case "groceries.household", "groceries.cleaning", "groceries.pet": return .nonFood
        default: return .other
        }
    }
}

public enum Nutrient: String, CaseIterable, Sendable {
    case protein, fibre, vitamins, calcium, omega3

    public var title: String {
        switch self {
        case .protein: return "Protein"
        case .fibre: return "Fibre"
        case .vitamins: return "Vitamins & minerals"
        case .calcium: return "Calcium"
        case .omega3: return "Omega-3 fats"
        }
    }

    /// Where it mostly comes from (shown under the title).
    public var sources: String {
        switch self {
        case .protein: return "meat, fish, eggs, dairy, pulses"
        case .fibre: return "vegetables, fruit, wholegrain, pulses"
        case .vitamins: return "a variety of vegetables and fruit"
        case .calcium: return "milk, yoghurt, cheese"
        case .omega3: return "oily fish, walnuts, linseed"
        }
    }

    /// Ideas to add (English; the app shows its language).
    public var ideas: [String] {
        switch self {
        case .protein: return ["Eggs", "Lentils", "Quark", "Chickpeas"]
        case .fibre: return ["Wholegrain bread", "Oats", "Lentils", "Broccoli"]
        case .vitamins: return ["Peppers", "Broccoli", "Carrots", "Berries", "Apples"]
        case .calcium: return ["Yoghurt", "Cheese", "Milk"]
        case .omega3: return ["Salmon", "Herring", "Walnuts", "Linseed"]
        }
    }
}

public enum NutrientLevel: Int, Comparable, Sendable {
    case missing, low, good
    public static func < (a: NutrientLevel, b: NutrientLevel) -> Bool { a.rawValue < b.rawValue }
}

public struct FoodBalanceReport: Sendable {
    public struct Item: Sendable, Identifiable {
        public let name: String
        public let amount: Decimal
        public let group: FoodGroup
        public var id: String { "\(group.rawValue)|\(name)" }
    }

    public let foodTotal: Decimal
    public let amounts: [FoodGroup: Decimal]
    public let purchaseCount: Int
    /// Different fruit and vegetables bought.
    public let freshVariety: Int
    /// nil = too little data (scan a few receipts with items first).
    public let score: Int?
    public let nutrients: [(Nutrient, NutrientLevel)]
    /// The biggest less-healthy purchases, grouped by name.
    public let lessHealthyItems: [Item]

    public func share(_ group: FoodGroup) -> Double {
        guard foodTotal > 0 else { return 0 }
        return NSDecimalNumber(decimal: (amounts[group] ?? 0) / foodTotal).doubleValue
    }

    public func share(_ groups: [FoodGroup]) -> Double { groups.map(share).reduce(0, +) }

    public var lessHealthyShare: Double { share(FoodGroup.allCases.filter(\.isLessHealthy)) }

    public func level(_ nutrient: Nutrient) -> NutrientLevel {
        nutrients.first { $0.0 == nutrient }?.1 ?? .missing
    }
}

public enum FoodBalance {
    public static let minimumTotal: Decimal = 15
    public static let minimumPurchases = 5

    public static func report(_ purchases: [FoodPurchase]) -> FoodBalanceReport {
        var amounts: [FoodGroup: Decimal] = [:]
        var fresh = Set<String>()
        var lessHealthy: [String: (String, Decimal, FoodGroup)] = [:]
        var foodCount = 0
        for purchase in purchases where purchase.amount > 0 {
            let group = FoodGroupClassifier.group(name: purchase.name, subcategoryKey: purchase.subcategoryKey)
            amounts[group, default: 0] += purchase.amount
            guard group.isFood else { continue }
            foodCount += 1
            let key = ItemRuleKey.make(purchase.name)
            if group == .vegetables || group == .fruits, !key.isEmpty {
                fresh.insert(key.split(separator: " ").first.map(String.init) ?? key)
            }
            if group.isLessHealthy {
                let old = lessHealthy[key] ?? (purchase.name, 0, group)
                lessHealthy[key] = (old.0, old.1 + purchase.amount, group)
            }
        }
        let foodTotal = amounts.filter { $0.key.isFood }.values.reduce(0, +)

        func share(_ groups: [FoodGroup]) -> Double {
            guard foodTotal > 0 else { return 0 }
            let sum = groups.compactMap { amounts[$0] }.reduce(Decimal(0), +)
            return NSDecimalNumber(decimal: sum / foodTotal).doubleValue
        }
        func has(_ group: FoodGroup) -> Bool { (amounts[group] ?? 0) > 0 }

        // Nutrients (from food groups, by spend).
        let proteinShare = share([.meat, .fish, .eggs, .dairy, .legumesNuts])
        let fibreShare = share([.vegetables, .fruits, .wholeGrains, .legumesNuts])
        let freshShare = share([.vegetables, .fruits])
        let nutrients: [(Nutrient, NutrientLevel)] = [
            (.protein, proteinShare >= 0.2 ? .good : (proteinShare > 0 ? .low : .missing)),
            (.fibre, fibreShare >= 0.3 && (has(.wholeGrains) || has(.legumesNuts)) ? .good : (fibreShare > 0 ? .low : .missing)),
            (.vitamins, freshShare >= 0.25 && fresh.count >= 4 ? .good : (freshShare > 0 ? .low : .missing)),
            (.calcium, share([.dairy]) >= 0.06 ? .good : (has(.dairy) ? .low : .missing)),
            (.omega3, has(.fish) ? .good : (has(.legumesNuts) ? .low : .missing))
        ]

        // Score 0...100: 25 base + up to 75 for good choices - up to 40 for less healthy ones.
        var score: Int?
        if foodTotal >= minimumTotal, foodCount >= minimumPurchases {
            var points = 25.0
            points += min(freshShare / 0.35, 1) * 35
            let proteinKinds = [FoodGroup.meat, .fish, .eggs, .dairy, .legumesNuts].filter(has).count
            points += Double(min(proteinKinds, 4)) / 4 * 15
            points += min(share([.wholeGrains, .legumesNuts]) / 0.08, 1) * 10
            points += has(.fish) ? 5 : 0
            points += min(Double(fresh.count) / 6, 1) * 10
            let less = share(FoodGroup.allCases.filter(\.isLessHealthy))
            points -= min(less / 0.4, 1) * 40
            score = Int(max(0, min(100, points)).rounded())
        }

        let items = lessHealthy.values
            .map { FoodBalanceReport.Item(name: $0.0, amount: $0.1, group: $0.2) }
            .sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.name < $1.name }
        return FoodBalanceReport(foodTotal: foodTotal, amounts: amounts, purchaseCount: foodCount, freshVariety: fresh.count,
                                 score: score, nutrients: nutrients, lessHealthyItems: Array(items.prefix(8)))
    }

    /// "Very balanced", "Good", "Could be better", "Unbalanced".
    public static func rating(_ score: Int) -> String {
        switch score {
        case 75...: return "Very balanced"
        case 55..<75: return "Good"
        case 35..<55: return "Could be better"
        default: return "Unbalanced"
        }
    }

    /// Scores per calendar month (oldest first), for the trend chart.
    public static func monthlyScores(_ purchases: [FoodPurchase], months: Int, endingAt now: Date, calendar: Calendar) -> [(month: Date, score: Int?)] {
        guard let current = calendar.dateInterval(of: .month, for: now) else { return [] }
        return (0..<months).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .month, value: -back, to: current.start),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            let inMonth = purchases.filter { $0.date >= start && $0.date < end }
            return (start, report(inMonth).score)
        }
    }
}
