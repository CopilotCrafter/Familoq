import Foundation
import SwiftData
import FamiloqCore
import FamiloqBudget

enum AppTab: String, Hashable {
    case dashboard, add, scan, reports, family
}

/// Who is using the app and which family is active.
@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var family: Family?
    @Published private(set) var currentMember: FamilyMember?
    @Published var startupError: String?
    @Published var selectedTab: AppTab = .dashboard
    /// True once local data was checked (family may still be nil -> setup).
    @Published private(set) var isLoaded = false

    var familyID: UUID? { family?.id }

    /// Authorisation context used by `AccessPolicy`.
    var membership: MembershipContext? {
        guard let family, let member = currentMember else { return nil }
        return MembershipContext(familyID: family.id, memberID: member.id, role: member.role, isActive: member.isActive)
    }

    var isOwner: Bool { membership?.role == .owner }

    var needsFamilySetup: Bool { isLoaded && family == nil }

    /// Loads the family stored on this device (none yet -> "Create your family").
    func start(context: ModelContext) {
        do {
            var family = try FamilyBootstrapper.existingFamily(in: context)
            if family == nil && LaunchOptions.seedDemoData {
                family = try FamilyBootstrapper.createFamily(named: "Demo Family", ownerName: "Martin", in: context)
            }
            if let family {
                try activate(family, context: context)
            }
            if let tab = LaunchOptions.initialTab {
                selectedTab = tab
            }
        } catch {
            startupError = "Could not open your data: \(error.localizedDescription)"
        }
        isLoaded = true
    }

    /// Creates the user's own family (they become its owner).
    func createFamily(name: String, ownerName: String, baseCurrency: String, context: ModelContext) throws {
        let family = try FamilyBootstrapper.createFamily(named: name, ownerName: ownerName, baseCurrency: baseCurrency, in: context)
        try activate(family, context: context)
    }

    private func activate(_ family: Family, context: ModelContext) throws {
        let repository = FamilyRepository(context: context, familyID: family.id)
        self.family = family
        self.currentMember = try repository.currentMember()
    }

    /// Owner-only actions (spec: invite/remove members, settings, categories, budgets).
    func can(_ permission: FamilyPermission) -> Bool {
        guard let role = membership?.role, membership?.isActive == true else { return false }
        switch permission {
        case .inviteMembers: return role.canInviteMembers
        case .removeMembers: return role.canRemoveMembers
        case .manageSettings: return role.canManageSettings
        case .manageCategories: return role.canManageCategories
        case .manageBudgets: return role.canManageBudgets
        case .addExpenses: return role.canAddExpenses
        }
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
