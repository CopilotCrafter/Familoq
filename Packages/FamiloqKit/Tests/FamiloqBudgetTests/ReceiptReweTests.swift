import XCTest
import FamiloqCore
@testable import FamiloqBudget

/// Real REWE receipt (Roding, 29.09.2026): names on the left, prices with
/// the tax letter "B" in a separate column, a weighed item, the card slip
/// and the VAT table below the total.
final class ReceiptReweTests: XCTestCase {
    let pitch = 0.0165
    let height = 0.013

    private func fragment(_ text: String, x: Double, row: Double, width: Double, offset: Double = 0) -> OCRFragment {
        OCRFragment(text: text, x: x, y: 0.165 + row * pitch + offset - height / 2, width: width, height: height)
    }

    /// - Parameter curl: how far each further price drifts down (in lines) -
    ///   paper curling towards the camera.
    private func receipt(curl: Double) -> [OCRFragment] {
        var f: [OCRFragment] = [
            OCRFragment(text: "REWE", x: 0.35, y: 0.05, width: 0.3, height: 0.03),
            OCRFragment(text: "Schellererstr. 1", x: 0.40, y: 0.10, width: 0.2, height: height),
            OCRFragment(text: "93426 Roding", x: 0.42, y: 0.117, width: 0.16, height: height),
            OCRFragment(text: "UID Nr.: DE279127485", x: 0.38, y: 0.134, width: 0.25, height: height),
            OCRFragment(text: "EUR", x: 0.72, y: 0.146, width: 0.05, height: height)
        ]
        let items: [(String, Double, String)] = [
            ("INGWER BIO", 0, "0,90 B"), ("TYROLINI WUERZIG", 2, "2,49 B"), ("KARTOFFELN", 3, "2,29 B"),
            ("JA! BASMATI REIS", 4, "2,49 B"), ("MANDELN GANZ", 5, "2,49 B"), ("ZWIEB.LAKTOSEFR.", 6, "1,99 B"),
            ("SALZ MIT SELEN", 7, "1,29 B"), ("ERDNUESSE", 8, "1,99 B")
        ]
        for (index, item) in items.enumerated() {
            f.append(fragment(item.0, x: 0.34, row: item.1, width: 0.2))
            f.append(fragment(item.2, x: 0.72, row: item.1, width: 0.07, offset: Double(index) * curl * pitch))
        }
        f.append(fragment("0,184 kg x 4,90 EUR/kg", x: 0.36, row: 1, width: 0.34))
        f += [
            fragment("SUMME", x: 0.34, row: 9.6, width: 0.08), fragment("EUR", x: 0.6, row: 9.6, width: 0.05),
            fragment("15,93", x: 0.72, row: 9.6, width: 0.07),
            fragment("Geg. EC-Cash", x: 0.34, row: 11, width: 0.15), fragment("EUR", x: 0.6, row: 11, width: 0.05),
            fragment("15,93", x: 0.72, row: 11, width: 0.07),
            fragment("** Kundenbeleg **", x: 0.45, row: 12.5, width: 0.2),
            fragment("Datum:", x: 0.34, row: 13.5, width: 0.08), fragment("29.09.2026", x: 0.68, row: 13.5, width: 0.12),
            fragment("Uhrzeit:", x: 0.34, row: 14.5, width: 0.08), fragment("19:19:06 Uhr", x: 0.66, row: 14.5, width: 0.14),
            fragment("Beleg-Nr.", x: 0.34, row: 15.5, width: 0.1), fragment("0280", x: 0.74, row: 15.5, width: 0.05),
            fragment("Trace-Nr.", x: 0.34, row: 16.5, width: 0.1), fragment("631281", x: 0.72, row: 16.5, width: 0.07),
            fragment("Kartenzahlung", x: 0.48, row: 17.5, width: 0.15),
            fragment("##############4375 0000", x: 0.52, row: 20, width: 0.28),
            fragment("56027930", x: 0.70, row: 21, width: 0.1),
            fragment("19:19 Uhr", x: 0.70, row: 23, width: 0.1),
            fragment("15,93", x: 0.73, row: 24, width: 0.07),
            fragment("14,89", x: 0.48, row: 27, width: 0.06), fragment("1,04", x: 0.6, row: 27, width: 0.05),
            fragment("15,93", x: 0.73, row: 27, width: 0.07)
        ]
        return f
    }

    private let now = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 30))!

    private func check(_ parsed: ParsedReceipt, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(parsed.merchant, "REWE", file: file, line: line)
        XCTAssertEqual(parsed.total, Decimal(string: "15.93"), file: file, line: line)
        XCTAssertEqual(parsed.items.map(\.name), ["INGWER BIO", "TYROLINI WUERZIG", "KARTOFFELN", "JA! BASMATI REIS", "MANDELN GANZ",
                                                  "ZWIEB.LAKTOSEFR", "SALZ MIT SELEN", "ERDNUESSE"], file: file, line: line)
        XCTAssertEqual(parsed.items.map(\.amount), ["0.90", "2.49", "2.29", "2.49", "2.49", "1.99", "1.29", "1.99"].map { Decimal(string: $0)! },
                       file: file, line: line)
        XCTAssertEqual(parsed.items.first?.quantity, Decimal(string: "0.184"), file: file, line: line)
        XCTAssertTrue(parsed.itemsMatchTotal, file: file, line: line)
        let parts = Calendar(identifier: .gregorian).dateComponents(in: FamiloqCalendar.make().timeZone, from: parsed.date!)
        XCTAssertEqual([parts.day, parts.month, parts.year, parts.hour, parts.minute], [29, 9, 2026, 19, 19], file: file, line: line)
    }

    func testFlatReceipt() {
        check(ReceiptParser.parse(fragments: receipt(curl: 0), now: now))
    }

    func testCurledReceiptPairsPricesInOrder() {
        let fragments = receipt(curl: 0.1)
        // The plain lines mix up the lower prices ...
        let plain = ReceiptParser.parse(lines: ReceiptLineAssembler.lines(from: fragments), now: now)
        XCTAssertFalse(plain.itemsMatchTotal, ReceiptLineAssembler.lines(from: fragments).joined(separator: " | "))
        // ... the price column paired in order is right.
        check(ReceiptParser.parse(fragments: fragments, now: now))
    }

    func testTotalFromRepeatedAmountWhenSummeIsMissing() {
        let lines = ["REWE", "Brot 2,00 B", "Milch 1,00 B", "Geg. EC-Cash EUR 3,00", "3,00", "Netto 2,80 0,20 3,00"]
        let parsed = ReceiptParser.parse(lines: lines, now: now)
        XCTAssertEqual(parsed.total, 3)
        XCTAssertEqual(parsed.items.count, 2)
        XCTAssertTrue(parsed.itemsMatchTotal)
    }

    func testRepeatedItemPriceIsNotTakenAsTotal() {
        let lines = ["Shop", "Brot 2,49 B", "Käse 2,49 B", "Milch 1,00 B"]
        XCTAssertNil(ReceiptParser.parse(lines: lines, now: now).total)
    }
}
