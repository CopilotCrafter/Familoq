import Foundation
import SwiftData
import FamiloqCore
import FamiloqBudget

/// Books due recurring/planned expenses and works out what is still ahead.
@MainActor
enum PlanningService {
    /// Creates the real expenses for every due date that was not booked yet.
    /// Safe on several iPhones at once: each due date gets a fixed expense ID
    /// (schedule + date), so two members' iPhones create the same record.
    @discardableResult
    static func bookDue(familyID: UUID, baseCurrency: String, context: ModelContext, now: Date = Date(), calendar: Calendar = FamiloqCalendar.make()) -> [Expense] {
        let fid = familyID
        let schedules = (try? context.fetch(FetchDescriptor<ScheduledExpense>(predicate: #Predicate { $0.familyID == fid && $0.isActive == true }))) ?? []
        var created: [Expense] = []
        for schedule in schedules {
            let due = ScheduleBooking.dueOccurrences(rule: schedule.rule, bookedThrough: schedule.bookedThrough, now: now, calendar: calendar)
            guard !due.isEmpty else { continue }
            for date in due {
                let id = expenseID(scheduleID: schedule.id, date: date)
                var existing = FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id })
                existing.fetchLimit = 1
                if let found = try? context.fetch(existing), !found.isEmpty { continue }
                let expense = Expense(familyID: familyID, amount: schedule.amount, currencyCode: schedule.currencyCode,
                                      baseCurrencyCode: baseCurrency, merchant: schedule.title, date: date)
                expense.id = id
                expense.categoryID = schedule.categoryID
                expense.subcategoryID = schedule.subcategoryID
                expense.memberID = schedule.memberID
                expense.createdByMemberID = schedule.createdByMemberID
                expense.paymentMethodRaw = schedule.paymentMethodRaw
                expense.note = schedule.note
                expense.carID = schedule.carID
                expense.carCostRaw = schedule.carCostRaw
                expense.entryMethod = .scheduled
                expense.resetConversion()
                context.insert(expense)
                created.append(expense)
            }
            if let last = due.last, (schedule.bookedThrough ?? .distantPast) < last {
                schedule.bookedThrough = last
            }
        }
        try? context.save()
        return created
    }

    static func expenseID(scheduleID: UUID, date: Date) -> UUID {
        DeterministicID.uuid("scheduled|\(scheduleID.uuidString)|\(Int(date.timeIntervalSince1970))")
    }

    struct Upcoming: Identifiable {
        let schedule: ScheduledExpense
        let date: Date
        var id: String { "\(schedule.id.uuidString)-\(Int(date.timeIntervalSince1970))" }
    }

    /// Not yet booked due dates with now < date < until, soonest first.
    static func upcoming(_ schedules: [ScheduledExpense], now: Date, until: Date, calendar: Calendar = FamiloqCalendar.make()) -> [Upcoming] {
        schedules.filter(\.isActive).flatMap { schedule in
            ScheduleBooking.upcoming(rule: schedule.rule, bookedThrough: schedule.bookedThrough, now: now, until: until, calendar: calendar)
                .map { Upcoming(schedule: schedule, date: $0) }
        }
        .sorted { $0.date < $1.date }
    }

    /// Amount in the base currency, using the newest cached exchange rate
    /// for other currencies (an estimate - the real expense gets the rate of
    /// its own date when it is booked).
    static func approximateInBase(_ amount: Decimal, currency: String, base: String, context: ModelContext) -> Decimal {
        let from = CurrencyInfo.normalize(currency)
        let to = CurrencyInfo.normalize(base)
        guard from != to else { return amount }
        var descriptor = FetchDescriptor<ExchangeRateCacheEntry>(
            predicate: #Predicate { $0.baseCode == from && $0.quoteCode == to },
            sortBy: [SortDescriptor(\ExchangeRateCacheEntry.rateDateKey, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let rate = (try? context.fetch(descriptor))?.first?.exchangeRate?.rate {
            return (amount * rate).rounded(scale: 2)
        }
        return amount
    }

    /// Money to keep back for the rest of the month: upcoming recurring and
    /// planned expenses + what savings goals still need this month.
    static func committedForRestOfMonth(schedules: [ScheduledExpense], goals: [SavingsGoal], contributions: [SavingsContribution],
                                        baseCurrency: String, now: Date, monthEnd: Date, context: ModelContext,
                                        calendar: Calendar = FamiloqCalendar.make()) -> (bills: Decimal, savings: Decimal) {
        let bills = upcoming(schedules, now: now, until: monthEnd, calendar: calendar)
            .reduce(Decimal(0)) { $0 + approximateInBase($1.schedule.amount, currency: $1.schedule.currencyCode, base: baseCurrency, context: context) }
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        var savings: Decimal = 0
        for goal in goals where goal.reserveInSafeToSpend && !goal.isArchived {
            let mine = contributions.filter { $0.goalID == goal.id }
            let saved = mine.reduce(Decimal(0)) { $0 + $1.amount }
            let thisMonth = mine.filter { $0.date >= monthStart && $0.date < monthEnd }.reduce(Decimal(0)) { $0 + $1.amount }
            let progress = SavingsPlanner.progress(target: goal.target, saved: saved - thisMonth, deadline: goal.deadline, now: now,
                                                   calendar: calendar, currencyCode: baseCurrency)
            if let monthly = progress.monthlyNeeded, !progress.isReached {
                savings += max(monthly - thisMonth, 0)
            }
        }
        return (bills, savings)
    }
}
