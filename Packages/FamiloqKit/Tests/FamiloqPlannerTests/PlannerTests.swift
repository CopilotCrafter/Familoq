import XCTest
import FamiloqCore
@testable import FamiloqPlanner

final class ShoppingTests: XCTestCase {
    func testParsesQuantities() {
        XCTAssertEqual(ShoppingEntryParser.parse("2x Milch"), ShoppingEntry(name: "Milch", quantity: "2"))
        XCTAssertEqual(ShoppingEntryParser.parse("2 x milch"), ShoppingEntry(name: "Milch", quantity: "2"))
        XCTAssertEqual(ShoppingEntryParser.parse("500g Hackfleisch"), ShoppingEntry(name: "Hackfleisch", quantity: "500 g"))
        XCTAssertEqual(ShoppingEntryParser.parse("1,5 kg Kartoffeln"), ShoppingEntry(name: "Kartoffeln", quantity: "1,5 kg"))
        XCTAssertEqual(ShoppingEntryParser.parse("Eier 10"), ShoppingEntry(name: "Eier", quantity: "10"))
        XCTAssertEqual(ShoppingEntryParser.parse("Butter x3"), ShoppingEntry(name: "Butter", quantity: "3"))
        XCTAssertEqual(ShoppingEntryParser.parse("Cola (6 Flaschen)"), ShoppingEntry(name: "Cola", quantity: "6 flaschen"))
        XCTAssertEqual(ShoppingEntryParser.parse("  bread  "), ShoppingEntry(name: "Bread", quantity: ""))
        XCTAssertEqual(ShoppingEntryParser.parse("Vitamin B12"), ShoppingEntry(name: "Vitamin B12", quantity: ""))
        XCTAssertEqual(ShoppingEntryParser.parse("7up"), ShoppingEntry(name: "7up", quantity: ""))
    }

    func testAislesFollowTheShop() {
        XCTAssertEqual(ShoppingAisles.aisleKey(for: "Bananen"), "groceries.fruits")
        XCTAssertEqual(ShoppingAisles.aisleKey(for: "Milch"), "groceries.dairy")
        XCTAssertEqual(ShoppingAisles.aisleKey(for: "Qwertz"), ShoppingAisles.other)
        XCTAssertLessThan(ShoppingAisles.order(of: "groceries.fruits"), ShoppingAisles.order(of: "groceries.frozen"))
        XCTAssertEqual(ShoppingAisles.name(of: "groceries.dairy"), "Milk & Dairy")
    }

    func testReceiptTicksOffBoughtItems() {
        let milk = UUID(), bananas = UUID(), potatoes = UUID(), chocolate = UUID(), soap = UUID()
        let open = [(id: milk, name: "Milch"), (id: bananas, name: "Banane"), (id: potatoes, name: "Kartoffeln"),
                    (id: chocolate, name: "Schokolade"), (id: soap, name: "Seife")]
        let lines = ["H-VOLLMILCH 3,5% 1L", "BANANEN 1,2KG", "KARTOFF. FESTK.", "MILCHSCHOKOLADE"]
        let bought = ShoppingReceiptMatcher.boughtItems(open: open, receiptLines: lines)
        XCTAssertEqual(Set(bought), [milk, bananas, potatoes, chocolate])
        XCTAssertFalse(bought.contains(soap))
    }

    func testChocolateLineDoesNotCountAsMilk() {
        let milk = UUID()
        XCTAssertEqual(ShoppingReceiptMatcher.boughtItems(open: [(id: milk, name: "Milch")], receiptLines: ["MILCHSCHOKOLADE"]), [])
    }

    func testOneLineTicksOffOneItem() {
        let a = UUID(), b = UUID()
        let bought = ShoppingReceiptMatcher.boughtItems(open: [(id: a, name: "Milch"), (id: b, name: "milch")], receiptLines: ["MILCH"])
        XCTAssertEqual(bought, [a])
    }

