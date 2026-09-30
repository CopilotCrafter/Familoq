import Foundation
import FamiloqCore

/// Kind of a family document in the vault.
public enum DocumentKind: String, CaseIterable, Identifiable, Sendable {
    case passport, idCard, drivingLicence, residencePermit, birthCertificate, marriageCertificate
    case insurance, carRegistration, certificate, medical, tax, contract, warranty, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .passport: return "Passport"
        case .idCard: return "ID card"
        case .drivingLicence: return "Driving licence"
        case .residencePermit: return "Residence permit"
        case .birthCertificate: return "Birth certificate"
        case .marriageCertificate: return "Marriage certificate"
        case .insurance: return "Insurance policy"
        case .carRegistration: return "Car registration"
        case .certificate: return "Certificate / diploma"
        case .medical: return "Medical document"
        case .tax: return "Tax document"
        case .contract: return "Contract"
        case .warranty: return "Warranty / invoice"
        case .other: return "Other"
        }
    }

    public var icon: String {
        switch self {
        case .passport: return "person.text.rectangle.fill"
        case .idCard: return "person.crop.rectangle.fill"
        case .drivingLicence: return "car.circle.fill"
        case .residencePermit: return "person.badge.shield.checkmark.fill"
        case .birthCertificate: return "figure.and.child.holdinghands"
        case .marriageCertificate: return "heart.text.square.fill"
        case .insurance: return "shield.lefthalf.filled"
        case .carRegistration: return "car.fill"
        case .certificate: return "graduationcap.fill"
        case .medical: return "cross.case.fill"
        case .tax: return "building.columns.fill"
        case .contract: return "signature"
        case .warranty: return "checkmark.shield.fill"
        case .other: return "doc.fill"
        }
    }

    /// Documents that usually run out (ask for the expiry date).
    public var usuallyExpires: Bool {
        switch self {
        case .passport, .idCard, .drivingLicence, .residencePermit, .insurance: return true
        default: return false
        }
    }

    /// Belongs to a person (passport) rather than the household.
    public var isPersonal: Bool {
        switch self {
        case .passport, .idCard, .drivingLicence, .residencePermit, .birthCertificate, .certificate, .medical: return true
        default: return false
        }
    }

    /// Days before expiry to remind. Passports take weeks to renew.
    public var reminderDays: [Int] {
        switch self {
        case .passport, .idCard, .residencePermit: return [90, 30]
        default: return [30, 7]
        }
    }
}

public enum DocumentExpiry {
    public enum State: Equatable, Sendable {
        case valid, soon(days: Int), expired
    }

    public static func state(expiresOn: Date?, now: Date, calendar: Calendar, soonDays: Int = 90) -> State? {
        guard let expiresOn else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: expiresOn)).day ?? 0
        if days < 0 { return .expired }
        if days <= soonDays { return .soon(days: days) }
        return .valid
    }

    /// Reminder times (9:00) that are still ahead.
    public static func reminders(expiresOn: Date, days: [Int], now: Date, calendar: Calendar) -> [(days: Int, date: Date)] {
        days.compactMap { d in
            guard let day = calendar.date(byAdding: .day, value: -d, to: calendar.startOfDay(for: expiresOn)),
                  let at = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day), at > now else { return nil }
            return (d, at)
        }
    }
}

extension DocumentKind {
    /// Cards with a front and a back (scanned as two sides).
    public var isTwoSided: Bool {
        switch self {
        case .idCard, .drivingLicence, .residencePermit, .carRegistration: return true
        default: return false
        }
    }
}

/// Which side of a card a page shows.
public enum PageSide: String, CaseIterable, Sendable {
    case none = "", front, back

    public var title: String {
        switch self {
        case .none: return "Page"
        case .front: return "Front"
        case .back: return "Back"
        }
    }
}

public enum DocumentLayout {
    /// Groups pages for "both sides on one A4 page": a front followed by its
    /// back share a page; two unlabeled photos of a card-type document too.
    /// Everything else stays alone. Returns page indices.
    public static func pairs(sides: [PageSide], isImage: [Bool], pairUnlabeled: Bool) -> [[Int]] {
        var result: [[Int]] = []
        var i = 0
        while i < sides.count {
            let next = i + 1
            if next < sides.count, isImage[i], isImage[next] {
                let labeled = sides[i] == .front && sides[next] == .back
                let unlabeled = pairUnlabeled && sides[i] == .none && sides[next] == .none
                if labeled || unlabeled {
                    result.append([i, next])
                    i += 2
                    continue
                }
            }
            result.append([i])
            i += 1
        }
        return result
    }
}

/// "KOPIE – nur für … – 30.09.2026" stamped over shared copies.
public enum CopyStamp {
    public enum Language: String, CaseIterable, Sendable {
        case german = "de", english = "en"

        public var title: String { self == .german ? "Deutsch" : "English" }
    }

    public static func text(language: Language, purpose: String, date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.day, .month, .year], from: date)
        let day = String(format: "%02d.%02d.%04d", c.day ?? 1, c.month ?? 1, c.year ?? 2000)
        let what = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        switch language {
        case .german:
            return what.isEmpty ? "KOPIE – \(day)" : "KOPIE – nur für \(what) – \(day)"
        case .english:
            let english = String(format: "%02d/%02d/%04d", c.day ?? 1, c.month ?? 1, c.year ?? 2000)
            return what.isEmpty ? "COPY – \(english)" : "COPY – only for \(what) – \(english)"
        }
    }
}

/// Tags ("Car", "Taxes 2026") of a document, stored comma-separated.
public enum DocumentTags {
    public static func parse(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { tag in
            guard !tag.isEmpty else { return false }
            return seen.insert(tag.lowercased()).inserted
        }
    }

    public static func encode(_ tags: [String]) -> String {
        parse(tags.map { $0.replacingOccurrences(of: ",", with: " ") }.joined(separator: ",")).joined(separator: ",")
    }

    /// Offered in the form (the year for taxes is the current one).
    public static func suggested(year: Int) -> [String] {
        ["Car", "House", "Kids", "Insurance", "Travel", "Health", "Work", "Taxes \(year)"]
    }
}

/// Search over a document's fields and the text read from its pages.
public enum DocumentSearch {
    /// Every word of the query must appear (umlauts and case ignored).
    public static func matches(query: String, in texts: [String]) -> Bool {
        let words = TextNormalizer.normalize(query, germanTransliteration: true).split(separator: " ")
        guard !words.isEmpty else { return true }
        let haystack = texts.map { TextNormalizer.normalize($0, germanTransliteration: true) }.joined(separator: " ")
        return words.allSatisfy { haystack.contains($0) }
    }
}
