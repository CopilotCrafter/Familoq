import Foundation
import FamiloqCore

// MARK: - Contracts (insurance, phone, internet, streaming, gym, energy …)

public enum NoticeUnit: String, CaseIterable, Codable, Sendable {
    case days, weeks, months

    public var title: String {
        switch self {
        case .days: return "days"
        case .weeks: return "weeks"
        case .months: return "months"
        }
    }
}

/// When a contract can be cancelled.
///
/// A contract starting 1 Jan 2025 with a 24-month minimum term runs until
/// 31 Dec 2026. With 3 months' notice it must be cancelled by 30 Sep 2026;
/// otherwise it renews by `renewalMonths` (German contracts since March
/// 2022: usually 1 month after the minimum term).
public struct ContractTerms: Equatable, Sendable {
    public var start: Date
    /// 0 = no minimum term (cancellable any time with the notice period).
    public var minimumTermMonths: Int
    /// Automatic renewal after the minimum term; 0 = the contract simply ends.
    public var renewalMonths: Int
    public var noticeValue: Int
    public var noticeUnit: NoticeUnit

    public init(start: Date, minimumTermMonths: Int, renewalMonths: Int, noticeValue: Int, noticeUnit: NoticeUnit) {
        self.start = start
        self.minimumTermMonths = max(0, minimumTermMonths)
        self.renewalMonths = max(0, renewalMonths)
        self.noticeValue = max(0, noticeValue)
        self.noticeUnit = noticeUnit
    }
}

public struct ContractDeadline: Equatable, Sendable {
    /// Last day the cancellation must arrive.
    public let deadline: Date
    /// Last day of the current term (the contract ends after it if cancelled).
    public let termEnd: Date
}

public enum ContractSchedule {
    /// Exclusive end of each term: start + minimum term, then + renewal.
    static func termEnds(_ terms: ContractTerms, calendar: Calendar, limit: Int = 600) -> AnyIterator<Date> {
        var index = 0
        let first = terms.minimumTermMonths > 0 ? terms.minimumTermMonths : max(terms.renewalMonths, 1)
        return AnyIterator {
            guard index < limit else { return nil }
            defer { index += 1 }
            if index > 0 && terms.renewalMonths == 0 { return nil }
            let months = first + index * max(terms.renewalMonths, 1)
            return calendar.date(byAdding: .month, value: months, to: calendar.startOfDay(for: terms.start))
        }
    }

    static func subtractNotice(_ terms: ContractTerms, from date: Date, calendar: Calendar) -> Date {
        let component: Calendar.Component
        var value = terms.noticeValue
        switch terms.noticeUnit {
        case .days: component = .day
        case .weeks: component = .day; value *= 7
        case .months: component = .month
        }
        return calendar.date(byAdding: component, value: -value, to: date) ?? date
    }

    /// The next deadline that has not passed yet (today counts).
    public static func next(_ terms: ContractTerms, now: Date, calendar: Calendar) -> ContractDeadline? {
        let today = calendar.startOfDay(for: now)
        for endExclusive in termEnds(terms, calendar: calendar) {
            // The notice must arrive by the day before (end - notice).
            let lastDay = calendar.date(byAdding: .day, value: -1, to: subtractNotice(terms, from: endExclusive, calendar: calendar)) ?? endExclusive
            if lastDay >= today {
                let termEnd = calendar.date(byAdding: .day, value: -1, to: endExclusive) ?? endExclusive
                return ContractDeadline(deadline: lastDay, termEnd: termEnd)
            }
        }
        return nil
    }
}

// MARK: - Fixed costs per month

public struct FixedCostItem: Sendable, Identifiable {
    public let id: String
    public let title: String
    /// Amount per payment, base currency.
    public let amount: Decimal
    public let frequency: RecurrenceFrequency
    public let categoryID: UUID?
    public let memberID: UUID?

    public init(id: String, title: String, amount: Decimal, frequency: RecurrenceFrequency, categoryID: UUID?, memberID: UUID?) {
        self.id = id
        self.title = title
        self.amount = amount
        self.frequency = frequency
        self.categoryID = categoryID
        self.memberID = memberID
    }

    /// Yearly and quarterly payments spread over the months.
    public var perMonth: Decimal {
        (amount * frequency.perMonth).rounded(scale: 2)
    }
}

public struct FixedCostSummary: Sendable {
    public let items: [FixedCostItem]
    public let perMonth: Decimal
    public let byCategory: [UUID?: Decimal]
    public let byMember: [UUID?: Decimal]

    public var perYear: Decimal { perMonth * 12 }
}

public enum FixedCosts {
    /// One-off (planned) payments are not fixed costs.
    public static func summary(_ items: [FixedCostItem]) -> FixedCostSummary {
        let recurring = items.filter { $0.frequency != .once && $0.amount > 0 }
        var byCategory: [UUID?: Decimal] = [:]
        var byMember: [UUID?: Decimal] = [:]
        for item in recurring {
            byCategory[item.categoryID, default: 0] += item.perMonth
            byMember[item.memberID, default: 0] += item.perMonth
        }
        return FixedCostSummary(items: recurring.sorted { $0.perMonth > $1.perMonth },
                                perMonth: recurring.map(\.perMonth).reduce(0, +),
                                byCategory: byCategory, byMember: byMember)
    }
}

// MARK: - Warranties

public enum WarrantyTerms {
    /// Last day of the warranty (purchase + months - 1 day).
    public static func end(purchase: Date, months: Int, calendar: Calendar) -> Date {
        let exclusive = calendar.date(byAdding: .month, value: max(months, 0), to: calendar.startOfDay(for: purchase)) ?? purchase
        return calendar.date(byAdding: .day, value: -1, to: exclusive) ?? exclusive
    }

    public static func daysLeft(purchase: Date, months: Int, now: Date, calendar: Calendar) -> Int {
        let end = end(purchase: purchase, months: months, calendar: calendar)
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: end).day ?? 0
    }
}
