import Foundation
import FamiloqCore

/// Key for remembering how the family files a receipt item.
///
/// Receipts print the same product slightly differently (sizes, fat
/// percentages, article numbers), so those parts are dropped:
///   "Blätterteig,275g"      -> "blatterteig"
///   "Landmilch 3,8%"        -> "landmilch"
///   "486763 Hähn. Minist."  -> "hahn minist"
public enum ItemRuleKey {
    private static let measure = try! NSRegularExpression(
        pattern: #"^\d+([.,]\d+)?(g|gr|kg|l|ml|cl|stk|st|x|er|%)?$"#, options: [.caseInsensitive])

    public static func make(_ name: String) -> String {
        // Keep decimal commas together ("3,8%") before normalising.
        let text = name.replacingOccurrences(of: #"(\d)[.,](\d)"#, with: "$1.$2", options: .regularExpression)
        let words = text.split(whereSeparator: { $0 == " " || $0 == "," || $0 == ";" || $0 == "/" })
            .map(String.init)
            .filter { word in
                let range = NSRange(word.startIndex..., in: word)
                return measure.firstMatch(in: word, range: range) == nil
            }
        return TextNormalizer.normalize(words.joined(separator: " "), germanTransliteration: true)
            .split(separator: " ")
            .filter { !$0.allSatisfy(\.isNumber) }
            .joined(separator: " ")
    }
}
