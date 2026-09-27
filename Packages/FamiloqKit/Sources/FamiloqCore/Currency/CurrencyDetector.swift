import Foundation

/// Result of looking for the currency on a receipt from any country.
public struct CurrencyDetection: Equatable, Sendable {
    public enum Confidence: String, Equatable, Sendable {
        /// An unambiguous marker was found ("EUR", "€", "£", "zł", "円" …).
        case certain
        /// Only a shared symbol ("$", "kr", "¥") or indirect hints (phone
        /// prefix, web address, tax name) were found - the user must confirm.
        case likely
        /// Nothing found - the user must choose.
        case unknown
    }

    /// Best guess, nil when nothing was found.
    public var code: String?
    public var confidence: Confidence
    /// Currencies to offer first when asking the user (best guess first).
    public var candidates: [String]

    public init(code: String?, confidence: Confidence, candidates: [String]) {
        self.code = code
        self.confidence = confidence
        self.candidates = candidates
    }

    /// The app asks "Which currency is this receipt in?" before saving.
    public var needsConfirmation: Bool { confidence != .certain }

    public static let unknown = CurrencyDetection(code: nil, confidence: .unknown, candidates: [])
}

/// Detects the currency of a receipt from anywhere in the world.
///
/// Order of evidence:
///   1. ISO codes written on the receipt ("EUR", "USD", "CHF" …) and symbols
///      that belong to exactly one currency ("€", "£", "₹", "zł", "Kč", "円" …)
///   2. Shared symbols ("$" -> USD/CAD/AUD/…, "kr" -> SEK/NOK/DKK/ISK,
///      "¥" -> JPY/CNY), narrowed down by hints
///   3. Hints: phone prefix (+44), web address (.co.uk), tax names (HST, MVA, CGST)
///
/// Anything that is not certain is confirmed by the user in the app.
public enum CurrencyDetector {
    // MARK: Evidence tables

    /// ISO codes matched as whole uppercase words. Codes that are also common
    /// English/receipt words (ALL, TOP, CUP, PEN, SOS, MAD, TRY, BAM, …) are
    /// deliberately missing - they are found through their symbols instead.
    static let isoCodes: [String] = [
        "EUR", "USD", "GBP", "CHF", "PLN", "CZK", "HUF", "SEK", "NOK", "DKK", "ISK", "RON",
        "BGN", "RSD", "UAH", "RUB", "INR", "JPY", "CNY", "RMB", "HKD", "TWD", "KRW", "SGD",
        "MYR", "THB", "VND", "IDR", "PHP", "AUD", "NZD", "CAD", "MXN", "BRL", "ARS", "CLP",
        "COP", "ZAR", "AED", "SAR", "QAR", "KWD", "BHD", "OMR", "JOD", "ILS", "EGP",
        "TND", "KES", "NGN", "PKR", "LKR", "NPR", "BDT", "GEL", "AZN", "KZT", "MKD"
    ]

