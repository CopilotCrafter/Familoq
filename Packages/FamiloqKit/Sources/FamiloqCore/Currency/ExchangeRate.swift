import Foundation

/// A single exchange rate: 1 `base` = `rate` `quote`.
public struct ExchangeRate: Equatable, Codable, Sendable {
    public var base: String
    public var quote: String
    public var rate: Decimal
    /// The day the rate was published by the source (yyyy-MM-dd).
    /// For weekends/holidays this is the previous business day.
    public var rateDateKey: String
    /// Human-readable source, e.g. "ECB reference rate (Frankfurter)".
    public var source: String

    public init(base: String, quote: String, rate: Decimal, rateDateKey: String, source: String) {
        self.base = CurrencyInfo.normalize(base)
        self.quote = CurrencyInfo.normalize(quote)
        self.rate = rate
        self.rateDateKey = rateDateKey
        self.source = source
    }

    /// The inverse rate (quote -> base), or nil if the rate is zero.
    public var inverted: ExchangeRate? {
        guard rate != 0 else { return nil }
        return ExchangeRate(base: quote, quote: base, rate: 1 / rate, rateDateKey: rateDateKey, source: source)
    }
}

public enum ExchangeRateError: Error, Equatable {
    /// The source does not publish this currency (e.g. AED at the ECB).
    case unsupportedCurrency
    /// Network or server problem - try again later.
    case unavailable
    /// The server answered with something we could not read.
    case invalidResponse
}

/// Anything that can supply exchange rates. The app uses `FrankfurterClient`;
/// tests use a stub.
public protocol ExchangeRateProviding {
    /// - Parameter dateKey: "yyyy-MM-dd", or nil for the latest available rate.
    func fetchRate(from: String, to: String, dateKey: String?) async throws -> ExchangeRate
}

/// Calendar-day keys ("2026-09-27") used for rate lookups and caching.
public enum DateKey {
    public static func string(from date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 1970, m = c.month ?? 1, d = c.day ?? 1
        return String(format: "%04ld-%02ld-%02ld", y, m, d)
    }

    public static func date(from key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        comps.hour = 12
        return calendar.date(from: comps)
    }

    /// Whole calendar days from `from` to `to` (positive if `to` is later).
    public static func daysBetween(_ from: String, _ to: String, calendar: Calendar) -> Int? {
        guard let a = date(from: from, calendar: calendar),
              let b = date(from: to, calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day
    }
}
