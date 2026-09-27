import XCTest
@testable import FamiloqCore

final class FamilyAndInvitationTests: XCTestCase {
    private let familyA = UUID()
    private let familyB = UUID()

    private struct Row {
        let familyID: UUID
        let name: String
    }

    // MARK: Family isolation

    func testMemberCannotReadOtherFamily() {
        let martin = MembershipContext(familyID: familyA, memberID: UUID(), role: .owner)
        XCTAssertTrue(AccessPolicy.canRead(recordFamilyID: familyA, context: martin))
        XCTAssertFalse(AccessPolicy.canRead(recordFamilyID: familyB, context: martin))
    }

    func testNoMembershipSeesNothing() {
        XCTAssertFalse(AccessPolicy.canRead(recordFamilyID: familyA, context: nil))
    }

    func testRemovedMemberSeesNothing() {
        let removed = MembershipContext(familyID: familyA, memberID: UUID(), role: .member, isActive: false)
        XCTAssertFalse(AccessPolicy.canRead(recordFamilyID: familyA, context: removed))
    }

    func testVisibleFiltersOtherFamilies() {
        let rows = [Row(familyID: familyA, name: "Lidl"), Row(familyID: familyB, name: "REWE"), Row(familyID: familyA, name: "Aral")]
        let carol = MembershipContext(familyID: familyA, memberID: UUID(), role: .member)
        let visible = AccessPolicy.visible(rows, familyID: \.familyID, context: carol)
        XCTAssertEqual(visible.map(\.name), ["Lidl", "Aral"])
    }

    func testEditRules() {
        let ownerID = UUID(), memberID = UUID()
        let owner = MembershipContext(familyID: familyA, memberID: ownerID, role: .owner)
        let member = MembershipContext(familyID: familyA, memberID: memberID, role: .member)
        XCTAssertTrue(AccessPolicy.canEditExpense(recordFamilyID: familyA, createdByMemberID: memberID, context: owner))
        XCTAssertTrue(AccessPolicy.canEditExpense(recordFamilyID: familyA, createdByMemberID: memberID, context: member))
        XCTAssertFalse(AccessPolicy.canEditExpense(recordFamilyID: familyA, createdByMemberID: ownerID, context: member))
        XCTAssertFalse(AccessPolicy.canEditExpense(recordFamilyID: familyB, createdByMemberID: ownerID, context: owner))
        XCTAssertTrue(AccessPolicy.canManageFamily(familyID: familyA, context: owner))
        XCTAssertFalse(AccessPolicy.canManageFamily(familyID: familyA, context: member))
    }

    func testMemberLimit() {
        XCTAssertEqual(FamilyLimits.defaultMaxMembers, 6)
        XCTAssertTrue(FamilyLimits.canAddMember(activeMemberCount: 5, maxMembers: 6))
        XCTAssertFalse(FamilyLimits.canAddMember(activeMemberCount: 6, maxMembers: 6))
    }

    // MARK: Invitation code format

    func testGeneratedCodesAreWellFormed() {
        for _ in 0..<500 {
            let code = InvitationCode.generate()
            XCTAssertEqual(code.count, 14, code) // 12 chars + 2 dashes
            XCTAssertTrue(InvitationCode.isWellFormed(code), code)
        }
    }

    func testNormalizationAcceptsLowercaseAndSpaces() {
        let code = InvitationCode.generate()
        let messy = " " + code.lowercased().replacingOccurrences(of: "-", with: " ") + " "
        XCTAssertTrue(InvitationCode.isWellFormed(messy))
        XCTAssertEqual(InvitationCode.format(messy), code)
    }

    func testSingleTypoIsDetected() {
        let code = Array(InvitationCode.normalize(InvitationCode.generate()))
        for position in 0..<code.count {
            for replacement in InvitationCode.alphabet where replacement != code[position] {
                var typo = code
                typo[position] = replacement
                XCTAssertFalse(InvitationCode.isWellFormed(String(typo)), "typo at \(position) not detected")
            }
        }
    }

    func testRejectsLookAlikesAndWrongLength() {
        XCTAssertFalse(InvitationCode.isWellFormed("O0I1-AAAA-AAAA"))
        XCTAssertFalse(InvitationCode.isWellFormed("ABCD-EFGH"))
        XCTAssertFalse(InvitationCode.isWellFormed(""))
    }
}
