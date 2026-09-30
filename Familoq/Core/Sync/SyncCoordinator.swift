import Foundation
import CloudKit
import SwiftData
import FamiloqCore

/// Keeps every family on this iPhone in sync with iCloud (CKSyncEngine).
///
///   own family    -> zone "family-<id>" in the user's PRIVATE database,
///                    shared with invited members through a zone-wide CKShare
///   joined family -> the owner's zone, read and written through the SHARED database
///
/// Every record is one `FQFamilyItem` (kind, payload JSON, modifiedAt, asset).
/// Local changes are found by comparing payload fingerprints with the
/// `SyncLedgerEntry` of each record; conflicts: last writer wins.
/// Only this one record type has to exist in the CloudKit schema
/// (docs/10-sync-and-sharing.md).
@MainActor
final class SyncCoordinator: ObservableObject, CKSyncEngineDelegate {
    enum Status: Equatable {
        case off
        case syncing
        case upToDate(Date)
        case offline
        case problem(String)
    }

    enum JoinState: Equatable {
        case idle
        case joining
        case joined(UUID)
        case failed(String)
    }

    static let recordType = "FQFamilyItem"

    @Published private(set) var status: Status = .off
    /// True after the first fetch (or its timeout) - a reinstalled iPhone
    /// must not offer "Create your family" before its family arrived.
    @Published private(set) var initialFetchDone = false
    /// Increases whenever iCloud changed data on this iPhone.
    @Published private(set) var remoteChangeCount = 0
    @Published var joinState: JoinState = .idle

    /// Called right before a family is removed from this iPhone (member
    /// removed, family left or deleted) so the session can switch away first.
    var willRemoveFamily: (@MainActor (UUID) -> Void)?

    let isEnabled: Bool
    private let containerIdentifier: String
    private lazy var ckContainer = CKContainer(identifier: containerIdentifier)
    private var modelContainer: ModelContainer?
    private var privateEngine: CKSyncEngine?
    private var sharedEngine: CKSyncEngine?
    private var loop: Task<Void, Never>?
    private(set) var userRecordName = ""

    private enum Keys {
        static let user = "sync.userRecordName"
        static let privateState = "sync.state.private"
        static let sharedState = "sync.state.shared"
    }

    init(containerIdentifier: String, isEnabled: Bool) {
        self.containerIdentifier = containerIdentifier
        self.isEnabled = isEnabled
        if !isEnabled { initialFetchDone = true }
    }

    static func live() -> SyncCoordinator {
        let identifier = Bundle.main.object(forInfoDictionaryKey: "FQCloudKitContainer") as? String ?? "iCloud.com.carolandmartin.familoq"
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard
        if env["XCTestConfigurationFilePath"] != nil || defaults.bool(forKey: "demoAccount") || defaults.bool(forKey: "noICloud") {
            // Unsigned test/screenshot builds have no iCloud entitlement.
            return SyncCoordinator(containerIdentifier: identifier, isEnabled: false)
        }
        #endif
        return SyncCoordinator(containerIdentifier: identifier, isEnabled: true)
    }

    private var context: ModelContext? { modelContainer?.mainContext }
    var isRunning: Bool { privateEngine != nil }

    // MARK: - Start