    func testSuggestionsByFrequency() {
        let d = Date(timeIntervalSince1970: 1_800_000_000)
        let history = [("Milch", d), ("milch", d.addingTimeInterval(10)), ("Brot", d), ("Butter", d), ("Butter", d), ("Butter", d)]
            .map { (name: $0.0, date: $0.1) }
        XCTAssertEqual(ShoppingSuggestions.frequent(history: history, excludingOpen: []), ["Butter", "milch", "Brot"])
        XCTAssertEqual(ShoppingSuggestions.frequent(history: history, excludingOpen: ["BUTTER"]), ["milch", "Brot"])
        XCTAssertEqual(ShoppingSuggestions.frequent(history: history, excludingOpen: [], prefix: "br"), ["Brot"])
    }
}

final class RepeatAndReminderTests: XCTestCase {
    let calendar = FamiloqCalendar.make(timeZone: TimeZone(identifier: "Europe/Berlin")!)

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testMonthlyKeepsDay() {
        let rule = RepeatRule(frequency: .monthly, start: date(2026, 1, 31))
        XCTAssertEqual(rule.occurrence(1, calendar: calendar), date(2026, 2, 28))
        XCTAssertEqual(rule.occurrence(2, calendar: calendar), date(2026, 3, 31))
    }

    func testOccurrencesInRangeAndEnd() {
        let rule = RepeatRule(frequency: .daily, start: date(2024, 1, 1, 8), end: date(2026, 9, 3))
        let list = rule.occurrences(from: date(2026, 9, 1), to: date(2026, 9, 10), calendar: calendar)
        XCTAssertEqual(list, [date(2026, 9, 1, 8), date(2026, 9, 2, 8)])
        XCTAssertEqual(rule.next(after: date(2026, 9, 1, 8), calendar: calendar), date(2026, 9, 2, 8))
        XCTAssertNil(rule.next(after: date(2026, 9, 2, 8), calendar: calendar))
    }

    func testBuckets() {
        let now = date(2026, 9, 28, 12)
        XCTAssertEqual(ReminderSchedule.bucket(due: date(2026, 9, 28, 11), hasTime: true, now: now, calendar: calendar), .overdue)
        XCTAssertEqual(ReminderSchedule.bucket(due: date(2026, 9, 28), hasTime: false, now: now, calendar: calendar), .today)
        XCTAssertEqual(ReminderSchedule.bucket(due: date(2026, 9, 27), hasTime: false, now: now, calendar: calendar), .overdue)
        XCTAssertEqual(ReminderSchedule.bucket(due: date(2026, 9, 29, 7), hasTime: true, now: now, calendar: calendar), .tomorrow)
        XCTAssertEqual(ReminderSchedule.bucket(due: date(2026, 10, 3), hasTime: false, now: now, calendar: calendar), .next7Days)
        XCTAssertEqual(ReminderSchedule.bucket(due: date(2026, 11, 3), hasTime: false, now: now, calendar: calendar), .later)
        XCTAssertEqual(ReminderSchedule.bucket(due: nil, hasTime: false, now: now, calendar: calendar), .noDate)
    }

    func testCompletingOverdueWeeklyChoreJumpsToThisWeek() {
        let rule = RepeatRule(frequency: .weekly, start: date(2026, 9, 1))  // Tuesdays
        let next = ReminderSchedule.nextDue(after: date(2026, 9, 8), rule: rule, now: date(2026, 9, 28, 12), calendar: calendar)
        XCTAssertEqual(next, date(2026, 9, 29))
        XCTAssertNil(ReminderSchedule.nextDue(after: date(2026, 9, 8), rule: RepeatRule(frequency: .never, start: date(2026, 9, 8)), now: date(2026, 9, 28), calendar: calendar))
    }
}

final class EventCalendarTests: XCTestCase {
    let calendar = FamiloqCalendar.make(timeZone: TimeZone(identifier: "Europe/Berlin")!)

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testBirthdayRepeatsYearly() {
        let id = UUID()
        let spec = EventSpec(id: id, start: date(1990, 10, 3), end: date(1990, 10, 4), isAllDay: true, frequency: .yearly)
        let occ = EventCalendar.occurrences(of: [spec], in: DateInterval(start: date(2026, 10, 1), end: date(2026, 11, 1)), calendar: calendar)
        XCTAssertEqual(occ.map(\.start), [date(2026, 10, 3)])
        XCTAssertEqual(EventCalendar.days(of: occ[0], calendar: calendar), [date(2026, 10, 3)])
    }

