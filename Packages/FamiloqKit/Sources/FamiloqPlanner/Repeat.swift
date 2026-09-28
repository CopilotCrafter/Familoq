import Foundation

/// How often a reminder or calendar event repeats.
public enum RepeatFrequency: String, Codable, CaseIterable, Sendable {
    case never
    case daily
    case weekly
    case biweekly
    case monthly
    case yearly

    public var displayName: String {
        switch self {
        case .never: return "Never"
        case .daily: return "Every day"
        case .weekly: return "Every week"
        case .biweekly: return "Every 2 weeks"
        case .monthly: return "Every month"
        case .yearly: return "Every year"
        }
    }
}

/// Dates are always computed from the first date (31 Jan -> 29 Feb -> 31 Mar),
/// never from the previous occurrence, so they do not drift.
public struct RepeatRule: Equatable, Sendable {
    public var frequency: RepeatFrequency
    public var start: Date
    /// Last day it may occur (inclusive); nil = forever.
    public var end: Date?

    public init(frequency: RepeatFrequency, start: Date, end: Date? = nil) {
        self.frequency = frequency
        self.start = start
        self.end = end
    }

    /// The n-th occurrence (0 = start), nil after the end.
    public func occurrence(_ n: Int, calendar: Calendar) -> Date? {
        guard n >= 0 else { return nil }
        let date: Date?
        switch frequency {
        case .never: date = n == 0 ? start : nil
        case .daily: date = calendar.date(byAdding: .day, value: n, to: start)
        case .weekly: date = calendar.date(byAdding: .day, value: 7 * n, to: start)
        case .biweekly: date = calendar.date(byAdding: .day, value: 14 * n, to: start)
        case .monthly: date = calendar.date(byAdding: .month, value: n, to: start)
        case .yearly: date = calendar.date(byAdding: .year, value: n, to: start)
        }
        guard let date else { return nil }
        if let end, date > end { return nil }
        return date
    }

    /// A safe index to start searching from (never past the wanted date).
    private func estimateIndex(before date: Date, calendar: Calendar) -> Int {
        guard date > start else { return 0 }
        let n: Int
        switch frequency {
        case .never: return 0
        case .daily: n = calendar.dateComponents([.day], from: start, to: date).day ?? 0
        case .weekly: n = (calendar.dateComponents([.day], from: start, to: date).day ?? 0) / 7
        case .biweekly: n = (calendar.dateComponents([.day], from: start, to: date).day ?? 0) / 14
        case .monthly: n = calendar.dateComponents([.month], from: start, to: date).month ?? 0
        case .yearly: n = calendar.dateComponents([.year], from: start, to: date).year ?? 0
        }
        return max(0, n - 1)
    }

    /// Occurrences with from <= date < to, oldest first.
    public func occurrences(from: Date, to: Date, calendar: Calendar, limit: Int = 500) -> [Date] {
        var result: [Date] = []
        var n = estimateIndex(before: from, calendar: calendar)
        var steps = 0
        while steps < 10_000, result.count < limit, let date = occurrence(n, calendar: calendar) {
            if date >= to { break }
            if date >= from { result.append(date) }
            n += 1
            steps += 1
        }
        return result
    }

    /// First occurrence strictly after `date`.
    public func next(after date: Date, calendar: Calendar) -> Date? {
        var n = estimateIndex(before: date, calendar: calendar)
        var steps = 0
        while steps < 10_000, let candidate = occurrence(n, calendar: calendar) {
            if candidate > date { return candidate }
            n += 1
            steps += 1
        }
        return nil
    }
}
