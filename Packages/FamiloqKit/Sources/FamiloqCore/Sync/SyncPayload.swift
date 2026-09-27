import Foundation

/// The fields of one record as sent to iCloud: a flat, sorted JSON object of
/// strings. Deterministic, so its fingerprint only changes when a value does.
///
/// * Optional values that are nil are simply left out.
/// * Dates are whole milliseconds, so they survive the round trip unchanged.
public struct SyncPayload: Equatable, Sendable {
    public private(set) var values: [String: String]

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    // MARK: Writing

    public mutating func set(_ key: String, _ value: String?) { values[key] = value }
    public mutating func set(_ key: String, _ value: Int) { values[key] = String(value) }
    public mutating func set(_ key: String, _ value: Int64) { values[key] = String(value) }
    public mutating func set(_ key: String, _ value: Int64?) { values[key] = value.map { String($0) } }
    public mutating func set(_ key: String, _ value: Bool) { values[key] = value ? "1" : "0" }
    public mutating func set(_ key: String, _ value: UUID) { values[key] = value.uuidString }
    public mutating func set(_ key: String, _ value: UUID?) { values[key] = value?.uuidString }
    public mutating func set(_ key: String, _ value: Date) { values[key] = String(Self.milliseconds(value)) }
    public mutating func set(_ key: String, _ value: Date?) { values[key] = value.map { String(Self.milliseconds($0)) } }

    // MARK: Reading (with the model's default when missing)

    public func string(_ key: String, default fallback: String = "") -> String { values[key] ?? fallback }
    public func optionalString(_ key: String) -> String? { values[key] }
    public func int(_ key: String, default fallback: Int = 0) -> Int { values[key].flatMap { Int($0) } ?? fallback }
    public func int64(_ key: String, default fallback: Int64 = 0) -> Int64 { values[key].flatMap { Int64($0) } ?? fallback }
    public func optionalInt64(_ key: String) -> Int64? { values[key].flatMap { Int64($0) } }
    public func bool(_ key: String, default fallback: Bool = false) -> Bool { values[key].map { $0 == "1" } ?? fallback }
    public func uuid(_ key: String) -> UUID? { values[key].flatMap { UUID(uuidString: $0) } }
    public func date(_ key: String) -> Date? {
        values[key].flatMap { Int64($0) }.map { Date(timeIntervalSince1970: Double($0) / 1000) }
    }
    public func date(_ key: String, default fallback: Date) -> Date { date(key) ?? fallback }

    // MARK: Encoding

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(values)) ?? Data()
    }

    public var jsonString: String { String(decoding: encoded(), as: UTF8.self) }

    public init?(json: String) {
        guard let decoded = try? JSONDecoder().decode([String: String].self, from: Data(json.utf8)) else { return nil }
        self.values = decoded
    }

    public var fingerprint: String { SyncFingerprint.of(encoded()) }

    public static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// A date as it looks after a round trip (for comparisons in tests).
    public static func roundTripped(_ date: Date) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds(date)) / 1000)
    }
}
