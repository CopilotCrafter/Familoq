import XCTest
import FamiloqCore
@testable import FamiloqBudget

final class CarsTests: XCTestCase {
    let calendar = FamiloqCalendar.make(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    func d(_ y: Int, _ m: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: day))! }

    func testConsumptionFromFullFillUps() {
        let entries = [
            CarLogEntry(date: d(2026, 9, 1), amount: 80, kind: .fuel, quantity: 45, odometer: 10_000),
            CarLogEntry(date: d(2026, 9, 10), amount: 60, kind: .fuel, quantity: 36, odometer: 10_600),
            CarLogEntry(date: d(2026, 9, 20), amount: 55, kind: .fuel, quantity: 30, odometer: 11_100),
            CarLogEntry(date: d(2026, 9, 21), amount: 4, kind: .parking)
        ]
        // (36 + 30) l over 1100 km = 6.0 l/100 km.
        XCTAssertEqual(CarStats.consumption(entries)!, 6.0, accuracy: 0.001)
        XCTAssertEqual(CarStats.distance(entries), 1100)
        XCTAssertEqual(CarStats.total(entries), 199)
        XCTAssertEqual(CarStats.costPerKm(entries), Decimal(string: "0.18"))
        XCTAssertEqual(CarStats.lastOdometer(entries), 11_100)
        XCTAssertEqual(CarStats.totals(entries).map(\.kind), [.fuel, .parking])
    }

    func testNoConsumptionWithoutTwoReadings() {
        let entries = [
            CarLogEntry(date: d(2026, 9, 1), amount: 80, kind: .fuel, quantity: 45, odometer: 10_000),
            CarLogEntry(date: d(2026, 9, 10), amount: 60, kind: .fuel, quantity: 36)
        ]
        XCTAssertNil(CarStats.consumption(entries))
        XCTAssertNil(CarStats.costPerKm(entries))
    }

    func testAveragePrice() {
        let entries = [
            CarLogEntry(date: d(2026, 9, 1), amount: Decimal(string: "81.37")!, kind: .fuel, quantity: 45.23),
            CarLogEntry(date: d(2026, 9, 2), amount: 300, kind: .service)
        ]
        XCTAssertEqual(CarStats.averagePrice(entries), Decimal(string: "1.799"))
    }

    func testFuelItems() {
        for name in ["Super E10", "SUPER PLUS", "Diesel", "V-Power 100", "Premium Diesel", "Autogas LPG", "Super E5"] {
            XCTAssertTrue(FuelReceipt.isFuelItem(name), name)
        }
        for name in ["Snickers", "Kaffee groß", "Supermarkt Tüte", "Scheibenwischer", "Waschanlage Premium"] {
            XCTAssertFalse(FuelReceipt.isFuelItem(name), name)
        }
        XCTAssertTrue(FuelReceipt.isFuelReceipt(subcategoryKey: "transport.fuel", itemNames: []))
        XCTAssertFalse(FuelReceipt.isFuelReceipt(subcategoryKey: "groceries.other", itemNames: ["Milch"]))
    }

    func testFuelLitersFromAralReceipt() {
        let lines = ["Aral", "Chamer Str. 50", "93426 Roding",
                     "Super E10", "45,23 l x 1,799 EUR/l 81,37 A", "Snickers 1,29 A",
                     "Gesamt 82,66", "Girocard 82,66", "29.09.2026 08:10"]
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12))!
        let receipt = ReceiptParser.parse(lines: lines, calendar: calendar, now: now)
        XCTAssertEqual(FuelReceipt.liters(items: receipt.items)!, 45.23, accuracy: 0.001)
        XCTAssertEqual(FuelReceipt.fuelAmount(items: receipt.items), Decimal(string: "81.37"))
    }

    func testCostKindsMapToTransport() {
        for kind in CarCostKind.allCases {
            XCTAssertTrue(kind.subcategoryKey.hasPrefix("transport."), kind.rawValue)
        }
        XCTAssertEqual(CarCostKind.guess(subcategoryKey: "transport.parking"), .parking)
        XCTAssertNil(CarCostKind.guess(subcategoryKey: "groceries.fruits"))
    }

    func testTyreSeason() {
        let next = TyreSeason.nextChange(after: d(2026, 9, 30), calendar: calendar)
        XCTAssertEqual(next?.toWinter, true)
        XCTAssertEqual(calendar.component(.month, from: next!.date), 10)
        XCTAssertEqual(calendar.component(.day, from: next!.date), 10)
        let spring = TyreSeason.nextChange(after: d(2026, 11, 1), calendar: calendar)
        XCTAssertEqual(spring?.toWinter, false)
        XCTAssertEqual(calendar.component(.year, from: spring!.date), 2027)
        XCTAssertEqual(calendar.component(.month, from: spring!.date), 4)
    }

    func testInspection() {
        XCTAssertEqual(CarInspection.next(after: d(2026, 5, 1), calendar: calendar), d(2028, 5, 1))
        XCTAssertEqual(CarInspection.next(after: d(2026, 5, 1), firstRegistration: true, calendar: calendar), d(2029, 5, 1))
    }
}

final class DocumentsTests: XCTestCase {
    let calendar = FamiloqCalendar.make(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    func d(_ y: Int, _ m: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: day))! }

    func testExpiryState() {
        let now = d(2026, 9, 30)
        XCTAssertNil(DocumentExpiry.state(expiresOn: nil, now: now, calendar: calendar))
        XCTAssertEqual(DocumentExpiry.state(expiresOn: d(2026, 9, 29), now: now, calendar: calendar), .expired)
        XCTAssertEqual(DocumentExpiry.state(expiresOn: d(2026, 10, 30), now: now, calendar: calendar), .soon(days: 30))
        XCTAssertEqual(DocumentExpiry.state(expiresOn: d(2027, 9, 30), now: now, calendar: calendar), .valid)
    }

    func testReminders() {
        let now = d(2026, 9, 30)
        let passport = DocumentExpiry.reminders(expiresOn: d(2027, 1, 28), days: DocumentKind.passport.reminderDays, now: now, calendar: calendar)
        XCTAssertEqual(passport.map(\.days), [90, 30])
        XCTAssertEqual(calendar.component(.hour, from: passport[0].date), 9)
        XCTAssertEqual(calendar.startOfDay(for: passport[0].date), d(2026, 10, 30))
        // 90 days before is already past: only the 30-day reminder is left.
        let soon = DocumentExpiry.reminders(expiresOn: d(2026, 12, 1), days: [90, 30], now: now, calendar: calendar)
        XCTAssertEqual(soon.map(\.days), [30])
    }

    func testKinds() {
        XCTAssertTrue(DocumentKind.passport.usuallyExpires)
        XCTAssertFalse(DocumentKind.birthCertificate.usuallyExpires)
        XCTAssertTrue(DocumentKind.idCard.isPersonal)
        XCTAssertFalse(DocumentKind.carRegistration.isPersonal)
        XCTAssertEqual(Set(DocumentKind.allCases.map(\.icon)).count, DocumentKind.allCases.count)
    }
}
