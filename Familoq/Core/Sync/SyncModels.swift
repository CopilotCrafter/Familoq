import Foundation
import SwiftData

/// What this iPhone last sent to / received from iCloud for one record.
/// Local only (never synced). A record whose current fingerprint differs
/// from its ledger entry has changed locally and is uploaded.
@Model
final class SyncLedgerEntry {
    var recordName: String = ""
    var familyID: UUID = UUID()
    var fingerprint: String = ""
    /// When the local change was made (last writer wins on conflicts).
    var localChangedAt: Date = Date()
    /// CloudKit's change tag etc. (`encodeSystemFields`), nil until first saved.
    var systemFields: Data? = nil

    init(recordName: String, familyID: UUID, fingerprint: String, localChangedAt: Date = Date(), systemFields: Data? = nil) {
        self.recordName = recordName
        self.familyID = familyID
        self.fingerprint = fingerprint
        self.localChangedAt = localChangedAt
        self.systemFields = systemFields
    }
}

/// Where a family lives in iCloud. Local only.
///   own family    -> zone "family-<id>" in this user's PRIVATE database
///   joined family -> the owner's zone, seen through the SHARED database
@Model
final class SyncZoneRecord {
    var familyID: UUID = UUID()
    var zoneName: String = ""
    /// CKCurrentUserDefaultName for own zones, the owner's user record name otherwise.
    var ownerName: String = ""
    var isShared: Bool = false

    init(familyID: UUID, zoneName: String, ownerName: String, isShared: Bool) {
        self.familyID = familyID
        self.zoneName = zoneName
        self.ownerName = ownerName
        self.isShared = isShared
    }
}
