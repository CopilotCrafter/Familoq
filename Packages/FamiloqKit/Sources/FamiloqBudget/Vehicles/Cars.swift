import Foundation
import FamiloqCore

/// What a car cost was for. Each maps to a Transport subcategory so budgets
/// and reports keep working without a car.
public enum CarCostKind: String, CaseIterable, Identifiable, Sendable {
    case fuel, charging, service, repair, tyres, inspection, insurance, tax, parking, toll, wash, other

    public var id: String { rawValue }

    /// Built-in subcategory key ("transport.fuel").
    public var subcategoryKey: String {
        switch self {
        case .fuel, .charging: return "transport.fuel"
        case .service, .repair, .tyres, .inspection: return "transport.maintenance"
        case .insurance: return "transport.insurance"
        case .parking: return "transport.parking"
        case .toll: return "transport.tolls"
        case .wash: return "transport.wash"
        case .tax, .other: return "transport.other"
        }
    }

    public var title: String {
        switch self {
        case .fuel: return "Fuel"
        case .charging: return "Charging"
        case .service: return "Service"
        case .repair: return "Repair"
        case .tyres: return "Tyres"
        case .inspection: return "TÜV / inspection"
        case .insurance: return "Car insurance"
        case .tax: return "Vehicle tax"
        case .parking: return "Parking"
        case .toll: return "Tolls & vignette"
        case .wash: return "Car wash"
        case .other: return "Other"
        }
    }

    public var icon: String {
        switch self {
        case .fuel: return "fuelpump.fill"
        case .charging: return "bolt.car.fill"
        case .service: return "wrench.and.screwdriver.fill"
        case .repair: return "hammer.fill"
        case .tyres: return "circle.circle"
        case .inspection: return "checkmark.seal.fill"
        case .insurance: return "shield.fill"
        case .tax: return "building.columns.fill"
        case .parking: return "parkingsign.circle.fill"
        case .toll: return "road.lanes"
        case .wash: return "drop.fill"
        case .other: return "car.fill"
        }
    }

    /// Fuel or electricity: liters / kWh can be entered.
    public var hasQuantity: Bool { self == .fuel || self == .charging }

    /// Best guess from a subcategory ("transport.parking" -> parking).
    public static func guess(subcategoryKey: String?) -> CarCostKind? {
        switch subcategoryKey {
        case "transport.fuel": return .fuel
        case "transport.maintenance": return .service
        case "transport.insurance": return .insurance
        case "transport.parking": return .parking
        case "transport.tolls": return .toll
        case "transport.wash": return .wash
        case "transport.other": return .other
        default: return nil
        }
    }
}

public enum FuelType: String, CaseIterable, Identifiable, Sendable {
    case petrol, diesel, lpg, electric, hybrid, plugInHybrid

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .petrol: return "Petrol"
        case .diesel: return "Diesel"
        case .lpg: return "LPG"
        case .electric: return "Electric"
        case .hybrid: return "Hybrid"
        case .plugInHybrid: return "Plug-in hybrid"
        }
    }

    /// "l/100 km" or "kWh/100 km".
    public var unit: String { self == .electric ? "kWh" : "l" }
}

/// One cost of a car (from an expense).
public struct CarLogEntry: Equatable, Sendable {
    public var date: Date
    public var amount: Decimal
    public var kind: CarCostKind
    /// Liters (or kWh when charging).
    public var quantity: Double?
    /// Odometer reading in km.
    public var odometer: Int?

    public init(date: Date, amount: Decimal, kind: CarCostKind, quantity: Double? = nil, odometer: Int? = nil) {
        self.date = date
        self.amount = amount
        self.kind = kind
        self.quantity = quantity
        self.odometer = odometer
    }
}

public enum CarStats {
    /// Average consumption per 100 km from full fill-ups with km readings.
    /// The first fill-up only sets the start; every later one refills what
    /// was used since the one before.
    public static func consumption(_ entries: [CarLogEntry]) -> Double? {
        let fills = entries
            .filter { $0.kind.hasQuantity && ($0.quantity ?? 0) > 0 && ($0.odometer ?? 0) > 0 }
            .sorted { ($0.odometer ?? 0, $0.date) < ($1.odometer ?? 0, $1.date) }
        guard fills.count >= 2, let first = fills.first?.odometer, let last = fills.last?.odometer, last > first else { return nil }
        let used = fills.dropFirst().reduce(0.0) { $0 + ($1.quantity ?? 0) }
        return used / Double(last - first) * 100
    }

