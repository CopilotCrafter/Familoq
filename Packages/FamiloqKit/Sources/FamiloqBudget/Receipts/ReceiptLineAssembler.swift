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

    public init(text: String, x: Double, y: Double, width: Double, height: Double, confidence: Double = 1, page: Int = 0) {
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.confidence = confidence
        self.page = page
    }

    var midY: Double { y + height / 2 }
}

/// Rebuilds receipt LINES from OCR fragments. Vision often returns the item
/// name and its price (far right) as separate fragments; they belong to the
/// same line when their vertical centres are close.
public enum ReceiptLineAssembler {
    public static func lines(from fragments: [OCRFragment]) -> [String] {
        let sorted = fragments
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { a, b in
                if a.page != b.page { return a.page < b.page }
                return a.midY < b.midY
            }

        var rows: [[OCRFragment]] = []
        for fragment in sorted {
            if let lastRow = rows.last, let anchor = lastRow.first, anchor.page == fragment.page {
                let tolerance = max(min(anchor.height, fragment.height) * 0.6, 0.004)
                let rowMid = lastRow.map(\.midY).reduce(0, +) / Double(lastRow.count)
                if abs(fragment.midY - rowMid) <= tolerance {
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
