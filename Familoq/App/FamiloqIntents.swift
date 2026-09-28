import AppIntents
import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqBudget

// Siri & Shortcuts ("Hey Siri, add to the shopping list in Familoq").
// App Intents need no extra capability or certificate. They run inside
// Familoq and save to the same database; iCloud sync sends the change the
// next time Familoq is active.

@MainActor
enum IntentData {
    static func context() throws -> ModelContext {
        try PersistenceController.shared().mainContext
    }

    /// The family used last in the app, and "me" in it.
    static func active(_ context: ModelContext) -> (family: Family, me: FamilyMember?)? {
        let families = (try? context.fetch(FetchDescriptor<Family>(sortBy: [SortDescriptor(\Family.createdAt)]))) ?? []
        let activeID = UserDefaults.standard.string(forKey: "activeFamilyID").flatMap(UUID.init(uuidString:))
        guard let family = families.first(where: { $0.id == activeID }) ?? families.first else { return nil }
        let fid = family.id
        let me = (try? context.fetch(FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.familyID == fid && $0.isCurrentUser == true })))?.first
        return (family, me)
    }

    static let notSetUp: IntentDialog = "Open Familoq once to set up your family first."
}

struct AddToShoppingListIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to shopping list"
    static let description = IntentDescription("Puts an item on the family's shopping list, e.g. \"2x milk\".")
    static let openAppWhenRun = false

    @Parameter(title: "Item", requestValueDialog: "What should I put on the list?")
    var item: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentData.context()
        guard let active = IntentData.active(context),
              let list = ShoppingService.lists(familyID: active.family.id, context: context).first else {
            return .result(dialog: IntentData.notSetUp)
        }
        ShoppingService.add(item, listID: list.id, familyID: active.family.id, memberID: active.me?.id, context: context)
        return .result(dialog: "Added \(item) to the shopping list.")
    }
}

struct LogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log an expense"
    static let description = IntentDescription("Adds an expense in the family's base currency, e.g. 12 € fuel.")
    static let openAppWhenRun = false

    @Parameter(title: "Amount", requestValueDialog: "How much was it?")
    var amount: Double

    @Parameter(title: "Shop or purpose", requestValueDialog: "Where or what for?")
    var merchant: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentData.context()
        guard let active = IntentData.active(context) else { return .result(dialog: IntentData.notSetUp) }
        let family = active.family
        let value = Decimal(string: String(format: "%.2f", amount)) ?? Decimal(amount)
        guard value > 0 else { return .result(dialog: "The amount must be more than zero.") }
        let fid = family.id
        let rules = (try? context.fetch(FetchDescriptor<MerchantRuleRecord>(predicate: #Predicate { $0.familyID == fid }))) ?? []
        let name = merchant.trimmingCharacters(in: .whitespaces)
        let expense = Expense(familyID: fid, amount: value, currencyCode: family.baseCurrencyCode, baseCurrencyCode: family.baseCurrencyCode,
                              merchant: name.isEmpty ? String(localized: "Expense") : name, date: Date())
        if let suggestion = CategorizationService.suggestion(for: name, rules: rules) {
            expense.categoryID = suggestion.categoryID
            expense.subcategoryID = suggestion.subcategoryID
        }
        expense.memberID = active.me?.id
        expense.createdByMemberID = active.me?.id
        expense.entryMethod = .quick
        expense.resetConversion()
        context.insert(expense)
        try context.save()
        let text = value.currency(family.baseCurrencyCode)
        return .result(dialog: "Logged \(text) for \(expense.merchant).")
    }
}

struct SpendingThisMonthIntent: AppIntent {
    static let title: LocalizedStringResource = "Spending this month"
    static let description = IntentDescription("Tells how much the family spent this month and where most of it went.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentData.context()
        guard let active = IntentData.active(context) else { return .result(dialog: IntentData.notSetUp) }
        let family = active.family
        let calendar = FamiloqCalendar.make()
        let month = BudgetPeriod.monthly.interval(containing: Date(), calendar: calendar)
        let fid = family.id, start = month.start, end = month.end
        let expenses = (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.familyID == fid && $0.date >= start && $0.date < end }))) ?? []
        let total = expenses.compactMap(\.baseAmount).reduce(0, +)
        let byCategory = Dictionary(grouping: expenses.filter { $0.baseAmount != nil }, by: \.categoryID).mapValues { $0.compactMap(\.baseAmount).reduce(0, +) }
        let text = total.currency(family.baseCurrencyCode)
        if let top = byCategory.max(by: { $0.value < $1.value }), let categoryID = top.key {
            var d = FetchDescriptor<ExpenseCategory>(predicate: #Predicate { $0.id == categoryID })
            d.fetchLimit = 1
            let name = (try? context.fetch(d).first?.name) ?? ""
            return .result(dialog: "This month you spent \(text). Most went to \(name) (\(top.value.currency(family.baseCurrencyCode))).")
        }
        return .result(dialog: "This month you spent \(text).")
    }
}

