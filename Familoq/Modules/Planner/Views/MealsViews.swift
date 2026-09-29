import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqPlanner
import FamiloqHealth
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Planner → Meals: the week's meals from the family's cuisines, balanced for
/// everyone's health settings; recipes, pantry, lunchboxes and the
/// ingredients onto the shopping list with one tap.
struct MealsScreen: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var meals: [MealPlanEntry]
    @Query private var recipes: [Recipe]
    @Query private var preferences: [MealPreferences]
    @Query private var pantry: [PantryItem]
    @Query private var people: [HealthPerson]
    @Query private var members: [FamilyMember]
    @AppStorage("meals.showLunch") private var showLunch = false
    @AppStorage("meals.showBreakfast") private var showBreakfast = false
    @State private var weekStart: Date
    @State private var editing: MealEditTarget?
    @State private var showSettings = false
    @State private var ideas: [MealIdea] = []
    @State private var aiWorking = false
    @State private var reshuffle = 0

    struct MealIdea: Identifiable {
        let id = UUID()
        let name: String
        let ingredients: [String]
    }

    init(family: Family) {
        self.family = family
        let fid = family.id
        _meals = Query(filter: #Predicate<MealPlanEntry> { $0.familyID == fid }, sort: \MealPlanEntry.day)
        _recipes = Query(filter: #Predicate<Recipe> { $0.familyID == fid }, sort: \Recipe.name)
        _preferences = Query(filter: #Predicate<MealPreferences> { $0.familyID == fid })
        _pantry = Query(filter: #Predicate<PantryItem> { $0.familyID == fid })
        _people = Query(filter: #Predicate<HealthPerson> { $0.familyID == fid }, sort: \HealthPerson.sortOrder)
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid && $0.isActive == true })
        let calendar = PlannerDates.calendar
        _weekStart = State(initialValue: calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date()))
    }

    private var slots: [MealSlot] {
        MealSlot.allCases.filter { $0 == .dinner || ($0 == .lunch && showLunch) || ($0 == .breakfast && showBreakfast) }
    }

    private var days: [Date] {
        (0..<7).compactMap { PlannerDates.calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var prefs: MealPreferences? { preferences.first }
    private var familySize: Int { max(members.count, people.count, 1) }
    private var recipeByID: [UUID: Recipe] { Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }

    private var profile: DietProfile {
        DietProfile(people: people.map(\.dietPerson), avoidWords: prefs?.avoidWords ?? [],
                    maxSpice: prefs?.maxSpice ?? 3, kidFriendly: prefs?.kidFriendly ?? false)
    }

    var body: some View {
        let calendar = PlannerDates.calendar
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let weekMeals = meals.filter { $0.day >= weekStart && $0.day < weekEnd }
        let recipesByID = recipeByID
        let shoppable = weekMeals.filter { !$0.isLeftover && !MealPlanService.ingredients(for: $0, recipes: recipesByID, familySize: familySize).isEmpty }
        let balance = MealPlanBalance.check(MealPlanService.traits(weekMeals, recipes: recipesByID))
        let soonLimit = calendar.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        let soon = pantry.filter { ($0.useBy ?? .distantFuture) < soonLimit }.count

        List {
            Section {
                HStack {
                    Button { shiftWeek(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                    Spacer()
                    Text(verbatim: "\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \((calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart).formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.headline)
                    Spacer()
                    Button { shiftWeek(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
                }
                Button {
                    planWeek(weekMeals)
                } label: {
                    Label("Plan my week", systemImage: "wand.and.stars")
                }
                .disabled(weekEnd <= calendar.startOfDay(for: Date()))
                Button {
                    addIngredients(shoppable)
                } label: {
                    Label("Put this week's ingredients on the shopping list", systemImage: "cart.badge.plus")
                }
                .disabled(shoppable.isEmpty)
            } footer: {
                if (prefs?.cuisines ?? []).isEmpty {
                    Text("Tip: choose your family's cuisines in Meal settings - \"Plan my week\" then follows them.")
                } else {
                    Text(verbatim: (prefs?.cuisines ?? []).map { $0.cuisine.flag + " " + String(localized: String.LocalizationValue($0.cuisine.title)) }.joined(separator: " · "))
                }
            }

            Section {
                NavigationLink {
                    LazyView(RecipesView(family: family))
                } label: {
                    Label("Recipes (\(recipes.count))", systemImage: "book")
                }
                NavigationLink {
                    LazyView(PantryView(family: family))
                } label: {
                    HStack {
                        Label("At home (\(pantry.count))", systemImage: "refrigerator")
                        if soon > 0 {
                            Spacer()
                            Text("\(soon) use soon").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                Button {
                    showSettings = true
                } label: {
                    Label("Meal settings", systemImage: "slider.horizontal.3")
                }
            }

            if let balance {
                balanceSection(balance)
            }

            ForEach(days, id: \.self) { day in
                Section {
                    ForEach(slots, id: \.self) { slot in
                        let entries = weekMeals.filter { calendar.isDate($0.day, inSameDayAs: day) && $0.slot == slot }
                        if entries.isEmpty {
                            Button {
                                editing = MealEditTarget(entry: nil, day: day, slot: slot)
                            } label: {
                                Label(LocalizedStringKey(slot.title), systemImage: "plus").foregroundStyle(.secondary)
                            }
                        }
                        ForEach(entries) { entry in
                            mealRow(entry, slot: slot)
                        }
                    }
                } header: {
                    Text(verbatim: day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                        .foregroundStyle(calendar.isDateInToday(day) ? Color.accentColor : Color.secondary)
                }
            }

            ideasSection

            Section {
                Toggle("Plan lunch", isOn: $showLunch)
                Toggle("Plan breakfast", isOn: $showBreakfast)
            }
        }
        .sheet(item: $editing) { target in
            MealEditSheet(family: family, target: target, recipes: recipes, profile: profile, familySize: familySize,
                          planLunch: showLunch)
        }
        .sheet(isPresented: $showSettings) {
            MealSettingsSheet(family: family)
        }
    }

    private func balanceSection(_ balance: MealPlanBalance.Result) -> some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Text("\(balance.score)")
                    .font(.title2.weight(.bold)).monospacedDigit()
                    .foregroundStyle(balance.score >= 70 ? Color.green : (balance.score >= 45 ? Color.orange : Color.red))
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Week balance").font(.headline)
                    ForEach(Array(balance.notes.enumerated()), id: \.offset) { _, note in
                        Text(verbatim: Self.text(for: note)).font(.caption).foregroundStyle(.secondary)
                    }
                    if balance.notes.isEmpty {
                        Text("Well balanced: fish, pulses and plenty of vegetables.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func mealRow(_ entry: MealPlanEntry, slot: MealSlot) -> some View {
        let dish = MealPlanService.dish(for: entry)
        let tips = dish.map { profile.tips(for: $0) } ?? []
        return Button {
            editing = MealEditTarget(entry: entry, day: entry.day, slot: slot)
        } label: {
            HStack(alignment: .top) {
                Image(systemName: entry.isLunchbox ? "bag.fill" : (entry.isLeftover ? "arrow.uturn.backward.circle" : slot.icon))
                    .foregroundStyle(.orange).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: entry.title).foregroundStyle(.primary)
                    if let dish, !entry.isLeftover {
                        Text(verbatim: dish.cuisine.flag + " " + dish.description(german: Self.german))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else if entry.recipeID != nil {
                        Text("Recipe").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        if entry.servings > 0 {
                            Label("\(entry.servings)", systemImage: "person.2").font(.caption2)
                        }
                        if entry.cookDouble {
                            Label("Cook double", systemImage: "square.stack").font(.caption2)
                        }
                        if !tips.isEmpty {
                            Label("\(tips.count) tip(s)", systemImage: "heart.text.square").font(.caption2).foregroundStyle(.pink)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions {
            Button("Delete", role: .destructive) {
                context.delete(entry)
                try? context.save()
            }
        }
    }

    static var german: Bool { (Bundle.main.preferredLocalizations.first ?? "en") == "de" }

    static func text(for note: MealPlanBalance.Note) -> String {
        switch note {
        case .noFish: return String(localized: "No fish this week - one fish dinner adds omega-3 and iodine.")
        case .fewPulses: return String(localized: "Pulses (lentils, beans, chickpeas) twice a week add fibre and protein.")
        case .muchMeat(let days): return String(localized: "Meat on \(days) days - two or three is plenty.")
        case .processedMeat(let days): return String(localized: "Sausage or ham on \(days) day(s) - salty and processed.")
        case .fewVegetables: return String(localized: "Fewer than half the meals are vegetable-rich - add a salad or vegetables.")
        }
    }

    @ViewBuilder
    private var ideasSection: some View {
        if case .available = AppleIntelligence.state {
            Section {
                if ideas.isEmpty {
                    Button {
                        Task { await suggest() }
                    } label: {
                        HStack {
                            Label("New dinner ideas from Apple Intelligence", systemImage: "sparkles")
                            if aiWorking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(aiWorking)
                }
                ForEach(ideas) { idea in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: idea.name).font(.headline)
                        Text(verbatim: idea.ingredients.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        Button {
                            let recipe = Recipe(familyID: family.id, name: idea.name)
                            recipe.ingredientsText = idea.ingredients.joined(separator: "\n")
                            context.insert(recipe)
                            try? context.save()
                            ideas.removeAll { $0.id == idea.id }
                        } label: {
                            Label("Save as recipe", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("Ideas are made on this iPhone and follow your cuisines and health settings.")
            }
        }
    }

    private func shiftWeek(_ weeks: Int) {
        withAnimation {
            weekStart = PlannerDates.calendar.date(byAdding: .day, value: 7 * weeks, to: weekStart) ?? weekStart
        }
    }

    private func planWeek(_ weekMeals: [MealPlanEntry]) {
        reshuffle += 1
        let count = MealPlanService.planWeek(family: family, weekStart: weekStart, existing: weekMeals, context: context, reshuffle: reshuffle)
        session.notice = count == 0
            ? String(localized: "Every day from today already has a dinner. Delete one to plan it again.")
            : String(localized: "\(count) dinner(s) planned. Tap one to swap, rate or cook it.")
    }

    private func addIngredients(_ entries: [MealPlanEntry]) {
        let result = MealPlanService.addToShoppingList(entries, recipes: recipeByID, familySize: familySize, family: family,
                                                       memberID: session.currentMember?.id, context: context)
        if result.skipped.isEmpty {
            session.notice = String(localized: "\(result.added) ingredient(s) put on the shopping list.")
        } else {
            session.notice = String(localized: "\(result.added) ingredient(s) put on the shopping list; \(result.skipped.count) already at home.")
        }
    }

    private func suggest() async {
        aiWorking = true
        defer { aiWorking = false }
        let known = recipes.map(\.name).prefix(20).joined(separator: ", ")
        let cuisines = (prefs?.cuisines ?? []).map { pref -> String in
            let regions = pref.regions.compactMap { code in pref.cuisine.regions.first { $0.code == code }?.title }
            return pref.cuisine.title + (regions.isEmpty ? "" : " (" + regions.joined(separator: ", ") + ")")
        }.joined(separator: "; ")
        var rules = profile.conditions.map(\.guidance)
        if !profile.allergens.isEmpty { rules.append("Never use: " + profile.allergens.map(\.title).joined(separator: ", ") + ".") }
        if !profile.avoidWords.isEmpty { rules.append("Avoid: " + profile.avoidWords.joined(separator: ", ") + ".") }
        let text = (try? await AppleIntelligence.mealIdeas(knownRecipes: known, cuisines: cuisines, rules: rules.joined(separator: " "))) ?? ""
        ideas = text.split(whereSeparator: \.isNewline).compactMap { line in
            let clean = line.trimmingCharacters(in: CharacterSet(charactersIn: " -•*\t"))
            guard let colon = clean.firstIndex(of: ":") else { return nil }
            let name = clean[..<colon].trimmingCharacters(in: .whitespaces)
            let ingredients = clean[clean.index(after: colon)...].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return name.isEmpty || ingredients.isEmpty ? nil : MealIdea(name: name, ingredients: ingredients)
        }
        if ideas.isEmpty { session.notice = String(localized: "Apple Intelligence is not available right now.") }
    }
}

struct MealEditTarget: Identifiable {
    let id = UUID()
    let entry: MealPlanEntry?
    let day: Date
    let slot: MealSlot
}

/// Plan, change, swap, rate or cook one meal. Own state; writes on Save.
private struct MealEditSheet: View {
    let family: Family
    let target: MealEditTarget
    let recipes: [Recipe]
    let profile: DietProfile
    let familySize: Int
    let planLunch: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @State private var recipeID: UUID?
    @State private var dishID: String
    @State private var title: String
    @State private var note: String
    @State private var servings: Int
    @State private var cookDouble: Bool
    @State private var isLunchbox: Bool
    @State private var alternatives: [Dish] = []
    @State private var lunchIdeas: [Dish] = []
    @State private var myRating = 0
    @State private var cooking: CookingTarget?
    @State private var showPicker = false

    init(family: Family, target: MealEditTarget, recipes: [Recipe], profile: DietProfile, familySize: Int, planLunch: Bool) {
        self.family = family
        self.target = target
        self.recipes = recipes
        self.profile = profile
        self.familySize = familySize
        self.planLunch = planLunch
        _recipeID = State(initialValue: target.entry?.recipeID)
        _dishID = State(initialValue: target.entry?.dishID ?? "")
        _title = State(initialValue: target.entry?.title ?? "")
        _note = State(initialValue: target.entry?.note ?? "")
        _servings = State(initialValue: target.entry.map { $0.servings > 0 ? $0.servings : familySize } ?? familySize)
        _cookDouble = State(initialValue: target.entry?.cookDouble ?? false)
        _isLunchbox = State(initialValue: target.entry?.isLunchbox ?? false)
    }

    private var dish: Dish? { dishID.isEmpty ? (recipeID == nil ? DishCatalogue.match(title: title) : nil) : DishCatalogue.byID[dishID] }
    private var recipe: Recipe? { recipes.first { $0.id == recipeID } }

    private var dishKey: String {
        if !dishID.isEmpty { return dishID }
        if let recipeID { return "recipe:" + recipeID.uuidString }
        return "title:" + TextNormalizer.normalize(title, germanTransliteration: true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Meal, e.g. Spaghetti Bolognese", text: $title)
                    Button {
                        showPicker = true
                    } label: {
                        Label("Choose from the dish catalogue", systemImage: "books.vertical")
                    }
                    Picker("Own recipe", selection: $recipeID) {
                        Text("No recipe").tag(UUID?.none)
                        ForEach(recipes) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                    }
                    .onChange(of: recipeID) { _, id in
                        if let recipe = recipes.first(where: { $0.id == id }) {
                            title = recipe.name
                            dishID = ""
                        }
                    }
                    TextField("Note", text: $note)
                } footer: {
                    Text(verbatim: target.day.formatted(.dateTime.weekday(.wide).day().month(.wide)) + " · " + String(localized: String.LocalizationValue(target.slot.title)))
                }

                if target.slot == .lunch {
                    lunchboxSection
                }

                if let dish {
                    dishSection(dish)
                }

                Section {
                    Stepper(value: $servings, in: 1...20) {
                        Label("\(servings) people", systemImage: "person.2")
                    }
                    Toggle(isOn: $cookDouble) {
                        Label("Cook double - leftovers tomorrow", systemImage: "square.stack")
                    }
                } footer: {
                    Text("More people (guests) scale the shopping list. \"Cook double\" adds tomorrow's leftovers to the plan.")
                }

                if target.entry != nil && !title.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section("How did you like it?") {
                        HStack(spacing: 24) {
                            ratingButton(1, icon: "hand.thumbsup")
                            ratingButton(-1, icon: "hand.thumbsdown")
                            Spacer()
                        }
                    }
                }

                if dish != nil || !(recipe?.ingredients.isEmpty ?? true) {
                    Section {
                        Button {
                            cooking = CookingTarget(title: title, ingredients: currentIngredients, steps: recipe?.steps ?? [])
                        } label: {
                            Label("Cook now (step by step)", systemImage: "frying.pan")
                        }
                    }
                }

                if target.entry != nil {
                    Section {
                        Button("Delete", role: .destructive) {
                            if let entry = target.entry {
                                context.delete(entry)
                                try? context.save()
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(LocalizedStringKey(target.slot.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showPicker) {
                DishPickerSheet(profile: profile) { picked in
                    dishID = picked.id
                    title = picked.name
                    recipeID = nil
                    alternatives = []
                }
            }
            .fullScreenCover(item: $cooking) { target in
                CookingModeView(target: target)
            }
            .onAppear {
                myRating = MealPlanService.myRating(dishKey: dishKey, familyID: family.id, memberID: session.currentMember?.id, context: context)
            }
        }
    }

    private var currentIngredients: [String] {
        let base = recipe.map { max(1, $0.servings) } ?? 4
        let lines = recipe?.ingredients ?? dish?.ingredients ?? []
        var factor = Double(servings) / Double(base)
        if cookDouble { factor *= 2 }
        if abs(factor - 1) < 0.2 { factor = 1 }
        return lines.map { IngredientScaler.scale($0, by: factor) }
    }

    @ViewBuilder
    private var lunchboxSection: some View {
        Section {
            Toggle(isOn: $isLunchbox) {
                Label("Lunchbox (school / work)", systemImage: "bag")
            }
            .onChange(of: isLunchbox) { _, on in
                if on && lunchIdeas.isEmpty {
                    lunchIdeas = MealPlanService.lunchboxIdeas(family: family, day: target.day, context: context)
                }
            }
            if isLunchbox {
                ForEach(lunchIdeas) { idea in
                    Button {
                        dishID = idea.id
                        title = idea.name
                        recipeID = nil
                    } label: {
                        VStack(alignment: .leading) {
                            Text(verbatim: idea.name).foregroundStyle(.primary)
                            Text(verbatim: idea.description(german: MealsScreen.german)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } footer: {
            if isLunchbox { Text("Leftovers from yesterday's dinner are a good lunchbox too (\"Cook double\").") }
        }
    }

    @ViewBuilder
    private func dishSection(_ dish: Dish) -> some View {
        let tips = profile.tips(for: dish)
        Section {
            Text(verbatim: dish.cuisine.flag + " " + dish.description(german: MealsScreen.german)).font(.subheadline)
            HStack(spacing: 12) {
                Label("\(dish.minutes) min", systemImage: "clock")
                if dish.isVegetarian { Label("Vegetarian", systemImage: "leaf") }
                if dish.spiceLevel > 0 { Text(verbatim: String(repeating: "🌶", count: dish.spiceLevel)) }
            }
            .font(.caption).foregroundStyle(.secondary)
            if let carbs = profile.carbsPerPortion(dish) {
                Label("About \(carbs) g carbohydrates per portion (rough estimate)", systemImage: "drop")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                Label {
                    Text(verbatim: tip.person + ": " + String(localized: String.LocalizationValue(tip.tip)))
                } icon: {
                    Image(systemName: "heart.text.square").foregroundStyle(.pink)
                }
                .font(.caption)
            }
            DisclosureGroup("Ingredients for \(servings)") {
                ForEach(Array(currentIngredients.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line).font(.callout)
                }
            }
            Button {
                let day = WeekPlanner.Day(date: target.day, isWeekend: PlannerDates.calendar.isDateInWeekend(target.day))
                let request = MealPlanService.request(family: family, days: [day], already: [], context: context)
                alternatives = WeekPlanner.alternatives(for: day, request: request, excluding: [dish.id], count: 5)
            } label: {
                Label("Swap for another suggestion", systemImage: "arrow.triangle.2.circlepath")
            }
            ForEach(alternatives) { other in
                Button {
                    dishID = other.id
                    title = other.name
                    alternatives = []
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: other.cuisine.flag + " " + other.name).foregroundStyle(.primary)
                        Text(verbatim: other.description(german: MealsScreen.german)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                let recipe = Recipe(familyID: family.id, name: dish.name)
                recipe.ingredientsText = dish.ingredients.joined(separator: "\n")
                recipe.dishID = dish.id
                recipe.cuisineRaw = dish.cuisine.rawValue
                recipe.note = dish.description(german: MealsScreen.german)
                context.insert(recipe)
                try? context.save()
                session.notice = String(localized: "Saved to your recipes.")
            } label: {
                Label("Save as own recipe (to edit)", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("From the dish catalogue")
        }
    }

    private func ratingButton(_ value: Int, icon: String) -> some View {
        Button {
            MealPlanService.rate(dishKey: dishKey, value: value, familyID: family.id, memberID: session.currentMember?.id, context: context)
            myRating = myRating == value ? 0 : value
        } label: {
            Image(systemName: myRating == value ? icon + ".fill" : icon)
                .font(.title2)
                .foregroundStyle(value > 0 ? Color.green : Color.red)
        }
        .buttonStyle(.borderless)
    }

    private func save() {
        let calendar = PlannerDates.calendar
        let entry = target.entry ?? {
            let new = MealPlanEntry(familyID: family.id, day: calendar.startOfDay(for: target.day), slot: target.slot, title: "")
            context.insert(new)
            return new
        }()
        let wasDouble = entry.cookDouble
        let pickedDish = dish
        entry.title = title.trimmingCharacters(in: .whitespaces)
        entry.recipeID = recipeID
        entry.dishID = recipeID == nil ? (pickedDish?.id ?? "") : ""
        entry.note = note
        entry.servings = servings == familySize ? 0 : servings
        entry.cookDouble = cookDouble
        entry.isLunchbox = target.slot == .lunch && isLunchbox
        entry.updatedAt = Date()
        if cookDouble && !wasDouble {
            MealPlanService.addLeftovers(of: entry, planLunch: planLunch, context: context)
        }
        try? context.save()
        dismiss()
    }
}

/// Search the built-in dish catalogue.
struct DishPickerSheet: View {
    let profile: DietProfile
    let onPick: (Dish) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var cuisine: Cuisine?
    @State private var onlyFitting = true
    @State private var onlyVegetarian = false

    private var dishes: [Dish] {
        let text = TextNormalizer.normalize(search, germanTransliteration: true)
        let filtered = DishCatalogue.all.filter { dish in
            if dish.has(.lunchboxOnly) { return false }
            if let cuisine, dish.cuisine != cuisine { return false }
            if onlyFitting && !profile.allows(dish) { return false }
            if onlyVegetarian && !dish.isVegetarian { return false }
            if text.isEmpty { return true }
            let haystack = TextNormalizer.normalize(([dish.name, dish.englishDescription, dish.germanDescription] + dish.ingredients).joined(separator: " "),
                                                    germanTransliteration: true)
            return haystack.contains(text)
        }
        return filtered.sorted { profile.fit($0) > profile.fit($1) }
    }

    var body: some View {
        let list = dishes
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            chip(nil)
                            ForEach(Cuisine.allCases) { chip($0) }
                        }
                    }
                    Toggle("Only dishes that fit our health settings", isOn: $onlyFitting)
                    Toggle("Vegetarian", isOn: $onlyVegetarian)
                }
                Section {
                    ForEach(list) { dish in
                        Button {
                            onPick(dish)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(verbatim: dish.cuisine.flag + " " + dish.name).foregroundStyle(.primary)
                                    if dish.isVegetarian { Image(systemName: "leaf.fill").foregroundStyle(.green).font(.caption) }
                                    Spacer()
                                    Text("\(dish.minutes) min").font(.caption).foregroundStyle(.secondary)
                                }
                                Text(verbatim: dish.description(german: MealsScreen.german)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("\(list.count) dishes")
                }
            }
            .searchable(text: $search)
            .navigationTitle("Dish catalogue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func chip(_ value: Cuisine?) -> some View {
        Button {
            cuisine = value
        } label: {
            Text(verbatim: value.map { $0.flag + " " + String(localized: String.LocalizationValue($0.title)) } ?? String(localized: "All"))
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(cuisine == value ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Planner → Meals → Recipes.
struct RecipesView: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @Query private var recipes: [Recipe]
    @State private var editing: RecipeEditTarget?
    @State private var importing: RecipeImportKind?
    @State private var cooking: CookingTarget?

    init(family: Family) {
        self.family = family
        let fid = family.id
        _recipes = Query(filter: #Predicate<Recipe> { $0.familyID == fid }, sort: \Recipe.name)
    }

    var body: some View {
        List {
            if recipes.isEmpty {
                Text("Add your family's favourite meals with their ingredients - one per line, e.g. \"500 g Hackfleisch\" - or import them from a website or a cookbook photo.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(recipes) { recipe in
                Button {
                    editing = RecipeEditTarget(recipe: recipe, prefill: nil)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: recipe.name).foregroundStyle(.primary)
                        Text("\(recipe.ingredients.count) ingredient(s) · \(recipe.steps.count) step(s)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        context.delete(recipe)
                        try? context.save()
                    }
                    Button("Cook") {
                        cooking = CookingTarget(title: recipe.name, ingredients: recipe.ingredients, steps: recipe.steps)
                    }
                    .tint(.orange)
                }
            }
        }
        .navigationTitle("Recipes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { editing = RecipeEditTarget(recipe: nil, prefill: nil) } label: { Label("New recipe", systemImage: "square.and.pencil") }
                    Button { importing = .link } label: { Label("Import from a website", systemImage: "link") }
                    Button { importing = .photo } label: { Label("Import from a photo", systemImage: "camera") }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { target in
            RecipeForm(family: family, target: target)
        }
        .sheet(item: $importing) { kind in
            RecipeImportSheet(kind: kind) { imported, url in
                importing = nil
                var target = RecipeEditTarget(recipe: nil, prefill: imported)
                target.sourceURL = url
                editing = target
            }
        }
        .fullScreenCover(item: $cooking) { target in
            CookingModeView(target: target)
        }
    }
}

struct RecipeEditTarget: Identifiable {
    let id = UUID()
    let recipe: Recipe?
    let prefill: ImportedRecipe?
    var sourceURL: String = ""
}

private struct RecipeForm: View {
    let family: Family
    let target: RecipeEditTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var ingredients: String
    @State private var steps: String
    @State private var servings: Int
    @State private var note: String
    @State private var aiWorking = false

    init(family: Family, target: RecipeEditTarget) {
        self.family = family
        self.target = target
        let r = target.recipe
        let p = target.prefill
        _name = State(initialValue: r?.name ?? p?.name ?? "")
        _ingredients = State(initialValue: r?.ingredientsText ?? p?.ingredients.joined(separator: "\n") ?? "")
        _steps = State(initialValue: r?.stepsText ?? p?.steps.joined(separator: "\n") ?? "")
        _servings = State(initialValue: r?.servings ?? p?.servings ?? 4)
        _note = State(initialValue: r?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Stepper(value: $servings, in: 1...12) { Text("\(servings) servings") }
                }
                Section {
                    TextField("One ingredient per line", text: $ingredients, axis: .vertical)
                        .lineLimit(6...20)
                } header: {
                    Text("Ingredients")
                } footer: {
                    Text("Amounts like \"2\", \"500 g\" or \"1 l\" at the start are recognised.")
                }
                Section {
                    TextField("One step per line", text: $steps, axis: .vertical)
                        .lineLimit(4...20)
                    if steps.isEmpty, case .available = AppleIntelligence.state {
                        Button {
                            Task { await writeSteps() }
                        } label: {
                            HStack {
                                Label("Write steps with Apple Intelligence", systemImage: "sparkles")
                                if aiWorking { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(aiWorking || name.isEmpty)
                    }
                } header: {
                    Text("Steps")
                } footer: {
                    Text("Shown one by one in cooking mode; a time like \"20 min\" gets a timer.")
                }
                Section {
                    TextField("Note", text: $note, axis: .vertical).lineLimit(1...6)
                    if let url = target.recipe?.sourceURL, !url.isEmpty, let link = URL(string: url) {
                        Link(destination: link) { Label("Original recipe", systemImage: "safari") }
                    }
                }
            }
            .navigationTitle(target.recipe == nil ? LocalizedStringKey("New recipe") : LocalizedStringKey("Recipe"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func writeSteps() async {
        aiWorking = true
        defer { aiWorking = false }
        let text = (try? await AppleIntelligence.recipeSteps(name: name, ingredients: MealIngredients.lines(from: ingredients))) ?? ""
        steps = MealIngredients.lines(from: text).joined(separator: "\n")
    }

    private func save() {
        let recipe = target.recipe ?? {
            let new = Recipe(familyID: family.id, name: "")
            context.insert(new)
            return new
        }()
        recipe.name = name.trimmingCharacters(in: .whitespaces)
        recipe.ingredientsText = ingredients
        recipe.stepsText = steps
        recipe.servings = servings
        recipe.note = note
        if target.recipe == nil, !target.sourceURL.isEmpty { recipe.sourceURL = target.sourceURL }
        recipe.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}

extension AppleIntelligence {
    /// "Name: ingredient, ingredient" lines for five dinners.
    static func mealIdeas(knownRecipes: String, cuisines: String, rules: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: """
                You suggest simple, balanced family dinners. Write in \(answerLanguage). Answer with exactly five lines, \
                each "Dish name: ingredient, ingredient, …" with amounts for four people (e.g. "500 g minced beef"). \
                Prefer vegetables, pulses, wholegrain and fish once a week. No other text, no calories, no diets.
                """)
            var prompt = "Suggest five dinners"
            if !cuisines.isEmpty { prompt += " from these cuisines (first ones more often): \(cuisines)" }
            prompt += "."
            if !rules.isEmpty { prompt += " Health rules for the family: \(rules)" }
            if !knownRecipes.isEmpty { prompt += " They must be different from: \(knownRecipes)." }
            let response = try await session.respond(to: prompt)
            return response.content
        }
        #endif
        return ""
    }

    /// Short cooking steps, one per line.
    static func recipeSteps(name: String, ingredients: [String]) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: """
                You write clear home-cooking steps. Write in \(answerLanguage). 4 to 8 short steps, one per line, \
                no numbering, no other text. Mention times like "10 min" where it matters.
                """)
            let response = try await session.respond(to: "Dish: \(name)\nIngredients: \(ingredients.joined(separator: ", "))")
            return response.content
        }
        #endif
        return ""
    }
}
