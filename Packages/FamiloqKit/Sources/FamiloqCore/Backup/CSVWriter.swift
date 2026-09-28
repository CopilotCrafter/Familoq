import Foundation

/// CSV that opens correctly in Excel and Numbers.
///   * separator ";" and decimal comma where the locale uses a decimal comma
///     (German Excel), otherwise "," and decimal point
///   * UTF-8 with byte order mark, CRLF line ends, fields quoted when needed
public struct CSVWriter: Sendable {
    public let separator: Character
    public let decimalComma: Bool

    public init(locale: Locale = .current) {
        let comma = (locale.decimalSeparator ?? ".") == ","
        self.decimalComma = comma
        self.separator = comma ? ";" : ","
    }

    public init(separator: Character, decimalComma: Bool) {
        self.separator = separator
        self.decimalComma = decimalComma
    }

    public func field(_ text: String) -> String {
        let needsQuotes = text.contains(separator) || text.contains("\"") || text.contains("\n") || text.contains("\r")
        let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }

    public func number(_ value: Decimal?, places: Int = 2) -> String {
        guard let value else { return "" }
        var rounded = Decimal()
        var input = value
        NSDecimalRound(&rounded, &input, places, .plain)
        let text = NSDecimalNumber(decimal: rounded).stringValue
        let fixed = Self.padFraction(text, places: places)
        return decimalComma ? fixed.replacingOccurrences(of: ".", with: ",") : fixed
    }

    public func line(_ fields: [String]) -> String {
        fields.map(field).joined(separator: String(separator)) + "\r\n"
    }

    public func document(header: [String], rows: [[String]]) -> Data {
        var text = line(header)
        for row in rows { text += line(row) }
        return Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
    }

    private static func padFraction(_ text: String, places: Int) -> String {
        guard places > 0 else { return text }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let whole = String(parts[0])
        let fraction = parts.count > 1 ? String(parts[1]) : ""
        return whole + "." + fraction.padding(toLength: places, withPad: "0", startingAt: 0)
    }
}
