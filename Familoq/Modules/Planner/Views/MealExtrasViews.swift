import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import Vision
import FamiloqCore
import FamiloqBudget
import FamiloqPlanner
import FamiloqHealth

// MARK: - Meal settings

/// Planner → Meals → Meal settings: cuisines (ranked) with regions, things to
/// avoid, spice, vegetarian days. Own copy; writes on Save.
struct MealSettingsSheet: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var cuisines: [CuisinePreference] = []
    @State private var avoid = ""
    @State private var maxSpice = 2
    @State private var vegetarianDays = 1
    @State private var weekdayMinutes = 40
    @State private var kidFriendly = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Array(cuisines.enumerated()), id: \.element.cuisine) { index, pref in
                        NavigationLink {
                            RegionPicker(cuisine: pref.cuisine, selection: Binding(
                                get: { cuisines.first { $0.cuisine == pref.cuisine }?.regions ?? [] },
                                set: { value in
                                    if let i = cuisines.firstIndex(where: { $0.cuisine == pref.cuisine }) { cuisines[i].regions = value }
                                }))
                        } label: {
                            HStack {
                                Text(verbatim: "\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                                Text(verbatim: pref.cuisine.flag + " " + String(localized: String.LocalizationValue(pref.cuisine.title)))
                                Spacer()
                                Text(verbatim: regionText(pref)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Remove", role: .destructive) {
                                cuisines.removeAll { $0.cuisine == pref.cuisine }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if index > 0 {
                                Button("Move up") {
                                    cuisines.swapAt(index, index - 1)
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    if cuisines.count < 4 {
                        Menu {
                            ForEach(Cuisine.allCases.filter { c in !cuisines.contains { $0.cuisine == c } }) { cuisine in
                                Button(cuisine.flag + " " + String(localized: String.LocalizationValue(cuisine.title))) {
                                    cuisines.append(CuisinePreference(cuisine: cuisine))
                                }
                            }
                        } label: {
                            Label("Add a cuisine", systemImage: "plus")
                        }
                    }
                } header: {
                    Text("Cuisines (first = most often)")
                } footer: {
                    Text("Choose 3-4 cuisines; swipe right on one to move it up, tap it for 1-2 regions or states (e.g. Bavaria, Kerala). A week then has about 3 dinners from the first, 2 from the second and 1 each from the others.")
                }

                Section {
                    Stepper(value: $vegetarianDays, in: 0...7) { Text("Vegetarian days per week: \(vegetarianDays)") }
                    Stepper(value: $weekdayMinutes, in: 15...90, step: 5) { Text("Weekday dinners up to \(weekdayMinutes) min") }
                    Picker("Spicy", selection: $maxSpice) {
                        Text("Not spicy").tag(0)
                        Text("Mild").tag(1)
                        Text("Medium").tag(2)
                        Text("Hot").tag(3)
                    }
                    Toggle("Kid-friendly", isOn: $kidFriendly)
                }

                Section {
                    TextField("One per line, e.g. Pilze, Koriander, Schwein", text: $avoid, axis: .vertical).lineLimit(2...8)
                } header: {
                    Text("Never suggest")
                } footer: {
                    Text("Allergies and health conditions are set per person in Health → the person.")
                }
            }
            .navigationTitle("Meal settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear(perform: load)
        }
    }

    private func regionText(_ pref: CuisinePreference) -> String {
        pref.regions.compactMap { code in pref.cuisine.regions.first { $0.code == code }?.title }
            .map { String(localized: String.LocalizationValue($0)) }
            .joined(separator: ", ")
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let prefs = MealSettingsService.preferences(familyID: family.id, context: context)
        cuisines = prefs.cuisines
        avoid = prefs.avoidRaw
        maxSpice = prefs.maxSpice
        vegetarianDays = prefs.vegetarianDays
        weekdayMinutes = prefs.weekdayMinutes
        kidFriendly = prefs.kidFriendly
    }

    private func save() {
        let prefs = MealSettingsService.preferences(familyID: family.id, context: context)
        prefs.cuisines = Array(cuisines.prefix(4))
        prefs.avoidRaw = avoid
        prefs.maxSpice = maxSpice
        prefs.vegetarianDays = vegetarianDays
        prefs.weekdayMinutes = weekdayMinutes
        prefs.kidFriendly = kidFriendly
        prefs.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}

private struct RegionPicker: View {
    let cuisine: Cuisine
    @Binding var selection: [String]

    var body: some View {
        List {
            Section {
                ForEach(cuisine.regions) { region in
                    Button {
                        if let i = selection.firstIndex(of: region.code) {
                            selection.remove(at: i)
                        } else if selection.count < 2 {
                            selection.append(region.code)
                        } else {
                            selection = [selection[1], region.code]
                        }
                    } label: {
                        HStack {
                            Text(LocalizedStringKey(region.title)).foregroundStyle(.primary)
                            Spacer()
                            if let i = selection.firstIndex(of: region.code) {
                                Text(verbatim: "\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(.white)
                                    .frame(width: 20, height: 20).background(Color.accentColor, in: Circle())
                            }
                        }
                    }
                }
            } footer: {
                if cuisine.regions.isEmpty {
                    Text("No regions for this cuisine.")
                } else {
                    Text("Up to 2. Dishes from these regions come more often; the rest of the cuisine is still suggested.")
                }
            }
        }
        .navigationTitle(Text(verbatim: cuisine.flag + " " + String(localized: String.LocalizationValue(cuisine.title))))
    }
}

// MARK: - Pantry

/// Planner → Meals → At home: food in the kitchen, use-by reminders, and
/// dishes that use it.
struct PantryView: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var items: [PantryItem]
    @State private var newName = ""
    @State private var newUseBy = Date()
    @State private var hasUseBy = false
    @State private var showReceipts = false

    init(family: Family) {
        self.family = family
        let fid = family.id
        _items = Query(filter: #Predicate<PantryItem> { $0.familyID == fid }, sort: \PantryItem.name)
    }

    private var sorted: [PantryItem] {
        items.sorted { ($0.useBy ?? .distantFuture, $0.name) < ($1.useBy ?? .distantFuture, $1.name) }
    }

    var body: some View {
        let calendar = PlannerDates.calendar
        let today = calendar.startOfDay(for: Date())
        List {
            Section {
                TextField("Add, e.g. 500 g Linsen", text: $newName)
                    .onSubmit(add)
                Toggle("Use by", isOn: $hasUseBy.animation())
                if hasUseBy {
                    DatePicker("Use by", selection: $newUseBy, in: today..., displayedComponents: [.date])
                }
                Button("Add", action: add).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button {
                    showReceipts = true
                } label: {
                    Label("Add food from recent receipts", systemImage: "doc.text.viewfinder")
                }
            } footer: {
                Text("\"Plan my week\" prefers dishes that use what is at home, and the shopping list skips it. Notifications remind you the day before the use-by date.")
            }

            if !items.isEmpty {
                Section {
                    ForEach(sorted) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: item.quantity.isEmpty ? item.name : "\(item.name) · \(item.quantity)")
                                if let useBy = item.useBy {
                                    let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: useBy)).day ?? 0
                                    Text(days < 0 ? LocalizedStringKey("Use by \(useBy.formatted(date: .abbreviated, time: .omitted)) - past") :
                                            (days <= 2 ? LocalizedStringKey("Use by \(useBy.formatted(date: .abbreviated, time: .omitted)) - soon") :
                                                LocalizedStringKey("Use by \(useBy.formatted(date: .abbreviated, time: .omitted))")))
                                        .font(.caption)
                                        .foregroundStyle(days < 0 ? Color.red : (days <= 2 ? Color.orange : Color.secondary))
                                }
                            }
                        }
                        .swipeActions {
                            Button("Used up", role: .destructive) {
                                context.delete(item)
                                try? context.save()
                            }
                        }
                    }
                } header: {
                    Text("At home (\(items.count))")
                }

                cookSection
            }
        }
        .navigationTitle("At home")
        .sheet(isPresented: $showReceipts) {
            ReceiptFoodPicker(family: family)
        }
    }

    @ViewBuilder
    private var cookSection: some View {
        let words = items.map(\.name)
        let profile = HealthService.dietProfile(familyID: family.id, context: context)
        let matches = Self.matches(words: words, profile: profile)
        if !matches.isEmpty {
            Section("Cook with what's at home") {
                ForEach(matches) { match in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: match.dish.cuisine.flag + " " + match.dish.name)
                        Text("Uses \(match.hits) things you have").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    struct PantryMatch: Identifiable {
        let dish: Dish
        let hits: Int
        var id: String { dish.id }
    }

    static func matches(words: [String], profile: DietProfile) -> [PantryMatch] {
        let keys = words.map { ShoppingEntryParser.key($0) }.filter { $0.count >= 4 }
        var result: [PantryMatch] = []
        for dish in DishCatalogue.all where !dish.has(.lunchboxOnly) && profile.allows(dish) {
            let text = TextNormalizer.normalize(dish.ingredients.joined(separator: " "), germanTransliteration: true)
            let hits = keys.filter { text.contains($0) }.count
            if hits >= 2 { result.append(PantryMatch(dish: dish, hits: hits)) }
        }
        result.sort { $0.hits > $1.hits }
        return Array(result.prefix(5))
    }

    private func add() {
        let text = newName.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let entry = ShoppingEntryParser.parse(text)
        let item = PantryItem(familyID: family.id, name: entry.name)
        item.quantity = entry.quantity
        item.useBy = hasUseBy ? PlannerDates.calendar.startOfDay(for: newUseBy) : nil
        item.addedByMemberID = session.currentMember?.id
        context.insert(item)
        try? context.save()
        newName = ""
        hasUseBy = false
        Task { await PlannerNotifications.reschedule(context: context) }
    }
}

/// Picks food lines from receipts of the last two weeks.
private struct ReceiptFoodPicker: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @State private var candidates: [Candidate] = []
    @State private var selected: Set<String> = []

    struct Candidate: Identifiable {
        let name: String
        let date: Date
        var id: String { name }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    Text("No food on receipts from the last 14 days.").foregroundStyle(.secondary)
                }
                ForEach(candidates) { item in
                    Button {
                        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                    } label: {
                        HStack {
                            Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(item.id) ? Color.accentColor : Color.secondary)
                            Text(verbatim: item.name).foregroundStyle(.primary)
                            Spacer()
                            Text(verbatim: item.date.formatted(.dateTime.day().month(.abbreviated))).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("From receipts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selected.count)") { save() }.disabled(selected.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        let fid = family.id
        let since = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let receipts = (try? context.fetch(FetchDescriptor<ReceiptRecord>(predicate: #Predicate { $0.familyID == fid && $0.date >= since }))) ?? []
        let dates = Dictionary(receipts.map { ($0.id, $0.date) }, uniquingKeysWith: { a, _ in a })
        let ids = Set(receipts.map(\.id))
        let lines = ((try? context.fetch(FetchDescriptor<ReceiptItemRecord>(predicate: #Predicate { $0.familyID == fid }))) ?? [])
            .filter { ids.contains($0.receiptID) }
        let existing = Set(((try? context.fetch(FetchDescriptor<PantryItem>(predicate: #Predicate { $0.familyID == fid }))) ?? []).map { ShoppingEntryParser.key($0.name) })
        var seen = Set<String>()
        var result: [Candidate] = []
        for line in lines {
            let group = FoodGroupClassifier.group(name: line.name, subcategoryKey: nil)
            guard ![.nonFood, .drinks, .alcohol, .sugaryDrinks, .other].contains(group) else { continue }
            let key = ShoppingEntryParser.key(line.name)
            guard !key.isEmpty, !seen.contains(key), !existing.contains(key) else { continue }
            seen.insert(key)
            result.append(Candidate(name: line.name, date: dates[line.receiptID] ?? Date()))
        }
        candidates = result.sorted { $0.date > $1.date }
    }

    private func save() {
        for name in selected {
            let item = PantryItem(familyID: family.id, name: name)
            item.addedFromReceipt = true
            item.addedByMemberID = session.currentMember?.id
            context.insert(item)
        }
        try? context.save()
        dismiss()
    }
}

// MARK: - Recipe import

enum RecipeImportKind: String, Identifiable {
    case link, photo
    var id: String { rawValue }
}

/// Imports a recipe from a web page (its recipe data) or a cookbook photo
/// (text read on the iPhone).
struct RecipeImportSheet: View {
    let kind: RecipeImportKind
    let onImport: (ImportedRecipe, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var photo: PhotosPickerItem?
    @State private var working = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                if kind == .link {
                    Section {
                        TextField("https://…", text: $link)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            Task { await importLink() }
                        } label: {
                            HStack {
                                Label("Import", systemImage: "arrow.down.doc")
                                if working { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(working || URL(string: link.trimmingCharacters(in: .whitespaces))?.scheme == nil)
                    } footer: {
                        Text("Works with most recipe sites (e.g. Chefkoch). Only the page itself is loaded; nothing about your family is sent.")
                    }
                } else {
                    Section {
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label("Choose a photo of the recipe", systemImage: "photo")
                        }
                        if working { ProgressView() }
                    } footer: {
                        Text("Take a photo of the cookbook page with the Camera first. The text is read on this iPhone; check the ingredients and steps before saving.")
                    }
                }
                if let errorText {
                    Section { Text(verbatim: errorText).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle(kind == .link ? LocalizedStringKey("Import from a website") : LocalizedStringKey("Import from a photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task { await importPhoto(item) }
            }
        }
    }

    private func importLink() async {
        errorText = nil
        guard let url = URL(string: link.trimmingCharacters(in: .whitespaces)) else { return }
        working = true
        defer { working = false }
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone) Familoq", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            if let recipe = RecipeImport.parse(html: html), !recipe.ingredients.isEmpty {
                onImport(recipe, url.absoluteString)
            } else {
                errorText = String(localized: "No recipe found on this page. Try the photo import or type it in.")
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        errorText = nil
        working = true
        defer { working = false }
        guard let data = try? await item.loadTransferable(type: Data.self), let original = UIImage(data: data) else {
            errorText = String(localized: "The photo could not be read.")
            return
        }
        let image = ReceiptOCRService.downscaled(original, maxDimension: 3000)
        guard let cgImage = image.cgImage else {
            errorText = String(localized: "The photo could not be read.")
            return
        }
        let lines = await Self.recognizeText(cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
        if let recipe = RecipeImport.parse(lines: lines) {
            onImport(recipe, "")
        } else {
            errorText = String(localized: "No text found in the photo.")
        }
    }

    static func recognizeText(_ image: CGImage, orientation: CGImagePropertyOrientation) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["de-DE", "en-US"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
            guard (try? handler.perform([request])) != nil else { return [String]() }
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }.value
    }
}

// MARK: - Cooking mode

struct CookingTarget: Identifiable {
    let id = UUID()
    let title: String
    let ingredients: [String]
    let steps: [String]
}

/// Step by step, big text, the screen stays on, timers from "20 min".
struct CookingModeView: View {
    let target: CookingTarget
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var steps: [String] = []
    @State private var aiWorking = false
    @State private var checked: Set<Int> = []
    @State private var timerEnd: Date?
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                ingredientsPage.tag(0)
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    stepPage(step, number: index + 1).tag(index + 1)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .navigationTitle(Text(verbatim: target.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if let timerEnd {
                    let left = max(0, Int(timerEnd.timeIntervalSince(now)))
                    HStack {
                        Image(systemName: left == 0 ? "bell.fill" : "timer")
                        Text(verbatim: String(format: "%d:%02d", left / 60, left % 60)).monospacedDigit().font(.title2.weight(.semibold))
                        Spacer()
                        Button("Stop") { self.timerEnd = nil }
                    }
                    .padding()
                    .background(left == 0 ? Color.orange.opacity(0.3) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                }
            }
        }
        .onReceive(tick) { now = $0 }
        .onAppear {
            steps = target.steps
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var ingredientsPage: some View {
        List {
            Section("Ingredients") {
                ForEach(Array(target.ingredients.enumerated()), id: \.offset) { index, line in
                    Button {
                        if checked.contains(index) { checked.remove(index) } else { checked.insert(index) }
                    } label: {
                        HStack {
                            Image(systemName: checked.contains(index) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(checked.contains(index) ? Color.green : Color.secondary)
                            Text(verbatim: line).font(.title3).foregroundStyle(.primary).strikethrough(checked.contains(index))
                        }
                    }
                }
            }
            if steps.isEmpty {
                Section {
                    if case .available = AppleIntelligence.state {
                        Button {
                            Task { await writeSteps() }
                        } label: {
                            HStack {
                                Label("Write steps with Apple Intelligence", systemImage: "sparkles")
                                if aiWorking { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(aiWorking)
                    } else {
                        Text("No steps saved. Add them in the recipe (Recipes → the recipe → Steps).").foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    Text("Swipe for the steps →").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stepPage(_ step: String, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Step \(number) of \(steps.count)").font(.headline).foregroundStyle(.secondary)
            Text(verbatim: step).font(.title2)
            if let minutes = Self.minutes(in: step) {
                Button {
                    timerEnd = Date().addingTimeInterval(Double(minutes * 60))
                } label: {
                    Label("Timer \(minutes) min", systemImage: "timer")
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "20 min", "20 Min.", "20 Minuten", "20 minutes".
    static func minutes(in text: String) -> Int? {
        let pattern = #"(\d{1,3})\s*(min|minute|minuten|minutes)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range]).flatMap { $0 > 0 ? $0 : nil }
    }

    private func writeSteps() async {
        aiWorking = true
        defer { aiWorking = false }
        let text = (try? await AppleIntelligence.recipeSteps(name: target.title, ingredients: target.ingredients)) ?? ""
        steps = MealIngredients.lines(from: text)
    }
}
