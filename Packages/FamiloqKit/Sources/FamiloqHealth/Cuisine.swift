import Foundation

/// Major cuisines the family can rank for meal suggestions, each with regions
/// (German and Indian by state, others by culinary region).
public enum Cuisine: String, CaseIterable, Codable, Sendable, Identifiable {
    case german = "de"
    case indian = "in"
    case italian = "it"
    case greek = "gr"
    case turkish = "tr"
    case levantine = "lv"
    case chinese = "cn"
    case japanese = "jp"
    case korean = "kr"
    case thai = "th"
    case vietnamese = "vn"
    case mexican = "mx"
    case spanish = "es"
    case french = "fr"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .german: return "German"
        case .indian: return "Indian"
        case .italian: return "Italian"
        case .greek: return "Greek & Mediterranean"
        case .turkish: return "Turkish"
        case .levantine: return "Lebanese & Middle Eastern"
        case .chinese: return "Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .thai: return "Thai"
        case .vietnamese: return "Vietnamese"
        case .mexican: return "Mexican"
        case .spanish: return "Spanish"
        case .french: return "French"
        }
    }

    public var flag: String {
        switch self {
        case .german: return "🇩🇪"
        case .indian: return "🇮🇳"
        case .italian: return "🇮🇹"
        case .greek: return "🇬🇷"
        case .turkish: return "🇹🇷"
        case .levantine: return "🇱🇧"
        case .chinese: return "🇨🇳"
        case .japanese: return "🇯🇵"
        case .korean: return "🇰🇷"
        case .thai: return "🇹🇭"
        case .vietnamese: return "🇻🇳"
        case .mexican: return "🇲🇽"
        case .spanish: return "🇪🇸"
        case .french: return "🇫🇷"
        }
    }

    /// Regions offered as sub-preference ("states" for Germany and India).
    public var regions: [CuisineRegion] {
        switch self {
        case .german:
            return [
                .init("bw", "Baden-Württemberg"), .init("by", "Bavaria"), .init("be", "Berlin"), .init("bb", "Brandenburg"),
                .init("hb", "Bremen"), .init("hh", "Hamburg"), .init("he", "Hesse"), .init("mv", "Mecklenburg-Vorpommern"),
                .init("ni", "Lower Saxony"), .init("nw", "North Rhine-Westphalia"), .init("rp", "Rhineland-Palatinate"),
                .init("sl", "Saarland"), .init("sn", "Saxony"), .init("st", "Saxony-Anhalt"), .init("sh", "Schleswig-Holstein"),
                .init("th", "Thuringia")
            ]
        case .indian:
            return [
                .init("ap", "Andhra Pradesh"), .init("br", "Bihar"), .init("ga", "Goa"), .init("gj", "Gujarat"),
                .init("jk", "Kashmir"), .init("ka", "Karnataka"), .init("kl", "Kerala"), .init("mh", "Maharashtra"),
                .init("od", "Odisha"), .init("pb", "Punjab"), .init("rj", "Rajasthan"), .init("tn", "Tamil Nadu"),
                .init("tg", "Telangana (Hyderabad)"), .init("up", "Uttar Pradesh & Delhi"), .init("wb", "West Bengal")
            ]
        case .italian:
            return [
                .init("cam", "Campania (Naples)"), .init("emr", "Emilia-Romagna"), .init("laz", "Lazio (Rome)"),
                .init("lig", "Liguria"), .init("lom", "Lombardy"), .init("pug", "Apulia"), .init("sic", "Sicily"),
                .init("tos", "Tuscany"), .init("ven", "Veneto")
            ]
        case .greek:
            return [.init("crete", "Crete")]
        case .turkish:
            return [.init("ege", "Aegean"), .init("gaz", "Southeast (Gaziantep)"), .init("ist", "Istanbul"), .init("kar", "Black Sea")]
        case .levantine:
            return [.init("leb", "Lebanon"), .init("pal", "Palestine & Jordan"), .init("syr", "Syria")]
        case .chinese:
            return [.init("gd", "Cantonese"), .init("hn", "Hunan"), .init("js", "Shanghai & Jiangsu"), .init("sd", "Shandong & North"), .init("sc", "Sichuan")]
        case .japanese:
            return [.init("hokkaido", "Hokkaido"), .init("kansai", "Kansai (Osaka)"), .init("kyushu", "Kyushu")]
        case .korean:
            return []
        case .thai:
            return [.init("central", "Central (Bangkok)"), .init("isan", "Isan (Northeast)"), .init("north", "North (Chiang Mai)"), .init("south", "South")]
        case .vietnamese:
            return [.init("north", "North (Hanoi)"), .init("central", "Central (Huế)"), .init("south", "South (Saigon)")]
        case .mexican:
            return [.init("cdmx", "Mexico City"), .init("oax", "Oaxaca"), .init("yuc", "Yucatán")]
        case .spanish:
            return [.init("and", "Andalusia"), .init("bas", "Basque Country"), .init("cat", "Catalonia"), .init("gal", "Galicia"), .init("val", "Valencia")]
        case .french:
            return [.init("als", "Alsace"), .init("bre", "Brittany"), .init("bur", "Burgundy"), .init("lyo", "Lyon"), .init("pro", "Provence")]
        }
    }
}

