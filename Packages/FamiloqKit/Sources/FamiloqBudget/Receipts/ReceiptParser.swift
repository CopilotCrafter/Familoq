import Foundation
import FamiloqCore

public struct ParsedReceiptItem: Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    /// Line total (after any discount that belonged to this line).
    public var amount: Decimal
    public var quantity: Decimal?
    /// e.g. "groceries.fruits" - suggestion only, the user confirms.
    public var suggestedSubcategoryKey: String?
    public var classificationConfidence: Double

    public init(id: Int, name: String, amount: Decimal, quantity: Decimal? = nil, suggestedSubcategoryKey: String? = nil, classificationConfidence: Double = 0) {
        self.id = id
        self.name = name
        self.amount = amount
        self.quantity = quantity
        self.suggestedSubcategoryKey = suggestedSubcategoryKey
        self.classificationConfidence = classificationConfidence
    }
}

public struct ParsedVATLine: Equatable, Sendable {
    public var ratePercent: Decimal
    public var taxAmount: Decimal?
    public var rawText: String
}

public struct ParsedReceipt: Equatable, Sendable {
    public var merchant: String?
    /// Merchant rule that matched (normalised pattern), if any.
    public var matchedMerchantPattern: String?
    public var date: Date?
    public var hasTime: Bool
    public var total: Decimal?
    public var currencyCode: String?
    public var items: [ParsedReceiptItem]
    public var vat: [ParsedVATLine]
    public var rawLines: [String]

    public var itemsSum: Decimal { items.reduce(0) { $0 + $1.amount } }

    /// Items add up to the total (±0.02) - a strong sign the scan is complete.
    public var itemsMatchTotal: Bool {
        guard let total, !items.isEmpty else { return false }
        let diff = itemsSum - total
        return diff >= Decimal(string: "-0.02")! && diff <= Decimal(string: "0.02")!
    }

    /// Fields the user should double-check before saving.
    public var warnings: [String] {
        var result: [String] = []
        if merchant == nil { result.append("Merchant not recognised") }
        if date == nil { result.append("Date not recognised - today is used") }
        if total == nil { result.append("Total not recognised") }
        if total != nil && !items.isEmpty && !itemsMatchTotal {
            result.append("Items do not add up to the total")
        }
        return result
    }
}

/// Turns receipt text lines into structured data. Works fully offline and
/// never saves anything - the result is shown to the user for confirmation.
///
/// Tuned for German supermarket receipts (Lidl, Aldi, REWE, Edeka, …) and
/// generic English receipts:
///   "Bananen            2,20 A"     -> item
///   "2 x 1,29"                      -> quantity for the neighbouring item
///   "Rabatt            -0,50"       -> reduces the previous item
///   "SUMME EUR        43,28"        -> total
///   "A 7,00%  1,23  0,09  1,32"     -> VAT line
///   "27.09.26 14:32"                -> date and time
public enum ReceiptParser {
    // MARK: Patterns

