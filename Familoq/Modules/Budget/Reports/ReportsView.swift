import SwiftUI
import SwiftData
import Charts
import FamiloqCore
import FamiloqBudget

enum ReportPeriod: String, CaseIterable, Identifiable {
    case today = "Today"
    case thisWeek = "This week"
    case thisMonth = "This month"
    case previousMonth = "Previous month"
    case thisYear = "This year"
    case last12Months = "Last 12 months"
    case custom = "Custom range"

    var id: String { rawValue }

    /// Current interval and the one to compare with (same length, just before).
    func intervals(now: Date, calendar: Calendar, customFrom: Date, customTo: Date) -> (current: DateInterval, previous: DateInterval) {
        func month(_ date: Date) -> DateInterval { BudgetPeriod.monthly.interval(containing: date, calendar: calendar) }
        switch self {
        case .today:
            let current = BudgetPeriod.daily.interval(containing: now, calendar: calendar)
            return (current, BudgetPeriod.daily.interval(containing: current.start.addingTimeInterval(-3600), calendar: calendar))
        case .thisWeek:
            let current = BudgetPeriod.weekly.interval(containing: now, calendar: calendar)
            return (current, BudgetPeriod.weekly.interval(containing: current.start.addingTimeInterval(-3600), calendar: calendar))
        case .thisMonth:
            let current = month(now)
            return (current, month(current.start.addingTimeInterval(-3600)))
        case .previousMonth:
            let current = month(month(now).start.addingTimeInterval(-3600))
            return (current, month(current.start.addingTimeInterval(-3600)))
        case .thisYear:
            let current = calendar.dateInterval(of: .year, for: now) ?? month(now)
            let previous = calendar.dateInterval(of: .year, for: current.start.addingTimeInterval(-3600)) ?? current
            return (current, previous)
        case .last12Months:
            let end = month(now).end
            let start = calendar.date(byAdding: .month, value: -12, to: end) ?? end
            let previousStart = calendar.date(byAdding: .month, value: -12, to: start) ?? start
            return (DateInterval(start: start, end: end), DateInterval(start: previousStart, end: start))
        case .custom:
            let start = calendar.startOfDay(for: min(customFrom, customTo))
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(customFrom, customTo))) ?? start
            let length = end.timeIntervalSince(start)
            return (DateInterval(start: start, end: end), DateInterval(start: start.addingTimeInterval(-length), end: start))
        }
    }

    /// Monthly budgets can be compared directly.
    var isSingleMonth: Bool { self == .thisMonth || self == .previousMonth }
}

/// Reports: totals with comparison, trend over 12 months, categories with
/// drill-down, members, budget vs actual; any period incl. a custom range.
struct ReportsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var period: ReportPeriod = .thisMonth
    @State private var customFrom = FamiloqCalendar.make().dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var customTo = Date()
    @State private var showCustomRange = false

    var body: some View {
        NavigationStack {
            if let family = session.family {
                let range = period.intervals(now: Date(), calendar: FamiloqCalendar.make(), customFrom: customFrom, customTo: customTo)
                ReportContent(family: family, period: period, current: range.current, previous: range.previous,
                              selection: $period, onEditRange: { showCustomRange = true })
                    .id("\(period.rawValue)-\(range.current.start.timeIntervalSince1970)-\(range.current.end.timeIntervalSince1970)")
                    .navigationTitle("Reports")
                    .onChange(of: period) { _, newValue in
                        if newValue == .custom { showCustomRange = true }
                    }
                    .sheet(isPresented: $showCustomRange) {
                        NavigationStack {
                            Form {
                                DatePicker("From", selection: $customFrom, displayedComponents: [.date])
                                DatePicker("To", selection: $customTo, in: customFrom..., displayedComponents: [.date])
                            }
                            .navigationTitle("Custom range")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) { Button("Done") { showCustomRange = false } }
                            }
                        }
                        .presentationDetents([.medium])
                    }
            } else {
                ProgressView()
            }
        }
    }
}

private struct ReportContent: View {
    let family: Family
    let period: ReportPeriod
    let current: DateInterval
    @Binding var selection: ReportPeriod
    let onEditRange: () -> Void

    @Query private var expenses: [Expense]
    @Query private var previousExpenses: [Expense]
    @Query private var trendExpenses: [Expense]
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @Query private var members: [FamilyMember]
    @Query private var budgets: [Budget]

