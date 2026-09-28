import Foundation

public struct MonthTotal: Equatable, Sendable, Identifiable {
    public let monthStart: Date
    public let total: Decimal
    public var id: Date { monthStart }
}

public enum SpendingTrends {
    /// Totals per calendar month for the `months` months ending with the
    /// month that contains `endingAt` (oldest first, empty months = 0).
    public static func monthlyTotals(entries: [(date: Date, amount: Decimal)], months: Int, endingAt: Date, calendar: Calendar) -> [MonthTotal] {
        guard months > 0, let lastMonth = calendar.dateInterval(of: .month, for: endingAt)?.start else { return [] }
        var starts: [Date] = []
        for back in stride(from: months - 1, through: 0, by: -1) {
            if let start = calendar.date(byAdding: .month, value: -back, to: lastMonth) { starts.append(start) }
        }
        var totals: [Date: Decimal] = [:]
        for entry in entries {
            guard let start = calendar.dateInterval(of: .month, for: entry.date)?.start else { continue }
            totals[start, default: 0] += entry.amount
        }
        return starts.map { MonthTotal(monthStart: $0, total: totals[$0] ?? 0) }
    }

    /// Average of the given month totals, ignoring the current (incomplete) month.
    public static func averageOfCompleteMonths(_ totals: [MonthTotal]) -> Decimal {
        let complete = totals.dropLast()
        guard !complete.isEmpty else { return 0 }
        return complete.reduce(0) { $0 + $1.total } / Decimal(complete.count)
    }
}
