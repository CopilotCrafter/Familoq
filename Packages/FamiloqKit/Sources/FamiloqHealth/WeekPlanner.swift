import Foundation
import FamiloqCore
import FamiloqBudget

/// Small deterministic random generator (same seed = same plan, testable).
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

/// Fills the empty dinners of a week from the catalogue.
public enum WeekPlanner {
    public struct Day: Sendable {
        public var date: Date
        public var isWeekend: Bool
        public init(date: Date, isWeekend: Bool) {
            self.date = date
            self.isWeekend = isWeekend
        }
    }

    public struct Request: Sendable {
        public var days: [Day]
        public var cuisines: [CuisinePreference]
        public var profile: DietProfile
        /// dish ID -> family rating (thumbs up +1, down -1, summed).
        public var ratings: [String: Double]
        /// Dishes of the last 3 weeks (not repeated).
        public var recentDishIDs: Set<String>
        /// Dishes already planned in this week (kept in the balance).
        public var alreadyPlanned: [Dish]
        /// Pantry item names - dishes using them come first.
        public var pantryWords: [String]
        public var vegetarianDays: Int
        public var weekdayMinutes: Int
        public var month: Int
        public var seed: UInt64

        public init(days: [Day], cuisines: [CuisinePreference], profile: DietProfile, ratings: [String: Double] = [:],
                    recentDishIDs: Set<String> = [], alreadyPlanned: [Dish] = [], pantryWords: [String] = [],
                    vegetarianDays: Int = 1, weekdayMinutes: Int = 40, month: Int, seed: UInt64) {
            self.days = days
            self.cuisines = cuisines
            self.profile = profile
            self.ratings = ratings
            self.recentDishIDs = recentDishIDs
            self.alreadyPlanned = alreadyPlanned
            self.pantryWords = pantryWords
            self.vegetarianDays = vegetarianDays
            self.weekdayMinutes = weekdayMinutes
            self.month = month
            self.seed = seed
        }
    }

    public struct Planned: Sendable {
        public let date: Date
        public let dish: Dish
    }

    /// Candidates: allowed by the strict rules, in the chosen cuisines, not lunchbox-only.
    public static func pool(_ request: Request, catalogue: [Dish] = DishCatalogue.all) -> [Dish] {
        let chosen = Set(request.cuisines.prefix(4).map(\.cuisine))
        return catalogue.filter { dish in
            !dish.has(.lunchboxOnly) && (chosen.isEmpty || chosen.contains(dish.cuisine)) && request.profile.allows(dish)
        }
    }

    public static func plan(_ request: Request, catalogue: [Dish] = DishCatalogue.all) -> [Planned] {
        let candidates = pool(request, catalogue: catalogue)
        guard !candidates.isEmpty, !request.days.isEmpty else { return [] }
        var random = SeededRandom(seed: request.seed)
        let sequence = request.cuisines.isEmpty ? [] : CuisinePreference.sequence(request.cuisines, days: request.days.count)
        var state = Balance(request.alreadyPlanned)
        var used = Set(request.alreadyPlanned.map(\.id))
        var result: [Planned] = []
        for (index, day) in request.days.enumerated() {
            let cuisine = index < sequence.count ? sequence[index] : nil
            var options = candidates.filter { !used.contains($0.id) && (cuisine == nil || $0.cuisine == cuisine) }
            if options.isEmpty { options = candidates.filter { !used.contains($0.id) } }
            if options.isEmpty { options = candidates }
            let daysLeft = request.days.count - index
            let previous = result.last?.dish
            var best: (dish: Dish, score: Double)?
            for option in options {
                let value = score(option, day: day, request: request, state: state, daysLeft: daysLeft, previous: previous, random: &random)
                if best == nil || value > best!.score { best = (option, value) }
            }
            guard let dish = best?.dish else { continue }
            used.insert(dish.id)
            state.add(dish)
            result.append(Planned(date: day.date, dish: dish))
        }
        return result
    }

    /// Other good choices for one day ("Swap").
    public static func alternatives(for day: Day, request: Request, excluding: Set<String>, count: Int = 6,
                                    catalogue: [Dish] = DishCatalogue.all) -> [Dish] {
        var random = SeededRandom(seed: request.seed)
        let state = Balance(request.alreadyPlanned)
        var scored: [(dish: Dish, score: Double)] = []
        for dish in pool(request, catalogue: catalogue) where !excluding.contains(dish.id) {
            scored.append((dish, score(dish, day: day, request: request, state: state, daysLeft: 1, previous: nil, random: &random)))
        }
        scored.sort { $0.score > $1.score }
        return scored.prefix(count).map(\.dish)
    }

    struct Balance {
        var fish = 0, pulses = 0, vegetarian = 0, redMeat = 0, processed = 0, fried = 0

        init(_ dishes: [Dish]) { dishes.forEach { add($0) } }

        mutating func add(_ dish: Dish) {
            if dish.hasFish { fish += 1 }
            if dish.hasLegumes { pulses += 1 }
            if dish.isVegetarian { vegetarian += 1 }
            if dish.hasRedMeat { redMeat += 1 }
            if dish.has(.processedMeat) { processed += 1 }
            if dish.has(.fried) { fried += 1 }
        }
    }

