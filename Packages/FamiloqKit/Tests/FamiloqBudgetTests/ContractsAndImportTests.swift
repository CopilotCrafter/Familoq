import XCTest
import FamiloqCore
@testable import FamiloqBudget

final class ContractTests: XCTestCase {
    let calendar = FamiloqCalendar.make(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    func d(_ y: Int, _ m: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: day))! }

    func testMinimumTermWithThreeMonthsNotice() {
        let terms = ContractTerms(start: d(2025, 1, 1), minimumTermMonths: 24, renewalMonths: 1, noticeValue: 3, noticeUnit: .months)
        let next = ContractSchedule.next(terms, now: d(2026, 9, 28), calendar: calendar)
        XCTAssertEqual(next?.deadline, d(2026, 9, 30))
        XCTAssertEqual(next?.termEnd, d(2026, 12, 31))
    }

    func testAfterMissedDeadlineRenewsMonthly() {
        let terms = ContractTerms(start: d(2025, 1, 1), minimumTermMonths: 24, renewalMonths: 1, noticeValue: 1, noticeUnit: .months)
        // Deadline for 31 Dec 2026 was 30 Nov 2026; on 1 Dec the next is 31 Dec for 31 Jan 2027.
        let next = ContractSchedule.next(terms, now: d(2026, 12, 1), calendar: calendar)
        XCTAssertEqual(next?.deadline, d(2026, 12, 31))
        XCTAssertEqual(next?.termEnd, d(2027, 1, 31))
    }

    func testYearlyRenewalWithWeeksNoticeAndEndingContract() {
        let yearly = ContractTerms(start: d(2024, 3, 15), minimumTermMonths: 12, renewalMonths: 12, noticeValue: 6, noticeUnit: .weeks)
        let next = ContractSchedule.next(yearly, now: d(2026, 9, 28), calendar: calendar)
        XCTAssertEqual(next?.termEnd, d(2027, 3, 14))
        XCTAssertEqual(next?.deadline, d(2027, 1, 31))
        let ending = ContractTerms(start: d(2025, 1, 1), minimumTermMonths: 12, renewalMonths: 0, noticeValue: 1, noticeUnit: .months)
        XCTAssertNil(ContractSchedule.next(ending, now: d(2026, 9, 28), calendar: calendar))
    }

    func testFixedCostsPerMonth() {
        let housing = UUID(), insurance = UUID(), martin = UUID()
        let items = [
            FixedCostItem(id: "rent", title: "Rent", amount: 950, frequency: .monthly, categoryID: housing, memberID: nil),
            FixedCostItem(id: "car", title: "Car insurance", amount: 480, frequency: .yearly, categoryID: insurance, memberID: martin),
            FixedCostItem(id: "water", title: "Water", amount: 90, frequency: .quarterly, categoryID: housing, memberID: nil),
            FixedCostItem(id: "tv", title: "TV once", amount: 700, frequency: .once, categoryID: nil, memberID: nil)
        ]
        let summary = FixedCosts.summary(items)
        XCTAssertEqual(summary.perMonth, 1020)
        XCTAssertEqual(summary.byCategory[housing], 980)
        XCTAssertEqual(summary.byMember[martin], 40)
        XCTAssertEqual(summary.items.map(\.id), ["rent", "car", "water"])
        XCTAssertEqual(summary.perYear, 12240)
    }

    func testWarranty() {
        XCTAssertEqual(WarrantyTerms.end(purchase: d(2025, 10, 5), months: 24, calendar: calendar), d(2027, 10, 4))
        XCTAssertEqual(WarrantyTerms.daysLeft(purchase: d(2024, 10, 5), months: 24, now: d(2026, 9, 28), calendar: calendar), 6)
    }
}

final class BankImportTests: XCTestCase {
    let calendar = FamiloqCalendar.make(timeZone: TimeZone(identifier: "Europe/Berlin")!)

    let sparkasse = """
    "Auftragskonto";"Buchungstag";"Valutadatum";"Buchungstext";"Verwendungszweck";"Beguenstigter/Zahlungspflichtiger";"Kontonummer/IBAN";"BIC (SWIFT-Code)";"Betrag";"Waehrung";"Info"
    "DE00123";"28.09.26";"28.09.26";"KARTENZAHLUNG";"ALDI SUED 021 RODING";"ALDI SUED";"DE11";"BIC";"-31,08";"EUR";"Umsatz gebucht"
    "DE00123";"27.09.26";"27.09.26";"GUTSCHRIFT";"Gehalt September";"Arbeitgeber GmbH";"DE22";"BIC";"3.210,00";"EUR";"Umsatz gebucht"
    "DE00123";"26.09.26";"26.09.26";"LASTSCHRIFT";"Vertrag 4711 ""Mobil""";"Telekom Deutschland";"DE33";"BIC";"-1.049,99";"EUR";"Umsatz gebucht"
    """

    let dkb = """
    "Konto:";"DE00 1234"
    "Kontostand vom 28.09.2026:";"1.234,00 EUR"

