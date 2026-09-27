import Foundation

/// Level 1 of Familoq's access model: an App Invitation lets ONE iCloud
/// account use Familoq. Stored in the CloudKit public database; this file
/// holds the platform-independent rules (tested on Linux).
///
/// CloudKit records (see docs/09-invitations-cloudkit.md):
///   FQInvitation    name = SHA-256(code)   status, expiresAt       admin creates, users can only fetch by exact name
///   FQRedemption    name = "redeemed-" + SHA-256(code)   users create; a name can exist only once -> one use
///   FQRevocation    name = "revoked-" + user record ID   admin only; revoked users are locked out
public enum AppInvitationStatus: String, Equatable, Sendable {
    case active
    case revoked
    case expired
    case notFound
}

public enum AppInvitationRules {
    public static let defaultValidityDays = 14
    public static let maxCodesPerBatch = 20

    /// Evaluates an invitation record fetched from CloudKit.
    public static func status(recordExists: Bool, statusField: String?, expiresAt: Date?, now: Date) -> AppInvitationStatus {
        guard recordExists else { return .notFound }
        if statusField == "revoked" { return .revoked }
        if let expiresAt, expiresAt <= now { return .expired }
        return .active
    }

    /// Last four characters shown in the admin list ("…4QP7").
    public static func hint(for code: String) -> String {
        String(InvitationCode.normalize(code).suffix(4))
    }

    /// Clamp admin input.
    public static func clampedValidityDays(_ days: Int) -> Int { min(max(days, 1), 365) }
    public static func clampedCount(_ count: Int) -> Int { min(max(count, 1), maxCodesPerBatch) }
}
