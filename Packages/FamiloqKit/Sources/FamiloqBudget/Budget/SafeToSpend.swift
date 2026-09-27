import Foundation
import FamiloqCore

public struct SafeToSpendInput: Equatable, Sendable {
    /// Budget for the period (base currency).
    public var budget: Decimal
    /// Already spent in the period.
    public var spent: Decimal
    /// Recurring/planned expenses still due before the period ends.
    public var upcomingCommitted: Decimal
    /// "Now".
    public var today: Date
    /// End of the period, exclusive (e.g. 1 October 00:00 for September).
    public var periodEnd: Date

    public init(budget: Decimal, spent: Decimal, upcomingCommitted: Decimal = 0, today: Date, periodEnd: Date) {
        self.budget = budget
        self.spent = spent
        self.upcomingCommitted = upcomingCommitted
        self.today = today
        self.periodEnd = periodEnd
    }
}

public struct SafeToSpendResult: Equatable, Sendable {
    /// budget - spent
    public let remaining: Decimal
    /// Upcoming committed expenses deducted.
    public let upcomingCommitted: Decimal
    /// remaining - upcoming (never below zero)
    public let available: Decimal
    /// Days left including today.
    public let remainingDays: Int
    /// available / remainingDays, rounded DOWN to cents (conservative).
    public let dailyAmount: Decimal
    /// What can be spent over the next 7 days (or fewer if the period ends sooner).
    public let weeklyAmount: Decimal
    /// True when spending (plus commitments) already exceeds the budget.
    public let isOverBudget: Bool
    /// Amount over budget including commitments (0 if not over).
    public let shortfall: Decimal
}

/// "Safe to spend" answers: how much can we spend per day for the rest of the
/// period without breaking the budget, after reserving money for bills that
/// are still due?
///
///   remaining  = budget - spent
///   available  = remaining - upcoming recurring/planned expenses
///   daily      = available / days left (including today)
///   weekly     = daily x min(7, days left)
public enum SafeToSpendCalculator {
    public static func calculate(_ input: SafeToSpendInput, calendar: Calendar, currencyCode: String = "EUR") -> SafeToSpendResult {
        let places = CurrencyInfo.minorUnits(for: currencyCode)
        let remaining = input.budget - input.spent
        let committed = max(input.upcomingCommitted, 0)
        let rawAvailable = remaining - committed
        let available = max(rawAvailable, 0)

        let startToday = calendar.startOfDay(for: input.today)
        let endDay = calendar.startOfDay(for: input.periodEnd)
        let days = max(calendar.dateComponents([.day], from: startToday, to: endDay).day ?? 0, 1)

        let daily = (available / Decimal(days)).rounded(scale: places, mode: .down)
        let weekDays = min(7, days)
        let weekly = (available * Decimal(weekDays) / Decimal(days)).rounded(scale: places, mode: .down)

        return SafeToSpendResult(
            remaining: remaining,
            upcomingCommitted: committed,
            available: available,
            remainingDays: days,
            dailyAmount: daily,
            weeklyAmount: weekly,
            isOverBudget: rawAvailable < 0,
            shortfall: rawAvailable < 0 ? -rawAvailable : 0
        )
    }
}
