import Foundation

/// One expense, reduced to what the reports need (amount already in the
/// family's base currency).
public struct SpendingEntry: Sendable {
    public var amount: Decimal
    public var categoryID: UUID?
    public var subcategoryID: UUID?
    public var memberID: UUID?
    public var merchant: String

    public init(amount: Decimal, categoryID: UUID?, subcategoryID: UUID?, memberID: UUID?, merchant: String = "") {
        self.amount = amount
        self.categoryID = categoryID
        self.subcategoryID = subcategoryID
        self.memberID = memberID
        self.merchant = merchant
    }
}

/// A category, a subcategory (with its category) or a person.
public struct BreakdownKey: Hashable, Sendable {
    public let categoryID: UUID?
    public let subcategoryID: UUID?
    public let memberID: UUID?

    public init(categoryID: UUID? = nil, subcategoryID: UUID? = nil, memberID: UUID? = nil) {
        self.categoryID = categoryID
        self.subcategoryID = subcategoryID
        self.memberID = memberID
    }
}

/// Spending in the chosen period next to the period before (same length).
public struct BreakdownRow: Equatable, Sendable, Identifiable {
    public let key: BreakdownKey
    public let current: Decimal
    public let previous: Decimal
    public let count: Int

    public var change: Decimal { current - previous }

    /// nil when there was nothing before (new spending).
    public var changePercent: Double? {
        guard previous > 0 else { return nil }
        return NSDecimalNumber(decimal: (current - previous) / previous * 100).doubleValue
    }

    public var id: String {
        [key.categoryID?.uuidString ?? "-", key.subcategoryID?.uuidString ?? "-", key.memberID?.uuidString ?? "-"].joined(separator: "|")
    }
}

public struct MerchantTotal: Equatable, Sendable, Identifiable {
    public let name: String
    public let amount: Decimal
    public let count: Int
    public var id: String { name }
}

public enum SpendingBreakdown {
    public enum Level: Sendable {
        case category
        /// Subcategory within its category; expenses without a subcategory
        /// form one "no subcategory" row per category.
        case subcategory
        case member
    }

    static func key(_ entry: SpendingEntry, level: Level) -> BreakdownKey {
        switch level {
        case .category: return BreakdownKey(categoryID: entry.categoryID)
        case .subcategory: return BreakdownKey(categoryID: entry.categoryID, subcategoryID: entry.subcategoryID)
        case .member: return BreakdownKey(memberID: entry.memberID)
        }
    }

    /// Rows sorted by current spending (largest first); rows that only had
    /// spending in the previous period come last.
    public static func rows(current: [SpendingEntry], previous: [SpendingEntry], level: Level) -> [BreakdownRow] {
        var now: [BreakdownKey: (Decimal, Int)] = [:]
        var before: [BreakdownKey: Decimal] = [:]
        for entry in current {
            let k = key(entry, level: level)
            let old = now[k] ?? (0, 0)
            now[k] = (old.0 + entry.amount, old.1 + 1)
        }
        for entry in previous {
            before[key(entry, level: level), default: 0] += entry.amount
        }
        let keys = Set(now.keys).union(before.keys)
        return keys.map { k in
            BreakdownRow(key: k, current: now[k]?.0 ?? 0, previous: before[k] ?? 0, count: now[k]?.1 ?? 0)
        }
        .sorted { a, b in
            if a.current != b.current { return a.current > b.current }
            if a.previous != b.previous { return a.previous > b.previous }
            return a.id < b.id
        }
    }

    /// Largest increases and decreases. Small changes (below `minimumChange`)
    /// are left out so the list shows what really matters.
    public static func biggestChanges(_ rows: [BreakdownRow], minimumChange: Decimal = 10, limit: Int = 3) -> (up: [BreakdownRow], down: [BreakdownRow]) {
        let up = rows.filter { $0.change >= minimumChange }.sorted { $0.change > $1.change }.prefix(limit)
        let down = rows.filter { $0.change <= -minimumChange }.sorted { $0.change < $1.change }.prefix(limit)
        return (Array(up), Array(down))
    }

    /// Where the money went, by shop (names compared without case).
    public static func topMerchants(_ entries: [SpendingEntry], limit: Int = 5) -> [MerchantTotal] {
        var totals: [String: (name: String, amount: Decimal, count: Int)] = [:]
        for entry in entries {
            let name = entry.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let k = name.lowercased()
            let old = totals[k] ?? (name, 0, 0)
            totals[k] = (old.name, old.amount + entry.amount, old.count + 1)
        }
        return totals.values
            .map { MerchantTotal(name: $0.name, amount: $0.amount, count: $0.count) }
            .sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.name < $1.name }
            .prefix(limit)
            .map { $0 }
    }
}
