import Foundation
import SwiftData

@MainActor
enum PersistenceController {
    /// Shared core models + the models of every enabled module.
    static var models: [any PersistentModel.Type] {
        var all: [any PersistentModel.Type] = [Family.self, FamilyMember.self]
        for module in FamiloqModules.enabled {
            all.append(contentsOf: module.models)
        }
        return all
    }

    /// Phase 1: local, offline-first SwiftData store on the device.
    /// CloudKit sync is added in Phase 4 (see docs/04-families-invitations-cloudkit.md),
    /// so it is explicitly disabled here.
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
