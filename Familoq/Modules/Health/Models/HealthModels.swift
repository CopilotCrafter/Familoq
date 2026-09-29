import Foundation
import SwiftData
import FamiloqCore
import FamiloqHealth

// Health space. Every record can be "Only on this iPhone" (`isPrivate`):
// it is then left out of family sync and stays on the iPhone that created it.

/// A person in the family's health view - a member with the app or a child
/// / relative without it.
@Model
final class HealthPerson {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var name: String = ""
    /// Linked family member (nil for children without the app).
    var memberID: UUID? = nil
    var birthDate: Date? = nil
    var conditionsRaw: String = ""
    var allergensRaw: String = ""
    var bloodType: String = ""
    var emergencyName: String = ""
    var emergencyPhone: String = ""
    var notes: String = ""
    /// Members who get this person's reminders (comma-separated IDs;
    /// empty = the person themselves, or everyone for someone without the app).
    var remindMembersRaw: String = ""
    var isPrivate: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, name: String) {
        self.id = id
        self.familyID = familyID
        self.name = name
    }

    var conditions: Set<HealthCondition> {
        get { Set(conditionsRaw.split(separator: ",").compactMap { HealthCondition(rawValue: String($0)) }) }
        set { conditionsRaw = newValue.map(\.rawValue).sorted().joined(separator: ",") }
    }

    var allergens: Set<FoodAllergen> {
        get { Set(allergensRaw.split(separator: ",").compactMap { FoodAllergen(rawValue: String($0)) }) }
        set { allergensRaw = newValue.map(\.rawValue).sorted().joined(separator: ",") }
    }

    var remindMembers: Set<UUID> {
        get { Set(remindMembersRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) }) }
        set { remindMembersRaw = newValue.map(\.uuidString).sorted().joined(separator: ",") }
    }

    /// Whose iPhones ring for this person's reminders (empty = everyone).
    var reminderTargets: Set<UUID> {
        if !remindMembers.isEmpty { return remindMembers }
        if let memberID { return [memberID] }
        return []
    }

    var dietPerson: DietPerson { DietPerson(name: name, conditions: conditions, allergens: allergens) }

    func age(on date: Date = Date()) -> Int? {
        guard let birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: date).year
    }
}

/// A regular check-up (dentist every 6 months …) of one person.
@Model
final class Checkup {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var personID: UUID = UUID()
    var kindRaw: String = CheckupKind.dentist.rawValue
    var title: String = ""
    var lastDate: Date? = nil
    var intervalMonths: Int = 6
    /// Booked appointment (overrides the calculated date).
    var appointment: Date? = nil
    /// Children's exams already done ("U3,U4").
    var doneExamsRaw: String = ""
    var note: String = ""
    var remind: Bool = true
    var isPrivate: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, personID: UUID, kind: CheckupKind) {
        self.id = id
        self.familyID = familyID
        self.personID = personID
        self.kindRaw = kind.rawValue
        self.intervalMonths = kind.defaultMonths
    }

    var kind: CheckupKind {
        get { CheckupKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    var doneExams: Set<String> {
        get { Set(doneExamsRaw.split(separator: ",").map(String.init)) }
        set { doneExamsRaw = newValue.sorted().joined(separator: ",") }
    }

    var displayTitle: String {
        kind == .custom && !title.isEmpty ? title : String(localized: String.LocalizationValue(kind.title))
    }
}

/// One vaccination (with the next booster).
@Model
final class Vaccination {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var personID: UUID = UUID()
    var kindRaw: String = VaccineKind.tetanusDiphtheriaPertussis.rawValue
    var title: String = ""
    var date: Date = Date()
    var boosterMonths: Int = 0
    /// Explicit next date (e.g. second dose); nil = date + booster interval.
    var nextDue: Date? = nil
    var batch: String = ""
    var note: String = ""
    var tripID: UUID? = nil
    var isPrivate: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, personID: UUID, kind: VaccineKind, date: Date) {
        self.id = id
        self.familyID = familyID
        self.personID = personID
        self.kindRaw = kind.rawValue
        self.date = date
        self.boosterMonths = kind.defaultBoosterMonths
    }

    var kind: VaccineKind {
        get { VaccineKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    var displayTitle: String {
        kind == .custom && !title.isEmpty ? title : String(localized: String.LocalizationValue(kind.title))
    }

    func due(calendar: Calendar) -> Date? {
        nextDue ?? HealthDue.next(after: date, months: boosterMonths, calendar: calendar)
    }
}

/// A medication with dose reminders and a refill reminder.
@Model
final class Medication {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var personID: UUID = UUID()
    var name: String = ""
    var dose: String = ""
    /// Reminder times "08:00,20:00".
    var timesRaw: String = ""
    /// Tablets (or units) per day, for the refill date.
    var perDay: Double = 1
    /// Units left on `stockDate`.
    var stock: Double = 0
    var stockDate: Date = Date()
    var remindDoses: Bool = true
    var remindRefill: Bool = true
    var isActive: Bool = true
    var note: String = ""
    var isPrivate: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, personID: UUID, name: String) {
        self.id = id
        self.familyID = familyID
        self.personID = personID
        self.name = name
    }

    /// (hour, minute) of each reminder.
    var times: [(hour: Int, minute: Int)] {
        get {
            timesRaw.split(separator: ",").compactMap { part in
                let hm = part.split(separator: ":").compactMap { Int($0) }
                guard hm.count == 2, (0..<24).contains(hm[0]), (0..<60).contains(hm[1]) else { return nil }
                return (hour: hm[0], minute: hm[1])
            }
        }
        set { timesRaw = newValue.map { String(format: "%02d:%02d", $0.hour, $0.minute) }.joined(separator: ",") }
    }

    func runOut(calendar: Calendar) -> Date? {
        guard stock > 0 else { return nil }
        return Refill.runOutDate(stock: stock, perDay: perDay, from: stockDate, calendar: calendar)
    }

    func remaining(now: Date = Date(), calendar: Calendar) -> Double {
        Refill.remaining(stock: stock, perDay: perDay, from: stockDate, now: now, calendar: calendar)
    }
}

/// Blood pressure, blood sugar, weight … for charts and the doctor.
@Model
final class HealthMeasurement {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var personID: UUID = UUID()
    var typeRaw: String = MeasurementType.bloodPressure.rawValue
    var value: Double = 0
    var value2: Double = 0
    var date: Date = Date()
    var note: String = ""
    var isPrivate: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, personID: UUID, type: MeasurementType, value: Double, date: Date) {
        self.id = id
        self.familyID = familyID
        self.personID = personID
        self.typeRaw = type.rawValue
        self.value = value
        self.date = date
    }

    var type: MeasurementType {
        get { MeasurementType(rawValue: typeRaw) ?? .weight }
        set { typeRaw = newValue.rawValue }
    }

    var text: String {
        let t = type
        let first = value.formatted(.number.precision(.fractionLength(t.decimals)))
        if t.hasSecondValue { return "\(first)/\(value2.formatted(.number.precision(.fractionLength(0)))) \(t.unit)" }
        return "\(first) \(t.unit)"
    }
}

