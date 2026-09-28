import Foundation
import FamiloqCore

public struct SavingsProgress: Equatable, Sendable {
    public let saved: Decimal
    public let target: Decimal
    /// target - saved, never below 0
    public let remaining: Decimal
    /// 0...1
    public let fraction: Double
    public let isReached: Bool
    /// Calendar months left including the current one (nil without deadline).
    public let monthsLeft: Int?
    /// Amount to put aside per month to reach the target in time (nil without deadline).
    public let monthlyNeeded: Decimal?
    /// Deadline passed and target not reached.
    public let isOverdue: Bool
}

/// Savings goals: "Holiday 2027: €2,000 by June".
public enum SavingsPlanner {
    public static func progress(target: Decimal, saved: Decimal, deadline: Date?, now: Date, calendar: Calendar, currencyCode: String = "EUR") -> SavingsProgress {
        let remaining = max(target - saved, 0)
        let fraction: Double = target > 0 ? min(max((saved / target).doubleValue, 0), 1) : 0
        let reached = target > 0 && saved >= target
        var monthsLeft: Int?
        var monthly: Decimal?
        var overdue = false
        if let deadline {
            let nowMonth = calendar.dateComponents([.year, .month], from: now)
            let endMonth = calendar.dateComponents([.year, .month], from: deadline)
            let diff = ((endMonth.year ?? 0) - (nowMonth.year ?? 0)) * 12 + ((endMonth.month ?? 0) - (nowMonth.month ?? 0))
            if deadline < calendar.startOfDay(for: now) {
                overdue = !reached
                monthsLeft = 0
                monthly = reached ? 0 : remaining
            } else {
                let months = max(diff + 1, 1)
                monthsLeft = months
                let places = CurrencyInfo.minorUnits(for: currencyCode)
                monthly = (remaining / Decimal(months)).rounded(scale: places, mode: .up)
            }
        }
        return SavingsProgress(saved: saved, target: target, remaining: remaining, fraction: fraction,
                               isReached: reached, monthsLeft: monthsLeft, monthlyNeeded: monthly, isOverdue: overdue)
    }
}
