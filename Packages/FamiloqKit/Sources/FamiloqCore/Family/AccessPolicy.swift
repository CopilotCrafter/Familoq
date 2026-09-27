import Foundation

public enum MemberRole: String, Codable, CaseIterable, Sendable {
    case owner
    case member

    public var displayName: String { self == .owner ? "Owner" : "Member" }

    public var canInviteMembers: Bool { self == .owner }
    public var canRemoveMembers: Bool { self == .owner }
    public var canManageSettings: Bool { self == .owner }
    public var canManageCategories: Bool { self == .owner }
    public var canManageBudgets: Bool { self == .owner }

    // Everyone in a family can do these:
    public var canAddExpenses: Bool { true }
    public var canViewFamilyData: Bool { true }
}

/// Who is asking, and for which family.
public struct MembershipContext: Equatable, Sendable {
    public let familyID: UUID
    public let memberID: UUID
    public let role: MemberRole
    public let isActive: Bool

    public init(familyID: UUID, memberID: UUID, role: MemberRole, isActive: Bool = true) {
        self.familyID = familyID
        self.memberID = memberID
        self.role = role
        self.isActive = isActive
    }
}

public enum FamilyLimits {
    /// Initial maximum; stored per family so it can be raised later.
    public static let defaultMaxMembers = 6

    public static func canAddMember(activeMemberCount: Int, maxMembers: Int) -> Bool {
        activeMemberCount < maxMembers
    }
}

/// Family-level authorisation used by the data-access layer.
///
/// In Phase 1 all data is local, so this is defence-in-depth. From Phase 4 the
/// hard boundary is enforced server-side by CloudKit sharing (a user can only
/// download zones that were shared with them); these checks stay as a second
/// layer so a bug in a view can never show another family's rows.
public enum AccessPolicy {
    public static func canRead(recordFamilyID: UUID, context: MembershipContext?) -> Bool {
        guard let context = context, context.isActive else { return false }
        return context.familyID == recordFamilyID
    }

    /// Owners may edit every expense of their family; members only their own.
    public static func canEditExpense(recordFamilyID: UUID, createdByMemberID: UUID?, context: MembershipContext?) -> Bool {
        guard let context = context, canRead(recordFamilyID: recordFamilyID, context: context) else { return false }
        if context.role == .owner { return true }
        return createdByMemberID == context.memberID
    }

    public static func canManageFamily(familyID: UUID, context: MembershipContext?) -> Bool {
        guard let context = context, canRead(recordFamilyID: familyID, context: context) else { return false }
        return context.role.canManageSettings
    }

    /// Filters any collection down to rows the caller may see.
    public static func visible<T>(_ records: [T], familyID: KeyPath<T, UUID>, context: MembershipContext?) -> [T] {
        records.filter { canRead(recordFamilyID: $0[keyPath: familyID], context: context) }
    }
}