    func testMultiDayEventOverlapsAndOrder() {
        let trip = EventSpec(id: UUID(), start: date(2026, 9, 27), end: date(2026, 9, 30), isAllDay: true)
        let dentist = EventSpec(id: UUID(), start: date(2026, 9, 28, 8), end: date(2026, 9, 28, 9), isAllDay: false)
        let occ = EventCalendar.occurrences(of: [dentist, trip], in: DateInterval(start: date(2026, 9, 28), end: date(2026, 9, 29)), calendar: calendar)
        XCTAssertEqual(occ.map(\.eventID), [trip.id, dentist.id])
        XCTAssertEqual(EventCalendar.days(of: occ[0], calendar: calendar).count, 3)
    }

    func testMonthGridStartsOnMonday() {
        let grid = EventCalendar.monthGrid(for: date(2026, 9, 15), calendar: calendar)
        // 1 Sep 2026 is a Tuesday -> one empty cell.
        XCTAssertNil(grid[0])
        XCTAssertEqual(grid[1], date(2026, 9, 1))
        XCTAssertEqual(grid.count % 7, 0)
        XCTAssertEqual(grid.compactMap { $0 }.count, 30)
    }
}

final class NotificationPlannerTests: XCTestCase {
    let calendar = FamiloqCalendar.make(timeZone: TimeZone(identifier: "Europe/Berlin")!)

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testOnlyMyFutureAlertsInOrder() {
        let me = UUID(), carol = UUID()
        let now = date(2026, 9, 28, 12)
        let reminders = [
            NotificationPlanner.Reminder(id: UUID(), due: date(2026, 9, 29), hasTime: false, assignees: []),      // 9:00 tomorrow
            NotificationPlanner.Reminder(id: UUID(), due: date(2026, 9, 28, 15), hasTime: true, assignees: [me]), // 15:00 today
            NotificationPlanner.Reminder(id: UUID(), due: date(2026, 9, 28, 16), hasTime: true, assignees: [carol]),
            NotificationPlanner.Reminder(id: UUID(), due: date(2026, 9, 28, 10), hasTime: true, assignees: [])    // past
        ]
        let dentist = EventSpec(id: UUID(), start: date(2026, 9, 30, 10), end: date(2026, 9, 30, 11), isAllDay: false)
        let birthday = EventSpec(id: UUID(), start: date(2000, 10, 2), end: date(2000, 10, 3), isAllDay: true, frequency: .yearly)
        let events = [
            NotificationPlanner.Event(spec: dentist, alertMinutes: 60, participants: [me]),
            NotificationPlanner.Event(spec: birthday, alertMinutes: 1440, participants: []),
            NotificationPlanner.Event(spec: dentist, alertMinutes: nil, participants: [])
        ]
        let bills = [NotificationPlanner.Bill(id: "rent", date: date(2026, 10, 1))]
        let plan = NotificationPlanner.plan(reminders: reminders, events: events, bills: bills, me: [me], now: now, calendar: calendar)
        XCTAssertEqual(plan.map(\.fireDate), [date(2026, 9, 28, 15), date(2026, 9, 29, 9), date(2026, 9, 30, 9), date(2026, 9, 30, 18), date(2026, 10, 1, 9)])
        XCTAssertEqual(plan.map(\.kind), [.reminder, .reminder, .event, .bill, .event])
    }

    func testLimit() {
        let now = date(2026, 9, 28, 12)
        let daily = EventSpec(id: UUID(), start: date(2026, 1, 1, 20), end: date(2026, 1, 1, 21), isAllDay: false, frequency: .daily)
        let plan = NotificationPlanner.plan(reminders: [], events: [.init(spec: daily, alertMinutes: 0, participants: [])], bills: [],
                                            me: [], now: now, calendar: calendar, limit: 10)
        XCTAssertEqual(plan.count, 10)
        XCTAssertEqual(plan.first?.fireDate, date(2026, 9, 28, 20))
    }
}
