import SwiftUI
import SwiftData
import Charts
import FamiloqCore
import FamiloqBudget
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads the grocery purchases of a period: receipt items where a receipt
/// was scanned item by item, otherwise the grocery expense itself.
@MainActor
enum FoodBasketLoader {
    /// - Parameter person: "" = whole family, "none" = not assigned, or a member ID.
    static func purchases(familyID: UUID, interval: DateInterval, person: String, lookup: CategoryLookup, context: ModelContext) -> [FoodPurchase] {
        guard let groceriesID = lookup.categories.first(where: { $0.systemKey == "groceries" })?.id else { return [] }
        let fid = familyID
        let start = interval.start, end = interval.end
        let expenses = ((try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate {
            $0.familyID == fid && $0.date >= start && $0.date < end
        }))) ?? []).filter { expense in
            guard expense.categoryID == groceriesID else { return false }
            switch person {
            case "": return true
            case "none": return expense.memberID == nil
            default: return expense.memberID?.uuidString == person
            }
        }

        var result: [FoodPurchase] = []
        let byReceipt = Dictionary(grouping: expenses.filter { $0.receiptID != nil }) { $0.receiptID! }
        let receiptIDs = Array(byReceipt.keys)
        let items = receiptIDs.isEmpty ? [] : ((try? context.fetch(FetchDescriptor<ReceiptItemRecord>(predicate: #Predicate {
            receiptIDs.contains($0.receiptID)
        }))) ?? [])
        let itemsByReceipt = Dictionary(grouping: items.filter { $0.name != ReceiptSaver.differenceItemName }) { $0.receiptID }

        for (receiptID, receiptExpenses) in byReceipt {
            let date = receiptExpenses.first?.date ?? start
            guard let receiptItems = itemsByReceipt[receiptID], !receiptItems.isEmpty else {
                result += receiptExpenses.compactMap { purchase(from: $0, lookup: lookup) }
                continue
            }
            // Receipt currency -> base currency (e.g. a Czech receipt).
            let amount = receiptExpenses.map(\.amount).reduce(0, +)
            let base = receiptExpenses.compactMap(\.baseAmount).reduce(0, +)
            let factor: Decimal = amount > 0 && base > 0 ? base / amount : 1
            for item in receiptItems where item.categoryID == groceriesID || item.categoryID == nil {
                result.append(FoodPurchase(name: item.name, amount: item.amount * factor,
                                           subcategoryKey: lookup.subcategory(item.subcategoryID)?.systemKey, date: date))
            }
        }
        result += expenses.filter { $0.receiptID == nil }.compactMap { purchase(from: $0, lookup: lookup) }
        return result
    }

    private static func purchase(from expense: Expense, lookup: CategoryLookup) -> FoodPurchase? {
        guard let amount = expense.baseAmount else { return nil }
        let name = expense.note.isEmpty ? (lookup.subcategory(expense.subcategoryID)?.name ?? expense.merchant) : expense.note
        return FoodPurchase(name: name, amount: amount, subcategoryKey: lookup.subcategory(expense.subcategoryID)?.systemKey, date: expense.date)
    }
}

/// Reports row: the score with a link to the details.
struct FoodBalanceCard: View {
    let family: Family
    let current: DateInterval
    let previous: DateInterval
    let person: String
    let lookup: CategoryLookup
    @Environment(\.modelContext) private var context
    @State private var score: Int?
    @State private var previousScore: Int?
    @State private var loaded = false

    var body: some View {
        Section {
            NavigationLink {
                LazyView(FoodBalanceView(family: family, current: current, previous: previous, person: person, lookup: lookup))
            } label: {
                HStack(spacing: 12) {
                    ScoreBadge(score: score, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Healthy basket")
                        if let score {
                            Text(LocalizedStringKey(FoodBalance.rating(score))).font(.caption).foregroundStyle(.secondary)
                        } else if loaded {
                            Text("Scan receipts item by item to see how balanced your food shopping is.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let score, let previousScore {
                        ScoreDelta(delta: score - previousScore)
                    }
                }
            }
        }
        .task {
            let now = FoodBalance.report(FoodBasketLoader.purchases(familyID: family.id, interval: current, person: person, lookup: lookup, context: context))
            let before = FoodBalance.report(FoodBasketLoader.purchases(familyID: family.id, interval: previous, person: person, lookup: lookup, context: context))
            score = now.score
            previousScore = before.score
            loaded = true
        }
    }
}

struct ScoreBadge: View {
    let score: Int?
    var size: CGFloat = 44

    static func color(_ score: Int?) -> Color {
        guard let score else { return .secondary }
        switch score {
        case 75...: return .green
        case 55..<75: return Color(hex: "#7CB342")
        case 35..<55: return .orange
        default: return .red
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: size * 0.1)
            Circle()
                .trim(from: 0, to: CGFloat(score ?? 0) / 100)
                .stroke(Self.color(score), style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: score.map(String.init) ?? "–")
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text("Score \(score ?? 0) of 100"))
    }
}

struct ScoreDelta: View {
    let delta: Int

