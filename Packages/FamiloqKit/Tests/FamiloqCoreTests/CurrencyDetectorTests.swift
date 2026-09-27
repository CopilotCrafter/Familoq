import XCTest
@testable import FamiloqCore

final class CurrencyDetectorTests: XCTestCase {
    private func detect(_ text: String) -> CurrencyDetection {
        CurrencyDetector.detect(lines: text.components(separatedBy: "\n"))
    }

    func testAllPatternsCompile() {
        let patterns = CurrencyDetector.uniqueMarkers.map(\.pattern)
            + CurrencyDetector.sharedMarkers.map(\.pattern)
            + CurrencyDetector.hints.map(\.pattern)
        for pattern in patterns {
            XCTAssertNoThrow(try NSRegularExpression(pattern: pattern), pattern)
        }
    }

    func testIsoCodeIsCertain() {
        let d = detect("REWE\nSUMME EUR 12,50")
        XCTAssertEqual(d.code, "EUR")
        XCTAssertEqual(d.confidence, .certain)
        XCTAssertFalse(d.needsConfirmation)
    }

    func testUniqueSymbols() {
        XCTAssertEqual(detect("Café\nTotal 4,50 €").code, "EUR")
        XCTAssertEqual(detect("Tesco\nTOTAL £8.20").code, "GBP")
        XCTAssertEqual(detect("Biedronka\nSUMA PLN 23,40").code, "PLN")
        XCTAssertEqual(detect("Żabka\nRazem 12,99 zł").code, "PLN")
        XCTAssertEqual(detect("Billa\nCelkem 249,00 Kč").code, "CZK")
        XCTAssertEqual(detect("SPAR\nÖSSZESEN 858 Ft").code, "HUF")
        XCTAssertEqual(detect("Pão de Açúcar\nTOTAL R$ 25,90").code, "BRL")
        XCTAssertEqual(detect("Dmart\nTotal ₹ 450.00").code, "INR")
        XCTAssertEqual(detect("Migros\nTotal CHF 18.35").code, "CHF")
        XCTAssertEqual(detect("Seven\n合計 1,280円").code, "JPY")
    }

    func testNothingFoundAsksTheUser() {
        let d = detect("Shop\nBrot 2,50\nTotal 2,50")
        XCTAssertNil(d.code)
        XCTAssertEqual(d.confidence, .unknown)
        XCTAssertTrue(d.needsConfirmation)
    }

    func testDollarAloneIsAmbiguous() {
        let d = detect("Joe's Diner\nBurger $12.50\nTotal $12.50")
        XCTAssertEqual(d.code, "USD")
        XCTAssertEqual(d.confidence, .likely)
        XCTAssertTrue(d.candidates.contains("CAD"))
        XCTAssertTrue(d.candidates.contains("AUD"))
    }

    func testDollarWithCanadianHints() {
        let d = detect("Tim Hortons\nTel +1 416 555 0100\nCoffee $2.50\nHST 13% 0.33\nTotal $2.83")
        XCTAssertEqual(d.code, "CAD")
        XCTAssertEqual(d.confidence, .certain)
    }

    func testDollarWithAustralianWebAddress() {
        let d = detect("Woolworths\nwww.woolworths.com.au\nTOTAL $15.20")
        XCTAssertEqual(d.code, "AUD")
        XCTAssertEqual(d.confidence, .certain)
    }

    func testKronerNarrowedToNorway() {
        let d = detect("REMA 1000\nTotalt 54,40 kr\nMVA 15% 7,10\nTlf +47 22 00 00 00")
        XCTAssertEqual(d.code, "NOK")
        XCTAssertEqual(d.confidence, .certain)
    }

    func testKronerWithoutHintsAsks() {
        let d = detect("Kiosk\nSumma 45,00 kr")
        XCTAssertEqual(d.confidence, .likely)
        XCTAssertEqual(Set(d.candidates), ["SEK", "NOK", "DKK", "ISK"])
    }

    func testYenWithJapaneseTax() {
        let d = detect("ローソン\n合計 ¥688\n(内消費税等 ¥50)")
        XCTAssertEqual(d.code, "JPY")
        XCTAssertEqual(d.confidence, .certain)
    }

    func testTwoCurrenciesOnOneReceiptAsks() {
        let d = detect("Hotel\nTotal EUR 100,00\nEUR\nCard payment USD 108.50")
        XCTAssertEqual(d.code, "EUR")
        XCTAssertEqual(d.confidence, .likely)
        XCTAssertEqual(d.candidates, ["EUR", "USD"])
    }

    func testHintOnlyIsLikely() {
        let d = detect("Bäckerei\nSumme 3,20\nMwSt 7% 0,21")
        XCTAssertEqual(d.code, "EUR")
        XCTAssertEqual(d.confidence, .likely)
        XCTAssertTrue(d.candidates.contains("CHF"))
    }

    func testWordsAreNotCurrencies() {
        // "EURO" inside a word is not the code "EUR".
        XCTAssertEqual(detect("EUROSHOP\nSumme 5,00").confidence, .unknown)
    }

    func testWholeAmountCurrencies() {
        XCTAssertTrue(CurrencyDetector.usesWholeAmounts("JPY"))
        XCTAssertTrue(CurrencyDetector.usesWholeAmounts("huf"))
        XCTAssertFalse(CurrencyDetector.usesWholeAmounts("EUR"))
        XCTAssertFalse(CurrencyDetector.usesWholeAmounts(nil))
    }
}
