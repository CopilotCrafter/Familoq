import Foundation
import SwiftData
import FamiloqCore

/// Level 2 invitation into one family, created by the owner.
/// Stored in the family's data (and, from Phase 4, in the family's iCloud zone).
@Model
final class FamilyInvitationRecord {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    /// Formatted code "XXXX-XXXX-XXXX" the owner shares.
    var code: String = ""
    var createdAt: Date = Date()
    var expiresAt: Date = Date()
    var maxUses: Int = 1
    var uses: Int = 0
    var isRevoked: Bool = false
    var createdByMemberID: UUID? = nil
    /// Optional name of the person it is meant for.
    var note: String = ""

    init(familyID: UUID, code: String, expiresAt: Date, createdByMemberID: UUID?, note: String = "") {
        self.familyID = familyID
        self.code = code
        self.expiresAt = expiresAt
        self.createdByMemberID = createdByMemberID
        self.note = note
    }

    var terms: FamilyInvitationTerms {
        FamilyInvitationTerms(expiresAt: expiresAt, maxUses: maxUses, uses: uses, isRevoked: isRevoked)
    }
}
