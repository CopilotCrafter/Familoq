import XCTest
import FamiloqCore
@testable import FamiloqBudget

/// Typical receipts of the common German shops (layout as printed), each
/// read four ways: as clean lines, and as OCR fragments of a flat, a curled
/// and a tilted photo (names and prices as separate pieces, like Vision
/// returns them).
final class ReceiptCorpusTests: XCTestCase {
    struct Sample {
        let name: String
        let merchant: String
        let total: String
        let itemCount: Int
        let lines: [String]
    }

    static let samples: [Sample] = [
        Sample(name: "REWE Roding", merchant: "REWE", total: "15.93", itemCount: 8, lines: [
            "REWE", "Schellererstr. 1", "93426 Roding", "UID Nr.: DE279127485", "EUR",
            "INGWER BIO 0,90 B", "0,184 kg x 4,90 EUR/kg", "TYROLINI WUERZIG 2,49 B", "KARTOFFELN 2,29 B",
            "JA! BASMATI REIS 2,49 B", "MANDELN GANZ 2,49 B", "ZWIEB.LAKTOSEFR. 1,99 B", "SALZ MIT SELEN 1,29 B",
            "ERDNUESSE 1,99 B", "--------------------", "SUMME EUR 15,93", "Geg. EC-Cash EUR 15,93",
            "** Kundenbeleg **", "Datum: 29.09.2026", "Uhrzeit: 19:19:06 Uhr", "Beleg-Nr. 0280", "Trace-Nr. 631281",
            "Kartenzahlung", "Contactless", "girocard", "Nr. ############4375 0000", "Terminal-ID 56027930",
            "Zahlung erfolgt", "Netto Steuer Brutto", "14,89 1,04 15,93"
        ]),
        Sample(name: "REWE with deposit and quantity", merchant: "REWE Markt GmbH", total: "5.33", itemCount: 5, lines: [
            "REWE Markt GmbH", "Hauptstr. 5", "93413 Cham", "EUR",
            "BIO BANANE 1,99 B", "MINERALWASSER 0,59 B", "PFAND 0,25 A", "BROETCHEN 1,78 B", "2 Stk x 0,89",
            "PAYBACK COUPON -0,20 B", "JOGHURT 0,92 B", "SUMME EUR 5,33", "Geg. BAR EUR 10,00", "Rueckgeld BAR EUR 4,67",
            "B= 7,0% 4,69 0,33 5,02", "A= 19,0% 0,21 0,04 0,25", "27.09.2026 10:15 Bon-Nr.:1234",
            "Mit PAYBACK 2 Punkte gesammelt"
        ]),
        Sample(name: "Lidl with weighed item", merchant: "Lidl", total: "12.52", itemCount: 7, lines: [
            "Lidl", "Hauptstr. 12", "93426 Roding", "EUR",
            "Bananen 1,29 A", "Gouda jung Scheiben 1,79 A", "Vollkornbrot 1,49 A", "Paprika rot 1,99 A", "Preisvorteil -0,40",
            "Mineralwasser 6x1,5l 1,74 B", "Pfand 1,50 B", "Äpfel Elstar", "1,254 kg x 2,49 EUR/kg 3,12 A",
            "zu zahlen 12,52", "Karte 12,52", "A 7 % 0,61 8,68 9,29", "B 19 % 0,52 2,72 3,24", "29.09.26 18:02 Uhr"
        ]),
        Sample(name: "ALDI SÜD", merchant: "ALDI SÜD", total: "31.08", itemCount: 16, lines: ReceiptAccuracyTests.aldiLines),
        Sample(name: "ALDI Nord", merchant: "ALDI Nord", total: "8.86", itemCount: 4, lines: [
            "ALDI Nord", "ALDI GmbH & Co. KG", "Musterweg 5", "12345 Berlin",
            "Milch 3,5% 1,09 A", "Eier 10er Freiland 2,29 A", "Toastbrot 0,99 A", "Kaffee gemahlen 4,49 A",
            "Summe 8,86", "Kartenzahlung 8,86", "29.09.2026 14:31"
        ]),
        Sample(name: "EDEKA", merchant: "EDEKA", total: "10.99", itemCount: 6, lines: [
            "EDEKA", "Center Müller", "Bahnhofstr. 3", "93413 Cham", "EUR",
            "Bio Vollmilch 3,8% 1,29 A", "Speisequark", "2 x 0,79 1,58 A", "Rinderhack 500g 4,99 A", "Zwiebeln 1kg 1,49 A",
            "Coca-Cola 1,0l 1,39 B", "Pfand 0,25 B", "--------------------------------", "SUMME EUR 10,99",
            "Geg. EC-Cash EUR 10,99", "Steuer % Netto Steuer Brutto", "A= 7,0% 8,74 0,61 9,35", "B= 19,0% 1,38 0,26 1,64",
            "Posten: 7", "29.09.2026 17:45 Bon-Nr.: 4567"
        ]),
        Sample(name: "Kaufland", merchant: "Kaufland", total: "10.71", itemCount: 5, lines: [
            "Kaufland", "Kaufland Cham", "Further Str. 20", "93413 Cham", "EUR",
            "Joghurt Natur 0,49 1", "Lachsfilet 250g 4,99 1", "Spülmittel 1,15 2", "Gurke 0,69 1", "Hähnchenschenkel",
            "0,850 kg x 3,99 EUR/kg 3,39 1", "Summe 10,71", "Bar 20,00", "Rückgeld 9,29",
            "MwSt 1 = 7% 9,56 0,63", "MwSt 2 = 19% 1,15 0,18", "29.09.2026 16:20"
        ]),
        Sample(name: "Netto", merchant: "NETTO Marken-Discount", total: "7.96", itemCount: 4, lines: [
            "NETTO Marken-Discount", "Regensburger Str. 8", "93426 Roding",
            "Toastbrot 1,19 A", "Butter 250g 2,29 A", "Äpfel 2kg 2,99 A", "Orangensaft 1,49 B",
            "Summe 7,96", "EC-Cash 7,96", "DeutschlandCard Punkte: 7", "A 7% 6,05 0,42 6,47", "29.09.2026 12:05"
        ]),
        Sample(name: "PENNY with coupon", merchant: "PENNY", total: "5.51", itemCount: 5, lines: [
            "PENNY", "PENNY Markt GmbH", "Am Markt 1", "93444 Bad Kötzting", "EUR",
            "Kartoffeln 2,5kg 2,49 B", "Mozzarella 0,89 B", "Mozzarella 0,89 B", "Coupon Mozzarella -0,20 B",
            "Nudeln Penne 0,79 B", "Tomaten passiert 0,65 B", "--------------------", "SUMME EUR 5,51",
            "Geg. Mastercard EUR 5,51", "29.09.2026 13:40"
        ]),
        Sample(name: "dm", merchant: "dm-drogerie markt", total: "13.34", itemCount: 4, lines: [
            "dm-drogerie markt", "Marktplatz 4", "93413 Cham",
            "Balea Duschgel 0,95 1", "Alverde Zahnpasta 1,45 1", "dmBio Haferflocken 0,99 2", "Babylove Windeln 9,95 1",
            "SUMME EUR 13,34", "EC-Karte 13,34", "MwSt 1 19,00% 10,43 1,98", "MwSt 2 7,00% 0,93 0,06", "29.09.2026 11:30"
        ]),
        Sample(name: "Rossmann", merchant: "ROSSMANN", total: "7.03", itemCount: 3, lines: [
            "ROSSMANN", "Dirk Rossmann GmbH", "Schulstr. 2", "93426 Roding",
            "Isana Shampoo 1,25 B", "Rival de Loop Creme 2,49 B", "Toilettenpapier 8x 3,29 B",
            "Summe EUR 7,03", "Kartenzahlung 7,03", "29.09.2026 10:12"
        ]),
        Sample(name: "NORMA", merchant: "NORMA", total: "4.67", itemCount: 3, lines: [
            "NORMA", "Industriestr. 1", "93426 Roding",
            "Milch 1,5% 0,99 A", "Käse Emmentaler 2,19 A", "Bananen 1,49 A",
            "Summe 4,67", "EC 4,67", "29.09.2026 09:00"
        ]),
        Sample(name: "Aral fuel", merchant: "Aral", total: "82.66", itemCount: 2, lines: [
            "Aral", "Chamer Str. 50", "93426 Roding",
            "Super E10", "45,23 l x 1,799 EUR/l 81,37 A", "Snickers 1,29 A",
            "Gesamt 82,66", "Girocard 82,66", "29.09.2026 08:10"
        ]),
        Sample(name: "Bakery", merchant: "Bäckerei Mustermann", total: "6.30", itemCount: 3, lines: [
            "Bäckerei Mustermann", "Marktplatz 1", "93426 Roding",
            "2 x Brezen 1,60", "Kaffee groß 2,80", "Butterbreze 1,90",
            "Summe 6,30", "Bar 10,00", "Rückgeld 3,70", "29.09.2026 07:45"
        ])
    ]

