import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqBudget

/// Daily / weekly / monthly budgets for the family, category and subcategory
/// (spec sections 12 and 13). Only owners can change budgets.
struct BudgetListView: View {
    let family: Family

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var budgets: [Budget]
    @Query private var expenses: [Expense]
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @State private var editor: BudgetEditorTarget?

    private let now = Date()
    private let calendar = FamiloqCalendar.make()

    init(family: Family) {
        self.family = family
        let fid = family.id
        let calendar = FamiloqCalendar.make()
        let now = Date()
        let month = BudgetPeriod.monthly.interval(containing: now, calendar: calendar)
        let week = BudgetPeriod.weekly.interval(containing: now, calendar: calendar)
        let start = min(month.start, week.start)
        let end = max(month.end, week.end)
        _budgets = Query(filter: #Predicate<Budget> { $0.familyID == fid }, sort: \Budget.createdAt)
        _expenses = Query(filter: #Predicate<Expense> { $0.familyID == fid && $0.date >= start && $0.date < end })
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid }, sort: \ExpenseCategory.sortOrder)
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid }, sort: \ExpenseSubcategory.sortOrder)
    }

    private var lookup: CategoryLookup { CategoryLookup(categories: categories, subcategories: subcategories) }

    var body: some View {
        let progress = BudgetProgressBuilder.progress(budgets: budgets, expenses: expenses, lookup: lookup, now: now, calendar: calendar)
        List {
            ForEach(BudgetScope.allCases, id: \.self) { scope in
                let items = progress.filter { $0.budget.scope == scope }
                Section(LocalizedStringKey(sectionTitle(scope))) {
                    if items.isEmpty {
                        Text(LocalizedStringKey(emptyText(scope))).font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(items) { item in
                        Button {
                            if session.can(.manageBudgets) { editor = BudgetEditorTarget(budget: item.budget, scope: scope) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                BudgetProgressRow(progress: item, currencyCode: family.baseCurrencyCode)
                                Text(LocalizedStringKey(item.budget.period.displayName))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if session.can(.manageBudgets) {
                                Button(role: .destructive) {
                                    context.delete(item.budget)
                                    try? context.save()
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
            Section {
                Text("Warnings appear at 75 %, 90 % and 100 %. Budgets are in \(family.baseCurrencyCode); foreign-currency expenses are converted automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Budgets")
        .toolbar {
            if session.can(.manageBudgets) {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Family budget") { editor = BudgetEditorTarget(budget: nil, scope: .overall) }
                        Button("Category budget") { editor = BudgetEditorTarget(budget: nil, scope: .category) }
                        Button("Subcategory budget") { editor = BudgetEditorTarget(budget: nil, scope: .subcategory) }
                    } label: {
                        Label("Add budget", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(item: $editor) { target in
            NavigationStack {
                BudgetEditorView(family: family, target: target, lookup: lookup)
            }
        }
    }

    private func sectionTitle(_ scope: BudgetScope) -> String {
        switch scope {
        case .overall: return "Family budget"
        case .category: return "Category budgets"
        case .subcategory: return "Subcategory budgets"
        }
    }

    private func emptyText(_ scope: BudgetScope) -> String {
        switch scope {
        case .overall: return "No family budget yet. A monthly family budget enables Safe to spend."
        case .category: return "e.g. Groceries €600 per month"
        case .subcategory: return "e.g. Groceries › Meat & Poultry €120 per month"
        }
    }
}

struct BudgetEditorTarget: Identifiable {
    let budget: Budget?
    let scope: BudgetScope
    let id = UUID()
}

struct BudgetEditorView: View {
    let family: Family
    let target: BudgetEditorTarget
    let lookup: CategoryLookup

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @State private var period: BudgetPeriod
    @State private var categoryID: UUID?
    @State private var subcategoryID: UUID?
    @State private var amountText: String
    @State private var error: String?

    init(family: Family, target: BudgetEditorTarget, lookup: CategoryLookup) {
        self.family = family
        self.target = target
        self.lookup = lookup
        _period = State(initialValue: target.budget?.period ?? .monthly)
        _categoryID = State(initialValue: target.budget?.categoryID)
        _subcategoryID = State(initialValue: target.budget?.subcategoryID)
        _amountText = State(initialValue: target.budget.map { "\($0.amount)" } ?? "")
    }

    var body: some View {
        Form {
            Picker("Period", selection: $period) {
                ForEach(BudgetPeriod.allCases, id: \.self) { Text(LocalizedStringKey($0.displayName)).tag($0) }
            }
            .pickerStyle(.segmented)

            if target.scope != .overall {
                Picker("Category", selection: $categoryID) {
                    Text("Choose…").tag(UUID?.none)
                    ForEach(lookup.activeCategories()) { Label($0.name, systemImage: $0.icon).tag(Optional($0.id)) }
                }
            }
            if target.scope == .subcategory {
                Picker("Subcategory", selection: $subcategoryID) {
                    Text("Choose…").tag(UUID?.none)
                    ForEach(lookup.activeSubcategories(of: categoryID)) { Text($0.name).tag(Optional($0.id)) }
                }
                .disabled(categoryID == nil)
            }

            HStack {
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                Text(family.baseCurrencyCode).foregroundStyle(.secondary)
            }

            if let error {
                Text(LocalizedStringKey(error)).foregroundStyle(.red)
            }
        }
        .navigationTitle(target.budget == nil ? "New budget" : "Edit budget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
    }

    private func save() {
        guard session.can(.manageBudgets) else {
            error = "Only the family owner can change budgets."
            return
        }
        guard let amount = DecimalParser.parse(amountText), amount > 0 else {
            error = "Enter an amount greater than zero."
            return
        }
        if target.scope != .overall && categoryID == nil {
            error = "Choose a category."
            return
        }
        if target.scope == .subcategory && subcategoryID == nil {
            error = "Choose a subcategory."
            return
        }
        let budget: Budget
        if let existing = target.budget {
            budget = existing
        } else {
            budget = Budget(familyID: family.id, period: period, scope: target.scope, amount: amount, currencyCode: family.baseCurrencyCode)
            context.insert(budget)
        }
        budget.period = period
        budget.categoryID = target.scope == .overall ? nil : categoryID
        budget.subcategoryID = target.scope == .subcategory ? subcategoryID : nil
        budget.amount = amount
        budget.currencyCode = family.baseCurrencyCode
        budget.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}
