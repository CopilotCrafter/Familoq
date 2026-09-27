import XCTest
@testable import FamiloqCore

final class MoneyTests: XCTestCase {
    func testFixedPointRoundTrip() {
        let values: [Decimal] = [0, 1, Decimal(string: "12.34")!, Decimal(string: "0.0001")!, Decimal(string: "-5.5")!, Decimal(string: "123456.789")!]
        for v in values {
            XCTAssertEqual(FixedPoint.decimal(from: FixedPoint.storage(from: v)), v, "round trip \(v)")
        }
    }

    func testFixedPointRoundsHalfUp() {
        XCTAssertEqual(FixedPoint.storage(from: Decimal(string: "0.00005")!), 1)
        XCTAssertEqual(FixedPoint.storage(from: Decimal(string: "1.23454")!), 12345)
    }

    func testDecimalParserGermanAndEnglish() {
        XCTAssertEqual(DecimalParser.parse("12,50"), Decimal(string: "12.50"))
        XCTAssertEqual(DecimalParser.parse("12.50"), Decimal(string: "12.50"))
        XCTAssertEqual(DecimalParser.parse("1.234,56"), Decimal(string: "1234.56"))
        XCTAssertEqual(DecimalParser.parse("1,234.56"), Decimal(string: "1234.56"))
        XCTAssertEqual(DecimalParser.parse("1.234"), Decimal(1234))
        XCTAssertEqual(DecimalParser.parse("0,123"), Decimal(string: "0.123"))
        XCTAssertEqual(DecimalParser.parse("€ 5,50"), Decimal(string: "5.50"))
        XCTAssertEqual(DecimalParser.parse(",5"), Decimal(string: "0.5"))
        XCTAssertEqual(DecimalParser.parse("3000"), Decimal(3000))
        XCTAssertEqual(DecimalParser.parse("-4,20"), Decimal(string: "-4.20"))
        XCTAssertNil(DecimalParser.parse(""))
        XCTAssertNil(DecimalParser.parse("abc"))
        XCTAssertNil(DecimalParser.parse("1-2"))
    }

    func testMinorUnits() {
        XCTAssertEqual(CurrencyInfo.minorUnits(for: "EUR"), 2)
        XCTAssertEqual(CurrencyInfo.minorUnits(for: "jpy"), 0)
        XCTAssertEqual(CurrencyInfo.minorUnits(for: "KWD"), 3)
    }

    func testCurrencyCodeValidation() {
        XCTAssertTrue(CurrencyInfo.isValidCode("usd"))
        XCTAssertFalse(CurrencyInfo.isValidCode("US"))
        XCTAssertFalse(CurrencyInfo.isValidCode("U5D"))
        XCTAssertTrue(CurrencyInfo.canAutoConvert(from: "USD", to: "EUR"))
        XCTAssertTrue(CurrencyInfo.canAutoConvert(from: "INR", to: "GBP"))
        XCTAssertFalse(CurrencyInfo.canAutoConvert(from: "AED", to: "EUR"))
    }
}