struct AddFamilyReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a family reminder"
    static let description = IntentDescription("Adds a reminder for the family in Familoq.")
    static let openAppWhenRun = false

    @Parameter(title: "Reminder", requestValueDialog: "What should I remind you of?")
    var title: String

    @Parameter(title: "When")
    var date: Date?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentData.context()
        guard let active = IntentData.active(context) else { return .result(dialog: IntentData.notSetUp) }
        let reminder = FamilyReminder(familyID: active.family.id, title: title)
        reminder.createdByMemberID = active.me?.id
        if let date {
            reminder.dueDate = date
            reminder.hasTime = true
            reminder.repeatStart = date
        }
        context.insert(reminder)
        try context.save()
        await PlannerNotifications.reschedule(context: context)
        return .result(dialog: "Added the reminder \"\(title)\".")
    }
}

struct FamiloqShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddToShoppingListIntent(),
                    phrases: ["Add to the shopping list in \(.applicationName)", "Add something to my \(.applicationName) list"],
                    shortTitle: "Add to shopping list", systemImageName: "cart.badge.plus")
        AppShortcut(intent: LogExpenseIntent(),
                    phrases: ["Log an expense in \(.applicationName)", "Add an expense to \(.applicationName)"],
                    shortTitle: "Log an expense", systemImageName: "eurosign.circle")
        AppShortcut(intent: SpendingThisMonthIntent(),
                    phrases: ["What did we spend this month in \(.applicationName)", "How much did we spend in \(.applicationName)"],
                    shortTitle: "Spending this month", systemImageName: "chart.bar.xaxis")
        AppShortcut(intent: AddFamilyReminderIntent(),
                    phrases: ["Add a family reminder in \(.applicationName)", "Remind the family in \(.applicationName)"],
                    shortTitle: "Family reminder", systemImageName: "bell.badge")
    }
}

/// Family → Siri & Shortcuts: what to say.
struct SiriHelpView: View {
    var body: some View {
        List {
            Section {
                phrase("Hey Siri, add to the shopping list in Familoq", icon: "cart.badge.plus")
                phrase("Hey Siri, log an expense in Familoq", icon: "eurosign.circle")
                phrase("Hey Siri, what did we spend this month in Familoq", icon: "chart.bar.xaxis")
                phrase("Hey Siri, add a family reminder in Familoq", icon: "bell.badge")
            } header: {
                Text("Say")
            } footer: {
                Text("Siri then asks for the item, amount or reminder. The same actions are in the Shortcuts app, in Spotlight and for the Action button.")
            }
            Section {
                ShortcutsLink()
            }
        }
        .navigationTitle("Siri & Shortcuts")
    }

    private func phrase(_ text: LocalizedStringKey, icon: String) -> some View {
        Label(text, systemImage: icon)
    }
}
