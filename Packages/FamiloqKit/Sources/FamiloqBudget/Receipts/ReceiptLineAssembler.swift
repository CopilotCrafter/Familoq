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

        guard let totalRow = grouped.firstIndex(where: { ReceiptParser.isTotalLine(join($0)) }),
              let firstPriceRow = grouped.firstIndex(where: { $0.contains(where: isColumnPrice) }),
              firstPriceRow < totalRow else { return nil }
        // A name can sit a little above its price: start one row earlier
        // when that row is a name without a price.
        var start = firstPriceRow
        if start > 0 {
            let previous = grouped[start - 1].filter { !isColumnPrice($0) }
            let text = join(previous)
            if !grouped[start].contains(where: { !isColumnPrice($0) }) && needsPrice(text) { start -= 1 }
        }

        let block = grouped[start..<totalRow]
        let prices = block.flatMap { $0.filter(isColumnPrice) }
        let names = block.map { row in join(row.filter { !isColumnPrice($0) }) }
        let needing = names.filter(needsPrice)
        guard !prices.isEmpty, needing.count == prices.count else { return nil }

        // Prices top to bottom (by height, slope removed like the rows).
        let orderedPrices = prices.sorted { $0.midY < $1.midY }
        var result = grouped[..<start].map(join)
        var next = 0
        for name in names where !name.isEmpty {
            if needsPrice(name) {
                result.append(name + " " + orderedPrices[next].text.trimmingCharacters(in: .whitespaces))
                next += 1
            } else {
                result.append(name)
            }
        }
        result.append(contentsOf: grouped[totalRow...].map(join))
        return result
    }

    /// An item name still waiting for its price (not a quantity line like
    /// "0,184 kg x 4,90 EUR/kg", not a header like "EUR", no price of its own).
    static func needsPrice(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.filter(\.isLetter).count >= 2 else { return false }
        if ["eur", "€", "chf", "usd", "gbp"].contains(trimmed.lowercased()) { return false }
        if ReceiptParser.isQuantityLine(trimmed) { return false }
        if ReceiptParser.trailingPriceValue(trimmed) != nil { return false }
        if ReceiptParser.isSkipLine(trimmed) { return false }
        return true
    }
}