    var body: some View {
        if delta != 0 {
            Text(verbatim: "\(delta > 0 ? "▲" : "▼") \(abs(delta))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(delta > 0 ? Color.green : Color.red)
        }
    }
}

/// The details: groups, nutrients with ideas, less healthy purchases,
/// comparison and a 6-month trend.
struct FoodBalanceView: View {
    let family: Family
    let current: DateInterval
    let previous: DateInterval
    let person: String
    let lookup: CategoryLookup
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @State private var report: FoodBalanceReport?
    @State private var previousReport: FoodBalanceReport?
    @State private var trend: [TrendPoint] = []

    struct TrendPoint: Identifiable {
        let month: Date
        let score: Int
        var id: Date { month }
    }
    @State private var added: Set<String> = []
    @State private var aiAnswer: String?
    @State private var aiWorking = false

    private var currency: String { family.baseCurrencyCode }

    var body: some View {
        List {
            if let report {
                header(report)
                groupsSection(report)
                nutrientsSection(report)
                lessHealthySection(report)
                trendSection
                aiSection(report)
            } else {
                ProgressView()
            }
            Section {
                EmptyView()
            } footer: {
                Text("Estimated from what your family bought and what it cost - not from what was eaten or from nutrition labels. A friendly guide, not medical or nutrition advice.")
            }
        }
        .navigationTitle("Healthy basket")
        .task { load() }
    }

    private func load() {
        let calendar = FamiloqCalendar.make()
        report = FoodBalance.report(FoodBasketLoader.purchases(familyID: family.id, interval: current, person: person, lookup: lookup, context: context))
        previousReport = FoodBalance.report(FoodBasketLoader.purchases(familyID: family.id, interval: previous, person: person, lookup: lookup, context: context))
        let monthEnd = calendar.dateInterval(of: .month, for: Date())?.end ?? Date()
        let sixMonths = calendar.date(byAdding: .month, value: -6, to: monthEnd) ?? monthEnd
        let history = FoodBasketLoader.purchases(familyID: family.id, interval: DateInterval(start: sixMonths, end: monthEnd), person: person, lookup: lookup, context: context)
        trend = FoodBalance.monthlyScores(history, months: 6, endingAt: Date(), calendar: calendar)
            .compactMap { point in point.score.map { TrendPoint(month: point.month, score: $0) } }
    }

    // MARK: Sections

