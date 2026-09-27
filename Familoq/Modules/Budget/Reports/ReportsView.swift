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

    var id: String { rawValue }

    func interval(now: Date, calendar: Calendar) -> DateInterval {
        switch self {
        case .today: return BudgetPeriod.daily.interval(containing: now, calendar: calendar)
        case .thisWeek: return BudgetPeriod.weekly.interval(containing: now, calendar: calendar)
        case .thisMonth: return BudgetPeriod.monthly.interval(containing: now, calendar: calendar)
        case .previousMonth:
            let thisMonth = BudgetPeriod.monthly.interval(containing: now, calendar: calendar)
            let dayBefore = thisMonth.start.addingTimeInterval(-3600)
            return BudgetPeriod.monthly.interval(containing: dayBefore, calendar: calendar)
        }
    }

    /// The period to compare against (same length, immediately before).
    func previousInterval(now: Date, calendar: Calendar) -> DateInterval {
        let current = interval(now: now, calendar: calendar)
        let justBefore = current.start.addingTimeInterval(-3600)
        switch self {
        case .today: return BudgetPeriod.daily.interval(containing: justBefore, calendar: calendar)
        case .thisWeek: return BudgetPeriod.weekly.interval(containing: justBefore, calendar: calendar)
        case .thisMonth, .previousMonth: return BudgetPeriod.monthly.interval(containing: justBefore, calendar: calendar)
        }
    }
}

/// Phase 1 reports: category breakdown with drill-down to subcategories and
/// comparison with the previous period. Trends, budget-vs-actual history and
/// custom ranges arrive in Phase 5.
struct ReportsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var period: ReportPeriod = .thisMonth

    var body: some View {
        NavigationStack {
            if let family = session.family {
                ReportContent(family: family, period: period, selection: $period)
                    .id(period)
                    .navigationTitle("Reports")
            } else {
                ProgressView()
            }
        }
    }
}

private struct ReportContent: View {
    let family: Family
    let period: ReportPeriod
    @Binding var selection: ReportPeriod

    @Query private var expenses: [Expense]
    @Query private var previousExpenses: [Expense]
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]

    init(family: Family, period: ReportPeriod, selection: Binding<ReportPeriod>) {
        self.family = family
        self.period = period
        _selection = selection
        let calendar = FamiloqCalendar.make()
        let now = Date()
        let current = period.interval(now: now, calendar: calendar)
        let previous = period.previousInterval(now: now, calendar: calendar)
        let fid = family.id
        let cs = current.start, ce = current.end, ps = previous.start, pe = previous.end
        _expenses = Query(filter: #Predicate<Expense> { $0.familyID == fid && $0.date >= cs && $0.date < ce }, sort: \Expense.date, order: .reverse)
        _previousExpenses = Query(filter: #Predicate<Expense> { $0.familyID == fid && $0.date >= ps && $0.date < pe })
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid }, sort: \ExpenseCategory.sortOrder)
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid }, sort: \ExpenseSubcategory.sortOrder)
    }

    private var lookup: CategoryLookup { CategoryLookup(categories: categories, subcategories: subcategories) }
    private var currency: String { family.baseCurrencyCode }

    var body: some View {
        let summary = SpendingSummary(expenses: expenses)
        let previous = SpendingSummary(expenses: previousExpenses)
        let rows = categoryRows(summary: summary)
        List {
            Section {
                Picker("Period", selection: $selection) {
                    ForEach(ReportPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.total.currency(currency))
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    comparisonText(current: summary.total, previous: previous.total)
                }
                .padding(.vertical, 4)
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
