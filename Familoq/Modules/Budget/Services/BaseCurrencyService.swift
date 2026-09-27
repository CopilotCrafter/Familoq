import Foundation
import SwiftData
import FamiloqCore
import FamiloqBudget

enum BaseCurrencyChangeError: LocalizedError {
    case rateUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .rateUnavailable(let pair):
            return "Could not get the exchange rate \(pair). Please connect to the internet and try again. Nothing was changed."
        }
    }
}

/// Changes a family's base currency (EUR by default).
///
/// * Budgets are converted with TODAY's rate and rounded to whole units.
/// * Every expense is re-converted with the rate of ITS OWN date.
/// * Expenses already in the new currency need no rate.
/// * Manual rates were entered against the old base, so they are re-fetched.
@MainActor
enum BaseCurrencyService {
    static func change(to newCode: String, family: Family, context: ModelContext, rates: ExchangeRateService) async throws {
        let oldBase = CurrencyInfo.normalize(family.baseCurrencyCode)
        let newBase = CurrencyInfo.normalize(newCode)
        guard oldBase != newBase, CurrencyInfo.isValidCode(newBase) else { return }

        let repository = FamilyRepository(context: context, familyID: family.id)
        let budgets = try repository.budgets()

        // Fetch the budget rate FIRST so nothing changes if we are offline.
        var budgetRate: ExchangeRate?
        if !budgets.isEmpty {
            do {
                budgetRate = try await rates.latestRate(from: oldBase, to: newBase)
            } catch {
                throw BaseCurrencyChangeError.rateUnavailable("\(oldBase) → \(newBase)")
            }
        }

        if let budgetRate {
            for budget in budgets {
                let converted = try CurrencyConverter.convert(budget.amount, from: oldBase, to: newBase, using: budgetRate)
                budget.amount = converted.rounded(scale: 0)
                budget.currencyCode = newBase
                budget.updatedAt = Date()
            }
        }

        family.baseCurrencyCode = newBase
        family.updatedAt = Date()

        for expense in try repository.allExpenses() {
            expense.baseCurrencyCode = newBase
            expense.resetConversion()
        }
        try context.save()

        await rates.refreshPending(familyID: family.id, baseCurrency: newBase, context: context)
    }
}
