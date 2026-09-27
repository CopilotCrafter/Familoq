import XCTest
import FamiloqCore
@testable import FamiloqBudget

final class ReceiptParserTests: XCTestCase {
    private let calendar = FamiloqCalendar.make(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 20))! }

    private func parse(_ text: String) -> ParsedReceipt {
        ReceiptParser.parse(lines: text.components(separatedBy: "\n"), calendar: calendar, now: now)
    }

    private func dec(_ s: String) -> Decimal { Decimal(string: s)! }

    // MARK: Lidl-style German receipt

    private let lidl = """
    Lidl
    Lidl Vertriebs GmbH & Co. KG
    Musterstraße 12
    93426 Roding
    EUR
    Hähnchenbrustfilet 8,50 A
    H-Milch 3,5% 1,49 A
    Bananen 2,20 A
    Rispentomaten 3,50 A
    Milka Schokolade 2,99 A
    Preisvorteil -0,50
    zu zahlen 18,18
    Karte 18,18
    A 7,00% 16,99 1,19 18,18
    Datum: 26.09.2026 18:42
    Vielen Dank für Ihren Einkauf
    """

    func testLidlHeaderFields() {
        let r = parse(lidl)
        XCTAssertEqual(r.merchant, "Lidl")
        XCTAssertEqual(r.matchedMerchantPattern, "lidl")
        XCTAssertEqual(r.currencyCode, "EUR")
        XCTAssertEqual(r.total, dec("18.18"))
        let d = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: r.date!)
        XCTAssertEqual([d.year, d.month, d.day, d.hour, d.minute], [2026, 9, 26, 18, 42])
        XCTAssertTrue(r.hasTime)
    }

    func testLidlItemsAndDiscount() {
        let r = parse(lidl)
        XCTAssertEqual(r.items.map(\.name), ["Hähnchenbrustfilet", "H-Milch 3,5%", "Bananen", "Rispentomaten", "Milka Schokolade"])
        XCTAssertEqual(r.items.last?.amount, dec("2.49"), "discount reduces the previous item")
        XCTAssertEqual(r.items.map(\.suggestedSubcategoryKey), [
            "groceries.meat", "groceries.dairy", "groceries.fruits", "groceries.vegetables", "groceries.snacks"
        ])
        XCTAssertTrue(r.itemsMatchTotal)
        XCTAssertTrue(r.warnings.isEmpty, "\(r.warnings)")
    }

    func testLidlVAT() {
        let r = parse(lidl)
        XCTAssertEqual(r.vat.count, 1)
        XCTAssertEqual(r.vat.first?.ratePercent, 7)
        XCTAssertEqual(r.vat.first?.taxAmount, dec("1.19"))
    }

    // MARK: REWE-style receipt with deposit, quantity and two VAT rates

    private let rewe = """
    REWE Markt GmbH
    Hauptstr. 5
    93413 Cham
    UID Nr.: DE812706034
    EUR
    BIO BANANE 1,99 B
    MINERALWASSER 0,59 B
    PFAND 0,25 A
    BROETCHEN 1,78 B
    2 Stk x 0,89
    --------------------
    SUMME EUR 4,61
    Geg. BAR EUR 10,00
    Rueckgeld BAR EUR 5,39
    Steuer % Netto Steuer Brutto
    B= 7,0% 4,06 0,30 4,36
    A= 19,0% 0,21 0,04 0,25
    27.09.2026 10:15 Bon-Nr.:1234
    """

    func testReweReceipt() {
        let r = parse(rewe)
        XCTAssertEqual(r.merchant, "REWE Markt GmbH")
        XCTAssertEqual(r.total, dec("4.61"))
        XCTAssertEqual(r.items.count, 4)
        XCTAssertEqual(r.items.map(\.suggestedSubcategoryKey), [
            "groceries.fruits", "groceries.beverages", "groceries.beverages", "groceries.bakery"
        ])
        XCTAssertEqual(r.items.last?.quantity, 2)
        XCTAssertTrue(r.itemsMatchTotal)
        XCTAssertEqual(r.vat.map(\.ratePercent), [7, 19])
        XCTAssertEqual(r.vat.map(\.taxAmount), [dec("0.30"), dec("0.04")])
    }

    // MARK: English receipt in USD with 12-hour time

    private let english = """
    CORNER STORE
    123 Main Street
    Springfield
    09/25/2026 3:45 PM
    Apples 3.20
    Chicken breast 7.99
    Chocolate bar 1.50
    Subtotal 12.69
    Tax 8% 1.02
    TOTAL 13.71
    VISA 13.71
    USD
    """

    func testEnglishReceipt() {
        let r = parse(english)
        XCTAssertEqual(r.merchant, "CORNER STORE")
        XCTAssertEqual(r.currencyCode, "USD")
        XCTAssertEqual(r.total, dec("13.71"))
        XCTAssertEqual(r.items.map(\.name), ["Apples", "Chicken breast", "Chocolate bar"])
        XCTAssertFalse(r.itemsMatchTotal, "tax is not an item")
        XCTAssertTrue(r.warnings.contains("Items do not add up to the total"))
        let d = calendar.dateComponents([.month, .day, .hour, .minute], from: r.date!)
        XCTAssertEqual([d.month, d.day, d.hour, d.minute], [9, 25, 15, 45])
        XCTAssertEqual(r.vat.first?.ratePercent, 8)
    }

    // MARK: Edge cases

    func testTotalOnNextLine() {
        let r = parse("Shop\nBrot 2,50\nSUMME\n2,50")
        XCTAssertEqual(r.total, dec("2.50"))
        XCTAssertEqual(r.items.count, 1)
    }

    func testFutureDateIsIgnored() {
        let r = parse("Shop\n01.01.2031\nBrot 2,50\nSumme 2,50")
        XCTAssertNil(r.date)
        XCTAssertTrue(r.warnings.contains("Date not recognised - today is used"))
    }

    func testItemWordContainingTotalIsNotTheTotal() {
        let r = parse("Drogerie\nTotalreiniger 3,99\nSumme 3,99")
        XCTAssertEqual(r.items.map(\.name), ["Totalreiniger"])
        XCTAssertEqual(r.total, dec("3.99"))
    }

    func testEmptyInput() {
        let r = parse("")
        XCTAssertNil(r.total)
        XCTAssertTrue(r.items.isEmpty)
        XCTAssertNil(r.merchant)
    }

    // MARK: Receipts from other countries

    func testJapaneseReceiptWithWholeYenAmounts() {
        let r = parse("""
        ローソン 渋谷店
        2026年09月20日(日) 14:05
        おにぎり ¥150
        お茶 ¥140
        サンドイッチ ¥398
        合計 ¥688
        (内消費税等 ¥50)
        お預り ¥1,000
        お釣り ¥312
        """)
        XCTAssertEqual(r.currencyCode, "JPY")
        XCTAssertFalse(r.currency.needsConfirmation)
        XCTAssertEqual(r.total, 688)
        XCTAssertEqual(r.items.map(\.name), ["おにぎり", "お茶", "サンドイッチ"])
        XCTAssertEqual(r.items.map(\.amount), [150, 140, 398])
        XCTAssertTrue(r.itemsMatchTotal)
        let d = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: r.date!)
        XCTAssertEqual([d.year, d.month, d.day, d.hour, d.minute], [2026, 9, 20, 14, 5])
    }

    func testThousandsInWholeAmounts() {
        let r = parse("Café\nKaffee 1,280円\n合計 1,280円")
        XCTAssertEqual(r.total, 1280)
        XCTAssertEqual(r.items.first?.amount, 1280)
    }

    func testHungarianReceipt() {
        let r = parse("SPAR\nKenyér 459 Ft\nTej 399 Ft\nÖSSZESEN 858 Ft")
        XCTAssertEqual(r.currencyCode, "HUF")
        XCTAssertEqual(r.total, 858)
        XCTAssertEqual(r.items.map(\.name), ["Kenyér", "Tej"])
        XCTAssertTrue(r.itemsMatchTotal)
    }

    func testNorwegianReceipt() {
        let r = parse("REMA 1000\nBrød 32,90\nMelk 21,50\nTotalt 54,40 kr\nMVA 15% 7,10\nTlf +47 22 00 00 00")
        XCTAssertEqual(r.currencyCode, "NOK")
        XCTAssertFalse(r.currency.needsConfirmation)
        XCTAssertEqual(r.total, dec("54.40"))
        XCTAssertEqual(r.items.map(\.name), ["Brød", "Melk"])
    }

    func testDollarReceiptAsksForCurrency() {
        let r = parse("Joe's Diner\nBurger $12.50\nTotal $12.50")
        XCTAssertEqual(r.currencyCode, "USD")
        XCTAssertTrue(r.currency.needsConfirmation)
        XCTAssertTrue(r.warnings.contains("Please confirm the currency"))
        XCTAssertEqual(r.items.map(\.name), ["Burger"])
        XCTAssertEqual(r.total, dec("12.50"))
    }

    func testUnknownCurrencyAsks() {
        let r = parse("Shop\nBrot 2,50\nSumme 2,50")
        XCTAssertNil(r.currencyCode)
        XCTAssertTrue(r.warnings.contains("Currency not recognised - please choose it"))
    }

    // MARK: Line assembly from OCR fragments

    func testFragmentsOnSameRowAreJoined() {
        let fragments = [
            OCRFragment(text: "2,20 A", x: 0.80, y: 0.1015, width: 0.1, height: 0.02),
            OCRFragment(text: "Bananen", x: 0.05, y: 0.1000, width: 0.3, height: 0.02),
            OCRFragment(text: "Milch", x: 0.05, y: 0.1300, width: 0.2, height: 0.02),
            OCRFragment(text: "1,49 A", x: 0.80, y: 0.1290, width: 0.1, height: 0.02),
            OCRFragment(text: "Lidl", x: 0.40, y: 0.0200, width: 0.2, height: 0.03)
        ]
        XCTAssertEqual(ReceiptLineAssembler.lines(from: fragments), ["Lidl", "Bananen 2,20 A", "Milch 1,49 A"])
    }

    func testPagesStayInOrder() {
        let fragments = [
            OCRFragment(text: "Summe 5,00", x: 0.1, y: 0.1, width: 0.5, height: 0.02, page: 1),
            OCRFragment(text: "Brot 5,00", x: 0.1, y: 0.9, width: 0.5, height: 0.02, page: 0)
        ]
        XCTAssertEqual(ReceiptLineAssembler.lines(from: fragments), ["Brot 5,00", "Summe 5,00"])
    }
}

extension ReceiptParserTests {
    func testChosenCurrencyReparsesWholeAmounts() {
        // No currency printed: read as decimals first, then as yen once chosen.
        let lines = ["Shop", "Ramen 1,280", "Total 1,280"]
        let guessed = ReceiptParser.parse(lines: lines)
        XCTAssertNil(guessed.currencyCode)
        let yen = ReceiptParser.parse(lines: lines, currency: "jpy")
        XCTAssertEqual(yen.currencyCode, "JPY")
        XCTAssertFalse(yen.currency.needsConfirmation)
        XCTAssertEqual(yen.total, 1280)
        XCTAssertEqual(yen.items.first?.amount, 1280)
    }
}
