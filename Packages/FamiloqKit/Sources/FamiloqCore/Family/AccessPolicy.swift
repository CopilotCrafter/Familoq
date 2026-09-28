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

/// Extra rights the owner can give a single member. The owner always has all.
/// Stored on the member as a comma-separated list (`FamilyGrant.encode`).
public enum FamilyGrant: String, CaseIterable, Codable, Sendable, Hashable {
    /// Create and change budgets.
    case budgets
    /// Categories, subcategories and merchant rules.
    case categories
    /// Family name and base currency.
    case familySettings
    /// Edit and delete expenses added by anyone (not just their own).
    case allExpenses

    public var title: String {
        switch self {
        case .budgets: return "Budgets"
        case .categories: return "Categories & merchant rules"
        case .familySettings: return "Family name & base currency"
        case .allExpenses: return "Edit everyone's expenses"
        }
    }

    public static func parse(_ raw: String) -> Set<FamilyGrant> {
        Set(raw.split(separator: ",").compactMap { FamilyGrant(rawValue: $0.trimmingCharacters(in: .whitespaces)) })
    }

    /// Stable order, so the same set always gives the same text (sync fingerprints).
    public static func encode(_ grants: Set<FamilyGrant>) -> String {
        allCases.filter(grants.contains).map(\.rawValue).joined(separator: ",")
    }
}

/// Who is asking, and for which family.
public struct MembershipContext: Equatable, Sendable {
    public let familyID: UUID
    public let memberID: UUID
    public let role: MemberRole
    public let isActive: Bool
    public let grants: Set<FamilyGrant>

    public init(familyID: UUID, memberID: UUID, role: MemberRole, isActive: Bool = true, grants: Set<FamilyGrant> = []) {
        self.familyID = familyID
        self.memberID = memberID
        self.role = role
        self.isActive = isActive
        self.grants = grants
    }

    /// Owner: everything. Member: only what the owner granted.
    public func has(_ grant: FamilyGrant) -> Bool {
        guard isActive else { return false }
        return role == .owner || grants.contains(grant)
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
        if context.has(.allExpenses) { return true }
        return createdByMemberID == context.memberID
    }

    public static func canManageFamily(familyID: UUID, context: MembershipContext?) -> Bool {
        guard let context = context, canRead(recordFamilyID: familyID, context: context) else { return false }
        return context.has(.familySettings)
    }

    /// Filters any collection down to rows the caller may see.
    public static func visible<T>(_ records: [T], familyID: KeyPath<T, UUID>, context: MembershipContext?) -> [T] {
        records.filter { canRead(recordFamilyID: $0[keyPath: familyID], context: context) }
    }
}
