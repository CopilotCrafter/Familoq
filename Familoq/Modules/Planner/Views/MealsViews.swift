import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqPlanner
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Planner → Meals: the week's meals, recipes, and the ingredients onto the
/// shopping list with one tap.
struct MealsScreen: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var meals: [MealPlanEntry]
    @Query private var recipes: [Recipe]
    @AppStorage("meals.showLunch") private var showLunch = false
    @AppStorage("meals.showBreakfast") private var showBreakfast = false
    @State private var weekStart: Date
    @State private var editing: MealEditTarget?
    @State private var ideas: [MealIdea] = []
    @State private var aiWorking = false

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
        let calendar = PlannerDates.calendar
        _weekStart = State(initialValue: calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date()))
    }

    private var slots: [MealSlot] {
        MealSlot.allCases.filter { $0 == .dinner || ($0 == .lunch && showLunch) || ($0 == .breakfast && showBreakfast) }
    }

    private var days: [Date] {
        (0..<7).compactMap { PlannerDates.calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        let calendar = PlannerDates.calendar
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let weekMeals = meals.filter { $0.day >= weekStart && $0.day < weekEnd }
        let recipeByID = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ingredientCount = weekMeals.compactMap { $0.recipeID.flatMap { recipeByID[$0] } }.flatMap(\.ingredients).count

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
                    addIngredients(weekMeals, recipeByID: recipeByID)
                } label: {
                    Label("Put this week's ingredients on the shopping list", systemImage: "cart.badge.plus")
                }
                .disabled(ingredientCount == 0)
                NavigationLink {
                    LazyView(RecipesView(family: family))
                } label: {
                    Label("Recipes (\(recipes.count))", systemImage: "book")
                }
            } footer: {
                if ingredientCount == 0 && !weekMeals.isEmpty {
                    Text("Pick meals from your recipes to add their ingredients automatically.")
                }
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
                            Button {
                                editing = MealEditTarget(entry: entry, day: day, slot: slot)
                            } label: {
                                HStack {
                                    Image(systemName: slot.icon).foregroundStyle(.orange).frame(width: 22)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(verbatim: entry.title).foregroundStyle(.primary)
                                        if entry.recipeID != nil {
                                            Text("Recipe").font(.caption2).foregroundStyle(.secondary)
                                        }
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
            MealEditSheet(family: family, target: target, recipes: recipes)
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
                            Label("Dinner ideas from Apple Intelligence", systemImage: "sparkles")
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
                Text("Ideas are made on this iPhone and lean towards what your Healthy basket is missing.")
            }
        }
    }

    private func shiftWeek(_ weeks: Int) {
        withAnimation {
            weekStart = PlannerDates.calendar.date(byAdding: .day, value: 7 * weeks, to: weekStart) ?? weekStart
        }
    }

    private func addIngredients(_ weekMeals: [MealPlanEntry], recipeByID: [UUID: Recipe]) {
        let lines = weekMeals.compactMap { $0.recipeID.flatMap { recipeByID[$0] } }.flatMap(\.ingredients)
        guard let list = ShoppingService.lists(familyID: family.id, context: context).first else { return }
        let entries = MealIngredients.merged(lines)
        for entry in entries {
            ShoppingService.add(entry: entry, listID: list.id, familyID: family.id, memberID: session.currentMember?.id, context: context)
        }
        session.notice = String(localized: "\(entries.count) ingredient(s) put on the shopping list.")
    }

    private func suggest() async {
        aiWorking = true
        defer { aiWorking = false }
        let known = recipes.map(\.name).prefix(20).joined(separator: ", ")
        let text = (try? await AppleIntelligence.mealIdeas(knownRecipes: known)) ?? ""
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

private struct MealEditSheet: View {
    let family: Family
    let target: MealEditTarget
    let recipes: [Recipe]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var recipeID: UUID?
    @State private var title: String
    @State private var note: String

    init(family: Family, target: MealEditTarget, recipes: [Recipe]) {
        self.family = family
        self.target = target
        self.recipes = recipes
        _recipeID = State(initialValue: target.entry?.recipeID)
        _title = State(initialValue: target.entry?.title ?? "")
        _note = State(initialValue: target.entry?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Recipe", selection: $recipeID) {
                        Text("No recipe").tag(UUID?.none)
                        ForEach(recipes) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                    }
                    .onChange(of: recipeID) { _, id in
                        if let recipe = recipes.first(where: { $0.id == id }) { title = recipe.name }
                    }
                    TextField("Meal, e.g. Spaghetti Bolognese", text: $title)
                    TextField("Note", text: $note)
                } footer: {
                    Text(verbatim: target.day.formatted(.dateTime.weekday(.wide).day().month(.wide)) + " · " + String(localized: String.LocalizationValue(target.slot.title)))
                }
                if let entry = target.entry {
                    Section {
                        Button("Delete", role: .destructive) {
                            context.delete(entry)
                            try? context.save()
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
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let entry = target.entry ?? {
            let new = MealPlanEntry(familyID: family.id, day: PlannerDates.calendar.startOfDay(for: target.day), slot: target.slot, title: "")
            context.insert(new)
            return new
        }()
        entry.title = title.trimmingCharacters(in: .whitespaces)
        entry.recipeID = recipeID
        entry.note = note
        entry.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}

/// Planner → Meals → Recipes.
struct RecipesView: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @Query private var recipes: [Recipe]
    @State private var editing: RecipeEditTarget?

    init(family: Family) {
        self.family = family
        let fid = family.id
        _recipes = Query(filter: #Predicate<Recipe> { $0.familyID == fid }, sort: \Recipe.name)
    }

    var body: some View {
        List {
            if recipes.isEmpty {
                Text("Add your family's favourite meals with their ingredients - one per line, e.g. \"500 g Hackfleisch\".")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(recipes) { recipe in
                Button {
                    editing = RecipeEditTarget(recipe: recipe)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: recipe.name).foregroundStyle(.primary)
                        Text("\(recipe.ingredients.count) ingredient(s)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        context.delete(recipe)
                        try? context.save()
                    }
                }
            }
        }
        .navigationTitle("Recipes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = RecipeEditTarget(recipe: nil) } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { target in
            RecipeForm(family: family, target: target)
        }
    }
}

struct RecipeEditTarget: Identifiable {
    let id = UUID()
    let recipe: Recipe?
}

private struct RecipeForm: View {
    let family: Family
    let target: RecipeEditTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var ingredients: String
    @State private var servings: Int
    @State private var note: String

    init(family: Family, target: RecipeEditTarget) {
        self.family = family
        self.target = target
        _name = State(initialValue: target.recipe?.name ?? "")
        _ingredients = State(initialValue: target.recipe?.ingredientsText ?? "")
        _servings = State(initialValue: target.recipe?.servings ?? 4)
        _note = State(initialValue: target.recipe?.note ?? "")
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
                    TextField("Note", text: $note, axis: .vertical).lineLimit(1...6)
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

    private func save() {
        let recipe = target.recipe ?? {
            let new = Recipe(familyID: family.id, name: "")
            context.insert(new)
            return new
        }()
        recipe.name = name.trimmingCharacters(in: .whitespaces)
        recipe.ingredientsText = ingredients
        recipe.servings = servings
        recipe.note = note
        recipe.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}

extension AppleIntelligence {
    /// "Name: ingredient, ingredient" lines for five dinners.
    static func mealIdeas(knownRecipes: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: """
                You suggest simple, balanced family dinners. Write in \(answerLanguage). Answer with exactly five lines, \
                each "Dish name: ingredient, ingredient, …" with amounts for four people (e.g. "500 g minced beef"). \
                Prefer vegetables, pulses, wholegrain and fish once a week. No other text, no calories, no diets.
                """)
            let prompt = knownRecipes.isEmpty ? "Suggest five dinners." : "Suggest five dinners that are different from: \(knownRecipes)."
            let response = try await session.respond(to: prompt)
            return response.content
        }
        #endif
        return ""
    }
}