    /// Kilometres driven between the lowest and highest reading.
    public static func distance(_ entries: [CarLogEntry]) -> Int? {
        let readings = entries.compactMap(\.odometer).filter { $0 > 0 }
        guard let low = readings.min(), let high = readings.max(), high > low else { return nil }
        return high - low
    }

    public static func total(_ entries: [CarLogEntry]) -> Decimal {
        entries.reduce(0) { $0 + $1.amount }
    }

    public static func totals(_ entries: [CarLogEntry]) -> [(kind: CarCostKind, amount: Decimal)] {
        var sums: [CarCostKind: Decimal] = [:]
        for entry in entries { sums[entry.kind, default: 0] += entry.amount }
        return CarCostKind.allCases.compactMap { kind in sums[kind].map { (kind, $0) } }
    }

    /// Everything spent per km driven (nil without two km readings).
    public static func costPerKm(_ entries: [CarLogEntry]) -> Decimal? {
        guard let km = distance(entries), km > 0 else { return nil }
        return (total(entries) / Decimal(km)).rounded(scale: 2)
    }

    /// Average price per liter (or kWh).
    public static func averagePrice(_ entries: [CarLogEntry]) -> Decimal? {
        let fills = entries.filter { $0.kind.hasQuantity && ($0.quantity ?? 0) > 0 }
        let quantity = fills.reduce(0.0) { $0 + ($1.quantity ?? 0) }
        guard quantity > 0 else { return nil }
        return (total(fills) / Decimal(quantity)).rounded(scale: 3)
    }

    /// Latest km reading.
    public static func lastOdometer(_ entries: [CarLogEntry]) -> Int? {
        entries.compactMap(\.odometer).max()
    }
}

/// Recognises fuel on a scanned receipt.
public enum FuelReceipt {
    static let words: Set<String> = [
        "super", "e10", "e5", "superplus", "diesel", "benzin", "normalbenzin", "kraftstoff", "lpg", "autogas",
        "vpower", "ultimate", "excellium", "maxxmotion", "hvo", "hvo100", "premiumdiesel", "superbenzin", "ottokraftstoff"
    ]

    public static func isFuelItem(_ name: String) -> Bool {
        let tokens = TextNormalizer.normalize(name, germanTransliteration: true).split(separator: " ").map(String.init)
        if tokens.contains(where: { words.contains($0) }) { return true }
        // "Super Plus", "V-Power", "Premium Diesel" spelt apart.
        for (a, b) in zip(tokens, tokens.dropFirst()) where words.contains(a + b) { return true }
        return false
    }

    /// Fuel receipt: a fuel station rule matched, or an item is fuel.
    public static func isFuelReceipt(subcategoryKey: String?, itemNames: [String]) -> Bool {
        subcategoryKey == "transport.fuel" || itemNames.contains(where: isFuelItem)
    }

    /// Liters of the fuel items (their quantity: "45,23 l x 1,799").
    public static func liters(items: [ParsedReceiptItem]) -> Double? {
        let total = items.filter { isFuelItem($0.name) }.compactMap(\.quantity).reduce(Decimal(0), +)
        guard total > 0 else { return nil }
        return NSDecimalNumber(decimal: total).doubleValue
    }

    /// Amount of the fuel items (the rest is shop - snacks, coffee).
    public static func fuelAmount(items: [ParsedReceiptItem]) -> Decimal {
        items.filter { isFuelItem($0.name) }.reduce(0) { $0 + $1.amount }
    }
}

/// "O bis O": winter tyres from October to Easter. Familoq reminds on
/// 10 October and 10 April.
public enum TyreSeason {
    public static let winterDay = DateComponents(month: 10, day: 10, hour: 9)
    public static let summerDay = DateComponents(month: 4, day: 10, hour: 9)

    /// Next change day after `date` and whether it is to winter tyres.
    public static func nextChange(after date: Date, calendar: Calendar) -> (date: Date, toWinter: Bool)? {
        let winter = calendar.nextDate(after: date, matching: winterDay, matchingPolicy: .nextTime)
        let summer = calendar.nextDate(after: date, matching: summerDay, matchingPolicy: .nextTime)
        switch (winter, summer) {
        case let (w?, s?): return w < s ? (w, true) : (s, false)
        case let (w?, nil): return (w, true)
        case let (nil, s?): return (s, false)
        default: return nil
        }
    }
}

/// Main inspection (HU, "TÜV"): every 2 years, the first after 3.
public enum CarInspection {
    public static func next(after date: Date, firstRegistration: Bool = false, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .month, value: firstRegistration ? 36 : 24, to: date)
    }
}
