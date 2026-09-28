import XCTest
import FamiloqCore
@testable import FamiloqBudget

/// Real ALDI SÜD receipt (28.09.2026), photographed at an angle.
final class ReceiptAccuracyTests: XCTestCase {
    static let aldiLines = [
        "ALDI SÜD", "Kagerstraße 2", "93426 Roding",
        "486763 Hähn. Minist. XXL 6,99 A",
        "486763 Hähn. Minist. XXL 6,99 A",
        "211172 Blätterteig,275g 0,95 A",
        "745940 Knoblauch fri Stk 1,29 A",
        "211172 Blätterteig,275g 0,95 A",
        "662394 Speisezwiebeln rot 1,29 A",
        "560115 Landmilch 3,8% 1,19 A",
        "80000843 Pfand 0,25 A",
        "202703 Traubendirektsa 1l 1,49 B",
        "205159 High Protein Pudd. 0,59 A",
        "205159 High Protein Pudd. 0,59 A",
        "205159 High Protein Pudd. 0,59 A",
        "205159 High Protein Pudd. 0,59 A",
        "229457 Nektarinen 1kg 1,99 A",
        "228578 Mandarinen pre los 5,32 A",
        "2,672 kg x 1,99 EUR/kg",
        "212268 Obstknotenbeutel 0,02 B",
        "K-U-N-D-E-N-B-E-L-E-G", "ALDI SÜD 021-064", "Kartenzahlung girocard",
        "Betrag 31,08 EUR",
        "28.09.2026 17:10 T-ID 65144812",
        "Summe 31,08", "15 Artikel", "girocard EUR 31,08",
        "A 07,0% Netto 27,64 MwSt 1,93", "B 19,0% Netto 1,27 MwSt 0,24"
    ]

    func testAldiItemsAndSubcategories() {
        let parsed = ReceiptParser.parse(lines: Self.aldiLines)
        XCTAssertEqual(parsed.total, Decimal(string: "31.08"))
        let expected: [(String, String, String)] = [
            ("Hähn. Minist. XXL", "6.99", "groceries.meat"),
            ("Hähn. Minist. XXL", "6.99", "groceries.meat"),
            ("Blätterteig,275g", "0.95", "groceries.bakery"),
            ("Knoblauch fri Stk", "1.29", "groceries.vegetables"),
            ("Blätterteig,275g", "0.95", "groceries.bakery"),
            ("Speisezwiebeln rot", "1.29", "groceries.vegetables"),
            ("Landmilch 3,8%", "1.19", "groceries.dairy"),
            ("Pfand", "0.25", "groceries.beverages"),
            ("Traubendirektsa 1l", "1.49", "groceries.beverages"),
            ("High Protein Pudd", "0.59", "groceries.dairy"),
            ("High Protein Pudd", "0.59", "groceries.dairy"),
            ("High Protein Pudd", "0.59", "groceries.dairy"),
            ("High Protein Pudd", "0.59", "groceries.dairy"),
            ("Nektarinen 1kg", "1.99", "groceries.fruits"),
            ("Mandarinen pre los", "5.32", "groceries.fruits"),
            ("Obstknotenbeutel", "0.02", "groceries.household")
        ]
        XCTAssertEqual(parsed.items.count, expected.count, parsed.items.map(\.name).joined(separator: " | "))
        for (item, want) in zip(parsed.items, expected) {
            XCTAssertEqual(item.name, want.0)
            XCTAssertEqual(item.amount, Decimal(string: want.1), item.name)
            XCTAssertEqual(item.suggestedSubcategoryKey, want.2, item.name)
        }
        XCTAssertEqual(parsed.itemsSum, Decimal(string: "31.08"))
    }

    /// The photo is tilted: each price sits about one line lower than its
    /// name. With the slope removed every price stays with its own item.
    func testTiltedPhotoKeepsPricesOnTheirLines() {
        let slope = 0.04          // falls 0.04 per full width
        let lineGap = 0.013
        let names = ["486763 Hähn. Minist. XXL", "211172 Blätterteig,275g", "745940 Knoblauch fri Stk", "560115 Landmilch 3,8%"]
        let prices = ["6,99 A", "0,95 A", "1,29 A", "1,19 A"]
        var fragments: [OCRFragment] = []
        for (i, name) in names.enumerated() {
            let y = 0.2 + Double(i) * lineGap
            // Name from x 0.1 to 0.5: its centre is at x 0.3.
            fragments.append(OCRFragment(text: name, x: 0.1, y: y + slope * (0.3 - 0.5) - 0.004, width: 0.4, height: 0.008, slope: slope))
            // Price at x 0.9: lower by slope * 0.6 = 0.024 ≈ two line gaps below its name's centre.
            fragments.append(OCRFragment(text: prices[i], x: 0.85, y: y + slope * (0.9 - 0.5) - 0.004, width: 0.1, height: 0.008, slope: 0))
        }
        let lines = ReceiptLineAssembler.lines(from: fragments)
        XCTAssertEqual(lines, zip(names, prices).map { "\($0) \($1)" })
    }

    func testLevelReceiptUnchanged() {
        let fragments = [
            OCRFragment(text: "Milch", x: 0.1, y: 0.1, width: 0.3, height: 0.01),
            OCRFragment(text: "1,19", x: 0.8, y: 0.101, width: 0.1, height: 0.01),
            OCRFragment(text: "Brot", x: 0.1, y: 0.12, width: 0.3, height: 0.01),
            OCRFragment(text: "2,49", x: 0.8, y: 0.12, width: 0.1, height: 0.01)
        ]
        XCTAssertEqual(ReceiptLineAssembler.lines(from: fragments), ["Milch 1,19", "Brot 2,49"])
    }

    func testItemRuleKeys() {
        XCTAssertEqual(ItemRuleKey.make("Blätterteig,275g"), "blatterteig")
        XCTAssertEqual(ItemRuleKey.make("Landmilch 3,8%"), "landmilch")
        XCTAssertEqual(ItemRuleKey.make("486763 Hähn. Minist. XXL"), "hahn minist xxl")
        XCTAssertEqual(ItemRuleKey.make("Traubendirektsa 1l"), "traubendirektsa")
        XCTAssertEqual(ItemRuleKey.make("Nektarinen 1kg"), ItemRuleKey.make("NEKTARINEN 500g"))
    }

    func testNewKeywords() {
        XCTAssertEqual(GroceryItemClassifier.classify("Teebeutel Pfefferminz")?.subcategoryKey, "groceries.coffee")
        XCTAssertEqual(GroceryItemClassifier.classify("Tomaten")?.subcategoryKey, "groceries.vegetables")
        XCTAssertEqual(GroceryItemClassifier.classify("Nektarinen")?.subcategoryKey, "groceries.fruits")
    }
}
