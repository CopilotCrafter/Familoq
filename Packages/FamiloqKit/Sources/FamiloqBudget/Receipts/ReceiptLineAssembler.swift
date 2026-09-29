import Foundation
import FamiloqCore

/// One piece of recognised text with its position on the page.
/// Coordinates are normalised 0...1 with the origin at the TOP-LEFT
/// (the app converts Vision's bottom-left coordinates before calling this).
public struct OCRFragment: Equatable, Sendable {
    public var text: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var confidence: Double
    /// Page index for multi-page scans (long receipts).
    public var page: Int
    /// How much the text line falls per unit to the right (dy/dx in the
    /// same normalised, top-left coordinates; 0 = level). Photos of a
    /// receipt lying at an angle have sloped lines.
    public var slope: Double

    public init(text: String, x: Double, y: Double, width: Double, height: Double, confidence: Double = 1, page: Int = 0, slope: Double = 0) {
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.confidence = confidence
        self.page = page
        self.slope = slope
    }

    var midY: Double { y + height / 2 }
    var midX: Double { x + width / 2 }
}

/// Rebuilds receipt LINES from OCR fragments. Vision often returns the item
/// name and its price (far right) as separate fragments; they belong to the
/// same line when their vertical centres are close.
///
/// A receipt photographed at an angle has sloped lines: without correction
/// the price on the right lands next to the NEXT item's name. The typical
/// slope of the long (name) fragments is measured and removed first.
public enum ReceiptLineAssembler {
    /// Median slope of the wide fragments of a page (short prices are too
    /// small to measure reliably).
    static func pageSlope(_ fragments: [OCRFragment]) -> Double {
        let slopes = fragments
            .filter { $0.width >= 0.15 && abs($0.slope) < 0.35 }
            .map(\.slope)
            .sorted()
        guard !slopes.isEmpty else { return 0 }
        return slopes[slopes.count / 2]
    }

    public static func lines(from fragments: [OCRFragment]) -> [String] {
        rows(from: fragments).map(join)
    }

    static func join(_ row: [OCRFragment]) -> String {
        row.sorted { $0.x < $1.x }
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
    }

    /// Fragments grouped into rows (top to bottom), slope removed.
    static func rows(from fragments: [OCRFragment]) -> [[OCRFragment]] {
        let usable = fragments.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        var slopeByPage: [Int: Double] = [:]
        for page in Set(usable.map(\.page)) {
            slopeByPage[page] = pageSlope(usable.filter { $0.page == page })
        }
        /// Vertical position with the slope removed (same for a whole line).
        func level(_ f: OCRFragment) -> Double {
            f.midY - (slopeByPage[f.page] ?? 0) * (f.midX - 0.5)
        }

        let sorted = usable.sorted { a, b in
            if a.page != b.page { return a.page < b.page }
            return level(a) < level(b)
        }

        var rows: [[OCRFragment]] = []
        for fragment in sorted {
            if let lastRow = rows.last, let anchor = lastRow.first, anchor.page == fragment.page {
                let tolerance = max(min(anchor.height, fragment.height) * 0.6, 0.004)
                let rowMid = lastRow.map(level).reduce(0, +) / Double(lastRow.count)
                if abs(level(fragment) - rowMid) <= tolerance {
                    rows[rows.count - 1].append(fragment)
                    continue
                }
            }
            rows.append([fragment])
        }
        return rows
    }

    // MARK: Price column paired in order

    private static let priceOnly = try! NSRegularExpression(
        pattern: #"^\s*-?\d{1,5}(?:[.,]\d{3})*[.,]\d{2}\s*(?:EUR|€)?\s*(?:[A-Z0-9]{1,2})?\s*\*?\s*$"#,
        options: [.caseInsensitive])

