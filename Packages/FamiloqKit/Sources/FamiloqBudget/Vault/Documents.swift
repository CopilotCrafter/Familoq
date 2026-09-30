import Foundation

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
