import Foundation

/// Money is stored as a fixed-point `Int64` with 4 decimal places.
///
/// Why not `Double`?  Floating point cannot represent 0.10 exactly.
/// Why not `Decimal` in the database?  Integers are exact, sortable, and map
/// cleanly to CloudKit (Phase 4) and to JSON/CSV export (Phase 5).
///
/// 4 decimal places cover every ISO currency (max 3 minor units) plus one
/// extra digit of headroom for intermediate conversions.
public enum FixedPoint {
    public static let scale: Int64 = 10_000

    /// Converts a `Decimal` into storage units, rounding half-up.
    public static func storage(from value: Decimal) -> Int64 {
        let scaled = (value * Decimal(scale)).rounded(scale: 0, mode: .plain)
        return NSDecimalNumber(decimal: scaled).int64Value
    }

    /// Converts storage units back into a `Decimal`.
    public static func decimal(from storage: Int64) -> Decimal {
        Decimal(storage) / Decimal(scale)
    }
}

public extension Decimal {
    /// Returns the value rounded to `scale` fractional digits.
    func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, mode)
        return result
    }

    /// Convenience for charts and progress bars (never use for money maths).
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
