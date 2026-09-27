import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqBudget

struct DashboardView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        NavigationStack {
            if let family = session.family {
                DashboardContent(family: family)
            } else {
                ProgressView()
            }
        }
    }
}

private struct DashboardContent: View {
    let family: Family

    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var rates: ExchangeRateService
    @Query private var periodExpenses: [Expense]
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @Query private var budgets: [Budget]

    @State private var showSafeToSpendExplanation = false
    @State private var editingExpense: Expense?

    private let now: Date
    private let calendar: Calendar
    private let month: DateInterval

    init(family: Family) {
        self.family = family
        let calendar = FamiloqCalendar.make()
        let now = Date()
        let month = BudgetPeriod.monthly.interval(containing: now, calendar: calendar)
        let week = BudgetPeriod.weekly.interval(containing: now, calendar: calendar)
        self.now = now
        self.calendar = calendar
        self.month = month

        // Load everything from the earlier of (month start, week start) so
        // daily/weekly/monthly budgets can all be evaluated.
        let start = min(month.start, week.start)
        let end = max(month.end, week.end)
        let fid = family.id
        _periodExpenses = Query(
            filter: #Predicate<Expense> { $0.familyID == fid && $0.date >= start && $0.date < end },
            sort: \Expense.date,
            order: .reverse
        )
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid }, sort: \ExpenseCategory.sortOrder)
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid }, sort: \ExpenseSubcategory.sortOrder)
        _budgets = Query(filter: #Predicate<Budget> { $0.familyID == fid && $0.isActive == true })
    }

    private var lookup: CategoryLookup {
        CategoryLookup(categories: categories, subcategories: subcategories)
    }

    private var monthExpenses: [Expense] {
        periodExpenses.filter { $0.date >= month.start && $0.date < month.end }
    }

    private var monthSummary: SpendingSummary {
        SpendingSummary(expenses: monthExpenses)
    }

    private var overallMonthlyBudget: Budget? {
        budgets.first { $0.scope == .overall && $0.period == .monthly }
    }

    private var currency: String { family.baseCurrencyCode }

    var body: some View {
        let summary = monthSummary
        let progress = BudgetProgressBuilder.progress(budgets: budgets, expenses: periodExpenses, lookup: lookup, now: now, calendar: calendar)
        let categoryProgress = progress.filter { $0.budget.scope == .category && $0.budget.period == .monthly }
        List {
            Section {
                headerCard(summary: summary)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if summary.unconvertedCount > 0 {
                Section {
                    Label("\(summary.unconvertedCount) foreign-currency expense(s) are waiting for an exchange rate and are not in the totals yet.", systemImage: "clock.arrow.circlepath")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Budgets this month") {
                if categoryProgress.isEmpty {
                    NavigationLink {
                        BudgetListView(family: family)
                    } label: {
                        Label("Set category budgets", systemImage: "slider.horizontal.3")
                    }
                } else {
                    ForEach(categoryProgress) { item in
                        BudgetProgressRow(progress: item, currencyCode: currency)
                    }
                    NavigationLink("All budgets") {
                        BudgetListView(family: family)
                    }
                }
            }

            Section {
                if monthExpenses.isEmpty {
                    EmptyStateView(icon: "tray", title: "No expenses yet", message: "Use the Add tab to record your first expense - receipts are optional.")
                } else {
                    ForEach(monthExpenses.prefix(6)) { expense in
                        Button {
                            editingExpense = expense
                        } label: {
                            ExpenseRow(expense: expense, lookup: lookup)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                HStack {
                    Text("Recent expenses")
                    Spacer()
                    NavigationLink("See all") {
                        ExpenseListView(family: family)
                    }
                    .font(.footnote)
                }
            }

            Section("Upcoming") {
                Label("Recurring and planned expenses arrive in Phase 5 and will be reserved in Safe to spend automatically.", systemImage: "calendar.badge.clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(month.start.formatted(.dateTime.month(.wide).year()))
        .refreshable {
            await rates.refreshPending(familyID: family.id, baseCurrency: family.baseCurrencyCode, context: modelContextForRefresh)
        }
        .sheet(isPresented: $showSafeToSpendExplanation) {
            if let result = safeToSpend(summary: summary), let budget = overallMonthlyBudget {
                SafeToSpendExplanationView(result: result, budget: budget.amount, spent: summary.total, currencyCode: currency)
            }
        }
        .sheet(item: $editingExpense) { expense in
            NavigationStack {
                ExpenseFormView(family: family, editing: expense)
            }
        }
    }

    @Environment(\.modelContext) private var modelContextForRefresh

    // MARK: Header

    @ViewBuilder
    private func headerCard(summary: SpendingSummary) -> some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                metric(title: "Spent", value: summary.total.currencyShort(currency))
                Spacer()
                if let budget = overallMonthlyBudget {
                    let remaining = budget.amount - summary.total
                    metric(title: remaining >= 0 ? "Remaining" : "Over budget",
                           value: (remaining >= 0 ? remaining : -remaining).currencyShort(currency),
                           color: remaining >= 0 ? .primary : .red)
                }
            }

            if let result = safeToSpend(summary: summary) {
                Button {
                    showSafeToSpendExplanation = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Safe to spend")
                                .font(.subheadline.weight(.medium))
                            Text(result.isOverBudget ? "Budget exceeded" : "\(result.weeklyAmount.currencyShort(currency)) this week")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(result.dailyAmount.currency(currency))/day")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(result.isOverBudget ? Color.red : Color.primary)
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows how this amount is calculated")
            } else {
                NavigationLink {
                    BudgetListView(family: family)
                } label: {
                    Label("Set a monthly family budget to see Safe to spend", systemImage: "target")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(
            LinearGradient(colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func metric(title: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func safeToSpend(summary: SpendingSummary) -> SafeToSpendResult? {
        guard let budget = overallMonthlyBudget else { return nil }
        // Phase 5 adds upcoming recurring/planned expenses here.
        let input = SafeToSpendInput(budget: budget.amount, spent: summary.total, upcomingCommitted: 0, today: now, periodEnd: month.end)
        return SafeToSpendCalculator.calculate(input, calendar: calendar, currencyCode: currency)
    }
}

struct SafeToSpendExplanationView: View {
    let result: SafeToSpendResult
    let budget: Decimal
    let spent: Decimal
    let currencyCode: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("How it is calculated") {
                    row("Monthly budget", budget)
                    row("− Spent so far", spent)
                    row("= Remaining", result.remaining, bold: true)
                    row("− Upcoming bills (recurring & planned)", result.upcomingCommitted)
                    row("= Available", result.available, bold: true)
                    HStack {
                        Text("÷ Days left (including today)")
                        Spacer()
                        Text("\(result.remainingDays)").monospacedDigit()
                    }
                    row("= Safe to spend per day", result.dailyAmount, bold: true)
                    row("Next 7 days", result.weeklyAmount)
                }
                Section {
                    Text("Daily amounts are rounded down so you never overshoot. Only converted amounts in \(currencyCode) are included; foreign-currency expenses waiting for an exchange rate are counted once converted.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if result.isOverBudget {
                        Text("You are \(result.shortfall.currency(currencyCode)) over budget for this month.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Safe to spend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ title: String, _ value: Decimal, bold: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.currency(currencyCode)).monospacedDigit()
        }
        .font(bold ? .body.weight(.semibold) : .body)
    }
}