    init(family: Family, period: ReportPeriod, current: DateInterval, previous: DateInterval,
         selection: Binding<ReportPeriod>, onEditRange: @escaping () -> Void) {
        self.family = family
        self.period = period
        self.current = current
        self.onEditRange = onEditRange
        _selection = selection
        let calendar = FamiloqCalendar.make()
        let fid = family.id
        let cs = current.start, ce = current.end, ps = previous.start, pe = previous.end
        let trendEnd = BudgetPeriod.monthly.interval(containing: Date(), calendar: calendar).end
        let trendStart = calendar.date(byAdding: .month, value: -12, to: trendEnd) ?? trendEnd
        _expenses = Query(filter: #Predicate<Expense> { $0.familyID == fid && $0.date >= cs && $0.date < ce }, sort: \Expense.date, order: .reverse)
        _previousExpenses = Query(filter: #Predicate<Expense> { $0.familyID == fid && $0.date >= ps && $0.date < pe })
        _trendExpenses = Query(filter: #Predicate<Expense> { $0.familyID == fid && $0.date >= trendStart && $0.date < trendEnd })
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid }, sort: \ExpenseCategory.sortOrder)
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid }, sort: \ExpenseSubcategory.sortOrder)
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid }, sort: \FamilyMember.joinedAt)
        _budgets = Query(filter: #Predicate<Budget> { $0.familyID == fid && $0.isActive == true })
    }

    private var lookup: CategoryLookup { CategoryLookup(categories: categories, subcategories: subcategories) }
    private var currency: String { family.baseCurrencyCode }

    var body: some View {
        let summary = SpendingSummary(expenses: expenses)
        let previous = SpendingSummary(expenses: previousExpenses)
        let rows = categoryRows(summary: summary)
        let trend = SpendingTrends.monthlyTotals(
            entries: trendExpenses.compactMap { e in e.baseAmount.map { (date: e.date, amount: $0) } },
            months: 12, endingAt: Date(), calendar: FamiloqCalendar.make())
        List {
            Section {
                Picker("Period", selection: $selection) {
                    ForEach(ReportPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                if period == .custom {
                    Button {
                        onEditRange()
                    } label: {
                        Text("\(current.start.formatted(date: .abbreviated, time: .omitted)) – \(current.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))")
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.total.currency(currency))
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    comparisonText(current: summary.total, previous: previous.total)
                }
                .padding(.vertical, 4)
            }

            Section {
                Chart(trend) { month in
                    BarMark(
                        x: .value("Month", month.monthStart, unit: .month),
                        y: .value("Spent", month.total.doubleValue)
                    )
                    .foregroundStyle(month.monthStart >= current.start && month.monthStart < current.end ? Color.accentColor : Color.accentColor.opacity(0.35))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.month(.narrow))
                    }
                }
                .frame(height: 160)
                .accessibilityHidden(true)
                Text("Average of complete months: \(SpendingTrends.averageOfCompleteMonths(trend).currency(currency))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Last 12 months")
            }

            if rows.isEmpty {
                EmptyStateView(icon: "chart.bar", title: "No spending", message: "Nothing recorded for this period.")
            } else {
                Section("By category") {
                    Chart(rows) { row in
                        BarMark(
                            x: .value("Amount", row.amount.doubleValue),
                            y: .value("Category", row.name)
                        )
                        .foregroundStyle(Color(hex: row.colorHex))
                    }
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(max(rows.count, 1)) * 32 + 20)
                    .accessibilityHidden(true)

                    ForEach(rows) { row in
                        NavigationLink {
                            CategoryDrillDownView(
                                categoryName: row.name,
                                categoryID: row.categoryID,
                                expenses: expenses.filter { $0.categoryID == row.categoryID },
                                lookup: lookup,
                                currency: currency
                            )
                        } label: {
                            HStack {
                                CategoryIcon(icon: row.icon, colorHex: row.colorHex, size: 28)
                                Text(row.name)
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(row.amount.currency(currency)).monospacedDigit()
                                    Text(percentText(row.amount, of: summary.total))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                let memberRows = memberTotals()
                if memberRows.count > 1 {
                    Section("By member") {
                        ForEach(memberRows) { row in
                            HStack {
                                Text(row.name)
                                Spacer()
                                Text(row.amount.currency(currency)).monospacedDigit()
                                Text(percentText(row.amount, of: summary.total))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                    }
                }

                if period.isSingleMonth {
                    let monthly = budgets.filter { $0.period == .monthly && $0.scope != .overall }
                    if !monthly.isEmpty {
                        Section("Budget vs actual") {
                            ForEach(BudgetProgressBuilder.progress(budgets: monthly, expenses: expenses, lookup: lookup,
                                                                   now: current.start.addingTimeInterval(3600), calendar: FamiloqCalendar.make())) { item in
                                BudgetProgressRow(progress: item, currencyCode: currency)
                            }
                        }
                    }
                }
            }

            if summary.unconvertedCount > 0 {
                Section {
                    Label("\(summary.unconvertedCount) foreign-currency expense(s) are waiting for an exchange rate.", systemImage: "clock.arrow.circlepath")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func memberTotals() -> [MemberTotal] {
        var totals: [UUID?: Decimal] = [:]
        for expense in expenses {
            guard let amount = expense.baseAmount else { continue }
            totals[expense.memberID, default: 0] += amount
        }
        return totals.map { id, amount in
            MemberTotal(name: id.flatMap { mid in members.first { $0.id == mid }?.displayName } ?? "Family / not assigned", amount: amount)
        }
        .sorted { $0.amount > $1.amount }
    }

    private func categoryRows(summary: SpendingSummary) -> [CategoryRow] {
        var rows: [CategoryRow] = summary.byCategory.map { id, amount in
            let category = lookup.category(id)
            return CategoryRow(categoryID: id, name: category?.name ?? "Deleted category", icon: category?.icon ?? "tag", colorHex: category?.colorHex ?? "#9E9E9E", amount: amount)
        }
        if summary.uncategorized > 0 {
            rows.append(CategoryRow(categoryID: nil, name: "Uncategorized", icon: "questionmark", colorHex: "#9E9E9E", amount: summary.uncategorized))
        }
        return rows.sorted { $0.amount > $1.amount }
    }

    @ViewBuilder
    private func comparisonText(current: Decimal, previous: Decimal) -> some View {
        if previous > 0 {
            let delta = current - previous
            let pct = ((delta / previous) * 100).doubleValue
            Text("\(delta >= 0 ? "▲" : "▼") \((delta >= 0 ? delta : -delta).currency(currency)) (\(String(format: "%.0f", abs(pct)))%) vs previous period")
                .font(.footnote)
                .foregroundStyle(delta > 0 ? Color.red : Color.green)
        } else {
            Text("No spending in the previous period")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func percentText(_ amount: Decimal, of total: Decimal) -> String {
        guard total > 0 else { return "" }
        return String(format: "%.0f %%", (amount / total * 100).doubleValue)
    }
}

struct MemberTotal: Identifiable {
    let name: String
    let amount: Decimal
    var id: String { name }
}

struct CategoryRow: Identifiable {
    let categoryID: UUID?
    let name: String
    let icon: String
    let colorHex: String
    let amount: Decimal
    var id: String { categoryID?.uuidString ?? "uncategorized" }
}

/// Groceries → Meat & Poultry / Vegetables / Fruits … (spec section 19)
struct CategoryDrillDownView: View {
    let categoryName: String
    let categoryID: UUID?
    let expenses: [Expense]
    let lookup: CategoryLookup
    let currency: String

    var body: some View {
        let summary = SpendingSummary(expenses: expenses)
        let noSub = expenses.filter { $0.subcategoryID == nil }.compactMap(\.baseAmount).reduce(Decimal(0), +)
        let rows = summary.bySubcategory
            .map { (id: $0.key, name: lookup.subcategory($0.key)?.name ?? "Other", amount: $0.value) }
            .sorted { $0.amount > $1.amount }
        List {
            Section("Subcategories") {
                ForEach(rows, id: \.id) { row in
                    HStack {
                        Text(row.name)
                        Spacer()
                        Text(row.amount.currency(currency)).monospacedDigit()
                    }
                }
                if noSub > 0 {
                    HStack {
                        Text("No subcategory").foregroundStyle(.secondary)
                        Spacer()
                        Text(noSub.currency(currency)).monospacedDigit()
                    }
                }
            }
            Section("Expenses") {
                ForEach(expenses) { expense in
                    ExpenseRow(expense: expense, lookup: lookup)
                }
            }
        }
        .navigationTitle(categoryName)
    }
}
