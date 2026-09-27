import Foundation
import SwiftData
import FamiloqCore

/// Role inside a family (owner / member). Shared by every Familoq module.
typealias FamilyRole = MemberRole

// MARK: - Storage conventions (important for Phases 3-5)
//
// * Every family-owned record carries `familyID`. All reads go through
//   `FamilyRepository` / family-filtered @Query, never an unfiltered fetch.
// * Records reference each other by UUID (no SwiftData relationships).
//   This keeps CloudKit sync (Phase 4, CKSyncEngine), export/import (Phase 5)
//   and family isolation simple and explicit.
// * Every stored property has a default value and there are no unique
//   constraints -> the schema stays CloudKit-compatible.
// * Money = Int64 fixed-point with 4 decimals (see FixedPoint in the core).

@Model
final class Family {
    var id: UUID = UUID()
    var name: String = ""
    /// ISO 4217 code. Defaults to EUR, changeable by the owner.
    var baseCurrencyCode: String = "EUR"
    /// Initial limit 6; stored per family so it can be raised later.
    var maxMembers: Int = 6
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), name: String, baseCurrencyCode: String = "EUR", maxMembers: Int = 6) {
        self.id = id
        self.name = name
        self.baseCurrencyCode = baseCurrencyCode
        self.maxMembers = maxMembers
    }
}

@Model
final class FamilyMember {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var displayName: String = ""
    var roleRaw: String = "member"
    var isActive: Bool = true
    /// The person using this device. Phase 3 replaces this with the
    /// activated iCloud user of this device.
    var isCurrentUser: Bool = false
    var joinedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, displayName: String, role: FamilyRole, isCurrentUser: Bool = false) {
        self.id = id
        self.familyID = familyID
        self.displayName = displayName
        self.roleRaw = role.rawValue
        self.isCurrentUser = isCurrentUser
    }

    var role: FamilyRole {
        get { FamilyRole(rawValue: roleRaw) ?? .member }
        set { roleRaw = newValue.rawValue }
    }
}
