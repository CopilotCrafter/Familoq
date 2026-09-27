import Foundation
import SwiftData

@MainActor
enum PersistenceController {
    /// Shared core models + the models of every enabled module.
    static var models: [any PersistentModel.Type] {
        var all: [any PersistentModel.Type] = [
            Family.self, FamilyMember.self, FamilyInvitationRecord.self,
            SyncLedgerEntry.self, SyncZoneRecord.self
        ]
        for module in FamiloqModules.enabled {
            all.append(contentsOf: module.models)
        }
        return all
    }

    /// Local, offline-first SwiftData store on the device. SwiftData's own
    /// CloudKit mirroring stays OFF: family sharing needs per-family zones,
    /// which `SyncCoordinator` (CKSyncEngine) handles - see docs/10-sync-and-sharing.md.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
