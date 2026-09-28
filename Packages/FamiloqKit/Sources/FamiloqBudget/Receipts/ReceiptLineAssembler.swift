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

        return rows.map { row in
            row.sorted { $0.x < $1.x }
                .map { $0.text.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
        }
    }
}
