import Foundation
import FamiloqCore

public enum BudgetPeriod: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly

    /// The period interval (start inclusive, end exclusive) containing `date`.
    public func interval(containing date: Date, calendar: Calendar) -> DateInterval {
        let component: Calendar.Component
        switch self {
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .monthly: component = .month
        }
        if let interval = calendar.dateInterval(of: component, for: date) {
            return interval
        }
        // Fallback should never happen with a Gregorian calendar.
        let start = calendar.startOfDay(for: date)
        return DateInterval(start: start, duration: 86_400)
    }

    public var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

public enum BudgetScope: String, Codable, CaseIterable, Sendable {
    /// Whole-family budget across all categories.
    case overall
    case category
    case subcategory
}

/// Warning thresholds: 75 %, 90 %, 100 %, over.
public enum BudgetWarningLevel: Int, Comparable, Sendable {
    case normal = 0
    case caution75
    case warning90
    case reached100
    case over

    public static func < (lhs: BudgetWarningLevel, rhs: BudgetWarningLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct BudgetStatus: Equatable, Sendable {
    public let limit: Decimal
    public let spent: Decimal
    /// limit - spent (negative when over budget)
    public let remaining: Decimal
    /// spent / limit (0 when limit is 0)
    public let fractionUsed: Double
    public let level: BudgetWarningLevel

    /// Amount above the limit, or 0.
    public var overAmount: Decimal { remaining < 0 ? -remaining : 0 }
    /// Whole percent used, e.g. 90.
    public var percentUsed: Int { Int((fractionUsed * 100).rounded(.down)) }
}

public enum BudgetCalculator {
    public static func status(limit: Decimal, spent: Decimal) -> BudgetStatus {
        let fraction: Double = limit > 0 ? (spent / limit).doubleValue : 0
        return BudgetStatus(
            limit: limit,
            spent: spent,
            remaining: limit - spent,
            fractionUsed: fraction,
            level: level(limit: limit, spent: spent)
        )
    }

    public static func level(limit: Decimal, spent: Decimal) -> BudgetWarningLevel {
        guard limit > 0 else { return spent > 0 ? .over : .normal }
        if spent > limit { return .over }
        if spent == limit { return .reached100 }
        if spent >= limit * Decimal(string: "0.9")! { return .warning90 }
        if spent >= limit * Decimal(string: "0.75")! { return .caution75 }
        return .normal
    }
}
