import Foundation

/// Level 2: invitation into ONE family, created by that family's owner.
/// The code uses the same format as App Invitations (`InvitationCode`), but it
/// is a different thing: it grants membership of a family, not use of the app.
public struct FamilyInvitationTerms: Equatable, Sendable {
    public var expiresAt: Date
    public var maxUses: Int
    public var uses: Int
    public var isRevoked: Bool

    public init(expiresAt: Date, maxUses: Int = 1, uses: Int = 0, isRevoked: Bool = false) {
        self.expiresAt = expiresAt
        self.maxUses = maxUses
        self.uses = uses
        self.isRevoked = isRevoked
    }
}

public enum FamilyInvitationStatus: String, Equatable, Sendable {
    case valid
    case expired
    case usedUp
    case revoked
    case familyFull

    public var message: String {
        switch self {
        case .valid: return "Valid"
        case .expired: return "This family invitation has expired."
        case .usedUp: return "This family invitation has already been used."
        case .revoked: return "This family invitation was withdrawn by the owner."
        case .familyFull: return "This family already has the maximum number of members."
        }
    }
}

public enum FamilyInvitationRules {
    /// Default validity of a new family invitation.
    public static let defaultValidityDays = 7

    public static func status(of terms: FamilyInvitationTerms, now: Date, activeMembers: Int, maxMembers: Int) -> FamilyInvitationStatus {
        if terms.isRevoked { return .revoked }
        if terms.expiresAt <= now { return .expired }
        if terms.uses >= terms.maxUses { return .usedUp }
        if !FamilyLimits.canAddMember(activeMemberCount: activeMembers, maxMembers: maxMembers) { return .familyFull }
        return .valid
    }
}
