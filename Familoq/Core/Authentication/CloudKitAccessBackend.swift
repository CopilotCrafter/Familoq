import Foundation
import CloudKit
import FamiloqCore

/// App Invitations stored in the CloudKit PUBLIC database of
/// iCloud.com.carolandmartin.familoq. Record types, fields and permissions
/// are set up once in the CloudKit Console (docs/09-invitations-cloudkit.md).
///
/// No family or financial data is ever stored here.
final class CloudKitAccessBackend: AccessBackend {
    enum RecordType {
        static let invitation = "FQInvitation"
        static let redemption = "FQRedemption"
        static let revocation = "FQRevocation"
        static let log = "FQInvitationLog"
        static let request = "FQInvitationRequest"
    }

    private let container: CKContainer
    private var database: CKDatabase { container.publicCloudDatabase }

    init(containerIdentifier: String) {
        container = CKContainer(identifier: containerIdentifier)
    }

    /// Container from Info.plist (FQCloudKitContainer = iCloud.<bundle id>).
    static func live() -> CloudKitAccessBackend {
        let identifier = Bundle.main.object(forInfoDictionaryKey: "FQCloudKitContainer") as? String ?? "iCloud.com.carolandmartin.familoq"
        return CloudKitAccessBackend(containerIdentifier: identifier)
    }

    // MARK: Identity

