import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqBudget

/// All expenses of the family, grouped by day, with basic search.
/// Full search & filters (member, amount, date range) arrive in Phase 5.
struct ExpenseListView: View {
    let family: Family

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var expenses: [Expense]
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @State private var search = ""
    @State private var editingExpense: Expense?

    init(family: Family) {
        self.family = family
        let fid = family.id
        _expenses = Query(filter: #Predicate<Expense> { $0.familyID == fid }, sort: \Expense.date, order: .reverse)
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid }, sort: \ExpenseCategory.sortOrder)
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid }, sort: \ExpenseSubcategory.sortOrder)
    }

    private var lookup: CategoryLookup {
        CategoryLookup(categories: categories, subcategories: subcategories)
    }

    private var filtered: [Expense] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return expenses }
        return expenses.filter { expense in
            expense.merchant.lowercased().contains(q)
                || expense.note.lowercased().contains(q)
                || lookup.path(categoryID: expense.categoryID, subcategoryID: expense.subcategoryID).lowercased().contains(q)
                || expense.amount.formatted().contains(q)
        }
    }

    private var groupedByDay: [(day: Date, items: [Expense])] {
        let calendar = FamiloqCalendar.make()
        let groups = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { (day: $0, items: groups[$0] ?? []) }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                EmptyStateView(icon: "magnifyingglass", title: "Nothing found", message: search.isEmpty ? "No expenses yet." : "Try a different search.")
            }
            ForEach(groupedByDay, id: \.day) { group in
                Section(group.day.formatted(date: .complete, time: .omitted)) {
                    ForEach(group.items) { expense in
                        Button {
                            editingExpense = expense
                        } label: {
                            ExpenseRow(expense: expense, lookup: lookup)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if session.canEdit(expense) {
                                Button(role: .destructive) {
                                    context.delete(expense)
                                    try? context.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Merchant, category, note, amount")
        .navigationTitle("Expenses")
        .sheet(item: $editingExpense) { expense in
            NavigationStack {
                ExpenseFormView(family: family, editing: expense)
            }
        }
    }
}