    /// Price at the end of a line, optionally followed by currency and a tax
    /// class letter: "2,20 A", "1.234,56 €", "-0,50", "3.49 B *".
    private static let trailingPrice = try! NSRegularExpression(
        pattern: #"(-?\s?\d{1,5}(?:[.,]\d{3})*[.,]\d{2})\s*(?:€|EUR|USD|\$|CHF|£)?\s*(?:[A-Z0-9]{1,2}\b)?\s*\*?\s*$"#,
        options: [.caseInsensitive]
    )
    private static let anyPrice = try! NSRegularExpression(pattern: #"-?\d{1,5}(?:[.,]\d{3})*[.,]\d{2}"#)
    private static let quantityLine = try! NSRegularExpression(
        pattern: #"^\s*(\d+(?:[.,]\d+)?)\s*(?:st|stk|x|kg|g)?\s*[x×*]\s*(\d+[.,]\d{2})"#,
        options: [.caseInsensitive]
    )
    private static let percent = try! NSRegularExpression(pattern: #"(\d{1,2}(?:[.,]\d{1,2})?)\s?%"#)
    private static let dateDMY = try! NSRegularExpression(pattern: #"\b(\d{1,2})\.(\d{1,2})\.(\d{2,4})\b"#)
    private static let dateISO = try! NSRegularExpression(pattern: #"\b(20\d{2})-(\d{2})-(\d{2})\b"#)
    private static let dateSlash = try! NSRegularExpression(pattern: #"\b(\d{1,2})/(\d{1,2})/(\d{2,4})\b"#)
    private static let time = try! NSRegularExpression(pattern: #"\b([01]?\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?\b"#)

    private static let totalKeywords = [
        "zu zahlen", "zu zahlen eur", "summe", "gesamtbetrag", "gesamt", "endbetrag", "betrag",
        "total", "amount due", "grand total", "balance due"
    ]
    private static let notTotalKeywords = ["zwischensumme", "subtotal", "sub total", "netto", "mwst", "steuer", "tax"]

    /// Lines that are never items.
    private static let skipKeywords = [
        "summe", "gesamt", "total", "zu zahlen", "zwischensumme", "subtotal", "betrag", "gegeben",
        "ruckgeld", "rückgeld", "zuruck", "zurück", "wechselgeld", "change", "cash", "card", "karte",
        "ec-karte", "ec karte", "girocard", "kartenzahlung", "visa", "mastercard", "maestro", "amex",
        "kontaktlos", "contactless", "mwst", "ust", "netto", "brutto", "steuer", "tax", "vat",
        "datum", "uhrzeit", "kasse", "bon-nr", "bon nr", "beleg-nr", "belegnr", "beleg nr", "tse", "signatur", "transaktion",
        "terminal", "trace", "genehmigung", "autorisierung", "kundenbeleg", "danke", "thank",
        "www", "http", "tel", "fax", "strasse", "straße", "steuer-nr", "ust-id", "filiale",
        "payback", "punkte", "kassierer", "bediener", "zahlung", "payment", "receipt", "rechnung",
        "posten", "artikel", "anzahl", "eur/kg", "€/kg"
    ]

    // MARK: Parse

    public static func parse(lines rawLines: [String], calendar: Calendar = FamiloqCalendar.make(), now: Date = Date()) -> ParsedReceipt {
        let lines = rawLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let (merchant, pattern) = findMerchant(lines)
        let (date, hasTime) = findDate(lines, calendar: calendar, now: now)
        let currency = findCurrency(lines)
        let (total, totalIndex) = findTotal(lines)
        let vat = findVAT(lines)
        let items = findItems(lines, totalIndex: totalIndex)

        return ParsedReceipt(
            merchant: merchant,
            matchedMerchantPattern: pattern,
            date: date,
            hasTime: hasTime,
            total: total,
            currencyCode: currency,
            items: items,
            vat: vat,
            rawLines: lines
        )
    }

    // MARK: Merchant

    static func findMerchant(_ lines: [String]) -> (String?, String?) {
        let header = Array(lines.prefix(10))
        let rules = DefaultMerchantRules.all
        // 1. A known merchant anywhere in the header (longest pattern wins).
        var best: (line: String, pattern: String)?
        for line in header where trailingPriceValue(line) == nil {
            let normalised = " \(TextNormalizer.normalize(line)) "
            for rule in rules where normalised.contains(" \(rule.pattern) ") {
                if best == nil || rule.pattern.count > best!.pattern.count {
                    best = (line, rule.pattern)
                }
            }
        }
        if let best {
            return (displayName(forPattern: best.pattern, line: best.line), best.pattern)
        }
        // 2. First line that looks like a name (letters, not an address/date/price).
        for line in header {
            let letters = line.filter(\.isLetter).count
            guard letters >= 3 else { continue }
            let lower = line.lowercased()
            if skipKeywords.contains(where: { lower.contains($0) }) { continue }
            if firstMatch(dateDMY, in: line) != nil || firstMatch(trailingPrice, in: line) != nil { continue }
            if line.range(of: #"\d{5}"#, options: .regularExpression) != nil { continue } // postcode line
            return (line.trimmingCharacters(in: CharacterSet(charactersIn: "*-=# ")), nil)
        }
        return (nil, nil)
    }

    private static func displayName(forPattern pattern: String, line: String) -> String {
        // Keep the merchant's own spelling when the line is short ("REWE", "Lidl").
        let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: "*-=# "))
        if trimmed.count <= 24 && !trimmed.contains(where: \.isNumber) { return trimmed }
        return pattern.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    // MARK: Date & time

    static func findDate(_ lines: [String], calendar: Calendar, now: Date) -> (Date?, Bool) {
        var comps: DateComponents?
        for line in lines {
            if let m = firstMatch(dateDMY, in: line) {
                comps = DateComponents(year: normaliseYear(m[3]), month: Int(m[2]), day: Int(m[1]))
            } else if let m = firstMatch(dateISO, in: line) {
                comps = DateComponents(year: Int(m[1]), month: Int(m[2]), day: Int(m[3]))
            } else if let m = firstMatch(dateSlash, in: line), let a = Int(m[1]), let b = Int(m[2]) {
                // dd/mm unless impossible (US mm/dd when the second number > 12).
                comps = b > 12 ? DateComponents(year: normaliseYear(m[3]), month: a, day: b)
                               : DateComponents(year: normaliseYear(m[3]), month: b, day: a)
            }
            if var found = comps {
                guard let month = found.month, (1...12).contains(month),
                      let day = found.day, (1...31).contains(day),
                      let year = found.year, year >= 2000 else { comps = nil; continue }
                var hasTime = false
                // Time on the same line, or anywhere else on the receipt.
                let timeMatch = firstMatch(time, in: line) ?? lines.lazy.compactMap { firstMatch(time, in: $0) }.first
                if let t = timeMatch, var h = Int(t[1]), let mi = Int(t[2]) {
                    // 12-hour clock on English receipts ("3:45 PM").
                    let timeLine = lines.first { $0.contains(t[0]) } ?? line
                    let upper = timeLine.uppercased()
                    let isPM = upper.range(of: #"\d\s?PM\b"#, options: .regularExpression) != nil
                    let isAM = upper.range(of: #"\d\s?AM\b"#, options: .regularExpression) != nil
                    if isPM && h < 12 { h += 12 }
                    if isAM && h == 12 { h = 0 }
                    found.hour = h
                    found.minute = mi
                    hasTime = true
                } else {
                    found.hour = 12
                }
                guard let date = calendar.date(from: found) else { comps = nil; continue }
                // Receipts are never from the future (allow 1 day clock skew).
                if date > now.addingTimeInterval(86_400) { comps = nil; continue }
                return (date, hasTime)
            }
        }
        return (nil, false)
    }

    private static func normaliseYear(_ text: String) -> Int? {
        guard let value = Int(text) else { return nil }
        return value < 100 ? 2000 + value : value
    }

    // MARK: Currency

    static func findCurrency(_ lines: [String]) -> String? {
        let text = " " + lines.joined(separator: " ").uppercased() + " "
        let markers: [(String, [String])] = [
            ("EUR", ["EUR", "€"]),
            ("USD", ["USD", "US$", "$"]),
            ("GBP", ["GBP", "£"]),
            ("CHF", [" CHF", "SFR"]),
            ("CZK", ["CZK", "KČ"]),
            ("PLN", ["PLN", "ZŁ"]),
            ("INR", ["INR", "₹", " RS."]),
            ("SEK", ["SEK"]),
            ("NOK", ["NOK"]),
            ("DKK", ["DKK"]),
            ("HUF", ["HUF", " FT "]),
            ("TRY", ["TRY", "₺"])
        ]
        var best: (code: String, count: Int)?
        for (code, tokens) in markers {
            let count = tokens.reduce(0) { $0 + text.components(separatedBy: $1).count - 1 }
            if count > 0 && (best == nil || count > best!.count) { best = (code, count) }
        }
        return best?.code
    }

    // MARK: Total

    static func findTotal(_ lines: [String]) -> (Decimal?, Int?) {
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard totalKeywords.contains(where: { hasPhrase($0, in: lower) }),
                  !notTotalKeywords.contains(where: { hasPhrase($0, in: lower) }) else { continue }
            if let price = trailingPriceValue(line) {
                return (price, index)
            }
            // Keyword on one line, amount on the next.
            if index + 1 < lines.count, let price = trailingPriceValue(lines[index + 1]), lines[index + 1].filter(\.isLetter).count <= 4 {
                return (price, index)
            }
        }
        return (nil, nil)
    }

    // MARK: VAT

    static func findVAT(_ lines: [String]) -> [ParsedVATLine] {
        var result: [ParsedVATLine] = []
        for line in lines {
            let lower = line.lowercased()
            guard let pm = firstMatch(percent, in: line), let rate = DecimalParser.parse(pm[1]) else { continue }
            let looksLikeVAT = ["mwst", "ust", "steuer", "vat", "tax", "netto"].contains { lower.contains($0) }
                || line.range(of: #"^\s*[A-D]\s*[=:]?\s*\d"#, options: .regularExpression) != nil
            guard looksLikeVAT, rate > 0, rate < 30 else { continue }
            // Remove the percentage itself before collecting amounts.
            let withoutRate = percent.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: " ")
            let amounts = allMatches(anyPrice, in: withoutRate).compactMap { DecimalParser.parse($0) }
            let tax: Decimal?
            switch amounts.count {
            case 0: tax = nil
            case 1: tax = amounts[0]
            case 2: tax = amounts[0] < amounts[1] ? amounts[0] : amounts[1]
            default: tax = amounts[amounts.count - 2] // net, tax, gross
            }
            if !result.contains(where: { $0.ratePercent == rate }) {
                result.append(ParsedVATLine(ratePercent: rate, taxAmount: tax, rawText: line))
            }
        }
        return result
    }

    // MARK: Items

    static func findItems(_ lines: [String], totalIndex: Int?) -> [ParsedReceiptItem] {
        let end = totalIndex ?? lines.count
        var items: [ParsedReceiptItem] = []
        var pendingQuantity: Decimal?
        var nextID = 0

        for line in lines.prefix(end) {
            let lower = line.lowercased()

            // "2 x 1,29" - belongs to the neighbouring item.
            if let q = firstMatch(quantityLine, in: line) {
                // Letters left after removing the quantity expression = an item name.
                let rest = line.replacingOccurrences(of: q[0], with: "")
                let hasName = rest.filter(\.isLetter).count > 2
                if !hasName {
                    let quantity = DecimalParser.parse(q[1])
                    if let last = items.indices.last, items[last].quantity == nil, pendingQuantity == nil {
                        items[last].quantity = quantity
                    } else {
                        pendingQuantity = quantity
                    }
                    continue
                }
            }

            guard let price = trailingPriceValue(line) else { continue }
            if skipKeywords.contains(where: { hasPhrase($0, in: lower) }) { continue }
            if firstMatch(dateDMY, in: line) != nil { continue }

            let name = itemName(from: line)
            let isDiscount = price < 0 || ["rabatt", "preisvorteil", "coupon", "discount", "nachlass", "aktion"].contains { lower.contains($0) }

            if isDiscount, let last = items.indices.last {
                items[last].amount += price < 0 ? price : -price
                continue
            }
            guard name.filter(\.isLetter).count >= 2, price > 0 else { continue }

            let classification = GroceryItemClassifier.classify(name)
            items.append(ParsedReceiptItem(
                id: nextID,
                name: name,
                amount: price,
                quantity: pendingQuantity,
                suggestedSubcategoryKey: classification?.subcategoryKey,
                classificationConfidence: classification?.confidence ?? 0
            ))
            nextID += 1
            pendingQuantity = nil
        }
        return items
    }

    private static func itemName(from line: String) -> String {
        let range = NSRange(line.startIndex..., in: line)
        var name = trailingPrice.stringByReplacingMatches(in: line, range: range, withTemplate: "")
        // Drop leading article numbers / quantities like "1234567 " or "2x ".
        name = name.replacingOccurrences(of: #"^\s*\d{4,}\s+"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: #"^\s*\d+\s*[x×]\s+"#, with: "", options: .regularExpression)
        return name.trimmingCharacters(in: CharacterSet(charactersIn: " .*-:"))
    }

    // MARK: Helpers

    static func trailingPriceValue(_ line: String) -> Decimal? {
        guard let m = firstMatch(trailingPrice, in: line) else { return nil }
        return DecimalParser.parse(m[1].replacingOccurrences(of: " ", with: ""))
    }

    /// Whole-word / whole-phrase match: "total" matches "TOTAL 12,50" but not "Totalreiniger".
    private static func hasPhrase(_ phrase: String, in lower: String) -> Bool {
        let padded = " " + lower.replacingOccurrences(of: #"[^\p{L}\p{N}/-]"#, with: " ", options: .regularExpression) + " "
        let collapsed = padded.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return collapsed.contains(" \(phrase) ")
    }

    /// Capture groups of the first match (index 0 = whole match).
    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> [String]? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { i in
            guard let r = Range(match.range(at: i), in: text) else { return "" }
            return String(text[r])
        }
    }

    private static func allMatches(_ regex: NSRegularExpression, in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { m in
            Range(m.range, in: text).map { String(text[$0]) }
        }
    }
}
