import XCTest
import FamiloqCore
@testable import FamiloqBudget

final class PlanningTests: XCTestCase {
    private let calendar = FamiloqCalendar.make(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testMonthlyKeepsDayAndClampsShortMonths() {
        let rule = RecurrenceRule(frequency: .monthly, start: day(2026, 1, 31))
        let dates = rule.occurrences(from: day(2026, 1, 1), to: day(2026, 5, 1), calendar: calendar)
        let days = dates.map { calendar.component(.day, from: $0) }
        XCTAssertEqual(days, [31, 28, 31, 30])
    }

    func testWeeklyBiweeklyQuarterlyYearlyOnce() {
        let start = day(2026, 9, 1)
        let end = day(2027, 9, 2)
        XCTAssertEqual(RecurrenceRule(frequency: .weekly, start: start).occurrences(from: start, to: day(2026, 9, 30), calendar: calendar).count, 5)
        XCTAssertEqual(RecurrenceRule(frequency: .biweekly, start: start).occurrences(from: start, to: day(2026, 9, 30), calendar: calendar).count, 3)
        XCTAssertEqual(RecurrenceRule(frequency: .quarterly, start: start).occurrences(from: start, to: end, calendar: calendar).count, 5)
        XCTAssertEqual(RecurrenceRule(frequency: .yearly, start: start).occurrences(from: start, to: end, calendar: calendar).count, 2)
        XCTAssertEqual(RecurrenceRule(frequency: .once, start: start).occurrences(from: day(2020, 1, 1), to: end, calendar: calendar), [start])
    }

    func testEndDateIsRespected() {
        let rule = RecurrenceRule(frequency: .monthly, start: day(2026, 1, 15), end: day(2026, 3, 15))
        XCTAssertEqual(rule.occurrences(from: day(2025, 1, 1), to: day(2027, 1, 1), calendar: calendar).count, 3)
    }

    func testDueOccurrencesBookEachDateOnce() {
        let rule = RecurrenceRule(frequency: .monthly, start: day(2026, 7, 1))
        let firstRun = ScheduleBooking.dueOccurrences(rule: rule, bookedThrough: nil, now: day(2026, 9, 27), calendar: calendar)
        XCTAssertEqual(firstRun.count, 3, "July, August, September")
        let secondRun = ScheduleBooking.dueOccurrences(rule: rule, bookedThrough: firstRun.last, now: day(2026, 9, 28), calendar: calendar)
        XCTAssertTrue(secondRun.isEmpty)
        let october = ScheduleBooking.dueOccurrences(rule: rule, bookedThrough: firstRun.last, now: day(2026, 10, 1, 10), calendar: calendar)
        XCTAssertEqual(october, [day(2026, 10, 1)])
    }

    func testCatchUpIsLimited() {
        let rule = RecurrenceRule(frequency: .weekly, start: day(2020, 1, 1))
        XCTAssertEqual(ScheduleBooking.dueOccurrences(rule: rule, bookedThrough: nil, now: day(2026, 9, 27), calendar: calendar).count, 12)
    }

    func testUpcomingUntilMonthEnd() {
        let rule = RecurrenceRule(frequency: .weekly, start: day(2026, 9, 1))
        let upcoming = ScheduleBooking.upcoming(rule: rule, bookedThrough: day(2026, 9, 22), now: day(2026, 9, 23), until: day(2026, 10, 1, 0), calendar: calendar)
        XCTAssertEqual(upcoming, [day(2026, 9, 29)])
    }

    func testDeterministicIDs() {
        let a = DeterministicID.uuid("rent|2026-09-01")
        XCTAssertEqual(a, DeterministicID.uuid("rent|2026-09-01"))
        XCTAssertNotEqual(a, DeterministicID.uuid("rent|2026-10-01"))
        XCTAssertEqual(a.uuidString.count, 36)
    }

    func testSavingsProgressAndMonthlyNeed() {
        let p = SavingsPlanner.progress(target: 2000, saved: 500, deadline: day(2027, 6, 30), now: day(2026, 9, 28), calendar: calendar)
        XCTAssertEqual(p.remaining, 1500)
        XCTAssertEqual(p.monthsLeft, 10, "Sep 2026 ... Jun 2027")
        XCTAssertEqual(p.monthlyNeeded, 150)
        XCTAssertEqual(p.fraction, 0.25, accuracy: 0.0001)
        XCTAssertFalse(p.isReached)
    }

    func testSavingsReachedAndOverdue() {
        XCTAssertTrue(SavingsPlanner.progress(target: 100, saved: 120, deadline: nil, now: day(2026, 9, 28), calendar: calendar).isReached)
        let late = SavingsPlanner.progress(target: 100, saved: 20, deadline: day(2026, 8, 1), now: day(2026, 9, 28), calendar: calendar)
        XCTAssertTrue(late.isOverdue)
        XCTAssertEqual(late.monthlyNeeded, 80)
    }

    func testMonthlyNeedRoundsUp() {
        let p = SavingsPlanner.progress(target: 100, saved: 0, deadline: day(2026, 11, 15), now: day(2026, 9, 28), calendar: calendar)
        XCTAssertEqual(p.monthsLeft, 3)
        XCTAssertEqual(p.monthlyNeeded, Decimal(string: "33.34"))
    }
}

final class InsightsTests: XCTestCase {
    private let calendar = FamiloqCalendar.make(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }
    private let groceries = UUID()
    private let martin = UUID()

