import Foundation
import SwiftData
import FamiloqCore
import FamiloqBudget
import FamiloqPlanner
import FamiloqHealth

@MainActor
enum MealSettingsService {
    /// The saved settings, if any (does not create them - safe while drawing a view).
    static func existing(familyID: UUID, context: ModelContext) -> MealPreferences? {
        let id = MealPreferences.preferencesID(familyID: familyID)
        var descriptor = FetchDescriptor<MealPreferences>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

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

    static func request(family: Family, days: [WeekPlanner.Day], already: [Dish], context: ModelContext,
                        slot: PlanSlot = .dinner) -> WeekPlanner.Request {
        let prefs = MealSettingsService.existing(familyID: family.id, context: context)
        let calendar = PlannerDates.calendar
        let first = days.first?.date ?? Date()
        let seed = UInt64(abs(Int(first.timeIntervalSince1970 / 86_400))) &* 31 &+ UInt64(family.id.uuid.0)
        return WeekPlanner.Request(
            days: days,
            cuisines: prefs?.cuisines ?? [],
            profile: HealthService.dietProfile(familyID: family.id, context: context),
            ratings: ratings(familyID: family.id, context: context),
            recentDishIDs: recentDishIDs(familyID: family.id, before: first, context: context),
            alreadyPlanned: already,
            pantryWords: pantryWords(familyID: family.id, context: context),
            vegetarianDays: prefs?.vegetarianDays ?? 1,
            weekdayMinutes: prefs?.weekdayMinutes ?? 40,
            month: calendar.component(.month, from: first),
            seed: seed,
            slot: slot)
    }

    static func planSlot(_ slot: MealSlot) -> PlanSlot {
        switch slot {
        case .breakfast: return .breakfast
        case .lunch: return .lunch
        case .dinner: return .dinner
        }
    }

    /// Fills the empty meals of the week from today: dinners, then lunches
    /// and breakfasts when they are planned. Returns how many were planned.
    @discardableResult
    static func planWeek(family: Family, weekStart: Date, existing: [MealPlanEntry], context: ModelContext,
                         slots: [MealSlot] = [.dinner], reshuffle: Int = 0) -> Int {
        let calendar = PlannerDates.calendar
        let today = calendar.startOfDay(for: Date())
        var planned: [MealPlanEntry] = existing
        var count = 0
        // Dinners first: lunches then avoid the same dishes and complete the balance.
        for slot in [MealSlot.dinner, .lunch, .breakfast] where slots.contains(slot) {
            let taken = planned.filter { $0.slot == slot }
            var days: [WeekPlanner.Day] = []
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart), day >= today else { continue }
                if taken.contains(where: { calendar.isDate($0.day, inSameDayAs: day) }) { continue }
                days.append(WeekPlanner.Day(date: day, isWeekend: calendar.isDateInWeekend(day)))
            }
            guard !days.isEmpty else { continue }
            // Balance over lunch and dinner; breakfast only avoids repeats of itself.
            let already = slot == .breakfast
                ? taken.compactMap(dish(for:))
                : planned.filter { $0.slot != .breakfast && !$0.isLeftover }.compactMap(dish(for:))
            var planRequest = request(family: family, days: days, already: already, context: context, slot: planSlot(slot))
            planRequest.seed &+= UInt64(reshuffle)
            for item in WeekPlanner.plan(planRequest) {
                let entry = MealPlanEntry(familyID: family.id, day: calendar.startOfDay(for: item.date), slot: slot, title: item.dish.name)
                entry.dishID = item.dish.id
                entry.isLunchbox = slot == .lunch && item.dish.has(.lunchboxOnly)
                context.insert(entry)
                planned.append(entry)
                count += 1
            }
        }
        try? context.save()
        return count
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
        let pantry = pantryWords(familyID: family.id, context: context).map { ShoppingEntryParser.key($0) }.filter { $0.count >= 4 }
        var skipped: [String] = []
        var added = 0
        for entry in MealIngredients.merged(lines) {
            let key = ShoppingEntryParser.key(entry.name)
            if isAtHome(key, pantry: pantry) {
                skipped.append(entry.name)
                continue
            }
            if ShoppingService.add(entry: entry, listID: list.id, familyID: family.id, memberID: memberID, context: context) != nil {
                added += 1
            }
        }
        return (added, skipped)
    }

    /// "Linsen" at home covers "Tellerlinsen"? No - only the same word or its
    /// start ("Reis" covers "Reis", "Basmatireis" is a different item; "Eis"
    /// never covers "Reis", "Milch" never "Kokosmilch").
    static func isAtHome(_ key: String, pantry: [String]) -> Bool {
        guard key.count >= 3 else { return false }
        let words = key.split(separator: " ").map(String.init)
        return pantry.contains { item in
            item == key || words.contains { $0 == item || ($0.count >= 4 && item.hasPrefix($0)) || (item.count >= 4 && $0.hasPrefix(item)) }
        }
    }

    /// Leftover entries created by "Cook double" for this meal.
    static func leftovers(of entry: MealPlanEntry, context: ModelContext) -> [MealPlanEntry] {
        let calendar = PlannerDates.calendar
        guard let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: entry.day)),
              let after = calendar.date(byAdding: .day, value: 1, to: next) else { return [] }
        let fid = entry.familyID
        let candidates = (try? context.fetch(FetchDescriptor<MealPlanEntry>(predicate: #Predicate {
            $0.familyID == fid && $0.isLeftover == true && $0.day >= next && $0.day < after
        }))) ?? []
        return candidates.filter { $0.dishID == entry.dishID && $0.recipeID == entry.recipeID }
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
        let prefs = MealSettingsService.existing(familyID: family.id, context: context)
        let profile = HealthService.dietProfile(familyID: family.id, context: context)
        let cuisines = Set((prefs?.cuisines ?? []).map(\.cuisine))
        let candidates = DishCatalogue.all.filter { dish in
            dish.has(.lunchbox) && profile.allows(dish) && (cuisines.isEmpty || cuisines.contains(dish.cuisine) || dish.has(.lunchboxOnly))
        }
        var random = SeededRandom(seed: UInt64(abs(Int(day.timeIntervalSince1970 / 86_400))))
        return candidates.shuffled(using: &random).prefix(6).map { $0 }
    }
}
