import Foundation

/// Scales ingredient amounts for guests or "cook double".
public enum IngredientScaler {
    /// "500 g Hack" x 1.5 -> "750 g Hack"; "1/2 Weißkohl" x 2 -> "1 Weißkohl"; "Salz" stays.
    public static func scale(_ line: String, by factor: Double) -> String {
        guard factor > 0, abs(factor - 1) > 0.001 else { return line }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(of: " ") else { return line }
        let first = String(trimmed[..<space])
        let rest = String(trimmed[space...])
        guard let value = number(first) else { return line }
        return format(value * factor) + rest
    }

    static func number(_ text: String) -> Double? {
        if text.contains("/") {
            let parts = text.split(separator: "/")
            guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 else { return nil }
            return a / b
        }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }

    /// Sensible rounding: 750, 1,5, 2, 0,5.
    static func format(_ value: Double) -> String {
        let rounded: Double
        if value >= 100 { rounded = (value / 10).rounded() * 10 }
        else if value >= 10 { rounded = value.rounded() }
        else { rounded = (value * 2).rounded() / 2 }
        let final = max(rounded, 0.5)
        if final == final.rounded() { return String(Int(final)) }
        return String(format: "%.1f", final).replacingOccurrences(of: ".", with: ",")
    }
}

/// A recipe read from a web page or a photographed cookbook page.
public struct ImportedRecipe: Equatable, Sendable {
    public var name: String
    public var ingredients: [String]
    public var steps: [String]
    public var servings: Int?

    public init(name: String, ingredients: [String], steps: [String], servings: Int?) {
        self.name = name
        self.ingredients = ingredients
        self.steps = steps
        self.servings = servings
    }
}

public enum RecipeImport {
    /// Reads the schema.org "Recipe" data that most recipe sites embed
    /// (Chefkoch, BBC Good Food, …) in `<script type="application/ld+json">`.
    public static func parse(html: String) -> ImportedRecipe? {
        for json in ldJSONBlocks(html) {
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let recipe = findRecipe(object) { return recipe }
        }
        return nil
    }

    static func ldJSONBlocks(_ html: String) -> [String] {
        var result: [String] = []
        var search = html.startIndex
        while let open = html.range(of: "application/ld+json", options: .caseInsensitive, range: search..<html.endIndex),
              let tagEnd = html.range(of: ">", range: open.upperBound..<html.endIndex),
              let close = html.range(of: "</script>", options: .caseInsensitive, range: tagEnd.upperBound..<html.endIndex) {
            result.append(String(html[tagEnd.upperBound..<close.lowerBound]))
            search = close.upperBound
        }
        return result
    }

    static func findRecipe(_ object: Any) -> ImportedRecipe? {
        if let array = object as? [Any] {
            for item in array { if let r = findRecipe(item) { return r } }
            return nil
        }
        guard let dict = object as? [String: Any] else { return nil }
        if let graph = dict["@graph"], let r = findRecipe(graph) { return r }
        let type = dict["@type"]
        let isRecipe = (type as? String) == "Recipe" || ((type as? [String])?.contains("Recipe") ?? false)
        guard isRecipe else { return nil }
        let name = clean((dict["name"] as? String) ?? "")
        let ingredients = ((dict["recipeIngredient"] as? [String]) ?? (dict["ingredients"] as? [String]) ?? []).map(clean).filter { !$0.isEmpty }
        let steps = instructions(dict["recipeInstructions"])
        return ImportedRecipe(name: name, ingredients: ingredients, steps: steps, servings: servings(dict["recipeYield"]))
    }

    static func instructions(_ value: Any?) -> [String] {
        if let text = value as? String {
            return text.components(separatedBy: CharacterSet.newlines).map(clean).filter { !$0.isEmpty }
        }
        guard let items = value as? [Any] else { return [] }
        var result: [String] = []
        for item in items {
            if let text = item as? String {
                result.append(clean(text))
            } else if let dict = item as? [String: Any] {
                if let list = dict["itemListElement"] {
                    result.append(contentsOf: instructions(list))
                } else if let text = (dict["text"] as? String) ?? (dict["name"] as? String) {
                    result.append(clean(text))
                }
            }
        }
        return result.filter { !$0.isEmpty }
    }

    static func servings(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        let text: String?
        if let s = value as? String { text = s } else if let list = value as? [Any] { text = list.first.map { "\($0)" } } else { text = nil }
        guard let text else { return nil }
        let digits = text.prefix { $0.isNumber || $0 == " " }.filter(\.isNumber)
        return Int(digits).flatMap { $0 > 0 && $0 < 100 ? $0 : nil }
    }

    /// Removes HTML tags and entities.
    static func clean(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&amp;": "&", "&nbsp;": " ", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">",
                        "&auml;": "ä", "&ouml;": "ö", "&uuml;": "ü", "&Auml;": "Ä", "&Ouml;": "Ö", "&Uuml;": "Ü", "&szlig;": "ß"]
        for (key, value) in entities { s = s.replacingOccurrences(of: key, with: value) }
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Photographed cookbook page -> recipe. The first line is the name;
    /// lines starting with an amount are ingredients; the rest are steps.
    public static func parse(lines: [String]) -> ImportedRecipe? {
        let cleaned = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count > 1 }
        guard let first = cleaned.first else { return nil }
        var ingredients: [String] = []
        var steps: [String] = []
        var servings: Int?
        var current = ""
        let units: Set<String> = ["g", "kg", "ml", "l", "el", "tl", "prise", "stk", "stück", "bund", "dose", "dosen", "tasse",
                                  "cup", "cups", "tbsp", "tsp", "oz", "lb", "pck", "packung", "zehe", "zehen", "scheiben", "becher"]
        for line in cleaned.dropFirst() {
            let lower = line.lowercased()
            if servings == nil, lower.contains("portion") || lower.contains("personen") || lower.contains("serves") || lower.contains("servings") {
                servings = Int(lower.filter(\.isNumber).prefix(2))
                continue
            }
            let firstWord = lower.split(separator: " ").first.map(String.init) ?? ""
            let startsWithAmount = firstWord.first.map { $0.isNumber || "½¼¾".contains($0) } ?? false
            let isShort = line.count <= 45
            if isShort && (startsWithAmount || units.contains(firstWord)) && steps.isEmpty {
                ingredients.append(line)
            } else if isShort && steps.isEmpty && ingredients.count > 0 && !line.hasSuffix(".") {
                ingredients.append(line)
            } else {
                // Steps: join wrapped lines until a sentence ends.
                current += (current.isEmpty ? "" : " ") + line
                if line.hasSuffix(".") || line.hasSuffix("!") {
                    steps.append(current)
                    current = ""
                }
            }
        }
        if !current.isEmpty { steps.append(current) }
        guard !ingredients.isEmpty || !steps.isEmpty else { return nil }
        return ImportedRecipe(name: first, ingredients: ingredients, steps: steps, servings: servings)
    }
}
