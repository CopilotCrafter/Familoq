import Foundation
import CryptoKit
import FamiloqCore

/// Everything the app needs from the invitation store. Implemented with the
/// CloudKit public database (`CloudKitAccessBackend`) and stubbed in tests.
protocol AccessBackend {
    // Identity
    /// Throws `AccessError.noICloudAccount` when the user is not signed in to iCloud.
    func currentUserRecordName() async throws -> String
    /// True when the current iCloud user has the FamiloqAdmin role.
    func isAdministrator() async -> Bool

    // Redeeming
    func invitationStatus(codeHash: String, now: Date) async throws -> AppInvitationStatus
    /// Creates the one-and-only redemption for a code.
    func redeem(codeHash: String, userRecordName: String) async throws -> RedemptionOutcome
    /// Reinstall / new iPhone: has this iCloud user redeemed an invitation before?
    func hasRedemption(userRecordName: String) async throws -> Bool
    func isRevoked(userRecordName: String) async throws -> Bool

    // Requests
    func submitRequest(name: String, contact: String, message: String) async throws

    // Administration (FamiloqAdmin role only)
    func createInvitations(count: Int, validityDays: Int, note: String) async throws -> [String]
    func adminOverview() async throws -> AdminOverview
    func revokeInvitation(codeHash: String) async throws
    func setUserRevoked(_ revoked: Bool, userRecordName: String) async throws
    func markRequestHandled(id: String) async throws
}

enum RedemptionOutcome: Equatable {
    /// First (and only) use of the code.
    case redeemed
    /// Same iCloud user redeemed it before (reinstall).
    case alreadyMine
    /// Someone else used it.
    case usedBySomeoneElse
}

enum AccessError: LocalizedError, Equatable {
    case noICloudAccount
    case invalidCode
    case invitationNotFound
    case expired
    case revoked
    case used
    case accountRevoked
    case notActivated
    case notAdministrator
    case offline
    case other(String)

    var errorDescription: String? {
        switch self {
        case .noICloudAccount: return "Please sign in to iCloud (Settings → your name) and try again. Familoq uses iCloud to keep your family's data private and in sync."
        case .invalidCode: return "This invitation code has a typo. Please check it."
        case .invitationNotFound: return "This invitation code does not exist."
        case .expired: return "This invitation has expired. Please ask for a new one."
        case .revoked: return "This invitation is no longer valid."
        case .used: return "This invitation has already been used."
        case .accountRevoked: return "Access to Familoq has been turned off for this iCloud account."
        case .notActivated: return "This iCloud account has not been activated yet. Please enter your invitation code."
        case .notAdministrator: return "Only the Familoq administrator can do this."
        case .offline: return "No connection to iCloud. Check your internet connection and try again."
        case .other(let text): return text
        }
    }
}

struct AdminInvitation: Identifiable, Equatable {
    var id: String { codeHash }
    let codeHash: String
    let hint: String
    let note: String
    let createdAt: Date
    let expiresAt: Date
    let status: AppInvitationStatus
    let redeemedBy: String?
    let redeemedAt: Date?
}

struct AdminAccount: Identifiable, Equatable {
    var id: String { userRecordName }
    let userRecordName: String
    let activatedAt: Date?
    let invitationHint: String?
    let invitationNote: String?
    let isRevoked: Bool
}

struct AdminRequest: Identifiable, Equatable {
    let id: String
    let name: String
    let contact: String
    let message: String
    let createdAt: Date
    let handled: Bool
}

struct AdminOverview: Equatable {
    var invitations: [AdminInvitation]
    var accounts: [AdminAccount]
    var requests: [AdminRequest]
}

enum InvitationHashing {
    /// Record name for a code: SHA-256 of the normalised code (the code itself is never stored).
    static func codeHash(_ code: String) -> String {
        SHA256.hash(data: Data(InvitationCode.normalize(code).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// Used where iCloud cannot work: unit tests (the host app has no iCloud
/// entitlement) and CI screenshots. Behaves like "not signed in to iCloud".
struct UnavailableAccessBackend: AccessBackend {
    func currentUserRecordName() async throws -> String { throw AccessError.noICloudAccount }
    func isAdministrator() async -> Bool { false }
    func invitationStatus(codeHash: String, now: Date) async throws -> AppInvitationStatus { throw AccessError.noICloudAccount }
    func redeem(codeHash: String, userRecordName: String) async throws -> RedemptionOutcome { throw AccessError.noICloudAccount }
    func hasRedemption(userRecordName: String) async throws -> Bool { throw AccessError.noICloudAccount }
    func isRevoked(userRecordName: String) async throws -> Bool { throw AccessError.noICloudAccount }
    func submitRequest(name: String, contact: String, message: String) async throws { throw AccessError.noICloudAccount }
    func createInvitations(count: Int, validityDays: Int, note: String) async throws -> [String] { throw AccessError.notAdministrator }
    func adminOverview() async throws -> AdminOverview { throw AccessError.notAdministrator }
    func revokeInvitation(codeHash: String) async throws { throw AccessError.notAdministrator }
    func setUserRevoked(_ revoked: Bool, userRecordName: String) async throws { throw AccessError.notAdministrator }
    func markRequestHandled(id: String) async throws { throw AccessError.notAdministrator }
}
