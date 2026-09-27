import Foundation

/// Platform-independent part of family sync (tested on Linux).
///
/// Every family-owned record is sent to iCloud as one generic record
/// (type `FQFamilyItem`) in the family's zone:
///   kind       e.g. "expense"
///   payload    JSON of the record's fields
///   modifiedAt when it was last changed (last writer wins)
///   asset      optional file (receipt image)
///
/// The app detects local changes by comparing a fingerprint of each record's
/// payload with the fingerprint that was last synced (the "ledger").
public enum SyncKind: String, CaseIterable, Codable, Sendable {
    case family
    case member
    case category
    case subcategory
    case expense
    case budget
    case rule
    case receipt
    case receiptItem

    /// Record name in CloudKit, e.g. "expense-6F1C…".
    public func recordName(for id: UUID) -> String { "\(rawValue)-\(id.uuidString)" }

    /// Parses "expense-<uuid>".
    public static func parse(recordName: String) -> (SyncKind, UUID)? {
        guard let dash = recordName.firstIndex(of: "-") else { return nil }
        let kindText = String(recordName[..<dash])
        let idText = String(recordName[recordName.index(after: dash)...])
        guard let kind = SyncKind(rawValue: kindText), let id = UUID(uuidString: idText) else { return nil }
        return (kind, id)
    }
}

public enum SyncZone {
    public static let prefix = "family-"

    public static func zoneName(for familyID: UUID) -> String { prefix + familyID.uuidString }

    public static func familyID(fromZoneName name: String) -> UUID? {
        guard name.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(prefix.count)))
    }
}

/// Stable fingerprint of a payload (FNV-1a 64-bit, hex). Used only to detect
/// changes, not for security.
public enum SyncFingerprint {
    public static func of(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

public struct SyncDiffResult: Equatable, Sendable {
    /// Record names whose content is new or changed locally -> upload.
    public var changed: [String]
    /// Record names that were synced before but no longer exist locally -> delete.
    public var deleted: [String]
}

public enum SyncDiff {
    /// - Parameters:
    ///   - current: record name -> fingerprint of everything that exists locally now
    ///   - ledger:  record name -> fingerprint last sent to / received from iCloud
    public static func compute(current: [String: String], ledger: [String: String]) -> SyncDiffResult {
        let changed = current.filter { ledger[$0.key] != $0.value }.map(\.key).sorted()
        let deleted = ledger.keys.filter { current[$0] == nil }.sorted()
        return SyncDiffResult(changed: changed, deleted: deleted)
    }
}

public enum SyncConflictResolver {
    /// Last writer wins. Returns true when the server version should replace
    /// the local one.
    public static func serverWins(serverModifiedAt: Date?, localChangedAt: Date?) -> Bool {
        guard let server = serverModifiedAt else { return false }
        guard let local = localChangedAt else { return true }
        return server > local
    }
}