/// Family doctor, dentist, paediatrician, pharmacy …
@Model
final class HealthContact {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var name: String = ""
    var specialty: String = ""
    var phone: String = ""
    var address: String = ""
    var note: String = ""
    var personIDsRaw: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, name: String) {
        self.id = id
        self.familyID = familyID
        self.name = name
    }

    var personIDs: Set<UUID> {
        get { Set(personIDsRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) }) }
        set { personIDsRaw = newValue.map(\.uuidString).sorted().joined(separator: ",") }
    }
}

/// A bill sent to the (private or supplementary) insurance for a refund.
@Model
final class InsuranceClaim {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var personID: UUID? = nil
    var title: String = ""
    var insurer: String = ""
    var expenseID: UUID? = nil
    var amountValue: Int64 = 0
    var currencyCode: String = "EUR"
    var submittedOn: Date? = nil
    var refundedValue: Int64 = 0
    var refundedOn: Date? = nil
    var note: String = ""
    var isPrivate: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, title: String) {
        self.id = id
        self.familyID = familyID
        self.title = title
    }

    var amount: Decimal {
        get { FixedPoint.decimal(from: amountValue) }
        set { amountValue = FixedPoint.storage(from: newValue) }
    }

    var refunded: Decimal {
        get { FixedPoint.decimal(from: refundedValue) }
        set { refundedValue = FixedPoint.storage(from: newValue) }
    }

    var status: ClaimStatus {
        if refundedOn != nil { return .refunded }
        if submittedOn != nil { return .submitted }
        return .toSubmit
    }

    /// Still expected back.
    var open: Decimal { status == .refunded ? 0 : amount }
}

enum ClaimStatus: String {
    case toSubmit, submitted, refunded
}

/// A photographed plate and its balance score.
@Model
final class PlateLog {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var personID: UUID? = nil
    var date: Date = Date()
    var slotRaw: String = "dinner"
    /// "vegetables:5,leanProtein:2.5"
    var partsRaw: String = ""
    var score: Int = 0
    var note: String = ""
    /// Small photo, kept on this iPhone only (not synced).
    @Attribute(.externalStorage) var thumbnail: Data? = nil
    var isPrivate: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, date: Date) {
        self.id = id
        self.familyID = familyID
        self.date = date
    }

    var parts: [PlatePart: Double] {
        get {
            var result: [PlatePart: Double] = [:]
            for item in partsRaw.split(separator: ",") {
                let kv = item.split(separator: ":")
                if kv.count == 2, let part = PlatePart(rawValue: String(kv[0])), let v = Double(kv[1]) { result[part] = v }
            }
            return result
        }
        set {
            partsRaw = newValue.filter { $0.value > 0 }.sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.rawValue):\($0.value)" }.joined(separator: ",")
        }
    }
}
