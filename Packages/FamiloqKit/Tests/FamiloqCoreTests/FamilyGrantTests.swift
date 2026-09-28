import XCTest
@testable import FamiloqCore

final class FamilyGrantTests: XCTestCase {
    private let fid = UUID()

    func testEncodeIsStableAndRoundTrips() {
        let set: Set<FamilyGrant> = [.allExpenses, .budgets]
        XCTAssertEqual(FamilyGrant.encode(set), "budgets,allExpenses")
        XCTAssertEqual(FamilyGrant.parse(FamilyGrant.encode(set)), set)
        XCTAssertEqual(FamilyGrant.parse(""), [])
        XCTAssertEqual(FamilyGrant.parse("budgets, unknown ,categories"), [.budgets, .categories])
    }

    func testOwnerHasEverythingMemberOnlyGranted() {
        let owner = MembershipContext(familyID: fid, memberID: UUID(), role: .owner)
        XCTAssertTrue(FamilyGrant.allCases.allSatisfy(owner.has))
        let member = MembershipContext(familyID: fid, memberID: UUID(), role: .member, grants: [.budgets])
        XCTAssertTrue(member.has(.budgets))
        XCTAssertFalse(member.has(.categories))
        let inactive = MembershipContext(familyID: fid, memberID: UUID(), role: .member, isActive: false, grants: [.budgets])
        XCTAssertFalse(inactive.has(.budgets))
    }

    func testEditingOthersExpensesNeedsGrant() {
        let me = UUID(), other = UUID()
        let plain = MembershipContext(familyID: fid, memberID: me, role: .member)
        XCTAssertTrue(AccessPolicy.canEditExpense(recordFamilyID: fid, createdByMemberID: me, context: plain))
        XCTAssertFalse(AccessPolicy.canEditExpense(recordFamilyID: fid, createdByMemberID: other, context: plain))
        let trusted = MembershipContext(familyID: fid, memberID: me, role: .member, grants: [.allExpenses])
        XCTAssertTrue(AccessPolicy.canEditExpense(recordFamilyID: fid, createdByMemberID: other, context: trusted))
        XCTAssertFalse(AccessPolicy.canEditExpense(recordFamilyID: UUID(), createdByMemberID: me, context: trusted))
    }
}
