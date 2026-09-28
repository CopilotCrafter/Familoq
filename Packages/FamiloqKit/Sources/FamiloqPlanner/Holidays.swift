import Foundation

/// A public holiday on one day (start of that day in the given calendar).
public struct PublicHoliday: Equatable, Sendable, Identifiable {
    public let date: Date
    /// English name; the app translates it.
    public let name: String
    public var id: Date { date }
}

public struct HolidayRegion: Equatable, Sendable, Identifiable {
    /// ISO 3166-1 alpha-2, e.g. "DE".
    public let code: String
    public let name: String
    public var id: String { code }
}

/// Public holidays calculated on the iPhone (no download): fixed dates,
/// dates relative to Easter and "n-th weekday of a month" rules.
public enum PublicHolidays {
    // MARK: Supported regions

    public static let countries: [HolidayRegion] = [
        .init(code: "DE", name: "Germany"), .init(code: "AT", name: "Austria"), .init(code: "CH", name: "Switzerland"),
        .init(code: "FR", name: "France"), .init(code: "IT", name: "Italy"), .init(code: "ES", name: "Spain"),
        .init(code: "NL", name: "Netherlands"), .init(code: "BE", name: "Belgium"), .init(code: "PL", name: "Poland"),
        .init(code: "CZ", name: "Czechia"), .init(code: "GB", name: "United Kingdom"), .init(code: "IE", name: "Ireland"),
        .init(code: "US", name: "United States"), .init(code: "IN", name: "India")
    ]

    public static func states(of country: String) -> [HolidayRegion] {
        switch country {
        case "DE":
            return [
                .init(code: "BW", name: "Baden-Württemberg"), .init(code: "BY", name: "Bavaria"), .init(code: "BE", name: "Berlin"),
                .init(code: "BB", name: "Brandenburg"), .init(code: "HB", name: "Bremen"), .init(code: "HH", name: "Hamburg"),
                .init(code: "HE", name: "Hesse"), .init(code: "MV", name: "Mecklenburg-Vorpommern"), .init(code: "NI", name: "Lower Saxony"),
                .init(code: "NW", name: "North Rhine-Westphalia"), .init(code: "RP", name: "Rhineland-Palatinate"), .init(code: "SL", name: "Saarland"),
                .init(code: "SN", name: "Saxony"), .init(code: "ST", name: "Saxony-Anhalt"), .init(code: "SH", name: "Schleswig-Holstein"),
                .init(code: "TH", name: "Thuringia")
            ]
        case "GB":
            return [.init(code: "ENG", name: "England & Wales"), .init(code: "SCT", name: "Scotland"), .init(code: "NIR", name: "Northern Ireland")]
        default:
            return []
        }
    }

    public static func isSupported(_ country: String) -> Bool { countries.contains { $0.code == country } }

    /// App Store countries come as alpha-3 ("DEU").
    public static func alpha2(fromAlpha3 code: String) -> String? {
        let map = ["DEU": "DE", "AUT": "AT", "CHE": "CH", "FRA": "FR", "ITA": "IT", "ESP": "ES", "NLD": "NL", "BEL": "BE",
                   "POL": "PL", "CZE": "CZ", "GBR": "GB", "IRL": "IE", "USA": "US", "IND": "IN"]
        return map[code.uppercased()]
    }

    // MARK: Calculation

