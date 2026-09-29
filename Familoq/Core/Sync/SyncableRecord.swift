import Foundation
import SwiftData
import FamiloqCore

/// A SwiftData model that is shared with the family through iCloud.
/// Each one becomes one `FQFamilyItem` record in the family's zone.
protocol SyncableRecord: PersistentModel {
    static var syncKind: SyncKind { get }
    var syncID: UUID { get }
    /// Every field except `id`/`familyID` (those come from the record name and zone).
    func syncPayload() -> SyncPayload
    func applySyncPayload(_ payload: SyncPayload)
    /// Receipt photos travel as a file (CKAsset) next to the record.
    var syncImage: Data? { get set }
}

extension SyncableRecord {
    var syncImage: Data? {
        get { nil }
        set { }
    }
}

/// How to find and create the records of one kind.
@MainActor
struct SyncHandler {
    let kind: SyncKind
    let hasImage: Bool
    /// All records of a family.
    let all: (ModelContext, UUID) throws -> [any SyncableRecord]
    /// For backups: also the records kept "only on this iPhone".
    let backupAll: (ModelContext, UUID) throws -> [any SyncableRecord]
    let find: (ModelContext, UUID) throws -> (any SyncableRecord)?
    /// Creates and inserts an empty record (id, familyID) before a payload is applied.
    let make: (ModelContext, UUID, UUID) -> any SyncableRecord

    static func of<T: SyncableRecord>(
        _ type: T.Type,
        hasImage: Bool = false,
        inFamily: @escaping (UUID) -> Predicate<T>,
        withID: @escaping (UUID) -> Predicate<T>,
        inFamilyForBackup: ((UUID) -> Predicate<T>)? = nil,
        make: @escaping (UUID, UUID) -> T
    ) -> SyncHandler {
        SyncHandler(
            kind: T.syncKind,
            hasImage: hasImage,
            all: { context, familyID in
                try context.fetch(FetchDescriptor<T>(predicate: inFamily(familyID))).map { $0 as any SyncableRecord }
            },
            backupAll: { context, familyID in
                try context.fetch(FetchDescriptor<T>(predicate: (inFamilyForBackup ?? inFamily)(familyID))).map { $0 as any SyncableRecord }
            },
            find: { context, id in
                var descriptor = FetchDescriptor<T>(predicate: withID(id))
                descriptor.fetchLimit = 1
                return try context.fetch(descriptor).first
            },
            make: { context, id, familyID in
                let record = make(id, familyID)
                context.insert(record)
                return record
            }
        )
    }
}

@MainActor
enum SyncRegistry {
    /// Core records (family, members) + every enabled module's records.
    /// Parents come first so children find them when applied in one batch.
    static var handlers: [SyncHandler] {
        var all: [SyncHandler] = [
            .of(Family.self,
                inFamily: { fid in #Predicate<Family> { $0.id == fid } },
                withID: { id in #Predicate<Family> { $0.id == id } },
                make: { id, _ in Family(id: id, name: "") }),
            .of(FamilyMember.self,
                inFamily: { fid in #Predicate<FamilyMember> { $0.familyID == fid } },
                withID: { id in #Predicate<FamilyMember> { $0.id == id } },
                make: { id, fid in FamilyMember(id: id, familyID: fid, displayName: "", role: .member) })
        ]
        for module in FamiloqModules.enabled {
            all.append(contentsOf: module.syncHandlers)
        }
        return all
    }

    static func handler(for kind: SyncKind) -> SyncHandler? {
        handlers.first { $0.kind == kind }
    }

    /// record name -> fingerprint of everything of a family that exists locally.
    static func currentFingerprints(familyID: UUID, context: ModelContext) throws -> [String: String] {
        var result: [String: String] = [:]
        for handler in handlers {
            for record in try handler.all(context, familyID) {
                result[handler.kind.recordName(for: record.syncID)] = record.syncPayload().fingerprint
            }
        }
        return result
    }

    /// Removes every synced record of a family from this iPhone.
    static func deleteAll(familyID: UUID, context: ModelContext) throws {
        for handler in handlers.reversed() {
            for record in try handler.all(context, familyID) {
                context.delete(record)
            }
        }
        let fid = familyID
        try context.delete(model: FamilyInvitationRecord.self, where: #Predicate { $0.familyID == fid })
        try context.delete(model: SyncLedgerEntry.self, where: #Predicate { $0.familyID == fid })
        try context.delete(model: SyncZoneRecord.self, where: #Predicate { $0.familyID == fid })
    }
}

// MARK: - Core records

extension Family: SyncableRecord {
    static var syncKind: SyncKind { .family }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("name", name)
        p.set("baseCurrencyCode", baseCurrencyCode)
        p.set("maxMembers", maxMembers)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        name = p.string("name")
        baseCurrencyCode = p.string("baseCurrencyCode", default: "EUR")
        maxMembers = p.int("maxMembers", default: 6)
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
    }
}

extension FamilyMember: SyncableRecord {
    static var syncKind: SyncKind { .member }
    var syncID: UUID { id }

    /// `isCurrentUser` is deliberately NOT synced: it is worked out on each
    /// iPhone from `cloudUserRecordName`.
    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("displayName", displayName)
        p.set("roleRaw", roleRaw)
        p.set("isActive", isActive)
        p.set("joinedAt", joinedAt)
        p.set("cloudUserRecordName", cloudUserRecordName)
        if !permissionsRaw.isEmpty { p.set("permissions", permissionsRaw) }
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        displayName = p.string("displayName")
        roleRaw = p.string("roleRaw", default: "member")
        isActive = p.bool("isActive", default: true)
        joinedAt = p.date("joinedAt", default: joinedAt)
        cloudUserRecordName = p.string("cloudUserRecordName")
        permissionsRaw = p.string("permissions")
    }
}
