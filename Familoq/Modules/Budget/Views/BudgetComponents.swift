import SwiftUI
import FamiloqCore
import FamiloqBudget

extension BudgetWarningLevel {
    var tint: Color {
        switch self {
        case .normal: return .green
        case .caution75: return .yellow
        case .warning90: return .orange
        case .reached100, .over: return .red
        }
    }
}

struct BudgetProgressRow: View {
    let progress: BudgetProgress
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                CategoryIcon(icon: progress.icon, colorHex: progress.colorHex, size: 28)
                Text(LocalizedStringKey(progress.title))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text("\(progress.status.spent.currencyShort(currencyCode)) / \(progress.status.limit.currencyShort(currencyCode))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(progress.status.fractionUsed, 1))
                .tint(progress.status.level.tint)
            if let message = warningText {
                Text(LocalizedStringKey(message))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(progress.status.level.tint)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var warningText: String? {
        switch progress.status.level {
        case .normal: return nil
        case .caution75, .warning90: return "\(progress.status.percentUsed)% used"
        case .reached100: return "Budget fully used"
        case .over: return "\(progress.status.overAmount.currency(currencyCode)) over budget"
        }
    }
}

struct ExpenseRow: View {
    let expense: Expense
    let lookup: CategoryLookup

    var body: some View {
        let category = lookup.category(expense.categoryID)
        HStack(spacing: 12) {
            CategoryIcon(icon: category?.icon ?? "questionmark", colorHex: category?.colorHex ?? "#9E9E9E")
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.merchant.isEmpty ? lookup.path(categoryID: expense.categoryID, subcategoryID: expense.subcategoryID) : expense.merchant)
                    .font(.body)
                    .lineLimit(1)
                Text("\(lookup.path(categoryID: expense.categoryID, subcategoryID: expense.subcategoryID)) · \(expense.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let base = expense.baseAmount {
                    Text(base.currency(expense.baseCurrencyCode))
                        .font(.body.monospacedDigit())
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
                if expense.isForeignCurrency {
                    HStack(spacing: 3) {
                        if expense.conversionStatus.needsRefresh || !expense.conversionStatus.hasBaseAmount {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        Text(expense.amount.currency(expense.currencyCode))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
