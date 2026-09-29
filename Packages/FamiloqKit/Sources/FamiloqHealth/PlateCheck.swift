import Foundation
import FamiloqCore

/// What is on a photographed plate (the user confirms or corrects it).
public enum PlatePart: String, CaseIterable, Codable, Sendable, Identifiable {
    case vegetables, fruit, wholegrain, refinedCarbs, legumes, leanProtein, redMeat, processedMeat
    case fried, creamyCheesy, sweets, sugaryDrink

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .vegetables: return "Vegetables & salad"
        case .fruit: return "Fruit"
        case .wholegrain: return "Wholegrain"
        case .refinedCarbs: return "White rice, pasta, bread, potatoes"
        case .legumes: return "Pulses & tofu"
        case .leanProtein: return "Fish, chicken, eggs"
        case .redMeat: return "Red meat"
        case .processedMeat: return "Sausage & ham"
        case .fried: return "Fried food"
        case .creamyCheesy: return "Cream, cheese & butter sauces"
        case .sweets: return "Dessert & sweets"
        case .sugaryDrink: return "Sweet drink"
        }
    }

    public var icon: String {
        switch self {
        case .vegetables: return "carrot.fill"
        case .fruit: return "applelogo"
        case .wholegrain: return "leaf.fill"
        case .refinedCarbs: return "takeoutbag.and.cup.and.straw.fill"
        case .legumes: return "circle.grid.3x3.fill"
        case .leanProtein: return "fish.fill"
        case .redMeat: return "fork.knife"
        case .processedMeat: return "exclamationmark.triangle.fill"
        case .fried: return "flame.fill"
        case .creamyCheesy: return "drop.fill"
        case .sweets: return "birthday.cake.fill"
        case .sugaryDrink: return "cup.and.saucer.fill"
        }
    }

    public var isLessHealthy: Bool {
        [.processedMeat, .fried, .creamyCheesy, .sweets, .sugaryDrink].contains(self)
    }

    /// Image labels (Apple's image classifier or Apple Intelligence, English
    /// or German) -> plate part. Longest keyword wins.
    static let keywords: [(PlatePart, [String])] = [
        (.vegetables, ["salad", "salat", "broccoli", "brokkoli", "vegetable", "gemuse", "spinach", "spinat", "tomato", "tomate",
                       "cucumber", "gurke", "carrot", "karotte", "pepper", "paprika", "cabbage", "kohl", "zucchini", "aubergine",
                       "eggplant", "cauliflower", "blumenkohl", "asparagus", "spargel", "mushroom", "pilz", "lettuce", "bean sprout",
                       "green bean", "okra", "sauerkraut", "coleslaw", "ratatouille", "curry vegetable"]),
        (.fruit, ["fruit", "obst", "apple", "apfel", "banana", "banane", "berry", "beere", "orange", "grape", "traube", "mango",
                  "melon", "melone", "kiwi", "pineapple", "ananas"]),
        (.wholegrain, ["wholegrain", "whole grain", "vollkorn", "brown rice", "naturreis", "oat", "hafer", "quinoa", "bulgur",
                       "millet", "hirse", "rye", "roggen", "muesli", "musli"]),
        (.refinedCarbs, ["rice", "reis", "pasta", "noodle", "nudel", "spaghetti", "bread", "brot", "baguette", "potato", "kartoffel",
                         "naan", "roti", "chapati", "tortilla", "couscous", "dumpling", "knodel", "spatzle", "pizza", "bun", "bagel",
                         "croissant", "dosa", "idli", "risotto", "lasagna", "lasagne", "ramen", "sushi"]),
        (.legumes, ["lentil", "linse", "dal", "dhal", "chickpea", "kichererbse", "bean", "bohne", "tofu", "hummus", "falafel", "pea", "erbse"]),
        (.leanProtein, ["fish", "fisch", "salmon", "lachs", "tuna", "thunfisch", "chicken", "huhn", "hahnchen", "turkey", "pute",
                        "egg", "ei", "omelette", "shrimp", "garnele", "prawn", "seafood", "cod", "kabeljau"]),
        (.redMeat, ["beef", "rind", "steak", "lamb", "lamm", "pork", "schwein", "meatball", "hackfleisch", "burger", "roast", "braten",
                    "gulasch", "goulash", "kebab", "doner"]),
        (.processedMeat, ["sausage", "wurst", "bratwurst", "hot dog", "salami", "ham", "schinken", "bacon", "speck", "currywurst",
                          "leberkase", "pepperoni"]),
        (.fried, ["fries", "pommes", "french fries", "fried", "frittiert", "schnitzel", "nugget", "tempura", "pakora", "samosa",
                  "chips", "onion ring", "fish and chips", "bhature", "doughnut"]),
        (.creamyCheesy, ["cheese", "kase", "cream", "sahne", "carbonara", "alfredo", "butter chicken", "hollandaise", "gratin",
                         "mac and cheese", "fondue", "raclette", "cheesecake", "quiche", "spatzle"]),
        (.sweets, ["cake", "kuchen", "torte", "dessert", "ice cream", "eis", "chocolate", "schokolade", "cookie", "keks", "pudding",
                   "waffle", "waffel", "pancake", "pfannkuchen", "donut", "muffin", "tiramisu", "brownie", "candy", "kaiserschmarrn"]),
        (.sugaryDrink, ["soda", "cola", "lemonade", "limonade", "juice", "saft", "soft drink", "milkshake", "energy drink"])
    ]

    public static func guess(label: String) -> PlatePart? {
        let text = TextNormalizer.normalize(label.replacingOccurrences(of: "_", with: " "), germanTransliteration: true)
        var best: (PlatePart, Int)?
        for (part, words) in keywords {
            for word in words {
                let key = TextNormalizer.normalize(word, germanTransliteration: true)
                let hit = key.count <= 3
                    ? text.split(separator: " ").contains { String($0) == key || String($0) == key + "s" }
                    : text.contains(key)
                if hit, key.count > (best?.1 ?? 0) { best = (part, key.count) }
            }
        }
        return best?.0
    }
}

