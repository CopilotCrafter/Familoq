import Foundation

/// Regular check-ups with a typical interval (Germany; adjustable per person).
public enum CheckupKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case dentist, dentalCleaning, eyeTest, generalCheckup, skinScreening, gynaecology, urology, bloodTest
    case colonoscopy, hearing, childExam, custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dentist: return "Dentist check-up"
        case .dentalCleaning: return "Professional teeth cleaning"
        case .eyeTest: return "Eye test"
        case .generalCheckup: return "General check-up (Check-up 35)"
        case .skinScreening: return "Skin cancer screening"
        case .gynaecology: return "Gynaecologist check-up"
        case .urology: return "Urologist check-up"
        case .bloodTest: return "Blood test"
        case .colonoscopy: return "Colonoscopy"
        case .hearing: return "Hearing test"
        case .childExam: return "Children's check-up (U/J exam)"
        case .custom: return "Other"
        }
    }

    public var icon: String {
        switch self {
        case .dentist, .dentalCleaning: return "mouth.fill"
        case .eyeTest: return "eye.fill"
        case .generalCheckup, .bloodTest: return "stethoscope"
        case .skinScreening: return "hand.raised.fill"
        case .gynaecology, .urology: return "cross.case.fill"
        case .colonoscopy: return "cross.fill"
        case .hearing: return "ear.fill"
        case .childExam: return "figure.and.child.holdinghands"
        case .custom: return "calendar.badge.clock"
        }
    }

    /// Typical interval in months (0 = by age, for children's exams).
    public var defaultMonths: Int {
        switch self {
        case .dentist: return 6
        case .dentalCleaning: return 12
        case .eyeTest: return 24
        case .generalCheckup: return 36
        case .skinScreening: return 24
        case .gynaecology, .urology, .bloodTest: return 12
        case .colonoscopy: return 120
        case .hearing: return 36
        case .childExam: return 0
        case .custom: return 12
        }
    }
}

/// German children's check-ups (U3-U9, J1) by age window in months.
public struct ChildExam: Sendable, Equatable {
    public let name: String
    public let fromMonths: Int
    public let toMonths: Int

    public static let all: [ChildExam] = [
        .init(name: "U3", fromMonths: 1, toMonths: 2), .init(name: "U4", fromMonths: 3, toMonths: 4),
        .init(name: "U5", fromMonths: 6, toMonths: 7), .init(name: "U6", fromMonths: 10, toMonths: 12),
        .init(name: "U7", fromMonths: 21, toMonths: 24), .init(name: "U7a", fromMonths: 34, toMonths: 36),
        .init(name: "U8", fromMonths: 46, toMonths: 48), .init(name: "U9", fromMonths: 60, toMonths: 64),
        .init(name: "U10", fromMonths: 84, toMonths: 96), .init(name: "U11", fromMonths: 108, toMonths: 120),
        .init(name: "J1", fromMonths: 144, toMonths: 168), .init(name: "J2", fromMonths: 192, toMonths: 204)
    ]

    /// The next exam not done yet whose window has not passed.
    public static func next(birthDate: Date, done: Set<String>, now: Date, calendar: Calendar) -> (exam: ChildExam, from: Date, to: Date)? {
        for exam in all where !done.contains(exam.name) {
            guard let from = calendar.date(byAdding: .month, value: exam.fromMonths, to: birthDate),
                  let to = calendar.date(byAdding: .month, value: exam.toMonths, to: birthDate) else { continue }
            if to >= calendar.startOfDay(for: now) { return (exam, from, to) }
        }
        return nil
    }
}

/// Vaccinations with the usual booster interval (STIKO; 0 = no routine booster).
public enum VaccineKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case tetanusDiphtheriaPertussis, flu, covid, pneumococcal, tbe, shingles, measlesMumpsRubella, hepatitisA, hepatitisB
    case hpv, meningococcal, typhoid, rabies, yellowFever, polio, custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tetanusDiphtheriaPertussis: return "Tetanus / diphtheria / whooping cough"
        case .flu: return "Flu"
        case .covid: return "COVID-19"
        case .pneumococcal: return "Pneumococcus"
        case .tbe: return "Tick-borne encephalitis (FSME)"
        case .shingles: return "Shingles"
        case .measlesMumpsRubella: return "Measles / mumps / rubella"
        case .hepatitisA: return "Hepatitis A"
        case .hepatitisB: return "Hepatitis B"
        case .hpv: return "HPV"
        case .meningococcal: return "Meningococcus"
        case .typhoid: return "Typhoid"
        case .rabies: return "Rabies"
        case .yellowFever: return "Yellow fever"
        case .polio: return "Polio"
        case .custom: return "Other"
        }
    }

    public var defaultBoosterMonths: Int {
        switch self {
        case .tetanusDiphtheriaPertussis, .polio: return 120
        case .flu, .covid: return 12
        case .pneumococcal: return 72
        case .tbe: return 60
        case .typhoid: return 36
        case .meningococcal: return 60
        case .shingles, .measlesMumpsRubella, .hepatitisA, .hepatitisB, .hpv, .rabies, .yellowFever, .custom: return 0
        }
    }

    /// Commonly needed for travel (linked to trips).
    public var isTravel: Bool { [.hepatitisA, .typhoid, .rabies, .yellowFever, .tbe, .polio].contains(self) }
}

