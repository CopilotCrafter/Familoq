import Foundation
import FamiloqCore

/// A merchant -> category rule. `Target` is whatever the caller uses to
/// identify a category (default keys in the core, UUIDs in the app).
public struct MerchantRuleCandidate<Target> {
    /// Normalised merchant pattern (see `TextNormalizer.normalize`).
    public let pattern: String
    public let target: Target
    public let isUserDefined: Bool

    public init(pattern: String, target: Target, isUserDefined: Bool) {
        self.pattern = TextNormalizer.normalize(pattern)
        self.target = target
        self.isUserDefined = isUserDefined
    }
}

public enum MerchantMatcher {
    /// Returns the best rule for a merchant:
    /// 1. user-defined rules win over built-in rules
    /// 2. longer (more specific) patterns win
    /// A pattern matches when it appears as whole word(s) in the merchant name,
    /// so "rewe" matches "REWE Markt GmbH" but "aral" does not match "Paralympics".
    public static func bestMatch<T>(for merchant: String, in rules: [MerchantRuleCandidate<T>]) -> MerchantRuleCandidate<T>? {
        let name = TextNormalizer.normalize(merchant)
        guard !name.isEmpty else { return nil }
        let padded = " \(name) "
        let matches = rules.filter { rule in
            !rule.pattern.isEmpty && padded.contains(" \(rule.pattern) ")
        }
        return matches.max { a, b in
            if a.isUserDefined != b.isUserDefined { return !a.isUserDefined }
            return a.pattern.count < b.pattern.count
        }
    }

    /// Whether to ask "Always categorize this merchant this way?".
    public static func shouldOfferRule<T: Equatable>(merchant: String, suggested: T?, chosen: T?) -> Bool {
        guard !TextNormalizer.normalize(merchant).isEmpty, let chosen = chosen else { return false }
        return suggested != chosen
    }
}

/// Built-in merchant rules (German market focus). Target = subcategory key
/// or category key.
public enum DefaultMerchantRules {
    public struct Rule: Equatable, Sendable {
        public let pattern: String
        public let categoryKey: String
        public let subcategoryKey: String?
    }

    public static let all: [Rule] = {
        var rules: [Rule] = []
        func add(_ patterns: [String], _ category: String, _ sub: String?) {
            for p in patterns {
                rules.append(Rule(pattern: TextNormalizer.normalize(p), categoryKey: category, subcategoryKey: sub))
            }
        }
        add(["lidl", "aldi", "aldi sud", "aldi nord", "rewe", "edeka", "netto", "penny", "kaufland",
             "norma", "globus", "tegut", "marktkauf", "hit markt", "denns", "alnatura", "rewe city"],
            "groceries", nil)
        add(["aral", "shell", "esso", "jet", "total", "totalenergies", "agip", "omv", "avia", "bft", "star tankstelle"],
            "transport", "transport.fuel")
        add(["db", "deutsche bahn", "db vertrieb", "mvv", "mvg", "rvv", "bvg", "hvv", "flixtrain", "deutschlandticket"],
            "transport", "transport.public")
        add(["apcoa", "contipark", "parkhaus", "easypark", "parkster"], "transport", "transport.parking")
        add(["ikea", "hoeffner", "xxxlutz", "poco", "roller", "moemax", "jysk"], "shopping", "shopping.home")
        add(["dm", "rossmann", "muller drogerie", "budni"], "shopping", "shopping.personalcare")
        add(["mediamarkt", "media markt", "saturn", "cyberport", "apple store"], "shopping", "shopping.electronics")
        add(["h m", "zara", "primark", "c a", "deichmann", "zalando", "about you"], "shopping", "shopping.clothing")
        add(["amazon", "amzn", "ebay", "otto", "temu"], "shopping", "shopping.other")
        add(["netflix", "disney plus", "disney", "spotify", "dazn", "wow", "prime video", "apple tv", "youtube premium"],
            "subscriptions", "subscriptions.streaming")
        add(["icloud", "google one", "dropbox", "onedrive"], "subscriptions", "subscriptions.cloud")
        add(["mcdonalds", "mcdonald s", "burger king", "kfc", "subway", "five guys"], "restaurants", "restaurants.fastfood")
        add(["starbucks", "tchibo", "coffee fellows", "backwerk"], "restaurants", "restaurants.cafe")
        add(["lieferando", "wolt", "uber eats"], "restaurants", "restaurants.delivery")
        add(["apotheke", "docmorris", "shop apotheke"], "health", "health.pharmacy")
        add(["telekom", "vodafone", "o2", "congstar", "1u1", "1 1"], "housing", "housing.mobile")
        add(["stadtwerke", "e on", "eon", "eprimo", "vattenfall", "enbw"], "housing", "housing.electricity")
        add(["lufthansa", "ryanair", "eurojet", "eurowings", "condor"], "travel", "travel.flights")
        add(["booking com", "airbnb", "hotel"], "travel", "travel.hotels")
        add(["sixt", "europcar", "hertz", "avis"], "travel", "travel.carrental")
        add(["cinemaxx", "kino", "cineplex", "uci"], "entertainment", "entertainment.cinema")
        add(["steam", "playstation", "nintendo", "xbox"], "entertainment", "entertainment.games")
        return rules
    }()

    /// Rules as candidates keyed by "categoryKey|subcategoryKey".
    public static func candidates() -> [MerchantRuleCandidate<Rule>] {
        all.map { MerchantRuleCandidate(pattern: $0.pattern, target: $0, isUserDefined: false) }
    }
}
