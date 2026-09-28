import XCTest
import FamiloqCore
@testable import FamiloqPlanner

final class MealsTravelTests: XCTestCase {
    func testIngredientsMerge() {
        let entries = MealIngredients.merged(["2 Zwiebeln", "500 g Hackfleisch", "1 Zwiebeln", "Hackfleisch", "Salz"])
        XCTAssertEqual(entries, [
            ShoppingEntry(name: "Zwiebeln", quantity: "3"),
            ShoppingEntry(name: "Hackfleisch", quantity: "500 g + 1"),
            ShoppingEntry(name: "Salz", quantity: "")
        ])
    }

    func testLinesFromText() {
        XCTAssertEqual(MealIngredients.lines(from: "- 2 Eier\n• Mehl\n\n* 1 l Milch"), ["2 Eier", "Mehl", "1 l Milch"])
    }

    func testSettleUp() {
        let people = ["martin", "carol", "anna"]
        let payments = [
            TripPayment(amount: 90, paidBy: "martin"),                          // 30 each
            TripPayment(amount: 60, paidBy: "carol", splitAmong: ["martin", "carol"]), // 30 each
            TripPayment(amount: 10, paidBy: "anna")                             // 3.33 / 3.33 / 3.34
        ]
        let balance = TripSettlement.balances(payments, participants: people)
        XCTAssertEqual(balance.values.reduce(0, +), 0)
        XCTAssertEqual(balance["martin"], Decimal(string: "26.67"))
        let transfers = TripSettlement.transfers(balance)
        XCTAssertEqual(transfers.reduce(Decimal(0)) { $0 + $1.amount }, Decimal(string: "26.67"))
        XCTAssertTrue(transfers.allSatisfy { $0.to == "martin" })
    }

    func testDeadlineAlerts() {
        let calendar = FamiloqCalendar.make(timeZone: TimeZone(identifier: "Europe/Berlin")!)
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12))!
        let deadline = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30))!
        let plan = NotificationPlanner.plan(reminders: [], events: [], bills: [],
                                            deadlines: [.init(id: "telekom", date: deadline, daysBefore: [30, 7, 0])],
                                            me: [], now: now, calendar: calendar)
        XCTAssertEqual(plan.map(\.id), ["fq.d.telekom.7", "fq.d.telekom.0"])
        XCTAssertEqual(plan.first?.fireDate, calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 9)))
    }
}
