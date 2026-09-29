import Foundation
import SwiftData
import FamiloqCore
import FamiloqBudget
import FamiloqPlanner
import FamiloqHealth

@MainActor
enum MealSettingsService {
    /// The family's meal settings (created with defaults on first use).
    static func preferences(familyID: UUID, context: ModelContext) -> MealPreferences {
        let id = MealPreferences.preferencesID(familyID: familyID)
        var descriptor = FetchDescriptor<MealPreferences>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first { return existing }
        let prefs = MealPreferences(id: id, familyID: familyID)
        // Old date: settings made on another iPhone win.
        prefs.updatedAt = Date(timeIntervalSince1970: 0)
        context.insert(prefs)
        try? context.save()
        return prefs
    }
}

/// Everything the Meals screen does with the data.
@MainActor
enum MealPlanService {
    /// Key used for ratings: catalogue dish, recipe or typed title.
    static func dishKey(for entry: MealPlanEntry) -> String {
        if !entry.dishID.isEmpty { return entry.dishID }
        if let recipeID = entry.recipeID { return "recipe:" + recipeID.uuidString }
        return "title:" + TextNormalizer.normalize(entry.title, germanTransliteration: true)
    }

    /// The catalogue dish of an entry (by ID, or a matching typed name).
    static func dish(for entry: MealPlanEntry) -> Dish? {
        if !entry.dishID.isEmpty { return DishCatalogue.byID[entry.dishID] }
        return entry.recipeID == nil ? DishCatalogue.match(title: entry.title) : nil
    }

    /// Family rating per dish key (sum of +1/-1).
    static func ratings(familyID: UUID, context: ModelContext) -> [String: Double] {
        let fid = familyID
        let all = (try? context.fetch(FetchDescriptor<MealRating>(predicate: #Predicate { $0.familyID == fid }))) ?? []
        var result: [String: Double] = [:]
        for rating in all { result[rating.dishKey, default: 0] += Double(rating.value) }
        return result
    }

    static func myRating(dishKey: String, familyID: UUID, memberID: UUID?, context: ModelContext) -> Int {
        guard let memberID else { return 0 }
        let id = MealRating.ratingID(familyID: familyID, dishKey: dishKey, memberID: memberID)
        var descriptor = FetchDescriptor<MealRating>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).first?.value) ?? 0
    }

    /// Thumbs up (+1) / down (-1); tapping the same again removes it.
    static func rate(dishKey: String, value: Int, familyID: UUID, memberID: UUID?, context: ModelContext) {
        guard let memberID else { return }
        let id = MealRating.ratingID(familyID: familyID, dishKey: dishKey, memberID: memberID)
        var descriptor = FetchDescriptor<MealRating>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.value = existing.value == value ? 0 : value
            existing.updatedAt = Date()
        } else {
            context.insert(MealRating(id: id, familyID: familyID, dishKey: dishKey, memberID: memberID, value: value))
        }
        try? context.save()
    }

