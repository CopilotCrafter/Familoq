import Foundation
import FamiloqCore

// MARK: - Meal planner

public enum MealSlot: String, CaseIterable, Codable, Sendable {
    case breakfast, lunch, dinner

    public var title: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        }
    }

    public var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        }
    }
}

public enum MealIngredients {
    /// Recipe ingredient lines -> shopping entries, the same item merged:
    /// "2 Zwiebeln" + "1 Zwiebeln" -> "Zwiebeln 3"; "500 g Hack" + "Hack" -> "500 g + 1".
    public static func merged(_ lines: [String]) -> [ShoppingEntry] {
        var order: [String] = []
        var entries: [String: (name: String, quantities: [String])] = [:]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let entry = ShoppingEntryParser.parse(trimmed)
            let key = ShoppingEntryParser.key(entry.name)
            guard !key.isEmpty else { continue }
            if entries[key] == nil {
                order.append(key)
                entries[key] = (entry.name, [])
            }
            entries[key]?.quantities.append(entry.quantity.isEmpty ? "1" : entry.quantity)
        }
        return order.compactMap { key in
            guard let item = entries[key] else { return nil }
            let numbers = item.quantities.compactMap { Int($0) }
            let quantity: String
            if numbers.count == item.quantities.count {
                let sum = numbers.reduce(0, +)
                quantity = sum == 1 ? "" : String(sum)
            } else {
                quantity = item.quantities.joined(separator: " + ")
            }
            return ShoppingEntry(name: item.name, quantity: quantity)
        }
    }

    /// Ingredient lines from pasted text ("- 2 Eier", "• Mehl").
    public static func lines(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " -•*\t")) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Travel: who owes whom

public struct TripPayment: Sendable {
    public var amount: Decimal
    /// Participant key (member UUID string or guest name).
    public var paidBy: String
    /// Empty = split between everyone on the trip.
    public var splitAmong: [String]

    public init(amount: Decimal, paidBy: String, splitAmong: [String] = []) {
        self.amount = amount
        self.paidBy = paidBy
        self.splitAmong = splitAmong
    }
}

public struct TripTransfer: Equatable, Sendable {
    public let from: String
    public let to: String
    public let amount: Decimal
}

public enum TripSettlement {
    /// Positive = gets money back, negative = owes.
    public static func balances(_ payments: [TripPayment], participants: [String]) -> [String: Decimal] {
        var balance: [String: Decimal] = Dictionary(uniqueKeysWithValues: participants.map { ($0, Decimal(0)) })
        for payment in payments where payment.amount != 0 {
            let among = (payment.splitAmong.isEmpty ? participants : payment.splitAmong).filter { participants.contains($0) }
            guard !among.isEmpty else { continue }
            balance[payment.paidBy, default: 0] += payment.amount
            let share = (payment.amount / Decimal(among.count)).rounded(scale: 2)
            var remaining = payment.amount
            for (index, person) in among.enumerated() {
                // The last person takes the rounding cent.
                let part = index == among.count - 1 ? remaining : share
                balance[person, default: 0] -= part
                remaining -= part
            }
        }
        return balance
    }

    /// Few transfers: the biggest debtor pays the biggest creditor first.
    public static func transfers(_ balances: [String: Decimal]) -> [TripTransfer] {
        var debtors = balances.filter { $0.value < Decimal(string: "-0.004")! }.map { ($0.key, -$0.value) }.sorted { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0 < $1.0) }
        var creditors = balances.filter { $0.value > Decimal(string: "0.004")! }.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0 < $1.0) }
        var result: [TripTransfer] = []
        var d = 0, c = 0
        while d < debtors.count, c < creditors.count {
            let amount = min(debtors[d].1, creditors[c].1).rounded(scale: 2)
            if amount > 0 { result.append(TripTransfer(from: debtors[d].0, to: creditors[c].0, amount: amount)) }
            debtors[d].1 -= amount
            creditors[c].1 -= amount
            if debtors[d].1 <= Decimal(string: "0.004")! { d += 1 }
            if creditors[c].1 <= Decimal(string: "0.004")! { c += 1 }
        }
        return result
    }
}
