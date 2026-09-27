import XCTest
@testable import FamiloqCore

final class CurrencyConversionTests: XCTestCase {
    private let calendar = FamiloqCalendar.make(timeZone: TimeZone(identifier: "Europe/Berlin")!)

    private func rate(_ base: String, _ quote: String, _ value: String, date: String = "2026-09-25") -> ExchangeRate {
        ExchangeRate(base: base, quote: quote, rate: Decimal(string: value)!, rateDateKey: date, source: "test")
    }

    func testSameCurrencyNeedsNoRate() throws {
        let r = rate("USD", "EUR", "0.9")
        XCTAssertEqual(try CurrencyConverter.convert(Decimal(string: "10.005")!, from: "EUR", to: "eur", using: r), Decimal(string: "10.01"))
    }

    func testDirectConversionRoundsToTargetMinorUnits() throws {
        // 25.00 USD at 0.8543 = 21.3575 -> 21.36 EUR
        let r = rate("USD", "EUR", "0.8543")
        XCTAssertEqual(try CurrencyConverter.convert(25, from: "USD", to: "EUR", using: r), Decimal(string: "21.36"))
    }

    func testInverseConversion() throws {
        // Rate EUR->USD 1.17; converting 117 USD -> EUR = 100.00
        let r = rate("EUR", "USD", "1.17")
        XCTAssertEqual(try CurrencyConverter.convert(117, from: "USD", to: "EUR", using: r), 100)
    }

    func testZeroDecimalTargetCurrency() throws {
        let r = rate("EUR", "JPY", "163.456")
        XCTAssertEqual(try CurrencyConverter.convert(10, from: "EUR", to: "JPY", using: r), 1635)
    }

    func testMismatchedRateThrows() {
        let r = rate("GBP", "EUR", "1.15")
        XCTAssertThrowsError(try CurrencyConverter.convert(10, from: "USD", to: "EUR", using: r))
    }

    func testCrossRateViaEuro() throws {
        let eurUsd = rate("EUR", "USD", "1.20")
        let eurGbp = rate("EUR", "GBP", "0.84")
        let usdGbp = try CurrencyConverter.crossRate(eurToFrom: eurUsd, eurToTo: eurGbp)
        XCTAssertEqual(usdGbp.base, "USD")
        XCTAssertEqual(usdGbp.quote, "GBP")
        XCTAssertEqual(usdGbp.rate, Decimal(string: "0.7"))
    }

    func testInvertedRate() {
        let r = rate("EUR", "USD", "1.25")
        XCTAssertEqual(r.inverted?.rate, Decimal(string: "0.8"))
        XCTAssertEqual(r.inverted?.base, "USD")
    }

    // MARK: Status resolution (rate for "date and time" of the receipt)

    func testRateForSameDayIsFinal() {
        XCTAssertEqual(ConversionStatusResolver.status(requestedDateKey: "2026-09-21", rateDateKey: "2026-09-21", todayKey: "2026-09-27", calendar: calendar), .converted)
    }

    func testWeekendExpenseUsesFridayRateAsFinal() {
        // Saturday 19 Sep 2026 -> ECB rate from Friday 18 Sep is the official one.
        XCTAssertEqual(ConversionStatusResolver.status(requestedDateKey: "2026-09-19", rateDateKey: "2026-09-18", todayKey: "2026-09-27", calendar: calendar), .converted)
    }

    func testTodayBeforePublicationIsEstimated() {
        XCTAssertEqual(ConversionStatusResolver.status(requestedDateKey: "2026-09-25", rateDateKey: "2026-09-24", todayKey: "2026-09-25", calendar: calendar), .estimated)
    }

    func testDateKeyRoundTrip() {
        let date = DateKey.date(from: "2026-02-28", calendar: calendar)!
        XCTAssertEqual(DateKey.string(from: date, calendar: calendar), "2026-02-28")
        XCTAssertEqual(DateKey.daysBetween("2026-02-28", "2026-03-02", calendar: calendar), 2)
    }

    func testStatusFlags() {
        XCTAssertTrue(ConversionStatus.estimated.needsRefresh)
        XCTAssertTrue(ConversionStatus.pending.needsRefresh)
        XCTAssertFalse(ConversionStatus.manual.needsRefresh)
        XCTAssertFalse(ConversionStatus.pending.hasBaseAmount)
        XCTAssertTrue(ConversionStatus.manual.hasBaseAmount)
    }
}

final class FrankfurterClientTests: XCTestCase {
    final class StubHTTP: HTTPClient {
        var responses: [(Data, Int)]
        var requested: [URL] = []
        init(_ responses: [(Data, Int)]) { self.responses = responses }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requested.append(request.url!)
            guard !responses.isEmpty else { throw ExchangeRateError.unavailable }
            return responses.removeFirst()
        }
    }

    private let sample = #"{"amount":1.0,"base":"USD","date":"2026-09-25","rates":{"EUR":0.8543}}"#

    func testURLBuilding() {
        let url = FrankfurterClient.url(endpoint: FrankfurterClient.defaultEndpoints[0], from: "usd", to: "eur", dateKey: "2026-09-25")
        XCTAssertEqual(url?.absoluteString, "https://api.frankfurter.dev/v1/2026-09-25?base=USD&symbols=EUR")
        let latest = FrankfurterClient.url(endpoint: FrankfurterClient.defaultEndpoints[1], from: "GBP", to: "EUR", dateKey: nil)
        XCTAssertEqual(latest?.absoluteString, "https://api.frankfurter.app/latest?from=GBP&to=EUR")
    }

    func testParse() throws {
        let rate = try FrankfurterClient.parse(data: Data(sample.utf8), from: "USD", to: "EUR")
        XCTAssertEqual(rate.base, "USD")
        XCTAssertEqual(rate.quote, "EUR")
        XCTAssertEqual(rate.rateDateKey, "2026-09-25")
        XCTAssertEqual(rate.rate.rounded(scale: 4), Decimal(string: "0.8543"))
    }

    func testParseMissingSymbolIsUnsupported() {
        XCTAssertThrowsError(try FrankfurterClient.parse(data: Data(sample.utf8), from: "USD", to: "GBP")) { error in
            XCTAssertEqual(error as? ExchangeRateError, .unsupportedCurrency)
        }
    }

    func testFallsBackToSecondEndpoint() async throws {
        let http = StubHTTP([(Data(), 503), (Data(sample.utf8), 200)])
        let client = FrankfurterClient(http: http)
        let rate = try await client.fetchRate(from: "USD", to: "EUR", dateKey: "2026-09-25")
        XCTAssertEqual(rate.rateDateKey, "2026-09-25")
        XCTAssertEqual(http.requested.count, 2)
    }

    func testUnknownCurrencyReportsUnsupported() async {
        let http = StubHTTP([(Data(), 404), (Data(), 404)])
        let client = FrankfurterClient(http: http)
        do {
            _ = try await client.fetchRate(from: "AED", to: "EUR", dateKey: nil)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? ExchangeRateError, .unsupportedCurrency)
        }
    }

    func testOfflineReportsUnavailable() async {
        let client = FrankfurterClient(http: StubHTTP([]))
        do {
            _ = try await client.fetchRate(from: "USD", to: "EUR", dateKey: nil)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? ExchangeRateError, .unavailable)
        }
    }
}