    /// Catalogue dishes of the last 3 weeks (not repeated by "Plan my week").
    static func recentDishIDs(familyID: UUID, before day: Date, context: ModelContext) -> Set<String> {
        let fid = familyID
        let from = PlannerDates.calendar.date(byAdding: .day, value: -21, to: day) ?? day
        let meals = (try? context.fetch(FetchDescriptor<MealPlanEntry>(predicate: #Predicate { $0.familyID == fid && $0.day >= from && $0.day < day }))) ?? []
        return Set(meals.map(\.dishID).filter { !$0.isEmpty })
    }

    static func pantryWords(familyID: UUID, context: ModelContext) -> [String] {
        let fid = familyID
        let items = (try? context.fetch(FetchDescriptor<PantryItem>(predicate: #Predicate { $0.familyID == fid }))) ?? []
        return items.map(\.name)
    }

    static func request(family: Family, days: [WeekPlanner.Day], already: [Dish], context: ModelContext) -> WeekPlanner.Request {
        let prefs = MealSettingsService.preferences(familyID: family.id, context: context)
        let calendar = PlannerDates.calendar
        let first = days.first?.date ?? Date()
        let seed = UInt64(abs(Int(first.timeIntervalSince1970 / 86_400))) &* 31 &+ UInt64(family.id.uuid.0)
        return WeekPlanner.Request(
            days: days,
            cuisines: prefs.cuisines,
            profile: HealthService.dietProfile(familyID: family.id, context: context),
            ratings: ratings(familyID: family.id, context: context),
            recentDishIDs: recentDishIDs(familyID: family.id, before: first, context: context),
            alreadyPlanned: already,
            pantryWords: pantryWords(familyID: family.id, context: context),
            vegetarianDays: prefs.vegetarianDays,
            weekdayMinutes: prefs.weekdayMinutes,
            month: calendar.component(.month, from: first),
            seed: seed)
    }

    /// Fills the empty dinners of the week. Returns how many were planned.
    @discardableResult
    static func planWeek(family: Family, weekStart: Date, existing: [MealPlanEntry], context: ModelContext, reshuffle: Int = 0) -> Int {
        let calendar = PlannerDates.calendar
        let today = calendar.startOfDay(for: Date())
        let dinners = existing.filter { $0.slot == .dinner }
        var days: [WeekPlanner.Day] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart), day >= today else { continue }
            if dinners.contains(where: { calendar.isDate($0.day, inSameDayAs: day) }) { continue }
            days.append(WeekPlanner.Day(date: day, isWeekend: calendar.isDateInWeekend(day)))
        }
        guard !days.isEmpty else { return 0 }
        var request = request(family: family, days: days, already: dinners.compactMap(dish(for:)), context: context)
        request.seed &+= UInt64(reshuffle)
        let plan = WeekPlanner.plan(request)
        for item in plan {
            let entry = MealPlanEntry(familyID: family.id, day: calendar.startOfDay(for: item.date), slot: .dinner, title: item.dish.name)
            entry.dishID = item.dish.id
            context.insert(entry)
        }
        try? context.save()
        return plan.count
    }

    /// Ingredient lines of an entry, scaled for guests / cook double.
    static func ingredients(for entry: MealPlanEntry, recipes: [UUID: Recipe], familySize: Int) -> [String] {
        guard !entry.isLeftover else { return [] }
        var lines: [String] = []
        var base = 4
        if let recipeID = entry.recipeID, let recipe = recipes[recipeID] {
            lines = recipe.ingredients
            base = max(1, recipe.servings)
        } else if let dish = dish(for: entry) {
            lines = dish.ingredients
        }
        var people = entry.servings > 0 ? entry.servings : max(familySize, 1)
        if entry.servings == 0 && familySize <= 0 { people = base }
        var factor = Double(people) / Double(base)
        if entry.cookDouble { factor *= 2 }
        // Close to the recipe size: keep the recipe amounts.
        if abs(factor - 1) < 0.2 { factor = 1 }
        return lines.map { IngredientScaler.scale($0, by: factor) }
    }

    /// Puts ingredients on the shopping list; items already in the pantry are skipped.
    static func addToShoppingList(_ entries: [MealPlanEntry], recipes: [UUID: Recipe], familySize: Int,
                                  family: Family, memberID: UUID?, context: ModelContext) -> (added: Int, skipped: [String]) {
        guard let list = ShoppingService.lists(familyID: family.id, context: context).first else { return (0, []) }
        let lines = entries.flatMap { ingredients(for: $0, recipes: recipes, familySize: familySize) }
        let pantry = pantryWords(familyID: family.id, context: context).map { ShoppingEntryParser.key($0) }.filter { !$0.isEmpty }
        var skipped: [String] = []
        var added = 0
        for entry in MealIngredients.merged(lines) {
            let key = ShoppingEntryParser.key(entry.name)
            if pantry.contains(where: { key.contains($0) || $0.contains(key) }) {
                skipped.append(entry.name)
                continue
            }
            if ShoppingService.add(entry: entry, listID: list.id, familyID: family.id, memberID: memberID, context: context) != nil {
                added += 1
            }
        }
        return (added, skipped)
    }

    /// Traits of the week's meals for the balance check.
    static func traits(_ entries: [MealPlanEntry], recipes: [UUID: Recipe]) -> [MealTraits] {
        entries.filter { !$0.isLeftover && $0.slot != .breakfast }.compactMap { entry in
            if let dish = dish(for: entry) { return MealTraits(dish: dish) }
            if let recipeID = entry.recipeID, let recipe = recipes[recipeID], !recipe.ingredients.isEmpty {
                return MealTraits(ingredients: recipe.ingredients)
            }
            return nil
        }
    }

    /// Adds "Leftovers: X" the next day (lunch when lunches are planned, else dinner).
    static func addLeftovers(of entry: MealPlanEntry, planLunch: Bool, context: ModelContext) {
        let calendar = PlannerDates.calendar
        guard let next = calendar.date(byAdding: .day, value: 1, to: entry.day) else { return }
        let leftover = MealPlanEntry(familyID: entry.familyID, day: next, slot: planLunch ? .lunch : .dinner,
                                     title: String(localized: "Leftovers: \(entry.title)"))
        leftover.isLeftover = true
        leftover.dishID = entry.dishID
        leftover.recipeID = entry.recipeID
        context.insert(leftover)
    }

    /// Lunchbox ideas: leftovers of yesterday's dinner, then lunchbox dishes.
    static func lunchboxIdeas(family: Family, day: Date, context: ModelContext) -> [Dish] {
        let prefs = MealSettingsService.preferences(familyID: family.id, context: context)
        let profile = HealthService.dietProfile(familyID: family.id, context: context)
        let cuisines = Set(prefs.cuisines.map(\.cuisine))
        let candidates = DishCatalogue.all.filter { dish in
            dish.has(.lunchbox) && profile.allows(dish) && (cuisines.isEmpty || cuisines.contains(dish.cuisine) || dish.has(.lunchboxOnly))
        }
        var random = SeededRandom(seed: UInt64(abs(Int(day.timeIntervalSince1970 / 86_400))))
        return candidates.shuffled(using: &random).prefix(6).map { $0 }
    }
}
