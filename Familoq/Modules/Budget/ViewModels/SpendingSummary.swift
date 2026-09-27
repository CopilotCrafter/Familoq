import Foundation
import FamiloqCore
import FamiloqBudget

/// Aggregates a list of expenses (in base currency).
struct SpendingSummary {
    let total: Decimal
    let byCategory: [UUID: Decimal]
    let bySubcategory: [UUID: Decimal]
    let uncategorized: Decimal
    /// Foreign-currency expenses that could not be converted yet
    /// (not included in totals).
    let unconvertedCount: Int

    init(expenses: [Expense]) {
        var total: Decimal = 0
        var byCategory: [UUID: Decimal] = [:]
        var bySubcategory: [UUID: Decimal] = [:]
        var uncategorized: Decimal = 0
        var unconverted = 0
        for expense in expenses {
            guard let amount = expense.baseAmount else {
                unconverted += 1
                continue
            }
            total += amount
            if let categoryID = expense.categoryID {
                byCategory[categoryID, default: 0] += amount
            } else {
                uncategorized += amount
            }
            if let subID = expense.subcategoryID {
                bySubcategory[subID, default: 0] += amount
            }
        }
        self.total = total
        self.byCategory = byCategory
        self.bySubcategory = bySubcategory
        self.uncategorized = uncategorized
        self.unconvertedCount = unconverted
    }

    func spent(for budget: Budget) -> Decimal {
        switch budget.scope {
        case .overall: return total
        case .category: return budget.categoryID.flatMap { byCategory[$0] } ?? 0
        case .subcategory: return budget.subcategoryID.flatMap { bySubcategory[$0] } ?? 0
        }
    }
}

/// Budget + its current period status.
struct BudgetProgress: Identifiable {
    let budget: Budget
    let title: String
    let icon: String
    let colorHex: String
    let status: BudgetStatus
    var id: UUID { budget.id }
}

enum BudgetProgressBuilder {
    /// Computes the status of every active budget for the period that
    /// contains `now`. `expenses` must cover at least all those periods.
    static func progress(budgets: [Budget], expenses: [Expense], lookup: CategoryLookup, now: Date, calendar: Calendar) -> [BudgetProgress] {
        budgets.filter(\.isActive).map { budget in
            let interval = budget.period.interval(containing: now, calendar: calendar)
            let inPeriod = expenses.filter { $0.date >= interval.start && $0.date < interval.end }
            let summary = SpendingSummary(expenses: inPeriod)
            let spent = summary.spent(for: budget)
            let title: String
            let icon: String
            let color: String
            switch budget.scope {
            case .overall:
                title = "\(budget.period.displayName) family budget"
                icon = "house.fill"
                color = "#2F6F4F"
            case .category:
                let category = lookup.category(budget.categoryID)
                title = category?.name ?? "Category"
                icon = category?.icon ?? "tag.fill"
                color = category?.colorHex ?? "#9E9E9E"
            case .subcategory:
                let category = lookup.category(budget.categoryID)
                title = lookup.path(categoryID: budget.categoryID, subcategoryID: budget.subcategoryID)
                icon = category?.icon ?? "tag.fill"
                color = category?.colorHex ?? "#9E9E9E"
            }
            return BudgetProgress(
                budget: budget,
                title: title,
                icon: icon,
                colorHex: color,
                status: BudgetCalculator.status(limit: budget.amount, spent: spent)
            )
        }
    }
}
