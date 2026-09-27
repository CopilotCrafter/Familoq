import Foundation
import SwiftData
import FamiloqCore

/// Family invitation codes of version 0.2 (local only, no longer created).
/// Since 0.3 family invitations are iCloud shares (Core/Sync/FamilySharing).
/// The model stays in the schema so existing stores open unchanged.
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