    static func isPriceOnly(_ text: String) -> Bool {
        priceOnly.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Second reading for photos where the paper is curled or unevenly
    /// angled: the prices on the right are paired with the item names IN
    /// ORDER (1st price - 1st name, …) instead of by height. Only when the
    /// numbers of names and prices between the first price and the total
    /// are the same; nil otherwise. The parser uses it when the normal
    /// lines do not add up to the total.
    public static func columnPairedLines(from fragments: [OCRFragment]) -> [String]? {
        let usable = fragments.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !usable.isEmpty, Set(usable.map(\.page)).count == 1 else { return nil }
        let grouped = rows(from: usable)
        let minX = usable.map(\.x).min() ?? 0
        let maxX = usable.map { $0.x + $0.width }.max() ?? 1
        let rightEdge = minX + (maxX - minX) * 0.5
        func isColumnPrice(_ f: OCRFragment) -> Bool { f.midX > rightEdge && isPriceOnly(f.text) }
        func name(_ row: [OCRFragment]) -> String { join(row.filter { !isColumnPrice($0) }) }

        guard let totalRow = grouped.firstIndex(where: { ReceiptParser.isTotalLine(name($0)) }),
              let firstPriceRow = grouped.firstIndex(where: { $0.contains(where: isColumnPrice) }),
              firstPriceRow < totalRow else { return nil }
        // A name can sit a little above its price: start one row earlier
        // when that row is a name without a price.
        var start = firstPriceRow
        if start > 0, !grouped[start].contains(where: { !isColumnPrice($0) }), needsPrice(name(grouped[start - 1])) {
            start -= 1
        }
        // Items end at the total, or earlier at a card-slip line
        // ("K-U-N-D-E-N-B-E-L-E-G" comes before ALDI's "Betrag").
        var itemEnd = start
        while itemEnd < totalRow && !isStopLine(name(grouped[itemEnd])) { itemEnd += 1 }

        let needing = (start..<itemEnd).filter { needsPrice(name(grouped[$0])) }
        let totalName = name(grouped[totalRow])
        let totalNeedsPrice = ReceiptParser.trailingPriceValue(totalName) == nil
        let wanted = needing.count + (totalNeedsPrice ? 1 : 0)
        // Prices top to bottom from the first item on (they may have drifted
        // below their row, even past the total).
        let prices = grouped[start...].flatMap { $0.filter(isColumnPrice) }.sorted { $0.midY < $1.midY }
        guard !needing.isEmpty, prices.count >= wanted else { return nil }
        let used = Array(prices.prefix(wanted))
        var assigned: [Int: OCRFragment] = [:]
        for (index, row) in needing.enumerated() { assigned[row] = used[index] }
        if totalNeedsPrice { assigned[totalRow] = used[needing.count] }
        let usedSet = Set(used.map { "\($0.x)|\($0.y)|\($0.text)" })
        func leftover(_ row: [OCRFragment]) -> String {
            join(row.filter { !isColumnPrice($0) || !usedSet.contains("\($0.x)|\($0.y)|\($0.text)") })
        }

        var result = grouped[..<start].map(join)
        for index in start..<grouped.count {
            let row = grouped[index]
            var text = leftover(row)
            if let price = assigned[index] {
                text = name(row) + " " + price.text.trimmingCharacters(in: .whitespaces)
                // Unused prices of this row (rare) stay at the end.
                let extra = row.filter { isColumnPrice($0) && !usedSet.contains("\($0.x)|\($0.y)|\($0.text)") }
                if !extra.isEmpty { text += " " + join(extra) }
            }
            if !text.trimmingCharacters(in: .whitespaces).isEmpty { result.append(text) }
        }
        return result
    }

    /// A card-slip / payment line: items do not continue after it.
    static func isStopLine(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.filter(\.isLetter).count >= 3 else { return false }
        let lower = trimmed.lowercased()
        if ["coupon", "rabatt", "preisvorteil", "nachlass", "pfand"].contains(where: { lower.contains($0) }) { return false }
        // "0,184 kg x 4,90 EUR/kg" belongs to the item above.
        if ReceiptParser.isQuantityLine(trimmed) { return false }
        return ReceiptParser.isSkipLine(trimmed) || ReceiptParser.isSkipLine(trimmed.replacingOccurrences(of: "-", with: ""))
    }

    /// An item name still waiting for its price (not a quantity line like
    /// "0,184 kg x 4,90 EUR/kg", not a header like "EUR", no price of its own).
    static func needsPrice(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.filter(\.isLetter).count >= 2 else { return false }
        if ["eur", "€", "chf", "usd", "gbp"].contains(trimmed.lowercased()) { return false }
        if ReceiptParser.isQuantityLine(trimmed) { return false }
        if ReceiptParser.trailingPriceValue(trimmed) != nil { return false }
        let lower = trimmed.lowercased()
        let isDiscount = ["coupon", "rabatt", "preisvorteil", "nachlass"].contains { lower.contains($0) }
        if !isDiscount && (ReceiptParser.isSkipLine(trimmed) || ReceiptParser.isSkipLine(trimmed.replacingOccurrences(of: "-", with: ""))) { return false }
        if ReceiptParser.containsDate(trimmed) { return false }
        return true
    }
}
