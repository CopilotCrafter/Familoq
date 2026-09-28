import XCTest
import FamiloqCore
@testable import FamiloqPlanner

final class HolidayTests: XCTestCase {
    let calendar = FamiloqCalendar.make(timeZone: TimeZone(identifier: "Europe/Berlin")!)

    func d(_ y: Int, _ m: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: day))! }

    func testEaster() {
        XCTAssertEqual(PublicHolidays.easter(2026, calendar: calendar), d(2026, 4, 5))
        XCTAssertEqual(PublicHolidays.easter(2027, calendar: calendar), d(2027, 3, 28))
        XCTAssertEqual(PublicHolidays.easter(2025, calendar: calendar), d(2025, 4, 20))
    }

    func testBavaria2026() {
        let list = PublicHolidays.holidays(year: 2026, country: "DE", state: "BY", calendar: calendar)
        XCTAssertEqual(list.count, 13)
        let byDate = Dictionary(uniqueKeysWithValues: list.map { ($0.date, $0.name) })
        XCTAssertEqual(byDate[d(2026, 1, 6)], "Epiphany")
        XCTAssertEqual(byDate[d(2026, 4, 3)], "Good Friday")
        XCTAssertEqual(byDate[d(2026, 5, 14)], "Ascension Day")
        XCTAssertEqual(byDate[d(2026, 6, 4)], "Corpus Christi")
        XCTAssertEqual(byDate[d(2026, 8, 15)], "Assumption Day")
        XCTAssertEqual(byDate[d(2026, 10, 3)], "German Unity Day")
        XCTAssertNil(byDate[d(2026, 10, 31)], "no Reformation Day in Bavaria")
    }

    func testGermanyWithoutStateIsNationwideOnly() {
        let list = PublicHolidays.holidays(year: 2026, country: "DE", state: nil, calendar: calendar)
        XCTAssertEqual(list.count, 9)
    }

    func testSaxonyDayOfPrayer() {
        let list = PublicHolidays.holidays(year: 2026, country: "DE", state: "SN", calendar: calendar)
        XCTAssertTrue(list.contains { $0.date == d(2026, 11, 18) && $0.name == "Day of Prayer and Repentance" })
    }

    func testUKSubstituteAndUSRules() {
        // 26 Dec 2026 is a Saturday -> Boxing Day on Monday 28 Dec; Christmas is Friday.
        let uk = PublicHolidays.holidays(year: 2026, country: "GB", state: nil, calendar: calendar)
        XCTAssertTrue(uk.contains { $0.date == d(2026, 12, 28) && $0.name == "Boxing Day" })
        let us = PublicHolidays.holidays(year: 2026, country: "US", state: nil, calendar: calendar)
        XCTAssertTrue(us.contains { $0.date == d(2026, 11, 26) && $0.name == "Thanksgiving" })
        XCTAssertTrue(us.contains { $0.date == d(2026, 5, 25) && $0.name == "Memorial Day" })
    }

    func testAlpha3() {
        XCTAssertEqual(PublicHolidays.alpha2(fromAlpha3: "DEU"), "DE")
        XCTAssertNil(PublicHolidays.alpha2(fromAlpha3: "XYZ"))
    }
}

final class TimeOffTests: XCTestCase {
    let calendar = FamiloqCalendar.make(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    let martin = UUID(), carol = UUID()

    func d(_ y: Int, _ m: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: day))! }

    var bavaria: Set<Date> {
        Set(PublicHolidays.holidays(year: 2026, country: "DE", state: "BY", calendar: calendar).map(\.date))
    }

    func testWeekendsAndHolidaysAreNotCounted() {
        // Thu 1 Oct - Tue 6 Oct 2026: Sat 3 Oct is German Unity Day (a Saturday anyway).
        let spans = [LeaveSpan(memberID: martin, type: .vacation, first: d(2026, 10, 1), last: d(2026, 10, 6))]
        let year = DateInterval(start: d(2026, 1, 1), end: d(2027, 1, 1))
        XCTAssertEqual(TimeOffCalculator.usedDays(spans, in: year, holidays: bavaria, calendar: calendar), 4)
        // Ascension Thursday 14 May + bridge day Friday 15 May.
        let bridge = [LeaveSpan(memberID: martin, type: .bridgeDay, first: d(2026, 5, 14), last: d(2026, 5, 15))]
        XCTAssertEqual(TimeOffCalculator.usedDays(bridge, in: year, holidays: bavaria, calendar: calendar), 1)
    }

    func testHalfDaysTrainingAndPeriod() {
        let year = DateInterval(start: d(2026, 1, 1), end: d(2027, 1, 1))
        let october = DateInterval(start: d(2026, 10, 1), end: d(2026, 11, 1))
        let spans = [
            LeaveSpan(memberID: martin, type: .halfDay, first: d(2026, 9, 30), last: d(2026, 9, 30)),
            LeaveSpan(memberID: martin, type: .training, first: d(2026, 10, 12), last: d(2026, 10, 13)),
            LeaveSpan(memberID: martin, type: .vacation, first: d(2026, 10, 29), last: d(2026, 11, 3))
        ]
        XCTAssertEqual(TimeOffCalculator.usedDays(spans, in: year, holidays: bavaria, calendar: calendar), 4.5)
        // In October only Thu 29 + Fri 30 count (Nov 2 & 3 are outside).
        XCTAssertEqual(TimeOffCalculator.usedDays(spans, in: october, holidays: bavaria, calendar: calendar), 2)
        XCTAssertEqual(TimeOffCalculator.trainingDays(spans, in: october, holidays: bavaria, calendar: calendar), 2)
    }

    func testFamilyOverlap() {
        let spans = [
            LeaveSpan(memberID: martin, type: .vacation, first: d(2026, 10, 12), last: d(2026, 10, 23)),
            LeaveSpan(memberID: carol, type: .vacation, first: d(2026, 10, 19), last: d(2026, 10, 30)),
            LeaveSpan(memberID: carol, type: .training, first: d(2026, 10, 5), last: d(2026, 10, 14))
        ]
        let october = DateInterval(start: d(2026, 10, 1), end: d(2026, 11, 1))
        let overlaps = TimeOffCalculator.overlaps(spans, in: october, calendar: calendar)
        XCTAssertEqual(overlaps.count, 1)
        XCTAssertEqual(overlaps.first?.first, d(2026, 10, 19))
        XCTAssertEqual(overlaps.first?.last, d(2026, 10, 23))
        XCTAssertEqual(overlaps.first?.people, [martin, carol])
    }
}
