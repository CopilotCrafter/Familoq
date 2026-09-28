import Foundation
import FamiloqCore
import FamiloqBudget

enum PaymentMethod: String, CaseIterable, Identifiable {
    case cash
    case debitCard
    case creditCard
    case paypal
    case bankTransfer
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cash: return "Cash"
        case .debitCard: return "Girocard / Debit card"
        case .creditCard: return "Credit card"
        case .paypal: return "PayPal"
        case .bankTransfer: return "Bank transfer"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .cash: return "banknote"
        case .debitCard: return "creditcard"
        case .creditCard: return "creditcard.fill"
        case .paypal: return "p.circle"
        case .bankTransfer: return "building.columns"
        case .other: return "ellipsis.circle"
        }
    }
}

enum EntryMethod: String, CaseIterable {
    case manual
    case quick
    case receipt
    /// Booked automatically from a recurring or planned expense.
    case scheduled

    var displayName: String {
        switch self {
        case .manual: return "Entered"
        case .quick: return "Quick entry"
        case .receipt: return "Scanned receipt"
        case .scheduled: return "Recurring / planned"
        }
    }
}

extension ConversionStatus {
    var displayName: String {
        switch self {
        case .notNeeded: return "Base currency"
        case .converted: return "Converted"
        case .estimated: return "Estimated - will update"
        case .pending: return "Waiting for exchange rate"
        case .manual: return "Manual rate"
        case .unsupported: return "Rate needed"
        }
    }
}
