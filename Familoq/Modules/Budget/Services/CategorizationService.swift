import Foundation
import SwiftData
import FamiloqCore
import FamiloqBudget

struct CategorySuggestion: Equatable {
    let categoryID: UUID
    let subcategoryID: UUID?
}

/// Merchant -> category suggestions without any external AI service.
@MainActor
enum CategorizationService {
    static func suggestion(for merchant: String, rules: [MerchantRuleRecord]) -> CategorySuggestion? {
        let candidates = rules.map {
            MerchantRuleCandidate(
                pattern: $0.pattern,
                target: CategorySuggestion(categoryID: $0.categoryID, subcategoryID: $0.subcategoryID),
                isUserDefined: $0.isUserDefined
            )
        }
        return MerchantMatcher.bestMatch(for: merchant, in: candidates)?.target
    }

    /// Whether to ask "Always categorize this merchant this way?".
    static func shouldOfferRule(merchant: String, suggested: CategorySuggestion?, chosen: CategorySuggestion?, rules: [MerchantRuleRecord]) -> Bool {
        guard MerchantMatcher.shouldOfferRule(merchant: merchant, suggested: suggested, chosen: chosen) else { return false }
        // Don't ask again if an identical user rule already exists.
        let pattern = TextNormalizer.normalize(merchant)
        return !rules.contains {
            $0.isUserDefined && $0.pattern == pattern && $0.categoryID == chosen?.categoryID && $0.subcategoryID == chosen?.subcategoryID
        }
    }

    /// Creates or updates the user's rule for this merchant.
    static func saveRule(merchant: String, choice: CategorySuggestion, familyID: UUID, rules: [MerchantRuleRecord], context: ModelContext) {
        let pattern = TextNormalizer.normalize(merchant)
        guard !pattern.isEmpty else { return }
        if let existing = rules.first(where: { $0.isUserDefined && $0.pattern == pattern && $0.familyID == familyID }) {
            existing.categoryID = choice.categoryID
            existing.subcategoryID = choice.subcategoryID
            existing.displayMerchant = merchant
        } else {
            let rule = MerchantRuleRecord(
                familyID: familyID,
                pattern: pattern,
                displayMerchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
                categoryID: choice.categoryID,
                subcategoryID: choice.subcategoryID,
                isUserDefined: true
            )
            context.insert(rule)
        }
    }
}
