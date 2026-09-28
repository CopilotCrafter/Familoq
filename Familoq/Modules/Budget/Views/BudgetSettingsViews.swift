import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqBudget

/// Budget settings shown inside the Family tab.
struct BudgetSettingsSection: View {
    let family: Family

    var body: some View {
        Section("Budget") {
            NavigationLink { BudgetListView(family: family) } label: {
                Label("Budgets", systemImage: "target")
            }
            NavigationLink { CategoryManagementView(family: family) } label: {
                Label("Categories", systemImage: "square.grid.2x2")
            }
            NavigationLink { MerchantRulesView(family: family) } label: {
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
                        CategoryEditorView(category: category)
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

struct CategoryEditorView: View {
    @Bindable var category: ExpenseCategory
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @Query private var subcategories: [ExpenseSubcategory]
    @State private var newSubName = ""

    private static let iconChoices = [
        "tag.fill", "cart.fill", "car.fill", "house.fill", "fork.knife", "bag.fill", "airplane", "cross.case.fill",
        "theatermasks.fill", "repeat.circle.fill", "book.fill", "shield.fill", "person.fill", "banknote.fill",
        "gift.fill", "pawprint.fill", "figure.run", "gamecontroller.fill", "wrench.and.screwdriver.fill", "heart.fill"
    ]

    init(category: ExpenseCategory) {
        self.category = category
        let cid = category.id
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.categoryID == cid }, sort: \ExpenseSubcategory.sortOrder)
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $category.name)
            }
            Section("Icon") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 10) {
                    ForEach(Self.iconChoices, id: \.self) { icon in
                        Button {
                            category.icon = icon
                        } label: {
                            CategoryIcon(icon: icon, colorHex: category.icon == icon ? category.colorHex : "#B0BEC5", size: 38)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section("Subcategories") {
                ForEach(subcategories.filter { !$0.isArchived }) { sub in
                    SubcategoryNameField(subcategory: sub)
                        .swipeActions {
                            Button("Archive", role: .destructive) {
                                sub.isArchived = true
                                try? context.save()
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
                    category.isArchived = true
                    try? context.save()
                    dismiss()
                }
            }
        }
        .disabled(!session.isOwner)
        .navigationTitle(category.name)
        .onDisappear {
            category.updatedAt = Date()
            try? context.save()
        }
    }

    private func addSub() {
        let name = newSubName.trimmingCharacters(in: .whitespaces)
        guard session.can(.manageCategories), !name.isEmpty else { return }
        let order = (subcategories.map(\.sortOrder).max() ?? 0) + 1
        context.insert(ExpenseSubcategory(familyID: category.familyID, categoryID: category.id, name: name, sortOrder: order))
        try? context.save()
        newSubName = ""
    }
}

private struct SubcategoryNameField: View {
    @Bindable var subcategory: ExpenseSubcategory

    var body: some View {
        TextField("Name", text: $subcategory.name)
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
