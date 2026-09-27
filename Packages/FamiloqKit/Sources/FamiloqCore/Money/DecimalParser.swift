import Foundation

/// Parses amounts typed by users or read from receipts.
///
/// Accepts both German and English notation:
///   "12,50"      -> 12.50
///   "12.50"      -> 12.50
///   "1.234,56"   -> 1234.56
///   "1,234.56"   -> 1234.56
///   "1.234"      -> 1234        (single separator followed by exactly 3 digits = thousands)
///   "€ 5,50"     -> 5.50
public enum DecimalParser {
    public static func parse(_ text: String) -> Decimal? {
        let allowed = Set("0123456789.,-")
        var s = String(text.filter { allowed.contains($0) })
        guard !s.isEmpty else { return nil }

        var negative = false
        if s.hasPrefix("-") {
            negative = true
            s.removeFirst()
        }
        guard !s.contains("-") else { return nil }

        let commaCount = s.filter { $0 == "," }.count
        let dotCount = s.filter { $0 == "." }.count

        var normalized: String
        if commaCount > 0 && dotCount > 0 {
            // The separator that appears last is the decimal separator.
            let lastComma = s.lastIndex(of: ",")!
            let lastDot = s.lastIndex(of: ".")!
            if lastComma > lastDot {
                normalized = s.replacingOccurrences(of: ".", with: "")
                normalized = normalized.replacingOccurrences(of: ",", with: ".")
            } else {
                normalized = s.replacingOccurrences(of: ",", with: "")
            }
        } else if commaCount + dotCount == 0 {
            normalized = s
        } else {
            let separator: Character = commaCount > 0 ? "," : "."
            let count = max(commaCount, dotCount)
            let parts = s.split(separator: separator, omittingEmptySubsequences: false)
            if count > 1 {
                // "1.234.567" -> thousands separators only.
                normalized = parts.joined()
            } else if let last = parts.last, last.count == 3, let first = parts.first, !first.isEmpty, first != "0" {
                // "1.234" / "1,234" -> thousands separator.
                normalized = parts.joined()
            } else {
                normalized = parts.joined(separator: ".")
            }
        }

        if normalized.hasPrefix(".") { normalized = "0" + normalized }
        if normalized.hasSuffix(".") { normalized.removeLast() }
        guard !normalized.isEmpty,
              normalized.filter({ $0 == "." }).count <= 1,
              let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }

        return negative ? -value : value
    }
}
