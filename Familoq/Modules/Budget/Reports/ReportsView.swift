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
    /// True when opened from the dashboard (shows a Done button).
    var showsDone = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @State private var period: ReportPeriod = .thisMonth
    @State private var customFrom = FamiloqCalendar.make().dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var customTo = Date()
    @State private var showCustomRange = false
    /// "" = whole family, "none" = not assigned, otherwise a member ID.
    @State private var person = ""

    var body: some View {
        NavigationStack {
            if let family = session.family {
                let range = period.intervals(now: Date(), calendar: FamiloqCalendar.make(), customFrom: customFrom, customTo: customTo)
                ReportContent(family: family, period: period, current: range.current, previous: range.previous,
                              selection: $period, person: $person, onEditRange: { showCustomRange = true })
                    .id("\(period.rawValue)-\(range.current.start.timeIntervalSince1970)-\(range.current.end.timeIntervalSince1970)-\(person)")
                    .navigationTitle("Reports")
                    .toolbar {
                        if showsDone {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { dismiss() }
                            }
                        }
                    }
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
    @Binding var person: String
    let onEditRange: () -> Void
    @State private var showAllSubcategories = false

    @Query private var queriedExpenses: [Expense]
    @Query private var queriedPrevious: [Expense]
    @Query private var queriedTrend: [Expense]
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @Query private var members: [FamilyMember]
    @Query private var budgets: [Budget]

    init(family: Family, period: ReportPeriod, current: DateInterval, previous: DateInterval,
         selection: Binding<ReportPeriod>, person: Binding<String>, onEditRange: @escaping () -> Void) {
        self.family = family
        self.period = period
        self.current = current
        self.onEditRange = onEditRange
        _selection = selection
        _person = person
        let calendar = FamiloqCalendar.make()
        let fid = family.id
        let cs = current.start, ce = current.end, ps = previous.start, pe = previous.end
        let trendEnd = BudgetPeriod.monthly.interval(containing: Date(), calendar: calendar).end
        let trendStart = calendar.date(byAdding: .month, value: -12, to: trendEnd) ?? trendEnd
        _queriedExpenses = Query(filter: #Predicate<Expense> { $0.familyID == fid && $0.date >= cs && $0.date < ce }, sort: \Expense.date, order: .reverse)
        _queriedPrevious = Query(filter: #Predicate<Expense> { $0.familyID == fid && $0.date >= ps && $0.date < pe })
        _queriedTrend = Query(filter: #Predicate<Expense> { $0.familyID == fid && $0.date >= trendStart && $0.date < trendEnd })
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid }, sort: \ExpenseCategory.sortOrder)
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid }, sort: \ExpenseSubcategory.sortOrder)
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid }, sort: \FamilyMember.joinedAt)
        _budgets = Query(filter: #Predicate<Budget> { $0.familyID == fid && $0.isActive == true })
    }

    private var lookup: CategoryLookup { CategoryLookup(categories: categories, subcategories: subcategories) }
    private var currency: String { family.baseCurrencyCode }

    // MARK: Person filter ("click on a person")

    private func matchesPerson(_ expense: Expense) -> Bool {
        switch person {
        case "": return true
        case "none": return expense.memberID == nil
        default: return expense.memberID?.uuidString == person
        }
    }

    private var expenses: [Expense] { queriedExpenses.filter(matchesPerson) }
    private var previousExpenses: [Expense] { queriedPrevious.filter(matchesPerson) }
    private var trendExpenses: [Expense] { queriedTrend.filter(matchesPerson) }

    private var personName: String? {
        switch person {
        case "": return nil
        case "none": return String(localized: "Family / not assigned")
        default: return members.first { $0.id.uuidString == person }?.displayName
        }
    }

    private func entries(_ list: [Expense]) -> [SpendingEntry] {
        list.compactMap { e in
            e.baseAmount.map { SpendingEntry(amount: $0, categoryID: e.categoryID, subcategoryID: e.subcategoryID, memberID: e.memberID, merchant: e.merchant) }
        }
    }

    /// "Meat & Poultry", or "Groceries (general)" for expenses without a subcategory.
    private func subcategoryName(_ key: BreakdownKey) -> String {
        if let sub = lookup.subcategory(key.subcategoryID) { return sub.name }
        let category = lookup.category(key.categoryID)?.name ?? String(localized: "Uncategorized")
        return key.categoryID == nil ? category : String(localized: "\(category) (general)")
    }

    var body: some View {
        let summary = SpendingSummary(expenses: expenses)
        let previous = SpendingSummary(expenses: previousExpenses)
        let rows = categoryRows(summary: summary)
        let currentEntries = entries(expenses)
        let subRows = SpendingBreakdown.rows(current: currentEntries, previous: entries(previousExpenses), level: .subcategory)
        let merchants = SpendingBreakdown.topMerchants(currentEntries, limit: 5)
        let trend = SpendingTrends.monthlyTotals(
            entries: trendExpenses.compactMap { e in e.baseAmount.map { (date: e.date, amount: $0) } },
            months: 12, endingAt: Date(), calendar: FamiloqCalendar.make())
        List {
            Section {
                Picker("Period", selection: $selection) {
                    ForEach(ReportPeriod.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                .pickerStyle(.menu)
                if period == .custom {
                    Button {
                        onEditRange()
                    } label: {
                        Text("\(current.start.formatted(date: .abbreviated, time: .omitted)) – \(current.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))")
                    }
                }

                if members.count > 1 {
                    Picker("Person", selection: $person) {
                        Text("Whole family").tag("")
                        ForEach(members) { member in
                            Text(verbatim: member.displayName).tag(member.id.uuidString)
                        }
                        Text("Family / not assigned").tag("none")
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let personName {
                        Text("Spent by \(personName)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(summary.total.currency(currency))
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    comparisonText(current: summary.total, previous: previous.total)
                }
                .padding(.vertical, 4)
            }

            SpendingInsightsSection(facts: insightFacts(subRows: subRows, categoryRows: rows, total: summary.total, merchants: merchants),
                                    modelInput: modelInput(summary: summary, previous: previous, categoryRows: rows, subRows: subRows, merchants: merchants))

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
                            LazyView(CategoryDrillDownView(
                                categoryName: row.name,
                                categoryID: row.categoryID,
                                expenses: expenses.filter { $0.categoryID == row.categoryID },
                                previousExpenses: previousExpenses.filter { $0.categoryID == row.categoryID },
                                lookup: lookup,
                                currency: currency
                            ))
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

                let visibleSubRows = subRows.filter { $0.current > 0 }
                Section {
                    ForEach(showAllSubcategories ? visibleSubRows : Array(visibleSubRows.prefix(8))) { row in
                        NavigationLink {
                            LazyView(ExpenseDrillDownView(
                                title: subcategoryName(row.key),
                                expenses: expenses.filter { $0.categoryID == row.key.categoryID && $0.subcategoryID == row.key.subcategoryID },
                                lookup: lookup, currency: currency))
                        } label: {
                            ChangeRow(icon: lookup.category(row.key.categoryID)?.icon ?? "tag",
                                      colorHex: lookup.category(row.key.categoryID)?.colorHex ?? "#9E9E9E",
                                      title: subcategoryName(row.key),
                                      subtitle: lookup.category(row.key.categoryID)?.name,
                                      row: row, total: summary.total, currency: currency)
                        }
                    }
                    if visibleSubRows.count > 8 {
                        Button(showAllSubcategories ? LocalizedStringKey("Show fewer") : LocalizedStringKey("Show all \(visibleSubRows.count) subcategories")) {
                            withAnimation { showAllSubcategories.toggle() }
                        }
                    }
                } header: {
                    Text("Top subcategories")
                } footer: {
                    Text("Compared with the previous period of the same length. Receipts split into subcategories (milk, meat, vegetables…) are counted per item group.")
                }

                let changes = SpendingBreakdown.biggestChanges(subRows, minimumChange: minimumChange(total: summary.total))
                if !changes.up.isEmpty || !changes.down.isEmpty {
                    Section("Biggest changes") {
                        ForEach(changes.up + changes.down) { row in
                            ChangeRow(icon: row.change > 0 ? "arrow.up.right" : "arrow.down.right",
                                      colorHex: row.change > 0 ? "#EA4335" : "#34A853",
                                      title: subcategoryName(row.key),
                                      subtitle: String(localized: "was \(row.previous.currency(currency))"),
                                      row: row, total: nil, currency: currency)
                        }
                    }
                }

                if !merchants.isEmpty {
                    Section("Top shops") {
                        ForEach(merchants) { shop in
                            NavigationLink {
                                LazyView(ExpenseDrillDownView(
                                    title: shop.name,
                                    expenses: expenses.filter { $0.merchant.trimmingCharacters(in: .whitespaces).lowercased() == shop.name.lowercased() },
                                    lookup: lookup, currency: currency))
                            } label: {
                                HStack {
                                    Text(verbatim: shop.name)
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text(shop.amount.currency(currency)).monospacedDigit()
                                        Text("\(shop.count)×").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                let memberRows = memberTotals()
                if person.isEmpty && memberRows.count > 1 {
                    Section {
                        ForEach(memberRows) { row in
                            Button {
                                withAnimation { person = row.filterValue }
                            } label: {
                                HStack {
                                    Text(verbatim: row.name).foregroundStyle(.primary)
                                    Spacer()
                                    Text(row.amount.currency(currency)).monospacedDigit().foregroundStyle(.primary)
                                    Text(percentText(row.amount, of: summary.total))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, alignment: .trailing)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    } header: {
                        Text("By member")
                    } footer: {
                        Text("Tap a person to see only their spending - categories, subcategories, shops and changes.")
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

    /// Changes smaller than this are not "big" (3 % of the total, at least 10).
    private func minimumChange(total: Decimal) -> Decimal {
        max(Decimal(10), total * 3 / 100)
    }

    /// Built-in insights (always available, no Apple Intelligence needed).
    private func insightFacts(subRows: [BreakdownRow], categoryRows: [CategoryRow], total: Decimal, merchants: [MerchantTotal]) -> [String] {
        guard total > 0 else { return [] }
        var facts: [String] = []
        if let top = categoryRows.first {
            facts.append(String(localized: "Most money goes to \(top.name): \(top.amount.currency(currency)) (\(percentText(top.amount, of: total)))."))
        }
        if let sub = subRows.first(where: { $0.current > 0 }) {
            facts.append(String(localized: "Largest subcategory: \(subcategoryName(sub.key)) with \(sub.current.currency(currency))."))
        }
        let changes = SpendingBreakdown.biggestChanges(subRows, minimumChange: minimumChange(total: total), limit: 2)
        for row in changes.up {
            if let pct = row.changePercent {
                let pctText = "+\(Int(pct.rounded())) %"
                facts.append(String(localized: "▲ \(subcategoryName(row.key)): \(row.change.currency(currency)) more than before (\(pctText))."))
            } else {
                facts.append(String(localized: "▲ New spending: \(subcategoryName(row.key)) \(row.current.currency(currency))."))
            }
        }
        for row in changes.down.prefix(1) {
            facts.append(String(localized: "▼ \(subcategoryName(row.key)): \((-row.change).currency(currency)) less than before."))
        }
        if let shop = merchants.first {
            facts.append(String(localized: "Most spent at \(shop.name): \(shop.amount.currency(currency)) in \(shop.count) purchase(s)."))
        }
        return facts
    }

    /// The report as plain numbers for Apple Intelligence.
    private func modelInput(summary: SpendingSummary, previous: SpendingSummary, categoryRows: [CategoryRow], subRows: [BreakdownRow], merchants: [MerchantTotal]) -> String {
        func n(_ d: Decimal) -> String { String(format: "%.2f", d.doubleValue) }
        let from = current.start.formatted(date: .abbreviated, time: .omitted)
        let to = current.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted)
        var lines: [String] = [
            "Period: \(period.rawValue), \(from) to \(to). 'before' means the previous period of the same length.",
            "Whose spending: \(personName ?? "the whole family").",
            "Currency: \(currency).",
            "Total: \(n(summary.total)) (before: \(n(previous.total))).",
            "Categories (now / before):"
        ]
        for row in categoryRows.prefix(8) {
            lines.append("- \(row.name): \(n(row.amount)) / \(n(row.categoryID.flatMap { previous.byCategory[$0] } ?? 0))")
        }
        lines.append("Subcategories (now / before):")
        for row in subRows.prefix(12) {
            let category = lookup.category(row.key.categoryID)?.name ?? "Uncategorized"
            lines.append("- \(category) > \(subcategoryName(row.key)): \(n(row.current)) / \(n(row.previous))")
        }
        if !merchants.isEmpty {
            lines.append("Shops: " + merchants.map { "\($0.name) \(n($0.amount)) (\($0.count) purchases)" }.joined(separator: ", "))
        }
        if person.isEmpty {
            let people = memberTotals()
            if people.count > 1 {
                lines.append("People: " + people.map { "\($0.name) \(n($0.amount))" }.joined(separator: ", "))
            }
        }
        return lines.joined(separator: "\n")
    }

    private func memberTotals() -> [MemberTotal] {
        var totals: [UUID?: Decimal] = [:]
        for expense in expenses {
            guard let amount = expense.baseAmount else { continue }
            totals[expense.memberID, default: 0] += amount
        }
        return totals.map { id, amount in
            MemberTotal(name: id.flatMap { mid in members.first { $0.id == mid }?.displayName } ?? String(localized: "Family / not assigned"),
                        amount: amount, filterValue: id?.uuidString ?? "none")
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
    /// Value for the report's person filter.
    var filterValue: String = ""
    var id: String { filterValue.isEmpty ? name : filterValue }
}

struct CategoryRow: Identifiable {
    let categoryID: UUID?
    let name: String
    let icon: String
    let colorHex: String
    let amount: Decimal
    var id: String { categoryID?.uuidString ?? "uncategorized" }
}

/// Amount, change against the previous period ("▲ 12 € (+30 %)", "new").
private struct ChangeRow: View {
    let icon: String
    let colorHex: String
    let title: String
    let subtitle: String?
    let row: BreakdownRow
    let total: Decimal?
    let currency: String

    private var changeText: String {
        if row.previous == 0 { return String(localized: "new") }
        if row.change == 0 { return "±0" }
        let arrow = row.change > 0 ? "▲" : "▼"
        let amount = (row.change > 0 ? row.change : -row.change).currency(currency)
        if let pct = row.changePercent {
            return "\(arrow) \(amount) (\(pct > 0 ? "+" : "")\(Int(pct.rounded())) %)"
        }
        return "\(arrow) \(amount)"
    }

    private var changeColor: Color {
        if row.previous == 0 || row.change == 0 { return .secondary }
        return row.change > 0 ? .red : .green
    }

    var body: some View {
        HStack {
            CategoryIcon(icon: icon, colorHex: colorHex, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                if let subtitle {
                    Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.current.currency(currency)).monospacedDigit()
                Text(verbatim: changeText).font(.caption).foregroundStyle(changeColor)
            }
        }
    }
}

/// The expenses behind a number (a subcategory, a shop).
struct ExpenseDrillDownView: View {
    let title: String
    let expenses: [Expense]
    let lookup: CategoryLookup
    let currency: String

    var body: some View {
        let sorted = expenses.sorted { $0.date > $1.date }
        let total = sorted.compactMap(\.baseAmount).reduce(Decimal(0), +)
        List {
            Section {
                LabeledContent("Total", value: total.currency(currency))
                LabeledContent("Expenses", value: "\(sorted.count)")
            }
            Section {
                ForEach(sorted) { expense in
                    ExpenseRow(expense: expense, lookup: lookup)
                }
            }
        }
        .navigationTitle(Text(verbatim: title))
    }
}

/// Groceries → Meat & Poultry / Vegetables / Fruits … with the change
/// against the previous period; tap a subcategory for its expenses.
struct CategoryDrillDownView: View {
    let categoryName: String
    let categoryID: UUID?
    let expenses: [Expense]
    var previousExpenses: [Expense] = []
    let lookup: CategoryLookup
    let currency: String

    private func entries(_ list: [Expense]) -> [SpendingEntry] {
        list.compactMap { e in e.baseAmount.map { SpendingEntry(amount: $0, categoryID: e.categoryID, subcategoryID: e.subcategoryID, memberID: e.memberID) } }
    }

    var body: some View {
        let rows = SpendingBreakdown.rows(current: entries(expenses), previous: entries(previousExpenses), level: .subcategory)
        let category = lookup.category(categoryID)
        List {
            Section {
                ForEach(rows) { row in
                    let name = lookup.subcategory(row.key.subcategoryID)?.name ?? String(localized: "No subcategory")
                    NavigationLink {
                        LazyView(ExpenseDrillDownView(
                            title: name,
                            expenses: expenses.filter { $0.subcategoryID == row.key.subcategoryID },
                            lookup: lookup, currency: currency))
                    } label: {
                        ChangeRow(icon: category?.icon ?? "tag", colorHex: category?.colorHex ?? "#9E9E9E",
                                  title: name, subtitle: nil, row: row, total: nil, currency: currency)
                    }
                }
            } header: {
                Text("Subcategories")
            } footer: {
                Text("Compared with the previous period of the same length.")
            }
            Section("Expenses") {
                ForEach(expenses.sorted { $0.date > $1.date }) { expense in
                    ExpenseRow(expense: expense, lookup: lookup)
                }
            }
        }
        .navigationTitle(Text(verbatim: categoryName))
    }
}
