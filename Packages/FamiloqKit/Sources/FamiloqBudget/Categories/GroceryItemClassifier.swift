import Foundation
import FamiloqCore

public struct GroceryClassification: Equatable, Sendable {
    /// e.g. "groceries.fruits"
    public let subcategoryKey: String
    public let matchedKeyword: String
    /// 0...1 - how sure the classifier is. The UI always lets the user correct it.
    public let confidence: Double
}

/// Offline, dependency-free classifier that maps a receipt line
/// ("BANANEN 1,2KG", "Hähnchenbrustfilet", "Milka Schokolade") to a grocery
/// subcategory using German + English keywords.
///
/// Rule: the LONGEST matching keyword wins, so
///   "Reis"            -> Rice (not "eis" = frozen)
///   "Milchschokolade" -> Snacks (not "milch" = dairy)
///   "Tomatenketchup"  -> Condiments (not "tomate" = vegetables)
///
/// Phase 2 feeds OCR receipt lines through this. It never saves anything by
/// itself - the user confirms every suggestion.
public enum GroceryItemClassifier {
    static let keywordsBySubcategory: [String: [String]] = [
        "groceries.meat": [
            "minist", "ministeak", "ministeaks", "geschnetzeltes", "cevapcici", "frikadelle", "nuggets",
            "hahnchen", "hähnchen", "haehn", "hahn", "huhn", "chicken", "pute", "puten", "truthahn", "turkey",
            "rind", "rinder", "beef", "schwein", "pork", "hack", "hackfleisch", "mince", "steak", "schnitzel",
            "wurst", "bratwurst", "wiener", "salami", "schinken", "ham", "speck", "bacon", "leberkas", "leberkäse",
            "gulasch", "lamm", "lamb", "fleisch", "meat", "brustfilet", "keule", "chicken wings", "wings", "kassler"
        ],
        "groceries.fish": [
            "lachs", "salmon", "thunfisch", "tuna", "fisch", "fish", "garnele", "garnelen", "shrimp", "prawn",
            "forelle", "trout", "kabeljau", "cod", "hering", "matjes", "seelachs", "muschel", "scampi", "sardine"
        ],
        "groceries.dairy": [
            "pudding", "pudd", "protein pudd", "dessert", "milchreis", "grießpudding", "sahnepudding", "rahm", "landmilch", "vollmilch", "hafermilch", "haferdrink", "sojadrink",
            "milch", "milk", "h milch", "joghurt", "jogurt", "yoghurt", "yogurt", "kase", "käse", "cheese", "gouda",
            "emmentaler", "mozzarella", "feta", "butter", "quark", "sahne", "cream", "schmand", "creme fraiche",
            "skyr", "kefir", "buttermilch", "frischkase", "frischkäse", "parmesan", "camembert", "ayran"
        ],
        "groceries.eggs": [
            "eier", "egg", "eggs", "freilandeier", "bodenhaltung"
        ],
        "groceries.vegetables": [
            "tomate", "tomaten", "tomato", "gurke", "cucumber", "salat", "lettuce", "eisbergsalat", "kartoffel",
            "kartoffeln", "potato", "zwiebel", "zwiebeln", "onion", "paprika", "pepper", "karotte", "karotten",
            "mohre", "möhre", "mohren", "carrot", "brokkoli", "broccoli", "zucchini", "blumenkohl", "kohl",
            "spinat", "spinach", "knoblauch", "garlic", "aubergine", "champignon", "pilze", "mushroom", "lauch",
            "sellerie", "radieschen", "ingwer", "ginger", "avocado", "rucola", "kurbis", "kürbis", "okra", "bohnen gruen"
        ],
        "groceries.fruits": [
            "nektarine", "nektarinen", "mandarinen", "clementinen", "aprikose", "feige", "datteln",
            "banane", "bananen", "banana", "apfel", "apfel ", "äpfel", "apple", "birne", "birnen", "pear",
            "orange", "orangen", "zitrone", "zitronen", "lemon", "limette", "trauben", "weintraube", "weintrauben",
            "grape", "beere", "beeren", "erdbeere", "erdbeeren", "strawberr", "heidelbeere", "himbeere", "mango",
            "ananas", "pineapple", "kiwi", "melone", "wassermelone", "pfirsich", "nektarine", "pflaume", "kirsche",
            "mandarine", "clementine", "granatapfel", "papaya"
        ],
        "groceries.bakery": [
            "blatterteig", "blätterteig", "pizzateig", "hefeteig", "mürbeteig", "murbeteig", "tortilla", "wraps", "knackebrot", "knäckebrot", "zwieback",
            "brot", "bread", "brotchen", "brötchen", "semmel", "toast", "toastbrot", "croissant", "brezel", "breze",
            "baguette", "vollkornbrot", "kuchen", "cake", "gebäck", "gebaeck", "backwaren", "laugen", "bagel", "muffin"
        ],
        "groceries.grains": [
            "reis", "rice", "basmati", "nudeln", "nudel", "pasta", "spaghetti", "penne", "fusilli", "lasagne",
            "mehl", "flour", "haferflocken", "oats", "musli", "müsli", "cornflakes", "couscous", "bulgur", "quinoa",
            "linsen", "lentil", "atta", "grieß", "griess"
        ],
        "groceries.canned": [
            "dose", "konserve", "canned", "passierte", "mais", "kichererbsen", "chickpea", "bohnen", "beans",
            "fertiggericht", "suppe", "soup", "instant", "ravioli"
        ],
        "groceries.snacks": [
            "schoko", "schokolade", "chocolate", "chips", "crisps", "keks", "kekse", "cookie", "biscuit", "gummi",
            "gummibar", "gummibärchen", "haribo", "bonbon", "riegel", "praline", "süßigkeiten", "suessigkeiten",
            "nutella", "erdnusse", "erdnüsse", "nuss", "nusse", "popcorn", "salzstangen", "cracker", "milka", "ritter sport"
        ],
        "groceries.beverages": [
            "direktsaft", "direktsa", "fruchtsaft", "traubensaft", "kombucha", "sirup",
            "wasser", "water", "mineralwasser", "sprudel", "saft", "juice", "orangensaft", "apfelsaft",
            "multivitaminsaft", "cola", "fanta", "sprite", "limo",
            "limonade", "bier", "beer", "wein", "wine", "sekt", "schorle", "eistee", "energy", "red bull", "smoothie",
            "pfand"
        ],
        "groceries.coffee": [
            "teebeutel", "fruchttee", "krautertee", "kräutertee",
            "kaffee", "coffee", "espresso", "cappuccino", "tee", "tea", "kakao", "cocoa", "kaffeepads", "kapseln",
            "bohnenkaffee", "chai"
        ],
        "groceries.condiments": [
            "salz", "salt", "pfeffer", "ketchup", "tomatenketchup", "senf", "mustard", "mayo", "mayonnaise", "essig", "vinegar",
            "speiseol", "speiseöl", "olivenol", "olivenöl", "olive oil", "sonnenblumenol", "sonnenblumenöl", "rapsol",
            "rapsöl", "sosse", "soße", "sauce", "gewurz", "gewürz", "spice", "curry", "paprikapulver", "bruhe",
            "brühe", "zucker", "sugar", "honig", "honey", "marmelade", "konfitüre", "pesto", "sojasauce", "masala"
        ],
        "groceries.frozen": [
            "tk", "tiefkuhl", "tiefkühl", "frozen", "eis", "eiscreme", "ice cream", "speiseeis", "pizza", "pommes",
            "fischstabchen", "fischstäbchen", "rahmspinat"
        ],
        "groceries.household": [
            "knotenbeutel", "obstbeutel", "tragetasche", "tragetüte", "papiertüte", "beutel",
            "toilettenpapier", "klopapier", "toilet paper", "kuchenrolle", "küchenrolle", "taschentucher",
            "taschentücher", "tissues", "mullbeutel", "müllbeutel", "alufolie", "frischhaltefolie", "backpapier",
            "servietten", "batterien", "gluhbirne", "kerzen", "zewa", "tempo"
        ],
        "groceries.cleaning": [
            "spulmittel", "spülmittel", "reiniger", "cleaner", "waschmittel", "detergent", "weichspuler",
            "weichspüler", "putzmittel", "spultabs", "spültabs", "geschirrspul", "entkalker", "wc reiniger",
            "schwamm", "sponge", "desinfektion", "bleach", "glasreiniger"
        ],
        "groceries.pet": [
            "katzenfutter", "hundefutter", "cat food", "dog food", "katzenstreu", "tierfutter", "whiskas", "felix",
            "pedigree", "sheba", "futter", "leckerli"
        ]
    ]