    /// Easter Sunday (Gregorian, anonymous algorithm).
    public static func easter(_ year: Int, calendar: Calendar) -> Date {
        let a = year % 19, b = year / 100, c = year % 100, d = b / 4, e = b % 4
        let f = (b + 8) / 25, g = (b - f + 1) / 3, h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7, m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public static func holidays(year: Int, country: String, state: String?, calendar: Calendar) -> [PublicHoliday] {
        var list: [PublicHoliday] = []
        let easter = easter(year, calendar: calendar)

        func fixed(_ month: Int, _ day: Int, _ name: String) {
            if let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) {
                list.append(PublicHoliday(date: date, name: name))
            }
        }
        func fromEaster(_ days: Int, _ name: String) {
            if let date = calendar.date(byAdding: .day, value: days, to: easter) {
                list.append(PublicHoliday(date: calendar.startOfDay(for: date), name: name))
            }
        }
        /// n-th weekday (1 = Sunday … 7 = Saturday) of a month; n = -1 = last.
        func nth(_ n: Int, weekday: Int, month: Int, _ name: String) {
            guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let days = calendar.range(of: .day, in: .month, for: first) else { return }
            let matches = days.compactMap { day -> Date? in
                let date = calendar.date(from: DateComponents(year: year, month: month, day: day))!
                return calendar.component(.weekday, from: date) == weekday ? date : nil
            }
            let pick = n > 0 ? (n <= matches.count ? matches[n - 1] : nil) : matches.last
            if let pick { list.append(PublicHoliday(date: pick, name: name)) }
        }
        /// UK: a holiday on a weekend moves to the next free weekday.
        func substitute(_ month: Int, _ day: Int, _ name: String) {
            guard var date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return }
            while calendar.isDateInWeekend(date) || list.contains(where: { $0.date == date }) {
                date = calendar.date(byAdding: .day, value: 1, to: date)!
            }
            list.append(PublicHoliday(date: date, name: name))
        }

