import Foundation
import SwiftData
import FamiloqCore
import FamiloqBudget

/// A recurring expense (rent, insurance, subscriptions) or a planned one-off
/// (frequency `once`). Due dates are booked automatically as real expenses;
/// dates still ahead this month are reserved in "Safe to spend".
@Model
final class ScheduledExpense {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var title: String = ""
    var amountValue: Int64 = 0
    var currencyCode: String = "EUR"
    var categoryID: UUID? = nil
    var subcategoryID: UUID? = nil
    var memberID: UUID? = nil
    var paymentMethodRaw: String = "bankTransfer"
    var note: String = ""
    var frequencyRaw: String = "monthly"
    /// First due date (for `once`: the only one).
    var startDate: Date = Date()
    var endDate: Date? = nil
    /// Newest due date that was already booked as an expense.
    var bookedThrough: Date? = nil
    var isActive: Bool = true
    var createdByMemberID: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, title: String, amount: Decimal, currencyCode: String, frequency: RecurrenceFrequency, startDate: Date) {
        self.id = id
        self.familyID = familyID
        self.title = title
        self.amountValue = FixedPoint.storage(from: amount)
        self.currencyCode = currencyCode
        self.frequencyRaw = frequency.rawValue
        self.startDate = startDate
    }

    var amount: Decimal {
        get { FixedPoint.decimal(from: amountValue) }
        set { amountValue = FixedPoint.storage(from: newValue) }
    }

    var frequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var rule: RecurrenceRule {
        RecurrenceRule(frequency: frequency, start: startDate, end: endDate)
    }

    var isPlanned: Bool { frequency == .once }
}

/// "Holiday 2027: €2,000 by June".
@Model
final class SavingsGoal {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var name: String = ""
    var icon: String = "star.fill"
    /// In the family's base currency.
    var targetValue: Int64 = 0
    var deadline: Date? = nil
    /// Reserve the monthly amount in "Safe to spend".
    var reserveInSafeToSpend: Bool = true
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, name: String, target: Decimal, deadline: Date?) {
        self.id = id
        self.familyID = familyID
        self.name = name
        self.targetValue = FixedPoint.storage(from: target)
        self.deadline = deadline
    }

    var target: Decimal {
        get { FixedPoint.decimal(from: targetValue) }
        set { targetValue = FixedPoint.storage(from: newValue) }
    }
}

/// Money put into (or taken out of, negative) a savings goal.
@Model
final class SavingsContribution {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var goalID: UUID = UUID()
    /// In the family's base currency.
    var amountValue: Int64 = 0
    var date: Date = Date()
    var memberID: UUID? = nil
    var note: String = ""

    init(id: UUID = UUID(), familyID: UUID, goalID: UUID, amount: Decimal, date: Date, memberID: UUID?) {
        self.id = id
        self.familyID = familyID
        self.goalID = goalID
        self.amountValue = FixedPoint.storage(from: amount)
        self.date = date
        self.memberID = memberID
    }

    var amount: Decimal {
        get { FixedPoint.decimal(from: amountValue) }
        set { amountValue = FixedPoint.storage(from: newValue) }
    }
}