    /// Symbols / words that identify exactly one currency. Matched case-sensitively.
    static let uniqueMarkers: [(pattern: String, code: String)] = [
        (#"€"#, "EUR"),
        (#"£"#, "GBP"),
        (#"₹"#, "INR"),
        (#"₺"#, "TRY"),
        (#"\bTL\b"#, "TRY"),
        (#"₩"#, "KRW"),
        (#"원"#, "KRW"),
        (#"₽"#, "RUB"),
        (#"₪"#, "ILS"),
        (#"฿"#, "THB"),
        (#"₫"#, "VND"),
        (#"₱"#, "PHP"),
        (#"₴"#, "UAH"),
        (#"₾"#, "GEL"),
        (#"₸"#, "KZT"),
        (#"円"#, "JPY"),
        (#"元"#, "CNY"),
        (#"人民币"#, "CNY"),
        (#"(?i)zł"#, "PLN"),
        (#"(?i)\bzl\b"#, "PLN"),
        (#"Kč"#, "CZK"),
        (#"\bFt\b"#, "HUF"),
        (#"(?i)\blei\b"#, "RON"),
        (#"\bSFr\b|\bsFr\b"#, "CHF"),
        (#"R\$"#, "BRL"),
        (#"US\$"#, "USD"),
        (#"C\$|CA\$"#, "CAD"),
        (#"A\$|AU\$"#, "AUD"),
        (#"NZ\$"#, "NZD"),
        (#"S\$"#, "SGD"),
        (#"HK\$"#, "HKD"),
        (#"NT\$"#, "TWD"),
        (#"MX\$"#, "MXN"),
        (#"\bRp\.?\s?\d"#, "IDR"),
        (#"\bRM\s?\d"#, "MYR"),
        (#"\bAED\b|\bDhs?\.?\s?\d|د\.إ"#, "AED"),
        (#"ر\.س"#, "SAR"),
        (#"\bKSh\b"#, "KES"),
        (#"₦"#, "NGN"),
        (#"(?i)\bден\b"#, "MKD"),
        (#"\bRSD\b|\bдин\b"#, "RSD"),
        (#"\bлв\b"#, "BGN")
    ]

    /// Symbols shared by several currencies (most common first).
    static let sharedMarkers: [(pattern: String, codes: [String])] = [
        (#"\$"#, ["USD", "CAD", "AUD", "NZD", "SGD", "HKD", "MXN"]),
        (#"(?i)(?<![\p{L}])kr\.?(?![\p{L}])"#, ["SEK", "NOK", "DKK", "ISK"]),
        (#"¥|￥"#, ["JPY", "CNY"]),
        (#"(?i)\bRs\.?\s?\d"#, ["INR", "PKR", "LKR", "NPR"]),
        (#"\bFr\.\s?\d"#, ["CHF"])
    ]

    /// Indirect hints: phone prefix, web address, tax name.
    static let hints: [(pattern: String, codes: [String])] = [
        // Phone prefixes (longer ones first)
        (#"\+ ?353\b"#, ["EUR"]), (#"\+ ?351\b"#, ["EUR"]), (#"\+ ?358\b"#, ["EUR"]),
        (#"\+ ?352\b"#, ["EUR"]), (#"\+ ?356\b"#, ["EUR"]), (#"\+ ?357\b"#, ["EUR"]),
        (#"\+ ?370\b"#, ["EUR"]), (#"\+ ?371\b"#, ["EUR"]), (#"\+ ?372\b"#, ["EUR"]),
        (#"\+ ?385\b"#, ["EUR"]), (#"\+ ?386\b"#, ["EUR"]), (#"\+ ?421\b"#, ["EUR"]),
        (#"\+ ?420\b"#, ["CZK"]), (#"\+ ?354\b"#, ["ISK"]), (#"\+ ?852\b"#, ["HKD"]),
        (#"\+ ?971\b"#, ["AED"]), (#"\+ ?966\b"#, ["SAR"]), (#"\+ ?972\b"#, ["ILS"]),
        (#"\+ ?380\b"#, ["UAH"]), (#"\+ ?886\b"#, ["TWD"]), (#"\+ ?359\b"#, ["BGN"]),
        (#"\+ ?381\b"#, ["RSD"]),
        (#"\+ ?49\b"#, ["EUR"]), (#"\+ ?33\b"#, ["EUR"]), (#"\+ ?39\b"#, ["EUR"]),
        (#"\+ ?34\b"#, ["EUR"]), (#"\+ ?31\b"#, ["EUR"]), (#"\+ ?32\b"#, ["EUR"]),
        (#"\+ ?43\b"#, ["EUR"]), (#"\+ ?30\b"#, ["EUR"]),
        (#"\+ ?44\b"#, ["GBP"]), (#"\+ ?41\b"#, ["CHF"]), (#"\+ ?46\b"#, ["SEK"]),
        (#"\+ ?47\b"#, ["NOK"]), (#"\+ ?45\b"#, ["DKK"]), (#"\+ ?48\b"#, ["PLN"]),
        (#"\+ ?36\b"#, ["HUF"]), (#"\+ ?40\b"#, ["RON"]), (#"\+ ?90\b"#, ["TRY"]),
        (#"\+ ?61\b"#, ["AUD"]), (#"\+ ?64\b"#, ["NZD"]), (#"\+ ?65\b"#, ["SGD"]),
        (#"\+ ?60\b"#, ["MYR"]), (#"\+ ?66\b"#, ["THB"]), (#"\+ ?62\b"#, ["IDR"]),
        (#"\+ ?63\b"#, ["PHP"]), (#"\+ ?84\b"#, ["VND"]), (#"\+ ?81\b"#, ["JPY"]),
        (#"\+ ?82\b"#, ["KRW"]), (#"\+ ?86\b"#, ["CNY"]), (#"\+ ?91\b"#, ["INR"]),
        (#"\+ ?52\b"#, ["MXN"]), (#"\+ ?55\b"#, ["BRL"]), (#"\+ ?27\b"#, ["ZAR"]),
        (#"\+ ?20\b"#, ["EGP"]), (#"\+ ?1\b"#, ["USD", "CAD"]),
        // Web / e-mail addresses
        (#"(?i)\.(de|fr|it|es|nl|at|be|ie|pt|fi|gr|lu|sk|si|ee|lv|lt|hr|mt|cy)\b"#, ["EUR"]),
        (#"(?i)\.co\.uk\b|\.uk\b"#, ["GBP"]),
        (#"(?i)\.ch\b"#, ["CHF"]), (#"(?i)\.se\b"#, ["SEK"]), (#"(?i)\.no\b"#, ["NOK"]),
        (#"(?i)\.dk\b"#, ["DKK"]), (#"(?i)\.is\b"#, ["ISK"]), (#"(?i)\.pl\b"#, ["PLN"]),
        (#"(?i)\.cz\b"#, ["CZK"]), (#"(?i)\.hu\b"#, ["HUF"]), (#"(?i)\.ro\b"#, ["RON"]),
        (#"(?i)\.ca\b"#, ["CAD"]), (#"(?i)\.com\.au\b|\.au\b"#, ["AUD"]),
        (#"(?i)\.co\.nz\b|\.nz\b"#, ["NZD"]), (#"(?i)\.sg\b"#, ["SGD"]),
        (#"(?i)\.hk\b"#, ["HKD"]), (#"(?i)\.mx\b"#, ["MXN"]), (#"(?i)\.jp\b"#, ["JPY"]),
        (#"(?i)\.cn\b"#, ["CNY"]), (#"(?i)\.in\b"#, ["INR"]), (#"(?i)\.co\.za\b"#, ["ZAR"]),
        (#"(?i)\.ae\b"#, ["AED"]), (#"(?i)\.tr\b"#, ["TRY"]), (#"(?i)\.th\b"#, ["THB"]),
        // Tax names
        (#"\bHST\b|\bPST\b|\bQST\b|\bTPS\b|\bTVQ\b"#, ["CAD"]),
        (#"\bCGST\b|\bSGST\b|\bIGST\b|\bGSTIN\b"#, ["INR"]),
        (#"(?i)\bsales tax\b"#, ["USD"]),
        (#"(?i)\bMVA\b"#, ["NOK"]),
        (#"(?i)\bmoms\b"#, ["SEK", "DKK"]),
        (#"(?i)\bVSK\b"#, ["ISK"]),
        (#"(?i)\bMwSt\b|\bUSt\b"#, ["EUR", "CHF"]),
        (#"(?i)\bTVA\b"#, ["EUR", "CHF", "RON"]),
        (#"(?i)\bIVA\b|\bBTW\b|\bALV\b|ΦΠΑ"#, ["EUR"]),
        (#"(?i)\bDPH\b"#, ["CZK", "EUR"]),
        (#"(?i)\bPTU\b"#, ["PLN"]),
        (#"(?i)\bÁFA\b|\bAFA\b"#, ["HUF"]),
        (#"(?i)\bKDV\b"#, ["TRY"]),
        (#"消費税|税込|税抜"#, ["JPY"]),
        (#"부가세|부가가치세"#, ["KRW"]),
        (#"增值税|发票"#, ["CNY"])
    ]

    // MARK: Detection

    public static func detect(lines: [String]) -> CurrencyDetection {
        let text = " " + lines.joined(separator: "\n") + " "

        // 1. Certain evidence, counted.
        var counts: [String: Int] = [:]
        for code in isoCodes {
            let n = count(#"(?<![A-Z])"# + code + #"(?![A-Z])"#, in: text)
            if n > 0 { counts[code == "RMB" ? "CNY" : code, default: 0] += n }
        }
        for marker in uniqueMarkers {
            let n = count(marker.pattern, in: text)
            if n > 0 { counts[marker.code, default: 0] += n }
        }
        if !counts.isEmpty {
            let ranked = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
            // Two different currencies (e.g. card payment converted to the
            // card's currency) -> ask which one was paid.
            return CurrencyDetection(code: ranked[0], confidence: ranked.count == 1 ? .certain : .likely, candidates: ranked)
        }

        // Hints: each matching hint is one vote for its currencies.
        var hintScore: [String: Int] = [:]
        var hinted: [String] = []
        for hint in hints where count(hint.pattern, in: text) > 0 {
            for code in hint.codes {
                if hintScore[code] == nil { hinted.append(code) }
                hintScore[code, default: 0] += 1
            }
        }
        func byScore(_ codes: [String]) -> [String] {
            codes.enumerated()
                .sorted { a, b in
                    let sa = hintScore[a.element] ?? 0, sb = hintScore[b.element] ?? 0
                    return sa != sb ? sa > sb : a.offset < b.offset
                }
                .map(\.element)
        }

        // 2. Shared symbols, narrowed down by hints.
        var shared: [String] = []
        for marker in sharedMarkers where count(marker.pattern, in: text) > 0 {
            for code in marker.codes where !shared.contains(code) { shared.append(code) }
        }
        if !shared.isEmpty {
            let ordered = byScore(shared)
            let top = hintScore[ordered[0]] ?? 0
            let second = ordered.count > 1 ? (hintScore[ordered[1]] ?? 0) : 0
            // One symbol only ("Fr. 5") or a clear winner among the hints
            // ("$" + "HST" -> CAD, "kr" + "MVA" -> NOK, "¥" + "消費税" -> JPY).
            let isClear = ordered.count == 1 || (top > 0 && top > second)
            return CurrencyDetection(code: ordered[0], confidence: isClear ? .certain : .likely, candidates: ordered)
        }

        // 3. Hints only.
        if !hinted.isEmpty {
            return CurrencyDetection(code: byScore(hinted)[0], confidence: .likely, candidates: byScore(hinted))
        }
        return .unknown
    }

    /// Currencies whose receipts normally show whole amounts without decimals
    /// ("¥1,280", "12 990 Ft", "35.000 ₫").
    public static func usesWholeAmounts(_ code: String?) -> Bool {
        guard let code else { return false }
        return ["JPY", "KRW", "VND", "IDR", "HUF", "ISK", "CLP", "COP", "UGX", "PYG", "TWD"].contains(CurrencyInfo.normalize(code))
    }

    private static func count(_ pattern: String, in text: String) -> Int {
        guard let regex = cachedRegex(pattern) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static let regexCache = RegexCache()

    private static func cachedRegex(_ pattern: String) -> NSRegularExpression? {
        regexCache.regex(for: pattern)
    }
}

/// Small thread-safe cache so the patterns are compiled once.
private final class RegexCache: @unchecked Sendable {
    private var store: [String: NSRegularExpression] = [:]
    private let lock = NSLock()

    func regex(for pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = store[pattern] { return cached }
        guard let compiled = try? NSRegularExpression(pattern: pattern) else { return nil }
        store[pattern] = compiled
        return compiled
    }
}
