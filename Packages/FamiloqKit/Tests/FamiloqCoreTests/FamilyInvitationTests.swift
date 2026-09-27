import XCTest
@testable import FamiloqCore

final class FamilyInvitationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testValidInvitation() {
        let terms = FamilyInvitationTerms(expiresAt: now.addingTimeInterval(3600))
        XCTAssertEqual(FamilyInvitationRules.status(of: terms, now: now, activeMembers: 2, maxMembers: 6), .valid)
    }

    func testExpiredFamilyInvitation() {
        let terms = FamilyInvitationTerms(expiresAt: now.addingTimeInterval(-1))
        XCTAssertEqual(FamilyInvitationRules.status(of: terms, now: now, activeMembers: 2, maxMembers: 6), .expired)
    }

    func testUsedRevokedAndFull() {
        let future = now.addingTimeInterval(3600)
        XCTAssertEqual(FamilyInvitationRules.status(of: .init(expiresAt: future, maxUses: 1, uses: 1), now: now, activeMembers: 1, maxMembers: 6), .usedUp)
        XCTAssertEqual(FamilyInvitationRules.status(of: .init(expiresAt: future, isRevoked: true), now: now, activeMembers: 1, maxMembers: 6), .revoked)
        XCTAssertEqual(FamilyInvitationRules.status(of: .init(expiresAt: future), now: now, activeMembers: 6, maxMembers: 6), .familyFull)
    }
}

final class AppInvitationRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testStatuses() {
        XCTAssertEqual(AppInvitationRules.status(recordExists: false, statusField: nil, expiresAt: nil, now: now), .notFound)
        XCTAssertEqual(AppInvitationRules.status(recordExists: true, statusField: "active", expiresAt: now.addingTimeInterval(60), now: now), .active)
        XCTAssertEqual(AppInvitationRules.status(recordExists: true, statusField: "active", expiresAt: now.addingTimeInterval(-60), now: now), .expired)
        XCTAssertEqual(AppInvitationRules.status(recordExists: true, statusField: "revoked", expiresAt: now.addingTimeInterval(60), now: now), .revoked)
    }

    func testHintAndClamping() {
        XCTAssertEqual(AppInvitationRules.hint(for: "mbf7-k92x-4qp7"), "4QP7")
        XCTAssertEqual(AppInvitationRules.clampedValidityDays(0), 1)
        XCTAssertEqual(AppInvitationRules.clampedValidityDays(9999), 365)
        XCTAssertEqual(AppInvitationRules.clampedCount(100), AppInvitationRules.maxCodesPerBatch)
    }
}