/// Plate balance compared with the healthy-plate model: half vegetables,
/// a quarter protein, a quarter (wholegrain) carbohydrates.
public enum PlateScore {
    public enum Note: String, Sendable {
        case moreVegetables, addProtein, bigCarbPortion, chooseWholegrain, lessFried, lessProcessed, lessCreamy, sweetExtras, great
    }

    public struct Result: Sendable {
        public let score: Int
        public let notes: [Note]
        /// Conditions of the family this plate is a concern for.
        public let concerns: [(HealthCondition, PlatePart)]
    }

    /// - Parameter shares: part -> share of the plate (any scale; normalised).
    public static func evaluate(_ shares: [PlatePart: Double], conditions: Set<HealthCondition> = []) -> Result {
        let total = shares.values.reduce(0, +)
        guard total > 0 else { return Result(score: 0, notes: [], concerns: []) }
        func share(_ part: PlatePart) -> Double { (shares[part] ?? 0) / total }
        let veg = share(.vegetables) + share(.fruit) * 0.5
        let protein = share(.leanProtein) + share(.legumes) + share(.redMeat) * 0.6
        let carbs = share(.wholegrain) + share(.refinedCarbs)
        let unhealthy = share(.fried) + share(.processedMeat) + share(.creamyCheesy) + share(.sweets) + share(.sugaryDrink)

        var score = 20.0
        score += min(veg / 0.5, 1) * 40
        score += min(protein / 0.25, 1) * 20
        if carbs > 0 {
            let wholeRatio = share(.wholegrain) / carbs
            let sizeFactor = carbs <= 0.35 ? 1.0 : max(0, 1 - (carbs - 0.35) * 3)
            score += 20 * sizeFactor * (0.6 + 0.4 * wholeRatio)
        } else {
            score += 12
        }
        score -= unhealthy * 80
        score -= share(.redMeat) * 20
        let value = Int(max(0, min(100, score)).rounded())

        var notes: [Note] = []
        if veg < 0.35 { notes.append(.moreVegetables) }
        if protein < 0.12 { notes.append(.addProtein) }
        if carbs > 0.4 { notes.append(.bigCarbPortion) }
        if share(.refinedCarbs) > 0.2 && share(.wholegrain) == 0 { notes.append(.chooseWholegrain) }
        if share(.fried) > 0.1 { notes.append(.lessFried) }
        if share(.processedMeat) > 0.05 { notes.append(.lessProcessed) }
        if share(.creamyCheesy) > 0.1 { notes.append(.lessCreamy) }
        if share(.sweets) + share(.sugaryDrink) > 0.05 { notes.append(.sweetExtras) }
        if notes.isEmpty && value >= 75 { notes.append(.great) }

        var concerns: [(HealthCondition, PlatePart)] = []
        func concern(_ condition: HealthCondition, _ part: PlatePart, _ threshold: Double) {
            if conditions.contains(condition) && share(part) > threshold { concerns.append((condition, part)) }
        }
        for c in conditions.sorted(by: { $0.rawValue < $1.rawValue }) {
            switch c {
            case .highBloodPressure, .heartDisease, .kidneyDisease:
                concern(c, .processedMeat, 0.05); concern(c, .fried, 0.15)
            case .diabetesType2, .diabetesType1:
                concern(c, .refinedCarbs, 0.3); concern(c, .sweets, 0.03); concern(c, .sugaryDrink, 0.01)
            case .highCholesterol:
                concern(c, .fried, 0.1); concern(c, .creamyCheesy, 0.1); concern(c, .processedMeat, 0.05); concern(c, .redMeat, 0.25)
            case .highTriglycerides, .fattyLiver:
                concern(c, .sweets, 0.03); concern(c, .sugaryDrink, 0.01); concern(c, .refinedCarbs, 0.35); concern(c, .fried, 0.1)
            case .gout:
                concern(c, .redMeat, 0.2); concern(c, .processedMeat, 0.05); concern(c, .sugaryDrink, 0.01)
            case .weightGoal:
                concern(c, .fried, 0.1); concern(c, .sweets, 0.05); concern(c, .creamyCheesy, 0.1); concern(c, .refinedCarbs, 0.35)
            case .reflux:
                concern(c, .fried, 0.1); concern(c, .creamyCheesy, 0.15)
            default:
                break
            }
        }
        return Result(score: value, notes: notes, concerns: concerns)
    }
}
