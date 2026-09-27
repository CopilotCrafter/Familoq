import XCTest
import FamiloqCore
@testable import FamiloqBudget

final class CategorizationTests: XCTestCase {
    func testDefaultCategoryTree() {
        XCTAssertEqual(DefaultCategories.all.count, 14)
        let groceries = DefaultCategories.category(forKey: "groceries")
        XCTAssertEqual(groceries?.subcategories.count, 18)
        XCTAssertEqual(groceries?.subcategories.first?.name, "Meat & Poultry")
        XCTAssertEqual(DefaultCategories.subcategory(forKey: "transport.parking")?.subcategory.name, "Parking")

        // Keys must be unique so rules and reports can rely on them.
        let categoryKeys = DefaultCategories.all.map(\.key)
        XCTAssertEqual(Set(categoryKeys).count, categoryKeys.count)
        let subKeys = DefaultCategories.all.flatMap { $0.subcategories.map(\.key) }
        XCTAssertEqual(Set(subKeys).count, subKeys.count)
    }

    func testNormalizer() {
        XCTAssertEqual(TextNormalizer.normalize("REWE Markt GmbH"), "rewe markt gmbh")
        XCTAssertEqual(TextNormalizer.normalize("  Café  Müller!! "), "cafe muller")
        XCTAssertEqual(TextNormalizer.normalize("Straße"), "strasse")
        XCTAssertEqual(TextNormalizer.normalize("HAEHNCHEN", germanTransliteration: true),
                       TextNormalizer.normalize("Hähnchen", germanTransliteration: true))
    }

    func testDefaultMerchantRules() {
        let rules = DefaultMerchantRules.candidates()
        XCTAssertEqual(MerchantMatcher.bestMatch(for: "LIDL Dienstleistung GmbH", in: rules)?.target.categoryKey, "groceries")
        XCTAssertEqual(MerchantMatcher.bestMatch(for: "REWE", in: rules)?.target.categoryKey, "groceries")
        XCTAssertEqual(MerchantMatcher.bestMatch(for: "Aral Tankstelle", in: rules)?.target.subcategoryKey, "transport.fuel")
        XCTAssertEqual(MerchantMatcher.bestMatch(for: "IKEA Regensburg", in: rules)?.target.subcategoryKey, "shopping.home")
        XCTAssertEqual(MerchantMatcher.bestMatch(for: "NETFLIX.COM", in: rules)?.target.subcategoryKey, "subscriptions.streaming")
        XCTAssertNil(MerchantMatcher.bestMatch(for: "Paralympics Shop", in: rules), "must match whole words only")
        XCTAssertNil(MerchantMatcher.bestMatch(for: "", in: rules))
    }

    func testUserRuleBeatsDefaultRule() {
        let rules: [MerchantRuleCandidate<String>] = [
            MerchantRuleCandidate(pattern: "amazon", target: "shopping.other", isUserDefined: false),
            MerchantRuleCandidate(pattern: "amazon", target: "groceries.other", isUserDefined: true)
        ]
        XCTAssertEqual(MerchantMatcher.bestMatch(for: "Amazon Fresh", in: rules)?.target, "groceries.other")
    }

    func testLongerPatternWins() {
        let rules: [MerchantRuleCandidate<String>] = [
            MerchantRuleCandidate(pattern: "db", target: "transport.public", isUserDefined: false),
            MerchantRuleCandidate(pattern: "db fernverkehr", target: "travel.train", isUserDefined: false)
        ]
        XCTAssertEqual(MerchantMatcher.bestMatch(for: "DB Fernverkehr AG", in: rules)?.target, "travel.train")
    }

    func testShouldOfferRule() {
        XCTAssertTrue(MerchantMatcher.shouldOfferRule(merchant: "Lidl", suggested: "groceries", chosen: "shopping"))
        XCTAssertFalse(MerchantMatcher.shouldOfferRule(merchant: "Lidl", suggested: "groceries", chosen: "groceries"))
        XCTAssertFalse(MerchantMatcher.shouldOfferRule(merchant: "  ", suggested: nil, chosen: "groceries"))
        XCTAssertTrue(MerchantMatcher.shouldOfferRule(merchant: "Bäckerei Huber", suggested: nil as String?, chosen: "groceries"))
    }

    // MARK: Grocery item-level categorisation (spec section 7)

    private func sub(_ text: String) -> String? {
        GroceryItemClassifier.classify(text)?.subcategoryKey
    }

    func testSpecExampleItems() {
        XCTAssertEqual(sub("Chicken"), "groceries.meat")
        XCTAssertEqual(sub("Milk"), "groceries.dairy")
        XCTAssertEqual(sub("Bananas"), "groceries.fruits")
        XCTAssertEqual(sub("Tomatoes"), "groceries.vegetables")
        XCTAssertEqual(sub("Chocolate"), "groceries.snacks")
    }

    func testGermanReceiptLines() {
        XCTAssertEqual(sub("Hähnchenbrustfilet"), "groceries.meat")
        XCTAssertEqual(sub("HAEHN.BRUSTFILET 400G"), "groceries.meat")
        XCTAssertEqual(sub("H-MILCH 3,5%"), "groceries.dairy")
        XCTAssertEqual(sub("BANANEN"), "groceries.fruits")
        XCTAssertEqual(sub("Rispentomaten"), "groceries.vegetables")
        XCTAssertEqual(sub("Freilandeier 10er"), "groceries.eggs")
        XCTAssertEqual(sub("Vollkornbrot"), "groceries.bakery")
        XCTAssertEqual(sub("SPUELMITTEL"), "groceries.cleaning")
        XCTAssertEqual(sub("Katzenfutter"), "groceries.pet")
        XCTAssertEqual(sub("Toilettenpapier"), "groceries.household")
        XCTAssertEqual(sub("Kaffee gemahlen"), "groceries.coffee")
        XCTAssertEqual(sub("Mineralwasser"), "groceries.beverages")
    }

    func testLongestKeywordWins() {
        XCTAssertEqual(sub("Reis 1kg"), "groceries.grains", "'Reis' must not match 'eis'")
        XCTAssertEqual(sub("Basmati Reis"), "groceries.grains")
        XCTAssertEqual(sub("Milchschokolade"), "groceries.snacks", "'schokolade' beats 'milch'")
        XCTAssertEqual(sub("Tomatenketchup"), "groceries.condiments")
        XCTAssertEqual(sub("Schweinefleisch"), "groceries.meat", "'schwein' beats 'wein'")
        XCTAssertEqual(sub("Orangensaft"), "groceries.beverages")
        XCTAssertEqual(sub("TK Pizza"), "groceries.frozen")
        XCTAssertEqual(sub("Vanille Eis"), "groceries.frozen")
    }

    func testUnknownItemReturnsNil() {
        XCTAssertNil(sub("XYZ 123"))
        XCTAssertNil(sub(""))
    }
}