    static func score(_ dish: Dish, day: Day, request: Request, state: Balance, daysLeft: Int, previous: Dish?,
                      random: inout SeededRandom) -> Double {
        var s = 1.0
        // Regions of the chosen cuisine.
        if let pref = request.cuisines.first(where: { $0.cuisine == dish.cuisine }), !pref.regions.isEmpty,
           !Set(pref.regions).isDisjoint(with: dish.regions) {
            s += 0.6
        }
        s += request.profile.fit(dish)
        s += 0.5 * max(-2, min(2, request.ratings[dish.id] ?? 0))
        if request.recentDishIDs.contains(dish.id) { s -= 2 }
        // Weekly balance: fish once, pulses twice, vegetarian days, not too much meat.
        if state.fish == 0 && dish.hasFish { s += daysLeft <= 3 ? 1.2 : 0.6 }
        if state.pulses < 2 && dish.hasLegumes { s += daysLeft <= 3 ? 0.9 : 0.5 }
        if state.vegetarian < request.vegetarianDays && dish.isVegetarian { s += daysLeft <= 3 ? 1.0 : 0.5 }
        if state.redMeat >= 2 && dish.hasRedMeat { s -= 0.8 }
        if state.processed >= 1 && dish.has(.processedMeat) { s -= 1.0 }
        if state.fried >= 1 && dish.has(.fried) { s -= 0.6 }
        if dish.has(.vegetableRich) { s += 0.3 }
        if let previous {
            if !previous.proteins.isDisjoint(with: dish.proteins) { s -= 0.3 }
            if previous.base == dish.base { s -= 0.2 }
        }
        // Time: quick on weekdays.
        if !day.isWeekend {
            if dish.minutes > request.weekdayMinutes { s -= dish.minutes > 75 ? 1.4 : 0.6 }
        } else if dish.minutes >= 60 {
            s += 0.2
        }
        // Season.
        if !dish.seasonMonths.isEmpty {
            s += dish.isInSeason(month: request.month) ? 0.4 : -1.5
        }
        // Use what is at home.
        if !request.pantryWords.isEmpty {
            let text = TextNormalizer.normalize(dish.ingredients.joined(separator: " "), germanTransliteration: true)
            let hits = request.pantryWords.filter { word in
                let key = TextNormalizer.normalize(word, germanTransliteration: true)
                return key.count >= 4 && text.contains(key)
            }.count
            s += min(0.9, 0.3 * Double(hits))
        }
        if dish.has(.sweet) { s -= 0.5 }
        s += random.unit() * 0.35
        return s
    }
}

/// How balanced a week of meals is (0-100) - planned or catalogue-matched.
public struct MealTraits: Sendable, Equatable {
    public var fish = false
    public var pulses = false
    public var vegetarian = false
    public var redMeat = false
    public var processedMeat = false
    public var vegetableRich = false
    public var fried = false
    public var sweet = false
    public var wholegrain = false

    public init() {}

    public init(dish: Dish) {
        fish = dish.hasFish
        pulses = dish.hasLegumes
        vegetarian = dish.isVegetarian
        redMeat = dish.hasRedMeat
        processedMeat = dish.has(.processedMeat)
        vegetableRich = dish.has(.vegetableRich)
        fried = dish.has(.fried)
        sweet = dish.has(.sweet)
        wholegrain = dish.base == .wholegrain
    }

    /// From a recipe's ingredient lines.
    public init(ingredients: [String]) {
        var vegetables = 0
        for line in ingredients {
            switch FoodGroupClassifier.group(name: line, subcategoryKey: nil) {
            case .fish: fish = true
            case .legumesNuts: pulses = true
            case .meat: redMeat = true
            case .processedMeat: processedMeat = true
            case .vegetables: vegetables += 1
            case .wholeGrains: wholegrain = true
            case .sweetsSnacks: sweet = true
            default: break
            }
        }
        vegetableRich = vegetables >= 2
        vegetarian = !fish && !redMeat && !processedMeat
    }
}

public enum MealPlanBalance {
    public enum Note: Sendable, Equatable {
        case noFish, fewPulses, muchMeat(Int), processedMeat(Int), fewVegetables
    }

    public struct Result: Sendable {
        public let score: Int
        public let notes: [Note]
    }

    public static func check(_ meals: [MealTraits]) -> Result? {
        guard meals.count >= 3 else { return nil }
        let n = Double(meals.count)
        var score = 50.0
        var notes: [Note] = []
        let fish = meals.filter(\.fish).count
        let pulses = meals.filter(\.pulses).count
        let vegetarian = meals.filter(\.vegetarian).count
        let red = meals.filter(\.redMeat).count
        let processed = meals.filter(\.processedMeat).count
        let fried = meals.filter(\.fried).count
        let vegRich = meals.filter(\.vegetableRich).count
        let vegShare = Double(vegRich) / n
        score += fish >= 1 ? 10 : 0
        score += Double(min(pulses, 2)) * 7
        score += Double(min(vegetarian, 3)) * 4
        score += vegShare * 20
        score -= Double(max(0, red - 2)) * 8
        score -= Double(processed) * 8
        score -= Double(max(0, fried - 1)) * 6
        if fish == 0 { notes.append(.noFish) }
        if pulses < 2 { notes.append(.fewPulses) }
        if red > 2 { notes.append(.muchMeat(red)) }
        if processed > 0 { notes.append(.processedMeat(processed)) }
        if vegShare < 0.5 { notes.append(.fewVegetables) }
        let clamped = max(0, min(100, score))
        return Result(score: Int(clamped.rounded()), notes: notes)
    }
}
