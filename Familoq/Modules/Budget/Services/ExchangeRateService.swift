import Foundation
import SwiftData
import FamiloqCore
import FamiloqBudget

/// Converts foreign-currency expenses into the family's base currency.
///
/// Rules (see docs/05-currency.md):
/// * Rate = ECB reference rate for the expense's calendar date (receipt date
///   or entered date). Weekends/holidays use the previous business day.
/// * Offline: the expense is saved immediately; it is converted with the most
///   recent cached rate (status `estimated`) or waits (`pending`), and is
///   refreshed automatically when the app becomes active again.
/// * A manually entered rate (`manual`) is never overwritten.
/// * Only currency codes and a date are sent to the rate API.
@MainActor
final class ExchangeRateService: ObservableObject {
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastProblem: String?

    private let provider: ExchangeRateProviding
    private let calendar: Calendar
    private let now: () -> Date

    init(provider: ExchangeRateProviding = FrankfurterClient(),
         calendar: Calendar = FamiloqCalendar.make(),
         now: @escaping () -> Date = { Date() }) {
        self.provider = provider
        self.calendar = calendar
        self.now = now
    }

    // MARK: Public API

    /// Sets `baseAmount` and the conversion fields of one expense, then saves.
    func convert(_ expense: Expense, baseCurrency: String, context: ModelContext) async {
        let base = CurrencyInfo.normalize(baseCurrency)
        let source = CurrencyInfo.normalize(expense.currencyCode)
        expense.baseCurrencyCode = base

        if source == base {
            expense.exchangeRateText = nil
            expense.exchangeRateDateKey = nil
            expense.exchangeRateSource = nil
            expense.baseAmount = expense.amount
            expense.conversionStatus = .notNeeded
            save(expense, context)
            return
        }

        if expense.conversionStatus == .manual, let rate = expense.exchangeRate {
            expense.baseAmount = (expense.amount * rate).rounded(scale: CurrencyInfo.minorUnits(for: base))
            save(expense, context)
            return
        }

        let requestedKey = DateKey.string(from: expense.date, calendar: calendar)
        let todayKey = DateKey.string(from: now(), calendar: calendar)
        // Future-dated expenses (planned) use the latest available rate.
        let queryKey: String? = requestedKey > todayKey ? nil : requestedKey

        do {
            let rate = try await resolveRate(from: source, to: base, dateKey: queryKey, requestedKey: requestedKey, todayKey: todayKey, context: context)
            expense.baseAmount = try CurrencyConverter.convert(expense.amount, from: source, to: base, using: rate)
            expense.exchangeRateText = "\(rate.rate)"
            expense.exchangeRateDateKey = rate.rateDateKey
            expense.exchangeRateSource = rate.source
            expense.conversionStatus = ConversionStatusResolver.status(
                requestedDateKey: requestedKey,
                rateDateKey: rate.rateDateKey,
                todayKey: todayKey,
                calendar: calendar
            )
            lastProblem = nil
        } catch ExchangeRateError.unsupportedCurrency {
            expense.baseAmountValue = nil
            expense.conversionStatus = .unsupported
        } catch {
            // Offline or server problem: fall back to the newest cached rate.
            if let cached = newestCachedRate(from: source, to: base, context: context),
               let converted = try? CurrencyConverter.convert(expense.amount, from: source, to: base, using: cached) {
                expense.baseAmount = converted
                expense.exchangeRateText = "\(cached.rate)"
                expense.exchangeRateDateKey = cached.rateDateKey
                expense.exchangeRateSource = cached.source
                expense.conversionStatus = .estimated
            } else {
                expense.baseAmountValue = nil
                expense.conversionStatus = .pending
            }
            lastProblem = "Exchange rates are unavailable right now. Foreign-currency expenses will be updated automatically."
        }
        save(expense, context)
    }

    /// Re-tries every pending/estimated expense of a family.
    func refreshPending(familyID: UUID, baseCurrency: String, context: ModelContext) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let repository = FamilyRepository(context: context, familyID: familyID)
        guard let expenses = try? repository.expensesNeedingConversion() else { return }
        for expense in expenses {
            await convert(expense, baseCurrency: baseCurrency, context: context)
        }
    }

    /// Latest rate, used when the owner changes the base currency.
    func latestRate(from: String, to: String) async throws -> ExchangeRate {
        try await provider.fetchRate(from: from, to: to, dateKey: nil)
    }

    // MARK: Cache

    private func resolveRate(from: String, to: String, dateKey: String?, requestedKey: String, todayKey: String, context: ModelContext) async throws -> ExchangeRate {
        if let dateKey, let cached = cachedRate(from: from, to: to, requestedKey: dateKey, context: context) {
            return cached
        }
        let fetched = try await provider.fetchRate(from: from, to: to, dateKey: dateKey)
        // Only cache FINAL rates; estimated ones must be re-fetched later.
        if let dateKey {
            let status = ConversionStatusResolver.status(requestedDateKey: requestedKey, rateDateKey: fetched.rateDateKey, todayKey: todayKey, calendar: calendar)
            if status == .converted {
                context.insert(ExchangeRateCacheEntry(requestedDateKey: dateKey, rate: fetched))
            }
        }
        return fetched
    }

    private func cachedRate(from: String, to: String, requestedKey: String, context: ModelContext) -> ExchangeRate? {
        let descriptor = FetchDescriptor<ExchangeRateCacheEntry>(
            predicate: #Predicate<ExchangeRateCacheEntry> {
                $0.baseCode == from && $0.quoteCode == to && $0.requestedDateKey == requestedKey
            }
        )
        return (try? context.fetch(descriptor))?.first?.exchangeRate
    }

    private func newestCachedRate(from: String, to: String, context: ModelContext) -> ExchangeRate? {
        var descriptor = FetchDescriptor<ExchangeRateCacheEntry>(
            predicate: #Predicate<ExchangeRateCacheEntry> { $0.baseCode == from && $0.quoteCode == to },
            sortBy: [SortDescriptor(\ExchangeRateCacheEntry.rateDateKey, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.exchangeRate
    }

    private func save(_ expense: Expense, _ context: ModelContext) {
        expense.updatedAt = now()
        try? context.save()
    }
}