    func currentUserRecordName() async throws -> String {
        do {
            let status = try await container.accountStatus()
            guard status == .available else { throw AccessError.noICloudAccount }
            return try await container.userRecordID().recordName
        } catch let error as AccessError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    func isAdministrator() async -> Bool {
        // Only the FamiloqAdmin role may read the invitation log.
        let query = CKQuery(recordType: RecordType.log, predicate: NSPredicate(value: true))
        do {
            _ = try await database.records(matching: query, resultsLimit: 1)
            return true
        } catch {
            return false
        }
    }

    // MARK: Redeeming

    func invitationStatus(codeHash: String, now: Date) async throws -> AppInvitationStatus {
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: codeHash))
            return AppInvitationRules.status(
                recordExists: true,
                statusField: record["status"] as? String,
                expiresAt: record["expiresAt"] as? Date,
                now: now
            )
        } catch let error as CKError where error.code == .unknownItem {
            return .notFound
        } catch {
            throw Self.map(error)
        }
    }

    func redeem(codeHash: String, userRecordName: String) async throws -> RedemptionOutcome {
        let record = CKRecord(recordType: RecordType.redemption, recordID: Self.redemptionID(codeHash))
        record["redeemedAt"] = Date()
        do {
            _ = try await database.save(record)
            return .redeemed
        } catch let error as CKError where error.code == .serverRecordChanged || error.code == .permissionFailure {
            // The redemption already exists: CloudKit allows each record name only once.
            do {
                let existing = try await database.record(for: Self.redemptionID(codeHash))
                let creator = existing.creatorUserRecordID?.recordName
                return (creator == userRecordName || creator == CKCurrentUserDefaultName) ? .alreadyMine : .usedBySomeoneElse
            } catch let fetchError as CKError where fetchError.code == .unknownItem {
                // Nothing exists but saving failed -> permissions are not set up (docs 09).
                throw AccessError.other("The invitation store is not set up correctly (CloudKit permissions). Please tell the administrator.")
            } catch {
                return .usedBySomeoneElse // exists but not readable = created by someone else
            }
        } catch {
            throw Self.map(error)
        }
    }

    func hasRedemption(userRecordName: String) async throws -> Bool {
        let me = CKRecord.Reference(recordID: CKRecord.ID(recordName: userRecordName), action: .none)
        let query = CKQuery(recordType: RecordType.redemption, predicate: NSPredicate(format: "creatorUserRecordID == %@", me))
        do {
            let result = try await database.records(matching: query, resultsLimit: 1)
            return !result.matchResults.isEmpty
        } catch {
            throw Self.map(error)
        }
    }

    func isRevoked(userRecordName: String) async throws -> Bool {
        do {
            _ = try await database.record(for: CKRecord.ID(recordName: "revoked-\(userRecordName)"))
            return true
        } catch let error as CKError where error.code == .unknownItem {
            return false
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: Requests

    func submitRequest(name: String, contact: String, message: String) async throws {
        let record = CKRecord(recordType: RecordType.request)
        record["name"] = name
        record["contact"] = contact
        record["message"] = message
        record["handled"] = 0 as Int64
        do {
            _ = try await database.save(record)
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: Administration

    func createInvitations(count: Int, validityDays: Int, note: String) async throws -> [String] {
        let expires = Calendar.current.date(byAdding: .day, value: AppInvitationRules.clampedValidityDays(validityDays), to: Date()) ?? Date()
        var codes: [String] = []
        var records: [CKRecord] = []
        for _ in 0..<AppInvitationRules.clampedCount(count) {
            let code = InvitationCode.generate()
            let hash = InvitationHashing.codeHash(code)
            let invitation = CKRecord(recordType: RecordType.invitation, recordID: CKRecord.ID(recordName: hash))
            invitation["status"] = "active"
            invitation["expiresAt"] = expires
            let log = CKRecord(recordType: RecordType.log, recordID: CKRecord.ID(recordName: "log-\(hash)"))
            log["codeHash"] = hash
            log["hint"] = AppInvitationRules.hint(for: code)
            log["note"] = note
            log["expiresAt"] = expires
            records += [invitation, log]
            codes.append(code)
        }
        do {
            let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
            for (_, saveResult) in result.saveResults {
                if case .failure(let error) = saveResult { throw error }
            }
        } catch {
            throw Self.map(error, adminOperation: true)
        }
        return codes
    }

    func adminOverview() async throws -> AdminOverview {
        do {
            let logs = try await all(RecordType.log)
            let redemptions = try await all(RecordType.redemption)
            let revocations = try await all(RecordType.revocation)
            let requests = try await all(RecordType.request)

            let hashes = logs.compactMap { $0["codeHash"] as? String }
            var invitationRecords: [String: CKRecord] = [:]
            if !hashes.isEmpty {
                let fetched = try await database.records(for: hashes.map { CKRecord.ID(recordName: $0) })
                for (id, result) in fetched {
                    if case .success(let record) = result { invitationRecords[id.recordName] = record }
                }
            }
            var redemptionByHash: [String: CKRecord] = [:]
            for r in redemptions { redemptionByHash[r.recordID.recordName.replacingOccurrences(of: "redeemed-", with: "")] = r }
            let revokedUsers = Set(revocations.compactMap { $0.recordID.recordName.replacingOccurrences(of: "revoked-", with: "") })
            let now = Date()

            let invitations: [AdminInvitation] = logs.compactMap { log in
                guard let hash = log["codeHash"] as? String else { return nil }
                let invitation = invitationRecords[hash]
                let redemption = redemptionByHash[hash]
                var status = AppInvitationRules.status(
                    recordExists: invitation != nil,
                    statusField: invitation?["status"] as? String,
                    expiresAt: invitation?["expiresAt"] as? Date,
                    now: now
                )
                if status == .expired && redemption != nil { status = .active } // used before expiry
                return AdminInvitation(
                    codeHash: hash,
                    hint: log["hint"] as? String ?? "",
                    note: log["note"] as? String ?? "",
                    createdAt: log.creationDate ?? now,
                    expiresAt: log["expiresAt"] as? Date ?? now,
                    status: status,
                    redeemedBy: redemption?.creatorUserRecordID?.recordName,
                    redeemedAt: redemption?.creationDate
                )
            }.sorted { $0.createdAt > $1.createdAt }

            let logByHash = Dictionary(uniqueKeysWithValues: logs.compactMap { log in
                (log["codeHash"] as? String).map { ($0, log) }
            })
            let accounts: [AdminAccount] = redemptions.compactMap { r in
                guard let user = r.creatorUserRecordID?.recordName else { return nil }
                let log = logByHash[r.recordID.recordName.replacingOccurrences(of: "redeemed-", with: "")]
                return AdminAccount(
                    userRecordName: user,
                    activatedAt: r.creationDate,
                    invitationHint: log?["hint"] as? String,
                    invitationNote: log?["note"] as? String,
                    isRevoked: revokedUsers.contains(user)
                )
            }.sorted { ($0.activatedAt ?? now) > ($1.activatedAt ?? now) }

            let adminRequests: [AdminRequest] = requests.map { r in
                AdminRequest(
                    id: r.recordID.recordName,
                    name: r["name"] as? String ?? "",
                    contact: r["contact"] as? String ?? "",
                    message: r["message"] as? String ?? "",
                    createdAt: r.creationDate ?? now,
                    handled: (r["handled"] as? Int64 ?? 0) != 0
                )
            }.sorted { $0.createdAt > $1.createdAt }

            return AdminOverview(invitations: invitations, accounts: accounts, requests: adminRequests)
        } catch {
            throw Self.map(error, adminOperation: true)
        }
    }

    func revokeInvitation(codeHash: String) async throws {
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: codeHash))
            record["status"] = "revoked"
            _ = try await database.save(record)
        } catch {
            throw Self.map(error, adminOperation: true)
        }
    }

    func setUserRevoked(_ revoked: Bool, userRecordName: String) async throws {
        let id = CKRecord.ID(recordName: "revoked-\(userRecordName)")
        do {
            if revoked {
                let record = CKRecord(recordType: RecordType.revocation, recordID: id)
                record["revokedAt"] = Date()
                do {
                    _ = try await database.save(record)
                } catch let error as CKError where error.code == .serverRecordChanged {
                    // already revoked
                }
            } else {
                do {
                    _ = try await database.deleteRecord(withID: id)
                } catch let error as CKError where error.code == .unknownItem {
                    // not revoked
                }
            }
        } catch {
            throw Self.map(error, adminOperation: true)
        }
    }

    func markRequestHandled(id: String) async throws {
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: id))
            record["handled"] = 1 as Int64
            _ = try await database.save(record)
        } catch {
            throw Self.map(error, adminOperation: true)
        }
    }

    // MARK: Helpers

    // Record names are unique per zone across ALL record types, so every type
    // gets its own prefix (the invitation itself uses the bare hash).
    private static func redemptionID(_ codeHash: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "redeemed-\(codeHash)")
    }

    private func all(_ type: String) async throws -> [CKRecord] {
        let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
        var records: [CKRecord] = []
        var (results, cursor) = try await database.records(matching: query, resultsLimit: 200)
        while true {
            for (_, result) in results {
                if case .success(let record) = result { records.append(record) }
            }
            guard let next = cursor, records.count < 2000 else { break }
            (results, cursor) = try await database.records(continuingMatchFrom: next, resultsLimit: 200)
        }
        return records
    }

    private static func map(_ error: Error, adminOperation: Bool = false) -> Error {
        if let access = error as? AccessError { return access }
        guard let ck = error as? CKError else { return AccessError.other(error.localizedDescription) }
        switch ck.code {
        case .notAuthenticated:
            return AccessError.noICloudAccount
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return AccessError.offline
        case .permissionFailure:
            return adminOperation ? AccessError.notAdministrator : AccessError.other("iCloud refused the request (permission).")
        default:
            return AccessError.other("iCloud error: \(ck.localizedDescription)")
        }
    }
}