    private struct Entry {
        let keyword: String
        let subcategoryKey: String
    }

    private static let index: [Entry] = {
        var entries: [Entry] = []
        for (key, words) in keywordsBySubcategory {
            for word in words {
                let normalized = TextNormalizer.normalize(word, germanTransliteration: true)
                if normalized.count >= 2 {
                    entries.append(Entry(keyword: normalized, subcategoryKey: key))
                }
            }
        }
        // Longest first so the first hit is the most specific one.
        return entries.sorted { a, b in
            if a.keyword.count != b.keyword.count { return a.keyword.count > b.keyword.count }
            return a.keyword < b.keyword
        }
    }()

    public static func classify(_ itemText: String) -> GroceryClassification? {
        let text = TextNormalizer.normalize(itemText, germanTransliteration: true)
        guard !text.isEmpty else { return nil }
        for entry in index {
            let hit: Bool
            if entry.keyword.count <= 3 {
                // Very short keywords ("tk", "tee", "eis") must START a word,
                // so "Reis" is not read as "eis" and "TK-Pizza" still matches "tk".
                hit = startsAWord(entry.keyword, in: text)
            } else {
                hit = text.contains(entry.keyword)
            }
            if hit {
                let confidence: Double
                switch entry.keyword.count {
                case 6...: confidence = 0.9
                case 4...5: confidence = 0.75
                default: confidence = 0.6
                }
                return GroceryClassification(subcategoryKey: entry.subcategoryKey, matchedKeyword: entry.keyword, confidence: confidence)
            }
        }
        return nil
    }

    private static func startsAWord(_ keyword: String, in text: String) -> Bool {
        text.split(separator: " ").contains { $0.hasPrefix(keyword) }
    }
}
