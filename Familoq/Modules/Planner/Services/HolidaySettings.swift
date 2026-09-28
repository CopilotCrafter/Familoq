import Foundation
import SwiftUI
import StoreKit
import FamiloqCore
import FamiloqPlanner

/// Which public holidays the calendar shows (this iPhone). The country comes
/// from the App Store account unless chosen; no state = nationwide only.
@MainActor
final class HolidaySettings: ObservableObject {
    static let shared = HolidaySettings()

    @Published private(set) var country: String
    @Published private(set) var state: String?
    /// Country of the App Store account (if Familoq could read it).
    @Published private(set) var storeCountry: String?

    private static let countryKey = "holidays.country"
    private static let stateKey = "holidays.state"
    private static let storeKey = "holidays.storeCountry"
    private var cache: [String: [Date: String]] = [:]

    private init() {
        let defaults = UserDefaults.standard
        storeCountry = defaults.string(forKey: Self.storeKey)
        country = defaults.string(forKey: Self.countryKey)
            ?? defaults.string(forKey: Self.storeKey)
            ?? Self.regionCountry()
        state = defaults.string(forKey: Self.stateKey)
    }

    /// The iPhone's region as a fallback ("DE").
    static func regionCountry() -> String {
        let region = Locale.current.region?.identifier ?? "DE"
        return PublicHolidays.isSupported(region) ? region : "DE"
    }

    var isAutomatic: Bool { UserDefaults.standard.string(forKey: Self.countryKey) == nil }

    /// Reads the App Store country once (StoreKit, no permission needed).
    func refreshStoreCountry() async {
        guard let code = await Storefront.current?.countryCode, let alpha2 = PublicHolidays.alpha2(fromAlpha3: code) else { return }
        UserDefaults.standard.set(alpha2, forKey: Self.storeKey)
        storeCountry = alpha2
        if isAutomatic, country != alpha2 {
            country = alpha2
            state = nil
            UserDefaults.standard.removeObject(forKey: Self.stateKey)
            cache.removeAll()
        }
    }

    /// nil = automatic (App Store country).
    func setCountry(_ code: String?) {
        if let code {
            UserDefaults.standard.set(code, forKey: Self.countryKey)
            country = code
        } else {
            UserDefaults.standard.removeObject(forKey: Self.countryKey)
            country = storeCountry ?? Self.regionCountry()
        }
        setState(nil)
    }

    func setState(_ code: String?) {
        if let code { UserDefaults.standard.set(code, forKey: Self.stateKey) } else { UserDefaults.standard.removeObject(forKey: Self.stateKey) }
        state = code
        cache.removeAll()
        objectWillChange.send()
    }

    var countryName: String {
        let name = PublicHolidays.countries.first { $0.code == country }?.name ?? country
        return String(localized: String.LocalizationValue(name))
    }

    var stateName: String? {
        state.flatMap { code in PublicHolidays.states(of: country).first { $0.code == code }?.name }
            .map { String(localized: String.LocalizationValue($0)) }
    }

    /// Start of day -> English holiday name, for the years around `date`.
    func holidays(around date: Date, calendar: Calendar) -> [Date: String] {
        let year = calendar.component(.year, from: date)
        let key = "\(country)|\(state ?? "-")|\(year)|\(calendar.timeZone.identifier)"
        if let cached = cache[key] { return cached }
        let value = PublicHolidays.lookup(years: (year - 1)...(year + 1), country: country, state: state, calendar: calendar)
        cache[key] = value
        return value
    }
}

/// A colour per family member (by joining order), for time off.
enum MemberColors {
    static let palette = ["#4285F4", "#E91E63", "#00897B", "#FB8C00", "#8E24AA", "#6D4C41"]

    static func hex(for memberID: UUID, members: [FamilyMember]) -> String {
        let ordered = members.sorted { $0.joinedAt < $1.joinedAt }
        let index = ordered.firstIndex { $0.id == memberID } ?? 0
        return palette[index % palette.count]
    }
}

/// Saturday, Sunday and public holidays share one red (as asked).
enum CalendarColors {
    static let holidayRed = Color(hex: "#D32F2F")
}
