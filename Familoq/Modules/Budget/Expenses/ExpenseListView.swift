import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqBudget

extension Expense {
    func facts(lookup: CategoryLookup) -> ExpenseFacts {
        ExpenseFacts(merchant: merchant, note: note,
                     categoryPath: lookup.path(categoryID: categoryID, subcategoryID: subcategoryID),
                     categoryID: categoryID, memberID: memberID, date: date,
                     amount: amount, currencyCode: currencyCode, baseAmount: baseAmount,
                     entryMethod: entryMethodRaw)
    }
}

/// All expenses of the family, grouped by day, with search and filters
/// (period, categories, members, amount, how it was entered, currency).
struct ExpenseListView: View {
    let family: Family

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var expenses: [Expense]
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @Query private var members: [FamilyMember]
    @State private var filter: ExpenseFilter
    @State private var showFilters = false
    @State private var editingExpense: Expense?

    init(family: Family, filter: ExpenseFilter = ExpenseFilter()) {
        self.family = family
        let fid = family.id
        _expenses = Query(filter: #Predicate<Expense> { $0.familyID == fid }, sort: \Expense.date, order: .reverse)
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid }, sort: \ExpenseCategory.sortOrder)
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid }, sort: \ExpenseSubcategory.sortOrder)
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid }, sort: \FamilyMember.joinedAt)
        _filter = State(initialValue: filter)
    }

    private var lookup: CategoryLookup {
        CategoryLookup(categories: categories, subcategories: subcategories)
    }

    private var filtered: [Expense] {
        guard filter.isActive else { return expenses }
        let lookup = lookup
        let base = family.baseCurrencyCode
        return expenses.filter { filter.matches($0.facts(lookup: lookup), baseCurrency: base) }
    }

    private func groupedByDay(_ items: [Expense]) -> [(day: Date, items: [Expense])] {
        let calendar = FamiloqCalendar.make()
        let groups = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { (day: $0, items: groups[$0] ?? []) }
    }

    var body: some View {
        let items = filtered
        let total = items.compactMap(\.baseAmount).reduce(Decimal(0), +)
        List {
            if filter.isActive {
                Section {
                    HStack {
                        Text("\(items.count) expense(s)")
                        Spacer()
                        Text(total.currency(family.baseCurrencyCode)).monospacedDigit().fontWeight(.semibold)
                    }
                    if filter.activeFilterCount > 0 {
                        Button("Clear filters") {
                            let text = filter.text
                            filter = ExpenseFilter()
                            filter.text = text
                        }
                        .font(.footnote)
                    }
                }
            }
            if items.isEmpty {
                EmptyStateView(icon: "magnifyingglass", title: "Nothing found",
                               message: filter.isActive ? "Try a different search or fewer filters." : "No expenses yet.")
            }
            ForEach(groupedByDay(items), id: \.day) { group in
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
        .searchable(text: $filter.text, prompt: "Shop, category, note or amount")
        .navigationTitle("Expenses")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showFilters = true
                } label: {
                    Label(filter.activeFilterCount > 0 ? "Filters (\(filter.activeFilterCount))" : "Filters",
                          systemImage: filter.activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showFilters) {
            NavigationStack {
                ExpenseFilterView(filter: filter, lookup: lookup, members: members) { filter = $0 }
            }
        }
        .sheet(item: $editingExpense) { expense in
            NavigationStack {
                ExpenseFormView(family: family, editing: expense)
            }
        }
    }
}

enum FilterPeriod: String, CaseIterable, Identifiable {
    case any, thisMonth, lastMonth, last3Months, thisYear, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any time"
        case .thisMonth: return "This month"
        case .lastMonth: return "Last month"
        case .last3Months: return "Last 3 months"
        case .thisYear: return "This year"
        case .custom: return "Custom"
        }
    }

    func range(now: Date = Date(), calendar: Calendar = FamiloqCalendar.make()) -> (Date, Date)? {
        guard let month = calendar.dateInterval(of: .month, for: now) else { return nil }
        switch self {
        case .any, .custom: return nil
        case .thisMonth: return (month.start, month.end)
        case .lastMonth:
            let start = calendar.date(byAdding: .month, value: -1, to: month.start) ?? month.start
            return (start, month.start)
        case .last3Months:
            let start = calendar.date(byAdding: .month, value: -2, to: month.start) ?? month.start
            return (start, month.end)
        case .thisYear:
            guard let year = calendar.dateInterval(of: .year, for: now) else { return nil }
            return (year.start, year.end)
        }
    }
}

