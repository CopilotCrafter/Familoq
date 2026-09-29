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
    /// Best guess of the receipt currency (nil = not found). Check
    /// `currency.needsConfirmation` before trusting it.
    public var currencyCode: String?
    /// How sure the detection is, and which currencies to offer the user.
    public var currency: CurrencyDetection
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
        switch currency.confidence {
        case .certain: break
        case .likely: result.append("Please confirm the currency")
        case .unknown: result.append("Currency not recognised - please choose it")
        }
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
/// generic receipts from other countries (currency: `CurrencyDetector`;
/// whole-number prices for JPY, KRW, HUF, …):
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
    private static let currencySuffix = #"(?:[€£$¥￥₹₩₺₽₪฿₫₱円원]|EUR|USD|CHF|GBP|JPY|KRW|HUF|SEK|NOK|DKK|PLN|CZK|kr\.?|zł|Kč|Ft|lei|TL|,-|\.-)?"#
    private static let trailingPrice = try! NSRegularExpression(
        pattern: #"(-?\s?\d{1,5}(?:[.,]\d{3})*[.,]\d{2})\s*"# + currencySuffix + #"\s*(?:[A-Z0-9]{1,2}\b)?\s*\*?\s*$"#,
        options: [.caseInsensitive]
    )
    /// Whole-amount currencies: a price with decimals that is really one ("1 290,00 Ft").
    private static let strictDecimalPrice = try! NSRegularExpression(
        pattern: #"(-?\s?(?:\d{1,3}(?:[.,' ]\d{3})+[.,]\d{2}|\d{1,7}[.,]\d{2}))(?!\d)\s*"# + currencySuffix + #"\s*(?:[A-Z]\b)?\s*\*?\s*$"#,
        options: [.caseInsensitive]
    )
    /// Whole-amount currencies: "¥1,280", "12 990 Ft", "35.000 ₫", "4500원".
    private static let wholePrice = try! NSRegularExpression(
        pattern: #"(-?\s?(?:\d{1,3}(?:[.,' ]\d{3})+|\d{1,7}))(?![.,]?\d)\s*"# + currencySuffix + #"\s*(?:[A-Z]\b)?\s*\*?\s*$"#,
        options: [.caseInsensitive]
    )
    private static let anyPrice = try! NSRegularExpression(pattern: #"-?\d{1,5}(?:[.,]\d{3})*[.,]\d{2}"#)
    private static let quantityLine = try! NSRegularExpression(
        pattern: #"^\s*(\d+(?:[.,]\d+)?)\s*(?:st|stk|x|kg|g|l|ltr)?\s*[x×*]\s*(\d+[.,]\d{2})"#,
        options: [.caseInsensitive]
    )
    private static let percent = try! NSRegularExpression(pattern: #"(\d{1,2}(?:[.,]\d{1,2})?)\s?%"#)
    private static let dateDMY = try! NSRegularExpression(pattern: #"\b(\d{1,2})\.(\d{1,2})\.(\d{2,4})\b"#)
    private static let dateISO = try! NSRegularExpression(pattern: #"\b(20\d{2})-(\d{2})-(\d{2})\b"#)
    /// Year first: "2026年9月20日", "2026.09.20", "2026/09/20" (Asia, Hungary, …).
    private static let dateYMD = try! NSRegularExpression(pattern: #"\b(20\d{2})\s?[./年]\s?(\d{1,2})\s?[./月]\s?(\d{1,2})(?:日|\b)"#)
    private static let dateSlash = try! NSRegularExpression(pattern: #"\b(\d{1,2})/(\d{1,2})/(\d{2,4})\b"#)
    private static let time = try! NSRegularExpression(pattern: #"\b([01]?\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?\b"#)

    private static let totalKeywords = [
        "zu zahlen", "zu zahlen eur", "summe", "gesamtbetrag", "gesamt", "endbetrag", "betrag",
        "total", "amount due", "grand total", "balance due",
        // other languages
        "totale", "importo", "importe", "a pagar", "à payer", "a payer", "montant", "net à payer",
        "totaal", "te betalen", "totalt", "att betala", "at betale", "å betale", "yhteensä",
        "suma", "razem", "do zapłaty", "celkem", "spolu", "összesen", "fizetendő", "toplam",
        "σύνολο", "итого", "合計", "お会計", "合计", "總計", "总计", "합계", "결제금액"
    ]
    private static let notTotalKeywords = [
        "zwischensumme", "subtotal", "sub total", "netto", "mwst", "steuer", "tax",
        "subtotale", "sous-total", "sous total", "subtotaal", "delsumma", "mellomsum",
        "小計", "小计", "소계", "消費税", "부가세"
    ]

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
        "posten", "artikel", "anzahl", "eur/kg", "€/kg",
        // other languages
        "totale", "totaal", "totalt", "razem", "celkem", "összesen", "toplam", "iva", "tva", "btw",
        "moms", "mva", "gst", "hst", "pst", "cgst", "sgst", "sous-total", "subtotale",
        "合計", "小計", "合计", "小计", "お釣り", "お預り", "합계", "소계", "부가세"
    ]

    // MARK: Parse

    /// - Parameter currency: the currency the user chose; skips detection
    ///   (amounts are then read in that currency's style, e.g. whole yen).
    public static func parse(lines rawLines: [String], calendar: Calendar = FamiloqCalendar.make(), now: Date = Date(), currency forcedCurrency: String? = nil) -> ParsedReceipt {
        let lines = rawLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let (merchant, pattern) = findMerchant(lines)
        let (date, hasTime) = findDate(lines, calendar: calendar, now: now)
        let currency = forcedCurrency.map { CurrencyDetection(code: CurrencyInfo.normalize($0), confidence: .certain, candidates: [CurrencyInfo.normalize($0)]) }
            ?? CurrencyDetector.detect(lines: lines)
        let wholeUnits = CurrencyDetector.usesWholeAmounts(currency.code)
        let (total, totalIndex) = findTotal(lines, wholeUnits: wholeUnits)
        let vat = findVAT(lines)
        let items = findItems(lines, totalIndex: totalIndex, wholeUnits: wholeUnits)

        return ParsedReceipt(
            merchant: merchant,
            matchedMerchantPattern: pattern,
            date: date,
            hasTime: hasTime,
            total: total,
            currencyCode: currency.code,
            currency: currency,
            items: items,
            vat: vat,
            rawLines: lines
        )
    }

    /// Reads OCR fragments. Uses the normal lines; when their items do not
    /// add up to the total, a second reading that pairs the price column with
    /// the names in order (curled paper, uneven angle) is tried.
    public static func parse(fragments: [OCRFragment], calendar: Calendar = FamiloqCalendar.make(), now: Date = Date()) -> ParsedReceipt {
        let geometric = parse(lines: ReceiptLineAssembler.lines(from: fragments), calendar: calendar, now: now)
        if geometric.itemsMatchTotal { return geometric }
        guard let alternative = ReceiptLineAssembler.columnPairedLines(from: fragments) else { return geometric }
        let paired = parse(lines: alternative, calendar: calendar, now: now)
        if paired.itemsMatchTotal { return paired }
        if paired.total != nil && geometric.total == nil { return paired }
        if let total = paired.total, total == geometric.total {
            let before = abs(NSDecimalNumber(decimal: geometric.itemsSum - total).doubleValue)
            let after = abs(NSDecimalNumber(decimal: paired.itemsSum - total).doubleValue)
            if after < before { return paired }
        }
        return geometric
    }

    static func isTotalLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return totalKeywords.contains { hasPhrase($0, in: lower) } && !notTotalKeywords.contains { hasPhrase($0, in: lower) }
    }

    static func isQuantityLine(_ line: String) -> Bool {
        guard let q = firstMatch(quantityLine, in: line) else { return false }
        let rest = line.replacingOccurrences(of: q[0], with: "").lowercased()
            .replacingOccurrences(of: #"eur|€|/|kg|stk|st\b"#, with: "", options: .regularExpression)
        return rest.filter(\.isLetter).count <= 2
    }

    /// "1,254" (kg) is 1.254 - quantities never have thousands separators.
    static func parseQuantity(_ text: String) -> Decimal? {
        Decimal(string: text.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
    }

    static func containsDate(_ line: String) -> Bool {
        firstMatch(dateDMY, in: line) != nil || firstMatch(dateYMD, in: line) != nil || firstMatch(dateISO, in: line) != nil
    }

    static func isSkipLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return skipKeywords.contains { hasPhrase($0, in: lower) }
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
            // Whole words: "Bäckerei Mustermann" is not skipped for "ust".
            if skipKeywords.contains(where: { hasPhrase($0, in: lower) }) { continue }
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
            } else if let m = firstMatch(dateYMD, in: line) {
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
        CurrencyDetector.detect(lines: lines).code
    }

    // MARK: Total

    static func findTotal(_ lines: [String], wholeUnits: Bool = false) -> (Decimal?, Int?) {
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard totalKeywords.contains(where: { hasPhrase($0, in: lower) }),
                  !notTotalKeywords.contains(where: { hasPhrase($0, in: lower) }) else { continue }
            if let price = trailingPriceValue(line, wholeUnits: wholeUnits) {
                return (price, index)
            }
            // Keyword on one line, amount on the next.
            if index + 1 < lines.count, let price = trailingPriceValue(lines[index + 1], wholeUnits: wholeUnits), lines[index + 1].filter(\.isLetter).count <= 4 {
                return (price, index)
            }
        }
        return repeatedTotal(lines, wholeUnits: wholeUnits)
    }

    /// No "Summe" line read: the total is usually printed several times
    /// (sum, card payment, card slip, VAT table). The largest amount that
    /// appears at least twice and equals the prices above it is the total.
    static func repeatedTotal(_ lines: [String], wholeUnits: Bool) -> (Decimal?, Int?) {
        var firstIndex: [Decimal: Int] = [:]
        var count: [Decimal: Int] = [:]
        for (index, line) in lines.enumerated() {
            for text in allMatches(anyPrice, in: line) {
                guard let value = DecimalParser.parse(text), value > 0 else { continue }
                count[value, default: 0] += 1
                if firstIndex[value] == nil { firstIndex[value] = index }
            }
        }
        for value in count.filter({ $0.value >= 2 }).keys.sorted(by: >) {
            guard let index = firstIndex[value] else { continue }
            let sum = findItems(lines, totalIndex: index, wholeUnits: wholeUnits).reduce(Decimal(0)) { $0 + $1.amount }
            let diff = sum - value
            if diff >= Decimal(string: "-0.02")!, diff <= Decimal(string: "0.02")! {
                return (value, index)
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

    static func findItems(_ lines: [String], totalIndex: Int?, wholeUnits: Bool = false) -> [ParsedReceiptItem] {
        let end = totalIndex ?? lines.count
        var items: [ParsedReceiptItem] = []
        var pendingQuantity: Decimal?
        /// A name line without a price ("Äpfel Elstar") whose price is on the
        /// quantity line below ("1,254 kg x 2,49 EUR/kg   3,12 A").
        var pendingName: String?
        var nextID = 0

        for line in lines.prefix(end) {
            let lower = line.lowercased()

            // "2 x 1,29" - belongs to the neighbouring item.
            if let q = firstMatch(quantityLine, in: line) {
                // Letters left after removing the quantity expression = an item name.
                // "2,672 kg x 1,99 EUR/kg": units are not a name.
                let restText = line.replacingOccurrences(of: q[0], with: "")
                let rest = restText.lowercased()
                    .replacingOccurrences(of: #"eur|€|/|kg|stk|st\b"#, with: "", options: .regularExpression)
                let hasName = rest.filter(\.isLetter).count > 2
                if !hasName {
                    let quantity = parseQuantity(q[1])
                    // The line total is on the quantity line; the name was the line above.
                    if let name = pendingName, let lineTotal = trailingPriceValue(restText, wholeUnits: wholeUnits), lineTotal > 0 {
                        let classification = GroceryItemClassifier.classify(name)
                        items.append(ParsedReceiptItem(
                            id: nextID, name: name, amount: lineTotal, quantity: quantity,
                            suggestedSubcategoryKey: classification?.subcategoryKey,
                            classificationConfidence: classification?.confidence ?? 0))
                        nextID += 1
                        pendingName = nil
                        pendingQuantity = nil
                        continue
                    }
                    if let last = items.indices.last, items[last].quantity == nil, pendingQuantity == nil {
                        items[last].quantity = quantity
                    } else {
                        pendingQuantity = quantity
                    }
                    continue
                }
            }

            guard let price = trailingPriceValue(line, wholeUnits: wholeUnits) else {
                let name = itemName(from: line, wholeUnits: wholeUnits)
                let looksLikeName = name.filter(\.isLetter).count >= 3
                    && !skipKeywords.contains(where: { hasPhrase($0, in: lower) })
                    && firstMatch(dateDMY, in: line) == nil
                pendingName = looksLikeName ? name : nil
                continue
            }
            pendingName = nil
            // A negative amount is always a discount ("PAYBACK Coupon -0,20").
            if price < 0, let last = items.indices.last {
                items[last].amount += price
                continue
            }
            if skipKeywords.contains(where: { hasPhrase($0, in: lower) }) { continue }
            if firstMatch(dateDMY, in: line) != nil || firstMatch(dateYMD, in: line) != nil { continue }
            // Whole-amount receipts: "14:05" would otherwise look like a price of 5.
            if wholeUnits && firstMatch(time, in: line) != nil { continue }

            let name = itemName(from: line, wholeUnits: wholeUnits)
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

    private static func itemName(from line: String, wholeUnits: Bool) -> String {
        var name = line
        if let match = trailingPriceMatch(line, wholeUnits: wholeUnits), let range = name.range(of: match.text, options: .backwards) {
            name.removeSubrange(range)
        }
        // Drop leading article numbers / quantities like "1234567 " or "2x ".
        name = name.replacingOccurrences(of: #"^\s*\d{4,}\s+"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: #"^\s*\d+\s*[x×]\s+"#, with: "", options: .regularExpression)
        return name.trimmingCharacters(in: CharacterSet(charactersIn: " .*-:€£$¥￥₹₩₺₽₪฿₫₱"))
    }

    // MARK: Helpers

    static func trailingPriceValue(_ line: String, wholeUnits: Bool = false) -> Decimal? {
        trailingPriceMatch(line, wholeUnits: wholeUnits)?.value
    }

    /// The price at the end of a line and the text it occupies.
    private static func trailingPriceMatch(_ line: String, wholeUnits: Bool) -> (value: Decimal, text: String)? {
        let patterns = wholeUnits ? [strictDecimalPrice, wholePrice] : [trailingPrice]
        for pattern in patterns {
            guard let m = firstMatch(pattern, in: line) else { continue }
            let digits = m[1].replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "'", with: "")
            if let value = DecimalParser.parse(digits) { return (value, m[0]) }
        }
        return nil
    }

    /// Whole-word / whole-phrase match: "total" matches "TOTAL 12,50" but not "Totalreiniger".
    private static func hasPhrase(_ phrase: String, in lower: String) -> Bool {
        // Chinese / Japanese / Korean are written without spaces.
        if phrase.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) { return lower.contains(phrase) }
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
