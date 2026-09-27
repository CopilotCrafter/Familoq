import Foundation
import SwiftData
import FamiloqCore
import FamiloqBudget

/// Sample data for CI screenshots and first-look demos.
/// Only runs with the launch argument `-seedDemoData YES` and only into a
/// family that has no expenses yet.
@MainActor
enum DemoDataSeeder {
    static func seedIfEmpty(family: Family, member: FamilyMember?, context: ModelContext) {
        let repository = FamilyRepository(context: context, familyID: family.id)
        guard let existing = try? repository.allExpenses(), existing.isEmpty,
              let categories = try? repository.categories(),
              let subcategories = try? repository.subcategories() else { return }

        func cat(_ key: String) -> UUID? { categories.first { $0.systemKey == key }?.id }
        func sub(_ key: String) -> UUID? { subcategories.first { $0.systemKey == key }?.id }

        let base = family.baseCurrencyCode
        let calendar = FamiloqCalendar.make()
        let now = Date()
        let monthStart = BudgetPeriod.monthly.interval(containing: now, calendar: calendar).start

        // Budgets from the spec example.
        let budgets: [(BudgetScope, String?, String?, Decimal)] = [
            (.overall, nil, nil, 3000),
            (.category, "groceries", nil, 600),
            (.subcategory, nil, "groceries.meat", 120),
            (.subcategory, nil, "groceries.vegetables", 80),
            (.category, "restaurants", nil, 200),
            (.category, "transport", nil, 300),
            (.category, "shopping", nil, 250)
        ]
        for (scope, catKey, subKey, amount) in budgets {
            let subID = subKey.flatMap { sub($0) }
            let catID: UUID? = catKey.flatMap { cat($0) } ?? subcategories.first { $0.id == subID }?.categoryID
            context.insert(Budget(familyID: family.id, period: .monthly, scope: scope, categoryID: catID, subcategoryID: subID, amount: amount, currencyCode: base))
        }

        // (days after month start, merchant, amount, category, subcategory)
        let samples: [(Int, String, String, String, String?)] = [
            (0, "Lidl", "43.28", "groceries", "groceries.other"),
            (1, "Aral", "62.10", "transport", "transport.fuel"),
            (2, "Amazon", "29.99", "shopping", "shopping.other"),
            (3, "REWE", "34.72", "groceries", "groceries.vegetables"),
            (4, "Metzgerei Huber", "18.40", "groceries", "groceries.meat"),
            (5, "Pizzeria Da Mario", "46.50", "restaurants", "restaurants.restaurant"),
            (6, "Parkhaus Altstadt", "5.50", "transport", "transport.parking"),
            (7, "dm", "21.35", "shopping", "shopping.personalcare"),
            (8, "Café Central", "9.80", "restaurants", "restaurants.cafe"),
            (9, "Edeka", "57.12", "groceries", "groceries.other")
        ]
        let today = calendar.startOfDay(for: now)
        for (offset, merchant, amountText, catKey, subKey) in samples {
            guard var date = calendar.date(byAdding: .day, value: offset, to: monthStart) else { continue }
            if date > today { date = today }
            date = calendar.date(byAdding: .hour, value: 10 + offset % 8, to: date) ?? date
            let expense = Expense(familyID: family.id, amount: Decimal(string: amountText)!, currencyCode: base, baseCurrencyCode: base, merchant: merchant, date: date)
            expense.categoryID = cat(catKey)
            expense.subcategoryID = subKey.flatMap { sub($0) }
            expense.memberID = member?.id
            expense.createdByMemberID = member?.id
            expense.baseAmount = expense.amount
            expense.conversionStatus = .notNeeded
            context.insert(expense)
        }

        // One foreign-currency example with a manual rate (deterministic offline).
        let usd = Expense(familyID: family.id, amount: 25, currencyCode: "USD", baseCurrencyCode: base, merchant: "App Store (US)", date: min(now, calendar.date(byAdding: .day, value: 2, to: monthStart) ?? now))
        usd.categoryID = cat("subscriptions")
        usd.subcategoryID = sub("subscriptions.software")
        usd.memberID = member?.id
        usd.createdByMemberID = member?.id
        if base == "USD" {
            usd.baseAmount = usd.amount
            usd.conversionStatus = .notNeeded
        } else {
            usd.exchangeRateText = "0.86"
            usd.exchangeRateSource = "Manual (demo)"
            usd.conversionStatus = .manual
            usd.baseAmount = (usd.amount * Decimal(string: "0.86")!).rounded(scale: 2)
        }
        context.insert(usd)

        try? context.save()
    }
}
