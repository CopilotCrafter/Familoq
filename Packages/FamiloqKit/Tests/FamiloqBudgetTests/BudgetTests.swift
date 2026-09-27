import XCTest
import FamiloqCore
@testable import FamiloqBudget

final class BudgetTests: XCTestCase {
    private let calendar = FamiloqCalendar.make(timeZone: TimeZone(identifier: "Europe/Berlin")!)

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testWarningLevels() {
        XCTAssertEqual(BudgetCalculator.level(limit: 600, spent: 400), .normal)
        XCTAssertEqual(BudgetCalculator.level(limit: 600, spent: 450), .caution75)
        XCTAssertEqual(BudgetCalculator.level(limit: 600, spent: 540), .warning90)
        XCTAssertEqual(BudgetCalculator.level(limit: 600, spent: 600), .reached100)
        XCTAssertEqual(BudgetCalculator.level(limit: 200, spent: 215), .over)
        XCTAssertEqual(BudgetCalculator.level(limit: 0, spent: 0), .normal)
        XCTAssertEqual(BudgetCalculator.level(limit: 0, spent: 1), .over)
    }

    func testSpecExamples() {
        let groceries = BudgetCalculator.status(limit: 600, spent: 540)
        XCTAssertEqual(groceries.percentUsed, 90)
        XCTAssertEqual(groceries.remaining, 60)

        let restaurants = BudgetCalculator.status(limit: 200, spent: 215)
        XCTAssertEqual(restaurants.overAmount, 15)
        XCTAssertEqual(restaurants.level, .over)
    }

    func testMonthlyInterval() {
        let interval = BudgetPeriod.monthly.interval(containing: date(2026, 9, 27), calendar: calendar)
        XCTAssertEqual(interval.start, calendar.startOfDay(for: date(2026, 9, 1)))
        XCTAssertEqual(interval.end, calendar.startOfDay(for: date(2026, 10, 1)))
    }

    func testWeekStartsOnMonday() {
        // Sunday 27 Sep 2026 belongs to the week Mon 21 - Sun 27.
        let interval = BudgetPeriod.weekly.interval(containing: date(2026, 9, 27), calendar: calendar)
        XCTAssertEqual(interval.start, calendar.startOfDay(for: date(2026, 9, 21)))
        XCTAssertEqual(interval.end, calendar.startOfDay(for: date(2026, 9, 28)))
    }

    func testDailyInterval() {
        let interval = BudgetPeriod.daily.interval(containing: date(2026, 9, 27, 23), calendar: calendar)
        XCTAssertEqual(interval.start, calendar.startOfDay(for: date(2026, 9, 27)))
    }

    // MARK: Safe to spend

    func testSafeToSpendSpecExample() {
        // Budget 3,000, spent 2,184, 30 days remaining -> 27.20/day
        let input = SafeToSpendInput(budget: 3000, spent: 2184, today: date(2026, 9, 1, 9), periodEnd: calendar.startOfDay(for: date(2026, 10, 1)))
        let result = SafeToSpendCalculator.calculate(input, calendar: calendar)
        XCTAssertEqual(result.remaining, 816)
        XCTAssertEqual(result.remainingDays, 30)
        XCTAssertEqual(result.dailyAmount, Decimal(string: "27.20"))
        XCTAssertEqual(result.weeklyAmount, Decimal(string: "190.40"))
        XCTAssertFalse(result.isOverBudget)
    }

    func testSafeToSpendReservesUpcomingBills() {
        // 816 remaining, Netflix 17.99 + car insurance 85 still due -> 713.01 over 4 days
        let input = SafeToSpendInput(budget: 3000, spent: 2184, upcomingCommitted: Decimal(string: "102.99")!, today: date(2026, 9, 27), periodEnd: calendar.startOfDay(for: date(2026, 10, 1)))
        let result = SafeToSpendCalculator.calculate(input, calendar: calendar)
        XCTAssertEqual(result.available, Decimal(string: "713.01"))
        XCTAssertEqual(result.remainingDays, 4)
        XCTAssertEqual(result.dailyAmount, Decimal(string: "178.25"))  // rounded down
        XCTAssertEqual(result.weeklyAmount, Decimal(string: "713.01")) // only 4 days left
    }

    func testSafeToSpendOverBudget() {
        let input = SafeToSpendInput(budget: 1000, spent: 1100, today: date(2026, 9, 15), periodEnd: calendar.startOfDay(for: date(2026, 10, 1)))
        let result = SafeToSpendCalculator.calculate(input, calendar: calendar)
        XCTAssertTrue(result.isOverBudget)
        XCTAssertEqual(result.shortfall, 100)
        XCTAssertEqual(result.dailyAmount, 0)
    }

    func testSafeToSpendLastDayCountsAsOneDay() {
        let input = SafeToSpendInput(budget: 100, spent: 50, today: date(2026, 9, 30, 22), periodEnd: calendar.startOfDay(for: date(2026, 10, 1)))
        let result = SafeToSpendCalculator.calculate(input, calendar: calendar)
        XCTAssertEqual(result.remainingDays, 1)
        XCTAssertEqual(result.dailyAmount, 50)
    }
}
