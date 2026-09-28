import Foundation
import SwiftData

/// Familoq is a family "everything space". Each space is a module that plugs
/// into the shared core (family, members, invitations, sync, currency).
/// Built: Budget, Shopping list, Reminders, Events (the last three live in
/// the Planner module). Travel and Health are planned.
enum FamiloqSpace: String, CaseIterable, Identifiable {
    case budget
    case shopping
    case reminders
    case events
    case travel
    case health

    var id: String { rawValue }

    var title: String {
        switch self {
        case .budget: return "Budget"
        case .travel: return "Travel"
        case .health: return "Health"
        case .shopping: return "Shopping list"
        case .reminders: return "Reminders"
        case .events: return "Events"
        }
    }

    var icon: String {
        switch self {
        case .budget: return "chart.pie.fill"
        case .travel: return "airplane.circle.fill"
        case .health: return "heart.circle.fill"
        case .shopping: return "cart.circle.fill"
        case .reminders: return "bell.circle.fill"
        case .events: return "calendar.circle.fill"
        }
    }

    var isAvailable: Bool { self != .travel && self != .health }
}

/// Contract every module implements. Adding a space later means:
///   1. create Familoq/Modules/<Space>/ with its models, views and services
///   2. add an enum conforming to FamiloqModule
///   3. make its family records `SyncableRecord`s and list them in `syncHandlers`
///   4. register it in `FamiloqModules.enabled`
/// Every module's records carry `familyID` and are read through
/// `FamilyRepository`, so family isolation works the same everywhere.
@MainActor
protocol FamiloqModule {
    static var space: FamiloqSpace { get }
    /// SwiftData models owned by the module.
    static var models: [any PersistentModel.Type] { get }
    /// Default data for a newly created family.
    static func seedDefaults(familyID: UUID, in context: ModelContext)
    /// Records shared with the family through iCloud (parents first).
    static var syncHandlers: [SyncHandler] { get }
}

@MainActor
enum FamiloqModules {
    static let enabled: [any FamiloqModule.Type] = [
        BudgetModule.self,
        PlannerModule.self
    ]
}
