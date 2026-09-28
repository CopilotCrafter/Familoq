import Foundation
import SwiftData
import FamiloqCore
import FamiloqBudget

enum AppTab: String, Hashable {
    case dashboard, add, scan, planner, family
}

/// Who is using the app and which family is active.
@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var family: Family?
    @Published private(set) var currentMember: FamilyMember?
    /// Every family on this iPhone (own + joined), for the family switcher.
    @Published private(set) var families: [Family] = []
    @Published var startupError: String?
    @Published var selectedTab: AppTab = .dashboard
    /// Short message shown at the top for a few seconds.
    @Published var notice: String?
    /// True once local data was checked (family may still be nil -> setup).
    @Published private(set) var isLoaded = false

    var familyID: UUID? { family?.id }

    /// Authorisation context used by `AccessPolicy`.
    var membership: MembershipContext? {
        guard let family, let member = currentMember else { return nil }
        return MembershipContext(familyID: family.id, memberID: member.id, role: member.role, isActive: member.isActive, grants: member.grants)
    }

    var isOwner: Bool { membership?.role == .owner }

    var needsFamilySetup: Bool { isLoaded && family == nil }

    /// Joined a family but did not choose a display name there yet.
    var needsMemberName: Bool { family != nil && currentMember == nil }

    private static let activeFamilyKey = "activeFamilyID"

    /// Loads the family stored on this device (none yet -> "Create your family").
    func start(context: ModelContext) {
        do {
            var family = try preferredFamily(in: context)
            if family == nil && LaunchOptions.seedDemoData {
                family = try FamilyBootstrapper.createFamily(named: "Demo Family", ownerName: "Martin", in: context)
            }
            if let family {
                try activate(family, context: context)
            }
            families = try allFamilies(in: context)
            if let tab = LaunchOptions.initialTab {
                selectedTab = tab
            }
        } catch {
            startupError = "Could not open your data: \(error.localizedDescription)"
        }
        isLoaded = true
    }

    /// Creates the user's own family (they become its owner).
    func createFamily(name: String, ownerName: String, baseCurrency: String, cloudUserRecordName: String = "", context: ModelContext) throws {
        let family = try FamilyBootstrapper.createFamily(named: name, ownerName: ownerName, baseCurrency: baseCurrency, ownerCloudUserRecordName: cloudUserRecordName, in: context)
        try activate(family, context: context)
        families = try allFamilies(in: context)
    }

    /// Family switcher.
    func switchTo(familyID: UUID, context: ModelContext) {
        guard let target = families.first(where: { $0.id == familyID }) else { return }
        try? activate(target, context: context)
    }

    /// iCloud changed data: pick up new/removed families and members.
    func refresh(context: ModelContext) {
        families = (try? allFamilies(in: context)) ?? []
        if let family, families.contains(where: { $0.id == family.id }) {
            currentMember = try? FamilyRepository(context: context, familyID: family.id).currentMember()
        } else if let next = try? preferredFamily(in: context) {
            try? activate(next, context: context)
        } else {
            family = nil
            currentMember = nil
        }
    }

    /// Called before a family is deleted from this iPhone.
    func familyWillBeRemoved(_ familyID: UUID, context: ModelContext) {
        families.removeAll { $0.id == familyID }
        guard family?.id == familyID else { return }
        family = nil
        currentMember = nil
        if let next = families.first {
            try? activate(next, context: context)
        }
    }

    private func activate(_ family: Family, context: ModelContext) throws {
        let repository = FamilyRepository(context: context, familyID: family.id)
        self.family = family
        self.currentMember = try repository.currentMember()
        UserDefaults.standard.set(family.id.uuidString, forKey: Self.activeFamilyKey)
    }

    private func allFamilies(in context: ModelContext) throws -> [Family] {
        try context.fetch(FetchDescriptor<Family>(sortBy: [SortDescriptor(\Family.createdAt)]))
    }

    /// The family used last, otherwise the oldest one.
    private func preferredFamily(in context: ModelContext) throws -> Family? {
        let all = try allFamilies(in: context)
        if let text = UserDefaults.standard.string(forKey: Self.activeFamilyKey), let id = UUID(uuidString: text),
           let match = all.first(where: { $0.id == id }) {
            return match
        }
        return all.first
    }

    /// Inviting/removing people is owner-only (only the owner can change the
    /// iCloud share). Budgets, categories and settings: owner, or a member the
    /// owner gave that right to.
    func can(_ permission: FamilyPermission) -> Bool {
        guard let membership, membership.isActive else { return false }
        switch permission {
        case .inviteMembers: return membership.role.canInviteMembers
        case .removeMembers: return membership.role.canRemoveMembers
        case .manageSettings: return membership.has(.familySettings)
        case .manageCategories: return membership.has(.categories)
        case .manageBudgets: return membership.has(.budgets)
        case .addExpenses: return membership.role.canAddExpenses
        }
    }

    /// Re-reads the current member (e.g. after the owner changed my rights).
    func reloadCurrentMember(context: ModelContext) {
        guard let family else { return }
        currentMember = try? FamilyRepository(context: context, familyID: family.id).currentMember()
    }

    func canEdit(_ expense: Expense) -> Bool {
        AccessPolicy.canEditExpense(recordFamilyID: expense.familyID, createdByMemberID: expense.createdByMemberID, context: membership)
    }
}

enum FamilyPermission {
    case inviteMembers, removeMembers, manageSettings, manageCategories, manageBudgets, addExpenses
}

/// Launch arguments, used by CI to produce screenshots on a simulator:
///   -seedDemoData YES   -> inserts sample data into an empty store
///   -initialTab reports -> opens a specific tab
///   -demoAccount YES    -> (Debug builds only) skip the invitation gate
enum LaunchOptions {
    static var seedDemoData: Bool {
        UserDefaults.standard.bool(forKey: "seedDemoData")
    }

    static var initialTab: AppTab? {
        UserDefaults.standard.string(forKey: "initialTab").flatMap(AppTab.init(rawValue:))
    }
}