    /// Starts syncing for the activated iCloud user. Safe to call repeatedly.
    func start(modelContainer: ModelContainer, userRecordName: String) {
        guard isEnabled, privateEngine == nil else { return }
        guard !userRecordName.isEmpty, userRecordName != "demo" else {
            initialFetchDone = true
            return
        }
        self.modelContainer = modelContainer
        self.userRecordName = userRecordName

        let defaults = UserDefaults.standard
        if let previous = defaults.string(forKey: Keys.user), previous != userRecordName {
            // Another iCloud account: its sync state must not be reused.
            defaults.removeObject(forKey: Keys.privateState)
            defaults.removeObject(forKey: Keys.sharedState)
            resetLedger()
        }
        defaults.set(userRecordName, forKey: Keys.user)

        privateEngine = makeEngine(database: ckContainer.privateCloudDatabase, stateKey: Keys.privateState)
        sharedEngine = makeEngine(database: ckContainer.sharedCloudDatabase, stateKey: Keys.sharedState)
        status = .syncing

        adoptLocalFamilies()
        scanNow()

        Task {
            // Give up waiting after 20 s (offline): the app works offline.
            let timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                self?.initialFetchDone = true
            }
            await fetchNow()
            timeout.cancel()
            initialFetchDone = true
            await catchUpNewKindsIfNeeded()
        }
        startLoop()
    }

    // MARK: - Catch-up after an update

    /// Raised whenever a new SyncKind is added (2 = Planner in 0.5.0,
    /// 3 = learned receipt items in 0.5.2).
    private static let kindsVersion = 7
    /// Kinds added since 0.4 (fetching one again is harmless). 4 = time off
    /// in 0.6, 5 = contracts, warranties, meals, travel in 0.7, 6 = meal
    /// settings, ratings, pantry and the Health space in 0.8, 7 = cars and
    /// documents in 0.9.
    private static let newKinds: Set<SyncKind> = [.shoppingList, .shoppingItem, .reminder, .event, .itemRule, .leave, .leaveAllowance,
                                                  .contract, .warranty, .recipe, .meal, .trip, .packingItem,
                                                  .mealPrefs, .mealRating, .pantry, .healthPerson, .checkup, .vaccination,
                                                  .medication, .measurement, .healthContact, .claim, .plate,
                                                  .car, .document, .documentPage]

    /// An older app version skips record kinds it does not know, and its
    /// change tokens move past them. After updating, fetch those kinds once
    /// from every family zone (e.g. Carol's shopping list when Martin
    /// updated first).
    private func catchUpNewKindsIfNeeded() async {
        let key = "sync.kindsVersion"
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: key) < Self.kindsVersion, let context else { return }
        let zones = (try? context.fetch(FetchDescriptor<SyncZoneRecord>())) ?? []
        var complete = true
        var applied = 0
        for zone in zones {
            let database = zone.isShared ? ckContainer.sharedCloudDatabase : ckContainer.privateCloudDatabase
            guard let engine = zone.isShared ? sharedEngine : privateEngine else { complete = false; continue }
            var token: CKServerChangeToken?
            var moreComing = true
            while moreComing {
                do {
                    let changes = try await database.recordZoneChanges(inZoneWith: recordZoneID(of: zone), since: token)
                    for (_, result) in changes.modificationResultsByID {
                        guard case .success(let modification) = result,
                              let parsed = SyncKind.parse(recordName: modification.record.recordID.recordName),
                              Self.newKinds.contains(parsed.0) else { continue }
                        applyRemote(modification.record, isShared: zone.isShared, engine: engine)
                        applied += 1
                    }
                    token = changes.changeToken
                    moreComing = changes.moreComing
                } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
                    moreComing = false
                } catch {
                    complete = false
                    moreComing = false
                }
            }
        }
        if applied > 0 {
            try? context.save()
            remoteChangeCount += 1
        }
        if complete { defaults.set(Self.kindsVersion, forKey: key) }
    }

    /// Stops syncing (iCloud account signed out or changed).
    func stop() {
        loop?.cancel()
        loop = nil
        privateEngine = nil
        sharedEngine = nil
        status = .off
    }

    private func makeEngine(database: CKDatabase, stateKey: String) -> CKSyncEngine {
        var state: CKSyncEngine.State.Serialization?
        if let data = UserDefaults.standard.data(forKey: stateKey) {
            state = try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        }
        let configuration = CKSyncEngine.Configuration(database: database, stateSerialization: state, delegate: self)
        return CKSyncEngine(configuration)
    }

    /// Checks for local changes every 15 s and for iCloud changes every
    /// minute while the app is open (Familoq uses no push notifications).
    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, !Task.isCancelled else { return }
                self.scanNow()
                tick += 1
                if tick % 4 == 0 { await self.fetchNow() }
            }
        }
    }

    /// App came to the foreground / pull to refresh.
    func refresh() async {
        guard isRunning else { return }
        scanNow()
        await fetchNow()
    }

    func fetchNow() async {
        guard let privateEngine, let sharedEngine else { return }
        do {
            try await privateEngine.fetchChanges()
            try await sharedEngine.fetchChanges()
        } catch {
            noteError(error)
        }
    }

    // MARK: - Local changes -> iCloud

    /// Families created before sync existed (or just now) live in the
    /// user's own zone. Also records who "me" is on this iPhone.
    private func adoptLocalFamilies() {
        guard let context, let privateEngine else { return }
        let families = (try? context.fetch(FetchDescriptor<Family>())) ?? []
        let zones = (try? context.fetch(FetchDescriptor<SyncZoneRecord>())) ?? []
        var newZones: [CKSyncEngine.PendingDatabaseChange] = []
        for family in families where !zones.contains(where: { $0.familyID == family.id }) {
            let record = SyncZoneRecord(familyID: family.id, zoneName: SyncZone.zoneName(for: family.id), ownerName: CKCurrentUserDefaultName, isShared: false)
            context.insert(record)
            newZones.append(.saveZone(CKRecordZone(zoneID: recordZoneID(of: record))))
            // Own family: the member marked as "me" is this iCloud user.
            let fid = family.id
            let members = (try? context.fetch(FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.familyID == fid }))) ?? []
            for member in members where member.isCurrentUser && member.cloudUserRecordName.isEmpty {
                member.cloudUserRecordName = userRecordName
            }
        }
        if !newZones.isEmpty {
            privateEngine.state.add(pendingDatabaseChanges: newZones)
        }
        try? context.save()
    }

    /// Compares every family's records with the ledger and queues uploads
    /// and deletions. Cheap enough to run every few seconds.
    func scanNow() {
        guard let context, let privateEngine, let sharedEngine else { return }
        adoptLocalFamilies()
        let zones = (try? context.fetch(FetchDescriptor<SyncZoneRecord>())) ?? []
        let now = Date()
        for zone in zones {
            let engine = zone.isShared ? sharedEngine : privateEngine
            let zoneID = recordZoneID(of: zone)
            guard let current = try? SyncRegistry.currentFingerprints(familyID: zone.familyID, context: context) else { continue }
            let entries = ledgerEntries(familyID: zone.familyID)
            let diff = SyncDiff.compute(current: current, ledger: entries.mapValues(\.fingerprint))
            guard !diff.changed.isEmpty || !diff.deleted.isEmpty else { continue }

            var pending: [CKSyncEngine.PendingRecordZoneChange] = []
            for name in diff.changed {
                if let entry = entries[name] {
                    entry.fingerprint = current[name] ?? ""
                    entry.localChangedAt = now
                } else {
                    context.insert(SyncLedgerEntry(recordName: name, familyID: zone.familyID, fingerprint: current[name] ?? "", localChangedAt: now))
                }
                pending.append(.saveRecord(CKRecord.ID(recordName: name, zoneID: zoneID)))
            }
            for name in diff.deleted {
                if let entry = entries[name] { context.delete(entry) }
                pending.append(.deleteRecord(CKRecord.ID(recordName: name, zoneID: zoneID)))
            }
            engine.state.add(pendingRecordZoneChanges: pending)
        }
        try? context.save()
    }

    func nextRecordZoneChangeBatch(_ sendContext: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = sendContext.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !changes.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { [weak self] recordID in
            await self?.outgoingRecord(for: recordID)
        }
    }

    /// Builds the CKRecord for a local record (nil = it no longer exists).
    private func outgoingRecord(for recordID: CKRecord.ID) -> CKRecord? {
        guard let context,
              let parsed = SyncKind.parse(recordName: recordID.recordName),
              let handler = SyncRegistry.handler(for: parsed.0),
              let object = try? handler.find(context, parsed.1),
              object.isSyncShareable else { return nil }
        let kind = parsed.0
        let entry = ledgerEntry(recordID.recordName)
        var record = entry?.systemFields.flatMap(Self.decodeSystemFields) ?? CKRecord(recordType: Self.recordType, recordID: recordID)
        if record.recordID != recordID {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        }
        record["kind"] = kind.rawValue
        record["payload"] = object.syncPayload().jsonString
        record["modifiedAt"] = entry?.localChangedAt ?? Date()
        if handler.hasImage {
            if let data = object.syncImage, let url = Self.writeAssetFile(data, name: recordID.recordName) {
                record["asset"] = CKAsset(fileURL: url)
            } else {
                record["asset"] = nil
            }
        }
        return record
    }

    // MARK: - iCloud -> this iPhone

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        let isShared = syncEngine.database.databaseScope == .shared
        switch event {
        case .stateUpdate(let update):
            if let data = try? JSONEncoder().encode(update.stateSerialization) {
                UserDefaults.standard.set(data, forKey: isShared ? Keys.sharedState : Keys.privateState)
            }

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                break
            case .signOut, .switchAccounts:
                UserDefaults.standard.removeObject(forKey: Keys.privateState)
                UserDefaults.standard.removeObject(forKey: Keys.sharedState)
                resetLedger()
                stop()
            @unknown default:
                break
            }

        case .fetchedDatabaseChanges(let changes):
            for modification in changes.modifications {
                registerZone(modification.zoneID, isShared: isShared)
            }
            for deletion in changes.deletions {
                zoneWasDeleted(deletion.zoneID, reason: deletion.reason, isShared: isShared)
            }

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                applyRemote(modification.record, isShared: isShared, engine: syncEngine)
            }
            for deletion in changes.deletions {
                applyRemoteDeletion(deletion.recordID)
            }
            try? context?.save()
            if !changes.modifications.isEmpty || !changes.deletions.isEmpty {
                remoteChangeCount += 1
            }

        case .sentDatabaseChanges(let sent):
            for failure in sent.failedZoneSaves {
                noteError(failure.error)
            }

        case .sentRecordZoneChanges(let sent):
            handleSent(sent, engine: syncEngine, isShared: isShared)

        case .willFetchChanges, .willSendChanges:
            if status != .syncing { status = .syncing }

        case .didFetchChanges, .didSendChanges:
            if case .problem = status { break }
            status = .upToDate(Date())

        default:
            break
        }
    }

    private func registerZone(_ zoneID: CKRecordZone.ID, isShared: Bool) {
        guard let context, let familyID = SyncZone.familyID(fromZoneName: zoneID.zoneName) else { return }
        let fid = familyID
        let existing = try? context.fetch(FetchDescriptor<SyncZoneRecord>(predicate: #Predicate { $0.familyID == fid })).first
        if existing == nil {
            context.insert(SyncZoneRecord(familyID: familyID, zoneName: zoneID.zoneName, ownerName: zoneID.ownerName, isShared: isShared))
            try? context.save()
        }
    }

    private func zoneWasDeleted(_ zoneID: CKRecordZone.ID, reason: CKDatabase.DatabaseChange.Deletion.Reason, isShared: Bool) {
        guard let familyID = SyncZone.familyID(fromZoneName: zoneID.zoneName) else { return }
        if !isShared && reason == .encryptedDataReset {
            // iCloud Keychain was reset: upload everything again.
            reuploadFamily(familyID)
            return
        }
        // Member removed / left, or the owner deleted the family (also from
        // another of their devices, or in iCloud settings).
        removeLocalFamily(familyID)
    }

    private func applyRemote(_ record: CKRecord, isShared: Bool, engine: CKSyncEngine) {
        guard let context,
              record.recordType == Self.recordType,
              let parsed = SyncKind.parse(recordName: record.recordID.recordName),
              let familyID = SyncZone.familyID(fromZoneName: record.recordID.zoneID.zoneName),
              let handler = SyncRegistry.handler(for: parsed.0),
              let json = record["payload"] as? String,
              let payload = SyncPayload(json: json) else { return }
        let (kind, id) = parsed
        registerZone(record.recordID.zoneID, isShared: isShared)

        let recordName = record.recordID.recordName
        let entry = ledgerEntry(recordName)
        let serverDate = (record["modifiedAt"] as? Date) ?? record.modificationDate
        let local = try? handler.find(context, id)
        let localFingerprint = local?.syncPayload().fingerprint

        // Nothing new (e.g. our own change coming back).
        if let local, localFingerprint == payload.fingerprint {
            upsertLedger(recordName, familyID: familyID, fingerprint: localFingerprint ?? "", changedAt: serverDate ?? Date(), record: record)
            if handler.hasImage, let asset = record["asset"] as? CKAsset, local.syncImage == nil {
                local.syncImage = asset.fileURL.flatMap { try? Data(contentsOf: $0) }
            }
            return
        }

        // Owner's iPhone guards the family's rules (members may only add and
        // edit expenses, receipts and merchant rules).
        if !isShared, !isChangeAllowed(kind: kind, payload: payload, local: local, record: record) {
            keepLocalVersion(of: record, familyID: familyID, engine: engine, existsLocally: local != nil)
            return
        }

        // A newer unsent local change wins (last writer wins).
        if local != nil, let entry, hasPendingSave(record.recordID, in: engine),
           !SyncConflictResolver.serverWins(serverModifiedAt: serverDate, localChangedAt: entry.localChangedAt) {
            entry.systemFields = Self.encodeSystemFields(record)
            return
        }

        let object = local ?? handler.make(context, id, familyID)
        object.applySyncPayload(payload)
        if handler.hasImage {
            object.syncImage = (record["asset"] as? CKAsset)?.fileURL.flatMap { try? Data(contentsOf: $0) }
        }
        if let member = object as? FamilyMember {
            member.isCurrentUser = !member.cloudUserRecordName.isEmpty && member.cloudUserRecordName == userRecordName
        }
        upsertLedger(recordName, familyID: familyID, fingerprint: object.syncPayload().fingerprint, changedAt: serverDate ?? Date(), record: record)
    }

    private func applyRemoteDeletion(_ recordID: CKRecord.ID) {
        guard let context, let parsed = SyncKind.parse(recordName: recordID.recordName),
              let handler = SyncRegistry.handler(for: parsed.0) else { return }
        let (kind, id) = parsed
        if kind == .family, let familyID = SyncZone.familyID(fromZoneName: recordID.zoneID.zoneName), familyID == id {
            // The family itself goes away together with its zone.
            return
        }
        if let object = try? handler.find(context, id) {
            context.delete(object)
        }
        if let entry = ledgerEntry(recordID.recordName) {
            context.delete(entry)
        }
    }

    /// Owner-only settings may only be changed by the owner, or by a member the
    /// owner gave that right to. Checked on the owner's iPhone, which then
    /// restores its own version in iCloud.
    private func isChangeAllowed(kind: SyncKind, payload: SyncPayload, local: (any SyncableRecord)?, record: CKRecord) -> Bool {
        guard let modifier = record.lastModifiedUserRecordID?.recordName else { return true }
        let byOwner = modifier == CKCurrentUserDefaultName || modifier == userRecordName || modifier == record.recordID.zoneID.ownerName
        if byOwner { return true }
        let grants = grantsOf(modifier: modifier, zoneID: record.recordID.zoneID)
        switch kind {
        case .family:
            return grants.contains(.familySettings)
        case .category, .subcategory:
            return grants.contains(.categories)
        case .budget:
            return grants.contains(.budgets)
        case .member:
            // Members may add themselves and edit their own name - never make
            // anyone owner, change someone else or give themselves rights.
            let role = payload.string("roleRaw", default: "member")
            if role == FamilyRole.owner.rawValue { return false }
            if let member = local as? FamilyMember {
                return member.role != .owner && member.cloudUserRecordName == modifier
                    && FamilyGrant.parse(payload.string("permissions")) == member.grants
            }
            return payload.string("cloudUserRecordName") == modifier && payload.string("permissions").isEmpty
        default:
            return true
        }
    }

    /// Rights of the person who changed a record, as stored on this iPhone.
    private func grantsOf(modifier: String, zoneID: CKRecordZone.ID) -> Set<FamilyGrant> {
        guard let context, let familyID = SyncZone.familyID(fromZoneName: zoneID.zoneName) else { return [] }
        let fid = familyID
        let members = (try? context.fetch(FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.familyID == fid }))) ?? []
        guard let member = members.first(where: { $0.cloudUserRecordName == modifier && $0.isActive }) else { return [] }
        return member.grants
    }

    private func keepLocalVersion(of record: CKRecord, familyID: UUID, engine: CKSyncEngine, existsLocally: Bool) {
        let recordName = record.recordID.recordName
        if existsLocally {
            let entry = ledgerEntry(recordName)
            if let entry {
                entry.systemFields = Self.encodeSystemFields(record)
                entry.localChangedAt = Date()
            } else {
                context?.insert(SyncLedgerEntry(recordName: recordName, familyID: familyID, fingerprint: "", systemFields: Self.encodeSystemFields(record)))
            }
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
        } else {
            engine.state.add(pendingRecordZoneChanges: [.deleteRecord(record.recordID)])
        }
    }

    // MARK: - Send results

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine, isShared: Bool) {
        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var zonesToCreate: [CKSyncEngine.PendingDatabaseChange] = []

        for record in sent.savedRecords {
            ledgerEntry(record.recordID.recordName)?.systemFields = Self.encodeSystemFields(record)
            Self.removeAssetFile(name: record.recordID.recordName)
        }

        for failure in sent.failedRecordSaves {
            let record = failure.record
            let recordName = record.recordID.recordName
            switch failure.error.code {
            case .serverRecordChanged:
                guard let server = failure.error.serverRecord else { continue }
                let entry = ledgerEntry(recordName)
                let serverDate = (server["modifiedAt"] as? Date) ?? server.modificationDate
                if SyncConflictResolver.serverWins(serverModifiedAt: serverDate, localChangedAt: entry?.localChangedAt) {
                    applyRemote(server, isShared: isShared, engine: engine)
                } else {
                    entry?.systemFields = Self.encodeSystemFields(server)
                    retry.append(.saveRecord(record.recordID))
                }
            case .zoneNotFound:
                if !isShared {
                    zonesToCreate.append(.saveZone(CKRecordZone(zoneID: record.recordID.zoneID)))
                    retry.append(.saveRecord(record.recordID))
                }
            case .unknownItem:
                ledgerEntry(recordName)?.systemFields = nil
                retry.append(.saveRecord(record.recordID))
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .notAuthenticated, .operationCancelled, .requestRateLimited:
                // CKSyncEngine retries these by itself.
                break
            default:
                noteError(failure.error)
            }
        }

        if !zonesToCreate.isEmpty { engine.state.add(pendingDatabaseChanges: zonesToCreate) }
        if !retry.isEmpty { engine.state.add(pendingRecordZoneChanges: retry) }
        try? context?.save()
    }

    private func noteError(_ error: Error) {
        guard let ck = error as? CKError else {
            status = .problem(error.localizedDescription)
            return
        }
        switch ck.code {
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            status = .offline
        case .quotaExceeded:
            status = .problem("iCloud storage is full. Free up space in Settings → your name → iCloud.")
        case .notAuthenticated:
            status = .problem("Sign in to iCloud to sync your family.")
        case .unknownItem where ck.localizedDescription.contains(Self.recordType):
            status = .problem("iCloud is not set up for family sync yet (record type \(Self.recordType)). See docs/10.")
        case .serverRejectedRequest, .invalidArguments:
            status = .problem("iCloud rejected the data. Is the record type \(Self.recordType) deployed to Production?")
        default:
            status = .problem(ck.localizedDescription)
        }
    }

    // MARK: - Families: leave, delete, re-upload

    /// Removes a family and everything in it from this iPhone.
    func removeLocalFamily(_ familyID: UUID) {
        guard let context else { return }
        willRemoveFamily?(familyID)
        // Let the screens showing this family disappear before its data does.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            try? SyncRegistry.deleteAll(familyID: familyID, context: context)
            try? context.save()
            self?.remoteChangeCount += 1
        }
    }

    /// Owner: deletes the family for everyone. Member: leaves the family.
    func deleteOrLeave(familyID: UUID) {
        guard let context else { return }
        let fid = familyID
        if let zone = try? context.fetch(FetchDescriptor<SyncZoneRecord>(predicate: #Predicate { $0.familyID == fid })).first,
           let engine = zone.isShared ? sharedEngine : privateEngine {
            let zoneID = recordZoneID(of: zone)
            let stale = engine.state.pendingRecordZoneChanges.filter { change in
                switch change {
                case .saveRecord(let id), .deleteRecord(let id): return id.zoneID == zoneID
                @unknown default: return false
                }
            }
            engine.state.remove(pendingRecordZoneChanges: stale)
            engine.state.add(pendingDatabaseChanges: [.deleteZone(zoneID)])
        }
        removeLocalFamily(familyID)
    }

    private func reuploadFamily(_ familyID: UUID) {
        guard let context, let privateEngine else { return }
        let fid = familyID
        try? context.delete(model: SyncLedgerEntry.self, where: #Predicate { $0.familyID == fid })
        privateEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CKRecordZone.ID(zoneName: SyncZone.zoneName(for: familyID), ownerName: CKCurrentUserDefaultName)))])
        try? context.save()
        scanNow()
    }

    private func resetLedger() {
        guard let context else { return }
        for entry in (try? context.fetch(FetchDescriptor<SyncLedgerEntry>())) ?? [] {
            entry.systemFields = nil
            entry.fingerprint = ""
        }
        try? context.save()
    }

    // MARK: - Helpers

    func zoneRecord(for familyID: UUID) -> SyncZoneRecord? {
        guard let context else { return nil }
        let fid = familyID
        return try? context.fetch(FetchDescriptor<SyncZoneRecord>(predicate: #Predicate { $0.familyID == fid })).first
    }

    func recordZoneID(of zone: SyncZoneRecord) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zone.zoneName, ownerName: zone.ownerName)
    }

    var container: CKContainer { ckContainer }
    var modelContainerContext: ModelContext? { context }

    func registerSharedZone(_ zoneID: CKRecordZone.ID) {
        registerZone(zoneID, isShared: true)
    }

    private func ledgerEntry(_ recordName: String) -> SyncLedgerEntry? {
        guard let context else { return nil }
        let name = recordName
        var descriptor = FetchDescriptor<SyncLedgerEntry>(predicate: #Predicate { $0.recordName == name })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func ledgerEntries(familyID: UUID) -> [String: SyncLedgerEntry] {
        guard let context else { return [:] }
        let fid = familyID
        let entries = (try? context.fetch(FetchDescriptor<SyncLedgerEntry>(predicate: #Predicate { $0.familyID == fid }))) ?? []
        var result: [String: SyncLedgerEntry] = [:]
        for entry in entries { result[entry.recordName] = entry }
        return result
    }

    private func upsertLedger(_ recordName: String, familyID: UUID, fingerprint: String, changedAt: Date, record: CKRecord) {
        let fields = Self.encodeSystemFields(record)
        if let entry = ledgerEntry(recordName) {
            entry.fingerprint = fingerprint
            entry.localChangedAt = changedAt
            entry.systemFields = fields
        } else {
            context?.insert(SyncLedgerEntry(recordName: recordName, familyID: familyID, fingerprint: fingerprint, localChangedAt: changedAt, systemFields: fields))
        }
    }

    private func hasPendingSave(_ recordID: CKRecord.ID, in engine: CKSyncEngine) -> Bool {
        engine.state.pendingRecordZoneChanges.contains(.saveRecord(recordID))
    }

    static func encodeSystemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    private static var assetDirectory: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sync-assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func writeAssetFile(_ data: Data, name: String) -> URL? {
        let url = assetDirectory.appendingPathComponent(name).appendingPathExtension("jpg")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func removeAssetFile(name: String) {
        try? FileManager.default.removeItem(at: assetDirectory.appendingPathComponent(name).appendingPathExtension("jpg"))
    }
}
