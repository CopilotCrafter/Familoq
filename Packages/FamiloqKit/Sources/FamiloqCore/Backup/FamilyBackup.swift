import Foundation

/// A complete family backup file (.json): every record as its sync payload,
/// optionally with receipt photos. Restoring merges the records into a
/// family (same IDs are updated, new ones added).
public struct FamilyBackup: Codable, Equatable, Sendable {
    public static let currentFormat = 1

    public struct Record: Codable, Equatable, Sendable {
        public var kind: String
        public var id: UUID
        public var fields: [String: String]
        /// Base64 JPEG (receipt photo), only when exported with photos.
        public var image: String?

        public init(kind: String, id: UUID, fields: [String: String], image: String? = nil) {
            self.kind = kind
            self.id = id
            self.fields = fields
            self.image = image
        }
    }

    public var format: Int
    public var app: String
    public var exportedAt: Date
    public var familyID: UUID
    public var familyName: String
    public var baseCurrency: String
    public var records: [Record]

    public init(familyID: UUID, familyName: String, baseCurrency: String, exportedAt: Date = Date(), records: [Record]) {
        self.format = Self.currentFormat
        self.app = "Familoq"
        self.exportedAt = exportedAt
        self.familyID = familyID
        self.familyName = familyName
        self.baseCurrency = baseCurrency
        self.records = records
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public enum ReadError: Error, Equatable {
        case notAFamiloqBackup
        case newerFormat(Int)
    }

    public static func decode(_ data: Data) throws -> FamilyBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(FamilyBackup.self, from: data), backup.app == "Familoq" else {
            throw ReadError.notAFamiloqBackup
        }
        guard backup.format <= currentFormat else { throw ReadError.newerFormat(backup.format) }
        return backup
    }

    /// Records per kind, e.g. ["expense": 120, "category": 14].
    public var counts: [String: Int] {
        Dictionary(grouping: records, by: \.kind).mapValues(\.count)
    }
}
