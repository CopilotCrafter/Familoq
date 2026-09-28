import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqBudget

/// Budget settings shown inside the Family tab.
struct BudgetSettingsSection: View {
    let family: Family

    var body: some View {
        Section("Budget") {
            NavigationLink { LazyView(BudgetListView(family: family)) } label: {
                Label("Budgets", systemImage: "target")
            }
            NavigationLink { LazyView(CategoryManagementView(family: family)) } label: {
                Label("Categories", systemImage: "square.grid.2x2")
            }
            NavigationLink { LazyView(MerchantRulesView(family: family)) } label: {
                Label("Merchant rules", systemImage: "wand.and.stars")
            }
        }
    }
}

// MARK: - Base currency

struct BaseCurrencySettingsView: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var rates: ExchangeRateService
    @State private var selection: String
    @State private var pending: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(family: Family) {
        self.family = family
        _selection = State(initialValue: family.baseCurrencyCode)
    }

    var body: some View {
        CurrencyPickerView(selection: $selection, title: "Base currency") { code in
            if code != family.baseCurrencyCode { pending = code }
        }
        .overlay {
            if isWorking {
                ProgressView("Recalculating…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .safeAreaInset(edge: .top) {
            Text("All totals, budgets and reports use the base currency. Default is EUR. Expenses keep their original currency and amount.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
        }
        .alert("Change base currency to \(pending ?? "")?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Change") {
                if let code = pending { Task { await change(to: code) } }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text("Budgets are converted with today's ECB rate (rounded). Every expense is recalculated with the rate of its own date. Requires an internet connection.")
        }
        .alert("Could not change currency", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(errorMessage ?? ""))
        }
        .disabled(isWorking)
    }

    private func change(to code: String) async {
        pending = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await BaseCurrencyService.change(to: code, family: family, context: context, rates: rates)
            selection = code
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Categories

struct CategoryManagementView: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @State private var newCategoryName = ""

    init(family: Family) {
        self.family = family
        let fid = family.id
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid }, sort: \ExpenseCategory.sortOrder)
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid }, sort: \ExpenseSubcategory.sortOrder)
    }

    var body: some View {
        List {
            Section {
                ForEach(categories.filter { !$0.isArchived }) { category in
                    NavigationLink {
                        LazyView(CategoryEditorView(category: category, subcategories: subcategories))
                    } label: {
                        HStack {
                            CategoryIcon(icon: category.icon, colorHex: category.colorHex, size: 28)
                            Text(category.name)
                            Spacer()
                            Text("\(subcategories.filter { $0.categoryID == category.id && !$0.isArchived }.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Archived categories keep their past expenses but are hidden when adding new ones.")
            }

            if session.isOwner {
                Section("New category") {
                    HStack {
                        TextField("Name", text: $newCategoryName)
                        Button("Add") { addCategory() }
                            .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .navigationTitle("Categories")
    }

    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard session.can(.manageCategories), !name.isEmpty else { return }
        let order = (categories.map(\.sortOrder).max() ?? 0) + 1
        context.insert(ExpenseCategory(familyID: family.id, name: name, icon: "tag.fill", colorHex: "#607D8B", sortOrder: order))
        try? context.save()
        newCategoryName = ""
    }
}

/// Edits one category. Owns its state (no @Query, no live model binding while
/// typing) - on iOS 27 a pushed screen with its own query re-created itself
/// endlessly and crashed (same pattern as the receipt check screen).
struct CategoryEditorView: View {
    let category: ExpenseCategory
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @State private var name: String
    @State private var icon: String
    @State private var subs: [SubDraft]
    @State private var newSubName = ""

    struct SubDraft: Identifiable, Equatable {
        let id: UUID
        var name: String
        var sortOrder: Int
        var isArchived: Bool
    }

    private static let iconChoices = [
        "tag.fill", "cart.fill", "car.fill", "house.fill", "fork.knife", "bag.fill", "airplane", "cross.case.fill",
        "theatermasks.fill", "repeat.circle.fill", "book.fill", "shield.fill", "person.fill", "banknote.fill",
        "gift.fill", "pawprint.fill", "figure.run", "gamecontroller.fill", "wrench.and.screwdriver.fill", "heart.fill"
    ]

    init(category: ExpenseCategory, subcategories: [ExpenseSubcategory]) {
        self.category = category
        _name = State(initialValue: category.name)
        _icon = State(initialValue: category.icon)
        _subs = State(initialValue: subcategories
            .filter { $0.categoryID == category.id }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { SubDraft(id: $0.id, name: $0.name, sortOrder: $0.sortOrder, isArchived: $0.isArchived) })
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $name)
            }
            Section("Icon") {
                ForEach(Array(stride(from: 0, to: Self.iconChoices.count, by: 5)), id: \.self) { start in
                    HStack {
                        ForEach(Self.iconChoices[start..<min(start + 5, Self.iconChoices.count)], id: \.self) { choice in
                            Button {
                                icon = choice
                            } label: {
                                CategoryIcon(icon: choice, colorHex: icon == choice ? category.colorHex : "#B0BEC5", size: 38)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            Section("Subcategories") {
                ForEach($subs) { $sub in
                    if !sub.isArchived {
                        TextField("Name", text: $sub.name)
                            .swipeActions {
                                Button("Archive", role: .destructive) { sub.isArchived = true }
                            }
                    }
                }
                HStack {
                    TextField("New subcategory", text: $newSubName)
                    Button("Add") { addSub() }
                        .disabled(newSubName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section {
                Button("Archive category", role: .destructive) {
                    commit(archiveCategory: true)
                    dismiss()
                }
            }
        }
        .disabled(!session.isOwner)
        .navigationTitle(Text(verbatim: name))
        .onDisappear { commit(archiveCategory: false) }
    }

    private func addSub() {
        let trimmed = newSubName.trimmingCharacters(in: .whitespaces)
        guard session.can(.manageCategories), !trimmed.isEmpty else { return }
        let order = (subs.map(\.sortOrder).max() ?? 0) + 1
        subs.append(SubDraft(id: UUID(), name: trimmed, sortOrder: order, isArchived: false))
        newSubName = ""
    }

    /// Writes the edits to SwiftData once, when leaving the screen.
    private func commit(archiveCategory: Bool) {
        guard session.can(.manageCategories) else { return }
        var changed = false
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty, trimmedName != category.name { category.name = trimmedName; changed = true }
        if icon != category.icon { category.icon = icon; changed = true }
        if archiveCategory, !category.isArchived { category.isArchived = true; changed = true }

        let cid = category.id
        let existing = (try? context.fetch(FetchDescriptor<ExpenseSubcategory>(predicate: #Predicate { $0.categoryID == cid }))) ?? []
        let byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for draft in subs {
            let subName = draft.name.trimmingCharacters(in: .whitespaces)
            if let model = byID[draft.id] {
                if !subName.isEmpty, model.name != subName { model.name = subName; model.updatedAt = Date(); changed = true }
                if model.isArchived != draft.isArchived { model.isArchived = draft.isArchived; model.updatedAt = Date(); changed = true }
            } else if !subName.isEmpty, !draft.isArchived {
                context.insert(ExpenseSubcategory(id: draft.id, familyID: category.familyID, categoryID: cid, name: subName, sortOrder: draft.sortOrder))
                changed = true
            }
        }
        if changed {
            category.updatedAt = Date()
            try? context.save()
        }
    }
}

// MARK: - Merchant rules

struct MerchantRulesView: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var rules: [MerchantRuleRecord]
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @State private var showBuiltIn = false

    init(family: Family) {
        self.family = family
        let fid = family.id
        _rules = Query(filter: #Predicate<MerchantRuleRecord> { $0.familyID == fid }, sort: \MerchantRuleRecord.pattern)
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid })
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid })
    }

    var body: some View {
        let lookup = CategoryLookup(categories: categories, subcategories: subcategories)
        let userRules = rules.filter(\.isUserDefined)
        let builtIn = rules.filter { !$0.isUserDefined }
        List {
            Section {
                if userRules.isEmpty {
                    Text("When you change a suggested category, Familoq asks whether to remember it. Your rules appear here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(userRules) { rule in
                    ruleRow(rule, lookup: lookup)
                        .swipeActions {
                            if session.isOwner {
                                Button("Delete", role: .destructive) {
                                    context.delete(rule)
                                    try? context.save()
                                }
                            }
                        }
                }
            } header: {
                Text("Your rules")
            }

            Section {
                Toggle("Show built-in rules (\(builtIn.count))", isOn: $showBuiltIn)
                if showBuiltIn {
                    ForEach(builtIn) { rule in
                        ruleRow(rule, lookup: lookup)
                    }
                }
            } footer: {
                Text("Your rules always win over built-in rules. Categorisation runs fully on the device - no AI service is used.")
            }
        }
        .navigationTitle("Merchant rules")
    }

    private func ruleRow(_ rule: MerchantRuleRecord, lookup: CategoryLookup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(rule.displayMerchant.isEmpty ? rule.pattern : rule.displayMerchant)
            Text("→ \(lookup.path(categoryID: rule.categoryID, subcategoryID: rule.subcategoryID))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