    @ViewBuilder
    private func header(_ report: FoodBalanceReport) -> some View {
        Section {
            HStack(spacing: 16) {
                ScoreBadge(score: report.score, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    if let score = report.score {
                        Text(LocalizedStringKey(FoodBalance.rating(score))).font(.title3.weight(.semibold))
                        if let before = previousReport?.score {
                            HStack(spacing: 4) {
                                ScoreDelta(delta: score - before)
                                Text("vs previous period (\(before))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Not enough data yet").font(.headline)
                        Text("Scan a few receipts item by item (not as one category) to get a score.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Food: \(report.foodTotal.currency(currency)) · \(report.purchaseCount) item(s)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func groupsSection(_ report: FoodBalanceReport) -> some View {
        let groups = FoodGroup.allCases.filter { $0.isFood && (report.amounts[$0] ?? 0) > 0 }
            .sorted { report.share($0) > report.share($1) }
        if !groups.isEmpty {
            Section {
                ForEach(groups, id: \.self) { group in
                    let share = report.share(group)
                    let before = previousReport?.share(group) ?? 0
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: group.icon).foregroundStyle(Color(hex: group.colorHex)).frame(width: 22)
                            Text(LocalizedStringKey(group.title))
                                .foregroundStyle(group.isLessHealthy ? Color.orange : Color.primary)
                            Spacer()
                            Text(verbatim: "\(Int((share * 100).rounded())) %").monospacedDigit()
                            if previousReport?.score != nil {
                                let diff = Int(((share - before) * 100).rounded())
                                if diff != 0 {
                                    Text(verbatim: diff > 0 ? "+\(diff)" : "\(diff)")
                                        .font(.caption2).foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                                }
                            }
                        }
                        ProgressView(value: min(share, 1))
                            .tint(Color(hex: group.colorHex))
                    }
                }
            } header: {
                Text("What was bought")
            } footer: {
                Text("Share of the money spent on food. Small numbers: change in percentage points against the previous period.")
            }
        }
    }

    @ViewBuilder
    private func nutrientsSection(_ report: FoodBalanceReport) -> some View {
        Section {
            ForEach(Nutrient.allCases, id: \.self) { nutrient in
                let level = report.level(nutrient)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: level == .good ? "checkmark.circle.fill" : (level == .low ? "exclamationmark.circle.fill" : "xmark.circle.fill"))
                            .foregroundStyle(level == .good ? Color.green : (level == .low ? Color.orange : Color.red))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(LocalizedStringKey(nutrient.title))
                            Text(LocalizedStringKey(nutrient.sources)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(LocalizedStringKey(level == .good ? "Well covered" : (level == .low ? "A bit low" : "Missing")))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if level != .good {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(nutrient.ideas, id: \.self) { idea in
                                    let name = String(localized: String.LocalizationValue(idea))
                                    Button {
                                        addToShoppingList(name)
                                    } label: {
                                        Label(name, systemImage: added.contains(name) ? "checkmark" : "plus")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                    .controlSize(.small)
                                    .disabled(added.contains(name))
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Nutrients")
        } footer: {
            Text("Tap an idea to put it on the shopping list (optional).")
        }
    }

    @ViewBuilder
    private func lessHealthySection(_ report: FoodBalanceReport) -> some View {
        if !report.lessHealthyItems.isEmpty {
            Section {
                ForEach(report.lessHealthyItems) { item in
                    HStack {
                        Image(systemName: item.group.icon).foregroundStyle(.orange).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: item.name)
                            Text(LocalizedStringKey(item.group.title)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.amount.currency(currency)).monospacedDigit()
                    }
                }
            } header: {
                Text("Better less often") + Text(verbatim: " (\(Int((report.lessHealthyShare * 100).rounded())) %)")
            } footer: {
                Text(swapTip(report))
            }
        }
    }

    private func swapTip(_ report: FoodBalanceReport) -> LocalizedStringKey {
        if report.share(.sugaryDrinks) >= report.share(.sweetsSnacks) && report.share(.sugaryDrinks) > 0 {
            return "Swap idea: water or unsweetened tea instead of soft drinks and juice."
        }
        if report.share(.processedMeat) > report.share(.sweetsSnacks) {
            return "Swap idea: fresh chicken, fish or pulses instead of sausage and cold cuts."
        }
        if report.share(.readyMeals) > report.share(.sweetsSnacks) {
            return "Swap idea: cook a simple meal with vegetables instead of ready meals."
        }
        return "Swap idea: fruit, nuts or yoghurt instead of sweets and snacks."
    }

    @ViewBuilder
    private var trendSection: some View {
        if trend.count >= 2 {
            Section("Last 6 months") {
                Chart(trend) { point in
                    LineMark(x: .value("Month", point.month, unit: .month), y: .value("Score", point.score))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Month", point.month, unit: .month), y: .value("Score", point.score))
                        .foregroundStyle(ScoreBadge.color(point.score))
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) }
                }
                .frame(height: 150)
            }
        }
    }

    @ViewBuilder
    private func aiSection(_ report: FoodBalanceReport) -> some View {
        if case .available = AppleIntelligence.state, report.score != nil {
            Section {
                if let aiAnswer {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Apple Intelligence", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(.purple)
                        Text(verbatim: aiAnswer).font(.subheadline)
                    }
                } else {
                    Button {
                        Task { await explain(report) }
                    } label: {
                        HStack {
                            Label("Tips from Apple Intelligence", systemImage: "sparkles")
                            if aiWorking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(aiWorking)
                }
            } footer: {
                if aiAnswer != nil {
                    Text("Written on this iPhone - nothing is sent anywhere. It can make mistakes.")
                }
            }
        }
    }

    // MARK: Actions

    private func addToShoppingList(_ name: String) {
        guard let list = ShoppingService.lists(familyID: family.id, context: context).first else { return }
        ShoppingService.add(name, listID: list.id, familyID: family.id, memberID: session.currentMember?.id, context: context)
        added.insert(name)
        session.notice = String(localized: "Added to the shopping list: \(name)")
    }

    private func explain(_ report: FoodBalanceReport) async {
        aiWorking = true
        defer { aiWorking = false }
        var lines = ["Score: \(report.score ?? 0) of 100.", "Share of food spending by group:"]
        for group in FoodGroup.allCases where group.isFood && report.share(group) > 0 {
            lines.append("- \(group.title): \(Int((report.share(group) * 100).rounded())) %")
        }
        lines.append("Nutrients (estimated from what was bought): " + report.nutrients.map { "\($0.0.title) \($0.1 == .good ? "good" : ($0.1 == .low ? "low" : "missing"))" }.joined(separator: ", "))
        if !report.lessHealthyItems.isEmpty {
            lines.append("Less healthy purchases: " + report.lessHealthyItems.map(\.name).joined(separator: ", "))
        }
        aiAnswer = try? await AppleIntelligence.foodTips(lines.joined(separator: "\n"))
        if aiAnswer == nil {
            session.notice = String(localized: "Apple Intelligence is not available right now.")
        }
    }
}

extension AppleIntelligence {
    /// Friendly, practical shopping tips from the basket summary.
    static func foodTips(_ summary: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: """
                You give a family friendly, practical grocery shopping tips based only on the summary of what they bought. \
                Write in \(answerLanguage). Give 3 to 5 short bullet points starting with "• ": what is already good, \
                what could be added for more balance (name concrete foods), and one gentle swap for less healthy items. \
                This is not medical advice: never mention calories, weight, diets, diseases or supplements, and never judge. \
                No greeting, no closing sentence.
                """)
            let response = try await session.respond(to: summary)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw NSError(domain: "Familoq", code: 2)
    }
}