        switch country {
        case "DE":
            fixed(1, 1, "New Year's Day")
            if ["BW", "BY", "ST"].contains(state ?? "") { fixed(1, 6, "Epiphany") }
            if ["BE", "MV"].contains(state ?? "") { fixed(3, 8, "International Women's Day") }
            fromEaster(-2, "Good Friday")
            if state == "BB" { fromEaster(0, "Easter Sunday") }
            fromEaster(1, "Easter Monday")
            fixed(5, 1, "Labour Day")
            fromEaster(39, "Ascension Day")
            if state == "BB" { fromEaster(49, "Whit Sunday") }
            fromEaster(50, "Whit Monday")
            if ["BW", "BY", "HE", "NW", "RP", "SL"].contains(state ?? "") { fromEaster(60, "Corpus Christi") }
            if ["BY", "SL"].contains(state ?? "") { fixed(8, 15, "Assumption Day") }
            if state == "TH" { fixed(9, 20, "World Children's Day") }
            fixed(10, 3, "German Unity Day")
            if ["BB", "HB", "HH", "MV", "NI", "SN", "ST", "SH", "TH"].contains(state ?? "") { fixed(10, 31, "Reformation Day") }
            if ["BW", "BY", "NW", "RP", "SL"].contains(state ?? "") { fixed(11, 1, "All Saints' Day") }
            if state == "SN", let nov23 = calendar.date(from: DateComponents(year: year, month: 11, day: 23)) {
                // Wednesday before 23 November.
                var date = calendar.date(byAdding: .day, value: -1, to: nov23)!
                while calendar.component(.weekday, from: date) != 4 { date = calendar.date(byAdding: .day, value: -1, to: date)! }
                list.append(PublicHoliday(date: date, name: "Day of Prayer and Repentance"))
            }
            fixed(12, 25, "Christmas Day")
            fixed(12, 26, "St. Stephen's Day")
        case "AT":
            fixed(1, 1, "New Year's Day"); fixed(1, 6, "Epiphany"); fromEaster(1, "Easter Monday"); fixed(5, 1, "Labour Day")
            fromEaster(39, "Ascension Day"); fromEaster(50, "Whit Monday"); fromEaster(60, "Corpus Christi")
            fixed(8, 15, "Assumption Day"); fixed(10, 26, "National Day"); fixed(11, 1, "All Saints' Day")
            fixed(12, 8, "Immaculate Conception"); fixed(12, 25, "Christmas Day"); fixed(12, 26, "St. Stephen's Day")
        case "CH":
            fixed(1, 1, "New Year's Day"); fromEaster(-2, "Good Friday"); fromEaster(1, "Easter Monday")
            fromEaster(39, "Ascension Day"); fromEaster(50, "Whit Monday"); fixed(8, 1, "Swiss National Day")
            fixed(12, 25, "Christmas Day"); fixed(12, 26, "St. Stephen's Day")
        case "FR":
            fixed(1, 1, "New Year's Day"); fromEaster(1, "Easter Monday"); fixed(5, 1, "Labour Day"); fixed(5, 8, "Victory in Europe Day")
            fromEaster(39, "Ascension Day"); fromEaster(50, "Whit Monday"); fixed(7, 14, "Bastille Day"); fixed(8, 15, "Assumption Day")
            fixed(11, 1, "All Saints' Day"); fixed(11, 11, "Armistice Day"); fixed(12, 25, "Christmas Day")
        case "IT":
            fixed(1, 1, "New Year's Day"); fixed(1, 6, "Epiphany"); fromEaster(1, "Easter Monday"); fixed(4, 25, "Liberation Day")
            fixed(5, 1, "Labour Day"); fixed(6, 2, "Republic Day"); fixed(8, 15, "Assumption Day"); fixed(11, 1, "All Saints' Day")
            fixed(12, 8, "Immaculate Conception"); fixed(12, 25, "Christmas Day"); fixed(12, 26, "St. Stephen's Day")
        case "ES":
            fixed(1, 1, "New Year's Day"); fixed(1, 6, "Epiphany"); fromEaster(-2, "Good Friday"); fixed(5, 1, "Labour Day")
            fixed(8, 15, "Assumption Day"); fixed(10, 12, "National Day"); fixed(11, 1, "All Saints' Day")
            fixed(12, 6, "Constitution Day"); fixed(12, 8, "Immaculate Conception"); fixed(12, 25, "Christmas Day")
        case "NL":
            fixed(1, 1, "New Year's Day"); fromEaster(0, "Easter Sunday"); fromEaster(1, "Easter Monday")
            if let kingsDay = calendar.date(from: DateComponents(year: year, month: 4, day: 27)) {
                let date = calendar.component(.weekday, from: kingsDay) == 1 ? calendar.date(byAdding: .day, value: -1, to: kingsDay)! : kingsDay
                list.append(PublicHoliday(date: date, name: "King's Day"))
            }
            if year % 5 == 0 { fixed(5, 5, "Liberation Day") }
            fromEaster(39, "Ascension Day"); fromEaster(49, "Whit Sunday"); fromEaster(50, "Whit Monday")
            fixed(12, 25, "Christmas Day"); fixed(12, 26, "St. Stephen's Day")
        case "BE":
            fixed(1, 1, "New Year's Day"); fromEaster(1, "Easter Monday"); fixed(5, 1, "Labour Day"); fromEaster(39, "Ascension Day")
            fromEaster(50, "Whit Monday"); fixed(7, 21, "National Day"); fixed(8, 15, "Assumption Day"); fixed(11, 1, "All Saints' Day")
            fixed(11, 11, "Armistice Day"); fixed(12, 25, "Christmas Day")
        case "PL":
            fixed(1, 1, "New Year's Day"); fixed(1, 6, "Epiphany"); fromEaster(0, "Easter Sunday"); fromEaster(1, "Easter Monday")
            fixed(5, 1, "Labour Day"); fixed(5, 3, "Constitution Day"); fromEaster(49, "Whit Sunday"); fromEaster(60, "Corpus Christi")
            fixed(8, 15, "Assumption Day"); fixed(11, 1, "All Saints' Day"); fixed(11, 11, "Independence Day")
            if year >= 2025 { fixed(12, 24, "Christmas Eve") }
            fixed(12, 25, "Christmas Day"); fixed(12, 26, "St. Stephen's Day")
        case "CZ":
            fixed(1, 1, "New Year's Day"); fromEaster(-2, "Good Friday"); fromEaster(1, "Easter Monday"); fixed(5, 1, "Labour Day")
            fixed(5, 8, "Liberation Day"); fixed(7, 5, "Saints Cyril and Methodius Day"); fixed(7, 6, "Jan Hus Day")
            fixed(9, 28, "Statehood Day"); fixed(10, 28, "Independence Day"); fixed(11, 17, "Freedom and Democracy Day")
            fixed(12, 24, "Christmas Eve"); fixed(12, 25, "Christmas Day"); fixed(12, 26, "St. Stephen's Day")
        case "GB":
            let region = state ?? "ENG"
            substitute(1, 1, "New Year's Day")
            if region == "SCT" { substitute(1, 2, "2nd January") }
            if region == "NIR" { substitute(3, 17, "St Patrick's Day") }
            fromEaster(-2, "Good Friday")
            if region != "SCT" { fromEaster(1, "Easter Monday") }
            nth(1, weekday: 2, month: 5, "Early May Bank Holiday")
            nth(-1, weekday: 2, month: 5, "Spring Bank Holiday")
            if region == "NIR" { substitute(7, 12, "Battle of the Boyne") }
            if region == "SCT" { nth(1, weekday: 2, month: 8, "Summer Bank Holiday") } else { nth(-1, weekday: 2, month: 8, "Summer Bank Holiday") }
            if region == "SCT" { substitute(11, 30, "St Andrew's Day") }
            substitute(12, 25, "Christmas Day")
            substitute(12, 26, "Boxing Day")
        case "IE":
            fixed(1, 1, "New Year's Day")
            if let feb1 = calendar.date(from: DateComponents(year: year, month: 2, day: 1)), calendar.component(.weekday, from: feb1) == 6 {
                list.append(PublicHoliday(date: feb1, name: "St Brigid's Day"))
            } else {
                nth(1, weekday: 2, month: 2, "St Brigid's Day")
            }
            fixed(3, 17, "St Patrick's Day"); fromEaster(1, "Easter Monday")
            nth(1, weekday: 2, month: 5, "May Bank Holiday"); nth(1, weekday: 2, month: 6, "June Bank Holiday")
            nth(1, weekday: 2, month: 8, "August Bank Holiday"); nth(-1, weekday: 2, month: 10, "October Bank Holiday")
            fixed(12, 25, "Christmas Day"); fixed(12, 26, "St. Stephen's Day")
        case "US":
            fixed(1, 1, "New Year's Day"); nth(3, weekday: 2, month: 1, "Martin Luther King Jr. Day")
            nth(3, weekday: 2, month: 2, "Presidents' Day"); nth(-1, weekday: 2, month: 5, "Memorial Day")
            fixed(6, 19, "Juneteenth"); fixed(7, 4, "Independence Day"); nth(1, weekday: 2, month: 9, "Labor Day")
            nth(2, weekday: 2, month: 10, "Columbus Day"); fixed(11, 11, "Veterans Day")
            nth(4, weekday: 5, month: 11, "Thanksgiving"); fixed(12, 25, "Christmas Day")
        case "IN":
            fixed(1, 26, "Republic Day"); fixed(8, 15, "Independence Day"); fixed(10, 2, "Gandhi Jayanti")
        default:
            break
        }
        return list.sorted { $0.date < $1.date }
    }

    /// Holidays by start of day, for several years (for a calendar view).
    public static func lookup(years: ClosedRange<Int>, country: String, state: String?, calendar: Calendar) -> [Date: String] {
        var result: [Date: String] = [:]
        for year in years {
            for holiday in holidays(year: year, country: country, state: state, calendar: calendar) where result[holiday.date] == nil {
                result[holiday.date] = holiday.name
            }
        }
        return result
    }
}
