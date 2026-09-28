import XCTest
@testable import FamiloqBudget

final class SpendingBreakdownTests: XCTestCase {
    let groceries = UUID(), meat = UUID(), veg = UUID(), transport = UUID(), fuel = UUID()
    let martin = UUID(), carol = UUID()

    func entry(_ amount: Decimal, _ cat: UUID?, _ sub: UUID?, _ member: UUID? = nil, _ merchant: String = "") -> SpendingEntry {
        SpendingEntry(amount: amount, categoryID: cat, subcategoryID: sub, memberID: member, merchant: merchant)
    }

    func testSubcategoryRowsCompareWithPreviousPeriod() {
        let current = [entry(60, groceries, meat), entry(20, groceries, meat), entry(30, groceries, veg), entry(50, transport, fuel), entry(5, groceries, nil)]
        let previous = [entry(40, groceries, meat), entry(40, groceries, veg), entry(70, transport, nil)]
        let rows = SpendingBreakdown.rows(current: current, previous: previous, level: .subcategory)
        XCTAssertEqual(rows.first?.key, BreakdownKey(categoryID: groceries, subcategoryID: meat))
        XCTAssertEqual(rows.first?.current, 80)
        XCTAssertEqual(rows.first?.count, 2)
        XCTAssertEqual(rows.first?.changePercent ?? 0, 100, accuracy: 0.01)
        let fuelRow = rows.first { $0.key.subcategoryID == fuel }
        XCTAssertNil(fuelRow?.changePercent, "new spending has no percentage")
        XCTAssertEqual(rows.last?.key, BreakdownKey(categoryID: transport, subcategoryID: nil), "only previous spending comes last")
        XCTAssertEqual(rows.last?.current, 0)
        XCTAssertEqual(rows.count, 5)
    }

    func testBiggestChanges() {
        let current = [entry(80, groceries, meat), entry(30, groceries, veg), entry(50, transport, fuel)]
        let previous = [entry(40, groceries, meat), entry(40, groceries, veg), entry(120, transport, fuel)]
        let rows = SpendingBreakdown.rows(current: current, previous: previous, level: .subcategory)
        let changes = SpendingBreakdown.biggestChanges(rows, minimumChange: 10)
        XCTAssertEqual(changes.up.map(\.key.subcategoryID), [meat])
        XCTAssertEqual(changes.down.map(\.key.subcategoryID), [fuel, veg])
    }

    func testMembersAndMerchants() {
        let current = [entry(10, groceries, meat, martin, "REWE"), entry(25, groceries, veg, carol, "Rewe"), entry(40, transport, fuel, carol, "Aral"), entry(5, nil, nil, nil, " ")]
        let members = SpendingBreakdown.rows(current: current, previous: [], level: .member)
        XCTAssertEqual(members.map(\.key.memberID), [carol, martin, nil])
        XCTAssertEqual(members.first?.current, 65)
        let shops = SpendingBreakdown.topMerchants(current)
        XCTAssertEqual(shops.map(\.name), ["Aral", "REWE"])
        XCTAssertEqual(shops.last?.amount, 35)
        XCTAssertEqual(shops.last?.count, 2)
    }
}
