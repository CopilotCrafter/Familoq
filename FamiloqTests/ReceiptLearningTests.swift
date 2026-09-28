import XCTest
import SwiftData
import UIKit
import FamiloqCore
import FamiloqBudget
@testable import Familoq

@MainActor
final class ReceiptLearningTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var family: Family!
    private var lookup: CategoryLookup!

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        context = container.mainContext
        family = try FamilyBootstrapper.createFamily(named: "Test", ownerName: "Martin", in: context)
        let repo = FamilyRepository(context: context, familyID: family.id)
        lookup = CategoryLookup(categories: try repo.categories(), subcategories: try repo.subcategories())
    }

    override func tearDown() async throws {
        lookup = nil; family = nil; context = nil; container = nil
    }

    private func sub(_ key: String) -> ExpenseSubcategory { lookup.subcategories.first { $0.systemKey == key }! }

    private func draft(_ lines: [String]) throws -> ReceiptDraft {
        let fid = family.id
        let rules = try context.fetch(FetchDescriptor<ItemCategoryRule>(predicate: #Predicate { $0.familyID == fid }))
        return ReceiptDrafting.draft(from: ReceiptParser.parse(lines: lines), family: family, lookup: lookup,
                                     rules: [], imageData: nil, itemRules: rules)
    }

    func testCorrectionIsRememberedForNextReceipt() throws {
        let lines = ["ALDI SÜD", "Zaziki Becher 1,49 A", "Brot 2,00 A", "SUMME 3,49"]
        var first = try draft(lines)
        first.categorizeWholeReceipt = false
        let dairy = sub("groceries.dairy")
        let index = try XCTUnwrap(first.items.firstIndex { $0.name.hasPrefix("Zaziki") })
        XCTAssertEqual(first.items[index].source, .unknown)
        first.items[index].categoryID = dairy.categoryID
        first.items[index].subcategoryID = dairy.id
        try ReceiptSaver.save(first, family: family, member: nil, lookup: lookup, context: context)

        let rules = try context.fetch(FetchDescriptor<ItemCategoryRule>())
        XCTAssertEqual(rules.map(\.key), ["zaziki becher"], "only the corrected item is learned")

        let second = try draft(["LIDL", "ZAZIKI BECHER 1,59", "SUMME 1,59"])
        XCTAssertEqual(second.items.first?.subcategoryID, dairy.id)
        XCTAssertEqual(second.items.first?.source, .learned)
    }

    func testEditingSavedReceiptReplacesItsExpenses() throws {
        var first = try draft(["REWE", "Milch 1,19", "Bananen 2,00", "SUMME 3,19"])
        first.categorizeWholeReceipt = false
        let saved = try ReceiptSaver.save(first, family: family, member: nil, lookup: lookup, context: context)
        XCTAssertEqual(saved.count, 2)
        let receipt = try XCTUnwrap(context.fetch(FetchDescriptor<ReceiptRecord>()).first)
        let items = try context.fetch(FetchDescriptor<ReceiptItemRecord>())

        var edit = ReceiptDrafting.draft(editing: receipt, items: items, lookup: lookup)
        XCTAssertFalse(edit.categorizeWholeReceipt)
        XCTAssertEqual(edit.items.count, 2)
        // Bananas were really 1,50 and the total 2,69.
        let bananas = try XCTUnwrap(edit.items.firstIndex { $0.name == "Bananen" })
        edit.items[bananas].amountText = "1.50"
        edit.totalText = "2.69"
        try ReceiptSaver.save(edit, family: family, member: nil, lookup: lookup, context: context, replacing: receipt)

        XCTAssertEqual(try context.fetch(FetchDescriptor<ReceiptRecord>()).count, 1)
        XCTAssertEqual(receipt.total, Decimal(string: "2.69"))
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(expenses.count, 2)
        XCTAssertEqual(expenses.reduce(Decimal(0)) { $0 + $1.amount }, Decimal(string: "2.69"))
        XCTAssertEqual(Set(expenses.map(\.id)), Set(saved.map(\.id)), "existing expenses are updated, not recreated")
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReceiptItemRecord>()).count, 2)
    }

    func testAppleIntelligenceAnswerParsing() {
        let choices = ["Groceries > Milk & Dairy", "Groceries > Bread & Bakery", "Household > Cleaning"]
        let answer = """
        1: Groceries > Bread & Bakery
        2. milk & dairy
        3: Something else
        9: Groceries > Milk & Dairy
        """
        let parsed = AppleIntelligence.parseClassification(answer, itemCount: 3, choices: choices)
        XCTAssertEqual(parsed, [0: "Groceries > Bread & Bakery", 1: "Groceries > Milk & Dairy"])
    }

    /// A receipt photographed at an angle: prices must stay on their lines.
    func testTiltedPhotoThroughVision() async throws {
        let size = CGSize(width: 1000, height: 900)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rows = [("Hähnchen Ministeaks", "6,99"), ("Blätterteig 275g", "0,95"), ("Knoblauch", "1,29"),
                    ("Speisezwiebeln rot", "0,95"), ("Landmilch 3,8%", "1,19"), ("Nektarinen 1kg", "1,99")]
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            cg.translateBy(x: 500, y: 450)
            cg.rotate(by: 3.5 * .pi / 180)
            cg.translateBy(x: -500, y: -450)
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 34, weight: .medium),
                                                             .foregroundColor: UIColor.black]
            for (i, row) in rows.enumerated() {
                let y = 150 + CGFloat(i) * 55
                (row.0 as NSString).draw(at: CGPoint(x: 60, y: y), withAttributes: attributes)
                (row.1 as NSString).draw(at: CGPoint(x: 800, y: y), withAttributes: attributes)
            }
        }
        let fragments = try await ReceiptOCRService.recognize(pages: [image])
        let lines = ReceiptLineAssembler.lines(from: fragments)
        print("Tilted OCR lines:", lines)
        let items = ReceiptParser.parse(lines: lines + ["SUMME 13,36"]).items
        let pairs = Dictionary(items.map { (String($0.name.prefix(6)), $0.amount) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(pairs["Hähnch"], Decimal(string: "6.99"))
        XCTAssertEqual(pairs["Knobla"], Decimal(string: "1.29"))
        XCTAssertEqual(pairs["Landmi"], Decimal(string: "1.19"))
        XCTAssertEqual(pairs["Nektar"], Decimal(string: "1.99"))
    }
}
