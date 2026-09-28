import Foundation

/// How often a scheduled expense repeats. `once` = a planned one-off.
public enum RecurrenceFrequency: String, Codable, CaseIterable, Sendable {
    case once
    case weekly
    case biweekly
    case monthly
    case quarterly
    case yearly

    public var displayName: String {
        switch self {
        case .once: return "Once (planned)"
        case .weekly: return "Every week"
        case .biweekly: return "Every 2 weeks"
        case .monthly: return "Every month"
        case .quarterly: return "Every 3 months"
        case .yearly: return "Every year"
        }
    }

    /// Rough number of occurrences per month (for "per month" overviews).
    public var perMonth: Decimal {
        switch self {
        case .once: return 0
        case .weekly: return Decimal(52) / Decimal(12)
        case .biweekly: return Decimal(26) / Decimal(12)
        case .monthly: return 1
        case .quarterly: return Decimal(1) / Decimal(3)
        case .yearly: return Decimal(1) / Decimal(12)
        }
    }
}

/// When a scheduled expense is due.
///
/// Monthly dates keep the start day and fall back to the last day of shorter
/// months (31 Jan -> 28/29 Feb -> 31 Mar), because every date is computed
/// from the start date, never from the previous occurrence.
public struct RecurrenceRule: Equatable, Sendable {
    public var frequency: RecurrenceFrequency
    public var start: Date
    /// Last day it may occur (inclusive), nil = no end.
    public var end: Date?

    public init(frequency: RecurrenceFrequency, start: Date, end: Date? = nil) {
        self.frequency = frequency
        self.start = start
        self.end = end
    }

    /// The n-th occurrence (n = 0 is the start).
    public func occurrence(_ n: Int, calendar: Calendar) -> Date? {
        switch frequency {
        case .once: return n == 0 ? start : nil
        case .weekly: return calendar.date(byAdding: .day, value: 7 * n, to: start)
        case .biweekly: return calendar.date(byAdding: .day, value: 14 * n, to: start)
        case .monthly: return calendar.date(byAdding: .month, value: n, to: start)
        case .quarterly: return calendar.date(byAdding: .month, value: 3 * n, to: start)
        case .yearly: return calendar.date(byAdding: .year, value: n, to: start)
        }
    }

    /// Occurrences with `from <= date < to`, oldest first.
    public func occurrences(from: Date, to: Date, calendar: Calendar, limit: Int = 1000) -> [Date] {
        var result: [Date] = []
        var n = 0
        while n < 100_000, result.count < limit, let date = occurrence(n, calendar: calendar) {
            if date >= to { break }
            if let end, date > end { break }
            if date >= from { result.append(date) }
            n += 1
        }
        return result
    }
}

/// Booking of scheduled expenses: which dates must become real expenses now,
/// and which are still ahead (reserved in "Safe to spend").
public enum ScheduleBooking {
    /// Due dates after `bookedThrough` (exclusive) up to `now` (inclusive).
    /// Catch-up is limited so a schedule that was paused for years does not
    /// flood the expense list.
    public static func dueOccurrences(rule: RecurrenceRule, bookedThrough: Date?, now: Date, calendar: Calendar, maxCatchUp: Int = 12) -> [Date] {
        let from = bookedThrough.map { $0.addingTimeInterval(1) } ?? rule.start
        let due = rule.occurrences(from: from, to: now.addingTimeInterval(1), calendar: calendar)
        return Array(due.suffix(maxCatchUp))
    }

    /// Not yet booked dates with `now < date < until`.
    public static func upcoming(rule: RecurrenceRule, bookedThrough: Date?, now: Date, until: Date, calendar: Calendar) -> [Date] {
        let after = max(now.addingTimeInterval(1), bookedThrough.map { $0.addingTimeInterval(1) } ?? rule.start)
        return rule.occurrences(from: after, to: until, calendar: calendar)
    }
}
