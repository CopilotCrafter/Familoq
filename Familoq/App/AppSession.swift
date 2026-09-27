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

    var familyID: UUID? { family?.id }

    /// Authorisation context used by `AccessPolicy`.
    var membership: MembershipContext? {
        guard let family, let member = currentMember else { return nil }
        return MembershipContext(familyID: family.id, memberID: member.id, role: member.role, isActive: member.isActive)
    }

    var isOwner: Bool { membership?.role == .owner }

    func start(context: ModelContext) {
        do {
            let family = try FamilyBootstrapper.ensureFamily(in: context)
            let repository = FamilyRepository(context: context, familyID: family.id)
            self.family = family
            self.currentMember = try repository.currentMember()
            if let tab = LaunchOptions.initialTab {
                selectedTab = tab
            }
        } catch {
            startupError = "Could not open your data: \(error.localizedDescription)"
        }
    }

    func canEdit(_ expense: Expense) -> Bool {
        AccessPolicy.canEditExpense(recordFamilyID: expense.familyID, createdByMemberID: expense.createdByMemberID, context: membership)
    }
}

/// Launch arguments, used by CI to produce screenshots on a simulator:
///   -seedDemoData YES   -> inserts sample data into an empty store
///   -initialTab reports -> opens a specific tab
enum LaunchOptions {
    static var seedDemoData: Bool {
        UserDefaults.standard.bool(forKey: "seedDemoData")
    }

    static var initialTab: AppTab? {
        UserDefaults.standard.string(forKey: "initialTab").flatMap(AppTab.init(rawValue:))
    }
}
