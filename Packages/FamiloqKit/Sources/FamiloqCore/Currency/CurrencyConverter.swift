import Foundation

public enum CurrencyConversionError: Error, Equatable {
    case rateDoesNotMatchCurrencies
    case zeroRate
}

public enum CurrencyConverter {
    /// Converts `amount` from `from` to `to` using `rate` (either direction),
    /// rounded to the target currency's minor units.
    public static func convert(_ amount: Decimal, from: String, to: String, using rate: ExchangeRate) throws -> Decimal {
        let f = CurrencyInfo.normalize(from)
        let t = CurrencyInfo.normalize(to)
        let places = CurrencyInfo.minorUnits(for: t)

        if f == t {
            return amount.rounded(scale: places)
        }
        if rate.base == f && rate.quote == t {
            return (amount * rate.rate).rounded(scale: places)
        }
        if rate.base == t && rate.quote == f {
            guard rate.rate != 0 else { throw CurrencyConversionError.zeroRate }
            return (amount / rate.rate).rounded(scale: places)
        }
        throw CurrencyConversionError.rateDoesNotMatchCurrencies
    }

    /// Builds a cross rate X -> Y from two EUR-based rates (EUR -> X, EUR -> Y).
    public static func crossRate(eurToFrom: ExchangeRate, eurToTo: ExchangeRate) throws -> ExchangeRate {
        guard eurToFrom.base == "EUR", eurToTo.base == "EUR" else {
            throw CurrencyConversionError.rateDoesNotMatchCurrencies
        }
        guard eurToFrom.rate != 0 else { throw CurrencyConversionError.zeroRate }
        return ExchangeRate(
            base: eurToFrom.quote,
            quote: eurToTo.quote,
            rate: eurToTo.rate / eurToFrom.rate,
            rateDateKey: min(eurToFrom.rateDateKey, eurToTo.rateDateKey),
            source: eurToFrom.source
        )
    }
}

/// How an expense's amount in the family base currency was obtained.
public enum ConversionStatus: String, Codable, CaseIterable, Sendable {
    /// Expense is already in the base currency.
    case notNeeded
    /// Converted with the official rate for the expense date (or the last
    /// business day before it, e.g. for weekends).
    case converted
    /// Converted with an older rate because the rate for the expense date is
    /// not published yet (ECB publishes around 16:00 CET) or the device was
    /// offline. Refreshed automatically later.
    case estimated
    /// No rate yet (offline and nothing cached). Not included in totals.
    case pending
    /// The user typed the rate (e.g. from a bank statement). Never overwritten.
    case manual
    /// The source does not publish this currency. User must enter a rate.
    case unsupported

    /// Whether the expense has a usable base amount.
    public var hasBaseAmount: Bool {
        switch self {
        case .notNeeded, .converted, .estimated, .manual: return true
        case .pending, .unsupported: return false
        }
    }

    /// Whether the app should try to (re)fetch a rate.
    public var needsRefresh: Bool {
        self == .pending || self == .estimated
    }
}

public enum ConversionStatusResolver {
    /// Decides whether a fetched rate is final (`converted`) or provisional
    /// (`estimated`).
    ///
    /// * Rate date == expense date                        -> converted
    /// * Rate date older, expense is today/yesterday/future -> estimated
    ///   (the rate for that day may still be published)
    /// * Rate date older, expense is 2+ days old          -> converted
    ///   (weekend / public holiday: previous business day is the official rate)
    public static func status(requestedDateKey: String, rateDateKey: String, todayKey: String, calendar: Calendar) -> ConversionStatus {
        if rateDateKey >= requestedDateKey { return .converted }
        guard let age = DateKey.daysBetween(requestedDateKey, todayKey, calendar: calendar) else { return .estimated }
        return age <= 1 ? .estimated : .converted
    }
}