    "Buchungsdatum";"Wertstellung";"Status";"Zahlungspflichtige*r";"Zahlungsempfänger*in";"Verwendungszweck";"Umsatztyp";"IBAN";"Betrag (€)"
    "28.09.26";"28.09.26";"Gebucht";"Martin";"REWE Markt";"REWE SAGT DANKE";"Ausgang";"DE44";"-45,20 €"
    """

    func testSparkasseGuessAndParse() throws {
        let rows = CSVReader.rows(sparkasse)
        XCTAssertEqual(rows.first?.count, 11)
        let mapping = try XCTUnwrap(BankStatement.guessMapping(rows))
        XCTAssertEqual(mapping.headerRow, 0)
        XCTAssertEqual(mapping.date, 1)
        XCTAssertEqual(mapping.amount, 8)
        XCTAssertEqual(mapping.payee, 5)
        XCTAssertEqual(mapping.purpose, 4)
        let tx = BankStatement.transactions(rows, mapping: mapping, calendar: calendar)
        XCTAssertEqual(tx.count, 3)
        XCTAssertEqual(tx[0].amount, Decimal(string: "-31.08"))
        XCTAssertEqual(tx[0].payee, "ALDI SUED")
        XCTAssertEqual(tx[2].amount, Decimal(string: "-1049.99"))
        XCTAssertEqual(tx[2].purpose, "Vertrag 4711 \"Mobil\"")
        XCTAssertEqual(tx[0].date, calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)))
    }

    func testDKBWithPreambleAndEuroSign() throws {
        let rows = CSVReader.rows(dkb)
        let mapping = try XCTUnwrap(BankStatement.guessMapping(rows))
        XCTAssertEqual(mapping.headerRow, 2)
        let tx = BankStatement.transactions(rows, mapping: mapping, calendar: calendar)
        XCTAssertEqual(tx.count, 1)
        XCTAssertEqual(tx[0].amount, Decimal(string: "-45.2"))
        XCTAssertEqual(tx[0].displayName, "REWE Markt")
    }

    func testDebitCreditColumnsAndCommaFiles() throws {
        let csv = "Date,Description,Debit,Credit\n2026-09-20,Netflix,12.99,\n2026-09-21,Refund,,5.00\n"
        let rows = CSVReader.rows(csv)
        let mapping = try XCTUnwrap(BankStatement.guessMapping(rows))
        XCTAssertNil(mapping.amount)
        let tx = BankStatement.transactions(rows, mapping: mapping, calendar: calendar)
        XCTAssertEqual(tx.map(\.amount), [Decimal(string: "-12.99")!, 5])
    }

    func testDuplicatesAreRecognised() {
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28))!
        let tx = BankTransaction(row: 1, date: day, amount: Decimal(string: "-31.08")!, payee: "ALDI SUED", purpose: "KARTENZAHLUNG")
        let existing = [(date: day.addingTimeInterval(-86_400), amount: Decimal(string: "31.08")!, merchant: "Aldi Süd")]
        XCTAssertTrue(BankStatement.isAlreadyRecorded(tx, existing: existing, calendar: calendar))
        XCTAssertFalse(BankStatement.isAlreadyRecorded(tx, existing: [(date: day, amount: 31, merchant: "Aldi")], calendar: calendar))
        XCTAssertEqual(tx.stableKey, BankTransaction(row: 9, date: day, amount: Decimal(string: "-31.08")!, payee: "ALDI SUED", purpose: "KARTENZAHLUNG").stableKey)
    }

    func testAmountsAndDates() {
        XCTAssertEqual(BankStatement.parseAmount("12,50 S"), Decimal(string: "-12.5"))
        XCTAssertEqual(BankStatement.parseAmount("−7,00 €"), -7)
        XCTAssertEqual(BankStatement.parseAmount("1,234.56"), Decimal(string: "1234.56"))
        XCTAssertNil(BankStatement.parseAmount(""))
        XCTAssertEqual(BankStatement.parseDate("28/09/2026"), DateComponents(year: 2026, month: 9, day: 28))
        XCTAssertNil(BankStatement.parseDate("Buchungstag"))
    }
}
