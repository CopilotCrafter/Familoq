import Foundation

/// Normalises free text (merchant names, receipt lines) for matching.
///
///   "REWE Markt GmbH"      -> "rewe markt gmbh"
///   "HAEHN.BRUSTFILET"     -> "hahn brustfilet"   (with `germanTransliteration`)
///   "Hähnchenbrust"        -> "hahnchenbrust"     (with `germanTransliteration`)
public enum TextNormalizer {
    public static func normalize(_ text: String, germanTransliteration: Bool = false) -> String {
        var s = text.lowercased()
        s = s.replacingOccurrences(of: "ß", with: "ss")
        s = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        if germanTransliteration {
            // Receipts often print umlauts as ae/oe/ue. Collapse both spellings
            // to the same key: "Hähnchen" and "HAEHNCHEN" -> "hahnchen".
            s = s.replacingOccurrences(of: "ae", with: "a")
            s = s.replacingOccurrences(of: "oe", with: "o")
            s = s.replacingOccurrences(of: "ue", with: "u")
        }
        var out = ""
        out.reserveCapacity(s.count)
        var lastWasSpace = true
        for ch in s {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        if out.hasSuffix(" ") { out.removeLast() }
        return out
    }
}