/// Filter sheet; changes are applied with Done.
struct ExpenseFilterView: View {
    let lookup: CategoryLookup
    let members: [FamilyMember]
    let onApply: (ExpenseFilter) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var filter: ExpenseFilter
    @State private var period: FilterPeriod
    @State private var customFrom: Date
    @State private var customTo: Date
    @State private var minText: String
    @State private var maxText: String

    init(filter: ExpenseFilter, lookup: CategoryLookup, members: [FamilyMember], onApply: @escaping (ExpenseFilter) -> Void) {
        self.lookup = lookup
        self.members = members
        self.onApply = onApply
        _filter = State(initialValue: filter)
        let calendar = FamiloqCalendar.make()
        let matched = FilterPeriod.allCases.first { p in
            guard let r = p.range() else { return false }
            return r.0 == filter.from && r.1 == filter.to
        }
        _period = State(initialValue: filter.from == nil && filter.to == nil ? .any : (matched ?? .custom))
        let monthStart = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        _customFrom = State(initialValue: filter.from ?? monthStart)
        _customTo = State(initialValue: (filter.to.flatMap { calendar.date(byAdding: .day, value: -1, to: $0) }) ?? Date())
        _minText = State(initialValue: filter.minAmount.map { "\($0)" } ?? "")
        _maxText = State(initialValue: filter.maxAmount.map { "\($0)" } ?? "")
    }

    var body: some View {
        Form {
            Section("Period") {
                Picker("Period", selection: $period) {
                    ForEach(FilterPeriod.allCases) { Text($0.title).tag($0) }
                }
                if period == .custom {
                    DatePicker("From", selection: $customFrom, displayedComponents: [.date])
                    DatePicker("To", selection: $customTo, in: customFrom..., displayedComponents: [.date])
                }
            }

            Section("Categories") {
                ForEach(lookup.activeCategories()) { category in
                    toggleRow(title: category.name, icon: category.icon, isOn: filter.categoryIDs.contains(category.id)) {
                        toggle(category.id, in: \.categoryIDs)
                    }
                }
            }

            if members.count > 1 {
                Section("Members") {
                    ForEach(members) { member in
                        toggleRow(title: member.displayName, icon: "person", isOn: filter.memberIDs.contains(member.id)) {
                            toggle(member.id, in: \.memberIDs)
                        }
                    }
                }
            }

            Section("Amount") {
                TextField("Minimum", text: $minText).keyboardType(.decimalPad)
                TextField("Maximum", text: $maxText).keyboardType(.decimalPad)
            }

            Section("Entered as") {
                ForEach(EntryMethod.allCases, id: \.self) { method in
                    toggleRow(title: method.displayName, icon: nil, isOn: filter.entryMethods.contains(method.rawValue)) {
                        if filter.entryMethods.contains(method.rawValue) {
                            filter.entryMethods.remove(method.rawValue)
                        } else {
                            filter.entryMethods.insert(method.rawValue)
                        }
                    }
                }
                Toggle("Only other currencies", isOn: $filter.onlyForeignCurrency)
            }

            Section {
                Button("Reset all filters", role: .destructive) {
                    let text = filter.text
                    filter = ExpenseFilter()
                    filter.text = text
                    period = .any
                    minText = ""
                    maxText = ""
                }
            }
        }
        .navigationTitle("Filters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    var result = filter
                    switch period {
                    case .any:
                        result.from = nil
                        result.to = nil
                    case .custom:
                        let calendar = FamiloqCalendar.make()
                        result.from = calendar.startOfDay(for: customFrom)
                        result.to = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customTo))
                    default:
                        let range = period.range()
                        result.from = range?.0
                        result.to = range?.1
                    }
                    result.minAmount = DecimalParser.parse(minText)
                    result.maxAmount = DecimalParser.parse(maxText)
                    onApply(result)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }

    private func toggle(_ id: UUID, in keyPath: WritableKeyPath<ExpenseFilter, Set<UUID>>) {
        if filter[keyPath: keyPath].contains(id) {
            filter[keyPath: keyPath].remove(id)
        } else {
            filter[keyPath: keyPath].insert(id)
        }
    }

    private func toggleRow(title: String, icon: String?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if let icon { Image(systemName: icon).foregroundStyle(.secondary).frame(width: 24) }
                Text(title).foregroundStyle(.primary)
                Spacer()
                if isOn { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
            .contentShape(Rectangle())
        }
    }
}