    static let calendar = FamiloqCalendar.make(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    static let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12))!

    // MARK: Fragments like Vision returns them

    static let pricePattern = try! NSRegularExpression(
        pattern: #"\s(-?\d{1,5}(?:[.,]\d{3})*[.,]\d{2}\s*(?:EUR|€)?\s*(?:[A-Z0-9]{1,2})?\s*\*?)$"#, options: [.caseInsensitive])

    /// Name and price of each line as separate fragments.
    /// - Parameters:
    ///   - curl: each further price drifts down by this share of a line.
    ///   - slope: the whole receipt tilted (dy per dx).
    static func fragments(_ lines: [String], curl: Double = 0, slope: Double = 0) -> [OCRFragment] {
        let pitch = 0.0165, height = 0.013
        var result: [OCRFragment] = []
        var priceIndex = 0
        for (index, line) in lines.enumerated() {
            let top = 0.04 + Double(index) * pitch
            func make(_ text: String, x: Double, width: Double, extra: Double = 0) -> OCRFragment {
                let mid = x + width / 2
                return OCRFragment(text: text, x: x, y: top + extra + slope * (mid - 0.5), width: width, height: height, slope: slope)
            }
            let range = NSRange(line.startIndex..., in: line)
            if let match = pricePattern.firstMatch(in: line, range: range), let priceRange = Range(match.range(at: 1), in: line) {
                let name = String(line[..<priceRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let price = String(line[priceRange])
                if !name.isEmpty { result.append(make(name, x: 0.08, width: min(0.6, 0.012 * Double(name.count)))) }
                result.append(make(price, x: 0.78, width: 0.12, extra: Double(priceIndex) * curl * pitch))
                priceIndex += 1
            } else {
                result.append(make(line, x: 0.08, width: min(0.6, max(0.05, 0.012 * Double(line.count)))))
            }
        }
        return result
    }

    private func check(_ parsed: ParsedReceipt, _ sample: Sample, _ variant: String, file: StaticString = #filePath, line: UInt = #line) {
        let label = "\(sample.name) (\(variant)): " + parsed.items.map { "\($0.name)=\($0.amount)" }.joined(separator: " | ")
        XCTAssertEqual(parsed.merchant, sample.merchant, label, file: file, line: line)
        XCTAssertEqual(parsed.total, Decimal(string: sample.total), label, file: file, line: line)
        XCTAssertEqual(parsed.items.count, sample.itemCount, label, file: file, line: line)
        XCTAssertTrue(parsed.itemsMatchTotal, label, file: file, line: line)
        XCTAssertNotNil(parsed.date, label, file: file, line: line)
    }

    func testCleanLines() {
        for sample in Self.samples {
            check(ReceiptParser.parse(lines: sample.lines, calendar: Self.calendar, now: Self.now), sample, "lines")
        }
    }

    func testFlatPhoto() {
        for sample in Self.samples {
            check(ReceiptParser.parse(fragments: Self.fragments(sample.lines), calendar: Self.calendar, now: Self.now), sample, "flat")
        }
    }

    func testCurledPhoto() {
        for sample in Self.samples {
            let fragments = Self.fragments(sample.lines, curl: 0.08)
            check(ReceiptParser.parse(fragments: fragments, calendar: Self.calendar, now: Self.now), sample, "curled")
        }
    }

    func testTiltedPhoto() {
        for sample in Self.samples {
            let fragments = Self.fragments(sample.lines, slope: 0.06)
            check(ReceiptParser.parse(fragments: fragments, calendar: Self.calendar, now: Self.now), sample, "tilted")
        }
    }

    func testWeighedAndQuantityLines() {
        let lidl = ReceiptParser.parse(lines: Self.samples[2].lines, calendar: Self.calendar, now: Self.now)
        XCTAssertEqual(lidl.items.last?.name, "Äpfel Elstar")
        XCTAssertEqual(lidl.items.last?.amount, Decimal(string: "3.12"))
        XCTAssertEqual(lidl.items.last?.quantity, Decimal(string: "1.254"))
        let edeka = ReceiptParser.parse(lines: Self.samples[5].lines, calendar: Self.calendar, now: Self.now)
        XCTAssertEqual(edeka.items[1].name, "Speisequark")
        XCTAssertEqual(edeka.items[1].quantity, 2)
        let aral = ReceiptParser.parse(lines: Self.samples[12].lines, calendar: Self.calendar, now: Self.now)
        XCTAssertEqual(aral.items.first?.name, "Super E10")
        XCTAssertEqual(aral.items.first?.quantity, Decimal(string: "45.23"))
        let rewe = ReceiptParser.parse(lines: Self.samples[0].lines, calendar: Self.calendar, now: Self.now)
        XCTAssertEqual(rewe.items.first?.quantity, Decimal(string: "0.184"))
    }
}