    private func facts(_ merchant: String, _ amount: Decimal, date: Date? = nil, currency: String = "EUR", category: UUID? = nil, member: UUID? = nil, method: String = "manual") -> ExpenseFacts {
        ExpenseFacts(merchant: merchant, note: "", categoryPath: category == nil ? "" : "Groceries › Fruits", categoryID: category, memberID: member,
                     date: date ?? day(2026, 9, 10), amount: amount, currencyCode: currency, baseAmount: amount, entryMethod: method)
    }

    func testTextSearchAllWordsAndUmlauts() {
        var filter = ExpenseFilter()
        filter.text = "rewe fruits"
        XCTAssertTrue(filter.matches(facts("REWE Markt", 5, category: groceries), baseCurrency: "EUR"))
        XCTAssertFalse(filter.matches(facts("Lidl", 5, category: groceries), baseCurrency: "EUR"))
        filter.text = "bäckerei"
        XCTAssertTrue(filter.matches(facts("Baeckerei Mueller", 3), baseCurrency: "EUR") || filter.matches(facts("Bäckerei Müller", 3), baseCurrency: "EUR"))
    }

    func testAmountSearch() {
        var filter = ExpenseFilter()
        filter.text = "12,50"
        XCTAssertTrue(filter.matches(facts("Shop", Decimal(string: "12.5")!), baseCurrency: "EUR"))
        XCTAssertFalse(filter.matches(facts("Shop", 13), baseCurrency: "EUR"))
    }

    func testFiltersCombine() {
        var filter = ExpenseFilter()
        filter.from = day(2026, 9, 1)
        filter.to = day(2026, 10, 1)
        filter.categoryIDs = [groceries]
        filter.memberIDs = [martin]
        filter.minAmount = 10
        filter.entryMethods = ["receipt"]
        XCTAssertEqual(filter.activeFilterCount, 5)
        XCTAssertTrue(filter.matches(facts("Lidl", 20, category: groceries, member: martin, method: "receipt"), baseCurrency: "EUR"))
        XCTAssertFalse(filter.matches(facts("Lidl", 5, category: groceries, member: martin, method: "receipt"), baseCurrency: "EUR"))
        XCTAssertFalse(filter.matches(facts("Lidl", 20, category: groceries, member: UUID(), method: "receipt"), baseCurrency: "EUR"))
        XCTAssertFalse(filter.matches(facts("Lidl", 20, date: day(2026, 8, 31), category: groceries, member: martin, method: "receipt"), baseCurrency: "EUR"))
    }

    func testForeignCurrencyOnly() {
        var filter = ExpenseFilter()
        filter.onlyForeignCurrency = true
        XCTAssertTrue(filter.matches(facts("Asia Center", 329, currency: "CZK"), baseCurrency: "EUR"))
        XCTAssertFalse(filter.matches(facts("REWE", 5), baseCurrency: "EUR"))
    }

    func testMonthlyTotalsFillEmptyMonths() {
        let entries: [(date: Date, amount: Decimal)] = [(day(2026, 7, 3), 10), (day(2026, 7, 20), 5), (day(2026, 9, 1), 7)]
        let totals = SpendingTrends.monthlyTotals(entries: entries, months: 3, endingAt: day(2026, 9, 28), calendar: calendar)
        XCTAssertEqual(totals.map(\.total), [15, 0, 7])
        XCTAssertEqual(SpendingTrends.averageOfCompleteMonths(totals), Decimal(string: "7.5"))
    }
}

final class BackupFormatTests: XCTestCase {
    func testCSVQuotingAndGermanNumbers() {
        let csv = CSVWriter(separator: ";", decimalComma: true)
        XCTAssertEqual(csv.number(Decimal(string: "12.5")), "12,50")
        XCTAssertEqual(csv.field("Müller; Söhne"), "\"Müller; Söhne\"")
        XCTAssertEqual(csv.field("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(csv.line(["a", "b"]), "a;b\r\n")
        let data = csv.document(header: ["x"], rows: [["1"]])
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
    }

    func testCSVEnglishNumbers() {
        let csv = CSVWriter(separator: ",", decimalComma: false)
        XCTAssertEqual(csv.number(3), "3.00")
        XCTAssertEqual(csv.number(Decimal(string: "329.1234"), places: 4), "329.1234")
        XCTAssertEqual(csv.number(nil), "")
    }

    func testBackupRoundTrip() throws {
        let backup = FamilyBackup(familyID: UUID(), familyName: "Martin & Carol", baseCurrency: "EUR",
                                  exportedAt: Date(timeIntervalSince1970: 1_790_000_000),
                                  records: [.init(kind: "expense", id: UUID(), fields: ["merchant": "Lidl"], image: "AAEC"),
                                            .init(kind: "category", id: UUID(), fields: ["name": "Groceries"])])
        let back = try FamilyBackup.decode(try backup.encoded())
        XCTAssertEqual(back, backup)
        XCTAssertEqual(back.counts, ["expense": 1, "category": 1])
    }

    func testRejectsOtherFiles() {
        XCTAssertThrowsError(try FamilyBackup.decode(Data("{\"hello\":1}".utf8)))
    }
}