public enum HealthDue {
    /// Next date after `last` with an interval in months (nil = no repeat).
    public static func next(after last: Date, months: Int, calendar: Calendar) -> Date? {
        guard months > 0 else { return nil }
        return calendar.date(byAdding: .month, value: months, to: last)
    }

    /// Flu shots are due each autumn: October of this or next year.
    public static func nextFluSeason(after last: Date?, now: Date, calendar: Calendar) -> Date {
        let year = calendar.component(.year, from: now)
        let thisSeason = calendar.date(from: DateComponents(year: year, month: 10, day: 1)) ?? now
        if let last, last >= (calendar.date(byAdding: .month, value: -2, to: thisSeason) ?? thisSeason) {
            return calendar.date(from: DateComponents(year: year + 1, month: 10, day: 1)) ?? now
        }
        return thisSeason
    }
}

/// When a medication pack runs out.
public enum Refill {
    public static func runOutDate(stock: Double, perDay: Double, from start: Date, calendar: Calendar) -> Date? {
        guard perDay > 0, stock >= 0 else { return nil }
        let days = Int((stock / perDay).rounded(.down))
        return calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: start))
    }

    /// Left today when `stock` was counted on `start`.
    public static func remaining(stock: Double, perDay: Double, from start: Date, now: Date, calendar: Calendar) -> Double {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: now)).day ?? 0
        return max(0, stock - Double(max(0, days)) * perDay)
    }
}

/// Values people track for their doctor.
public enum MeasurementType: String, CaseIterable, Codable, Sendable, Identifiable {
    case bloodPressure, pulse, bloodSugar, hba1c, weight, cholesterol, ldl, hdl, triglycerides, tsh

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bloodPressure: return "Blood pressure"
        case .pulse: return "Pulse"
        case .bloodSugar: return "Blood sugar"
        case .hba1c: return "HbA1c"
        case .weight: return "Weight"
        case .cholesterol: return "Total cholesterol"
        case .ldl: return "LDL cholesterol"
        case .hdl: return "HDL cholesterol"
        case .triglycerides: return "Triglycerides"
        case .tsh: return "TSH (thyroid)"
        }
    }

    public var unit: String {
        switch self {
        case .bloodPressure: return "mmHg"
        case .pulse: return "bpm"
        case .bloodSugar, .cholesterol, .ldl, .hdl, .triglycerides: return "mg/dl"
        case .hba1c: return "%"
        case .weight: return "kg"
        case .tsh: return "mU/l"
        }
    }

    public var icon: String {
        switch self {
        case .bloodPressure, .pulse: return "heart.fill"
        case .bloodSugar, .hba1c: return "drop.fill"
        case .weight: return "scalemass.fill"
        case .cholesterol, .ldl, .hdl, .triglycerides: return "waveform.path.ecg"
        case .tsh: return "bolt.heart.fill"
        }
    }

    /// Blood pressure has two values (systolic / diastolic).
    public var hasSecondValue: Bool { self == .bloodPressure }

    public var decimals: Int {
        switch self {
        case .hba1c, .weight, .tsh: return 1
        default: return 0
        }
    }

    /// Measurements that fit a condition (suggested in the profile).
    public static func suggested(for conditions: Set<HealthCondition>) -> [MeasurementType] {
        var result: [MeasurementType] = []
        func add(_ types: [MeasurementType]) { for t in types where !result.contains(t) { result.append(t) } }
        for c in conditions.sorted(by: { $0.rawValue < $1.rawValue }) {
            switch c {
            case .highBloodPressure, .heartDisease, .kidneyDisease: add([.bloodPressure, .pulse])
            case .diabetesType1, .diabetesType2: add([.bloodSugar, .hba1c])
            case .highCholesterol: add([.cholesterol, .ldl, .hdl])
            case .highTriglycerides, .fattyLiver: add([.triglycerides])
            case .hypothyroidism, .hyperthyroidism: add([.tsh])
            case .weightGoal: add([.weight])
            default: break
            }
        }
        return result
    }
}
