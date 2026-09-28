import Foundation

public enum LeaveType: String, CaseIterable, Codable, Sendable {
    case vacation, halfDay, bridgeDay, companyClosure, training

    public var title: String {
        switch self {
        case .vacation: return "Vacation"
        case .halfDay: return "Half day"
        case .bridgeDay: return "Bridge day"
        case .companyClosure: return "Company closure"
        case .training: return "Training"
        }
    }

    public var icon: String {
        switch self {
        case .vacation: return "sun.max.fill"
        case .halfDay: return "circle.lefthalf.filled"
        case .bridgeDay: return "arrow.left.and.right"
        case .companyClosure: return "building.2.fill"
        case .training: return "graduationcap.fill"
        }
    }

    /// Vacation days taken from the allowance per working day.
    public var daysPerWorkingDay: Double {
        switch self {
        case .vacation, .bridgeDay, .companyClosure: return 1
        case .halfDay: return 0.5
        case .training: return 0
        }
    }
}

/// One stretch of time off (days inclusive).
public struct LeaveSpan: Sendable, Equatable {
    public var memberID: UUID
    public var type: LeaveType
    /// First and last day (any time on those days).
    public var first: Date
    public var last: Date

    public init(memberID: UUID, type: LeaveType, first: Date, last: Date) {
        self.memberID = memberID
        self.type = type
        self.first = first
        self.last = max(first, last)
    }
}

public enum TimeOffCalculator {
    /// Days of the span (start of day), inclusive.
    public static func days(of span: LeaveSpan, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var day = calendar.startOfDay(for: span.first)
        let end = calendar.startOfDay(for: span.last)
        while day <= end, result.count < 400 {
            result.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    /// Monday-Friday and not a public holiday.
    public static func isWorkingDay(_ day: Date, holidays: Set<Date>, calendar: Calendar) -> Bool {
        !calendar.isDateInWeekend(day) && !holidays.contains(calendar.startOfDay(for: day))
    }

    /// Vacation days used by the spans inside `period` (weekends and public
    /// holidays do not count; half days count 0.5; training 0).
    public static func usedDays(_ spans: [LeaveSpan], in period: DateInterval, holidays: Set<Date>, calendar: Calendar) -> Double {
        spans.reduce(0) { total, span in
            let working = days(of: span, calendar: calendar).filter {
                period.contains($0) && $0 < period.end && isWorkingDay($0, holidays: holidays, calendar: calendar)
            }
            return total + Double(working.count) * span.type.daysPerWorkingDay
        }
    }

    /// Working days of training (shown separately, not taken from the allowance).
    public static func trainingDays(_ spans: [LeaveSpan], in period: DateInterval, holidays: Set<Date>, calendar: Calendar) -> Int {
        spans.filter { $0.type == .training }.reduce(0) { total, span in
            total + days(of: span, calendar: calendar).filter {
                period.contains($0) && $0 < period.end && isWorkingDay($0, holidays: holidays, calendar: calendar)
            }.count
        }
    }

    /// Stretches of days in `period` on which at least `minimumPeople` are
    /// off together (weekends between them included, so a trip shows as one).
    public static func overlaps(_ spans: [LeaveSpan], in period: DateInterval, minimumPeople: Int = 2, calendar: Calendar) -> [(first: Date, last: Date, people: Set<UUID>)] {
        var peopleByDay: [Date: Set<UUID>] = [:]
        for span in spans where span.type != .training {
            for day in days(of: span, calendar: calendar) where day >= period.start && day < period.end {
                peopleByDay[day, default: []].insert(span.memberID)
            }
        }
        let shared = peopleByDay.filter { $0.value.count >= minimumPeople }.keys.sorted()
        var result: [(first: Date, last: Date, people: Set<UUID>)] = []
        for day in shared {
            if let last = result.last, let next = calendar.date(byAdding: .day, value: 1, to: last.last), next == day {
                result[result.count - 1].last = day
                result[result.count - 1].people.formUnion(peopleByDay[day] ?? [])
            } else {
                result.append((day, day, peopleByDay[day] ?? []))
            }
        }
        return result
    }
}