public struct CuisineRegion: Hashable, Sendable, Identifiable {
    public let code: String
    public let title: String
    public var id: String { code }

    public init(_ code: String, _ title: String) {
        self.code = code
        self.title = title
    }
}

/// One ranked cuisine with 0-2 regions.
public struct CuisinePreference: Codable, Hashable, Sendable {
    public var cuisine: Cuisine
    public var regions: [String]

    public init(cuisine: Cuisine, regions: [String] = []) {
        self.cuisine = cuisine
        self.regions = regions
    }

    /// Stored as "de:by,bw;in:kl" (stable text for sync).
    public static func encode(_ list: [CuisinePreference]) -> String {
        list.map { $0.cuisine.rawValue + ":" + $0.regions.joined(separator: ",") }.joined(separator: ";")
    }

    public static func decode(_ text: String) -> [CuisinePreference] {
        text.split(separator: ";").compactMap { part in
            let pieces = part.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard let cuisine = Cuisine(rawValue: String(pieces[0])) else { return nil }
            let regions = pieces.count > 1 ? pieces[1].split(separator: ",").map(String.init) : []
            return CuisinePreference(cuisine: cuisine, regions: regions)
        }
    }

    /// Dinners per cuisine for a number of days, by rank (weights 4:3:2:1).
    public static func allocation(_ list: [CuisinePreference], days: Int) -> [Cuisine: Int] {
        let ranked = Array(list.prefix(4))
        guard !ranked.isEmpty, days > 0 else { return [:] }
        let weights = [4.0, 3.0, 2.0, 1.0].prefix(ranked.count)
        let total = weights.reduce(0, +)
        var result: [Cuisine: Int] = [:]
        var remainders: [(Cuisine, Double, Int)] = []
        var assigned = 0
        for (index, pref) in ranked.enumerated() {
            let exact = Double(days) * weights[index] / total
            let whole = Int(exact.rounded(.down))
            result[pref.cuisine] = whole
            assigned += whole
            remainders.append((pref.cuisine, exact - Double(whole), index))
        }
        // Largest remainder first; ties go to the higher rank.
        remainders.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
        var i = 0
        while assigned < days {
            result[remainders[i % remainders.count].0, default: 0] += 1
            assigned += 1
            i += 1
        }
        return result
    }

    /// Order of cuisines over the days, spread out (not 3 German days in a row).
    public static func sequence(_ list: [CuisinePreference], days: Int) -> [Cuisine] {
        let counts = allocation(list, days: days)
        let ranked = Array(list.prefix(4)).map(\.cuisine)
        var remaining = counts
        var result: [Cuisine] = []
        var credit: [Cuisine: Double] = [:]
        for _ in 0..<days {
            // Smooth weighted round robin.
            for cuisine in ranked { credit[cuisine, default: 0] += Double(counts[cuisine] ?? 0) }
            let candidates = ranked.filter { (remaining[$0] ?? 0) > 0 && $0 != result.last }
            let pool = candidates.isEmpty ? ranked.filter { (remaining[$0] ?? 0) > 0 } : candidates
            guard let pick = pool.max(by: { (credit[$0] ?? 0) < (credit[$1] ?? 0) }) else { break }
            credit[pick, default: 0] -= Double(days)
            remaining[pick, default: 0] -= 1
            result.append(pick)
        }
        return result
    }
}
