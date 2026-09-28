import Foundation

// MARK: - Reminders

public enum ReminderSchedule {
    /// Where a reminder shows up in the list.
    public enum Bucket: Int, CaseIterable, Comparable, Sendable {
        case overdue, today, tomorrow, next7Days, later, noDate

        public var title: String {
            switch self {
            case .overdue: return "Overdue"
            case .today: return "Today"
            case .tomorrow: return "Tomorrow"
            case .next7Days: return "Next 7 days"
            case .later: return "Later"
            case .noDate: return "No date"
            }
        }

        public static func < (a: Bucket, b: Bucket) -> Bool { a.rawValue < b.rawValue }
    }

    /// With a time: overdue once the time passed. Without: once the day passed.
    public static func isOverdue(due: Date, hasTime: Bool, now: Date, calendar: Calendar) -> Bool {
        hasTime ? due < now : calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
    }

    public static func bucket(due: Date?, hasTime: Bool, now: Date, calendar: Calendar) -> Bucket {
        guard let due else { return .noDate }
        if isOverdue(due: due, hasTime: hasTime, now: now, calendar: calendar) { return .overdue }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: due)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch days {
        case ..<1: return .today
        case 1: return .tomorrow
        case 2...7: return .next7Days
        default: return .later
        }
    }

    /// After ticking off a repeating reminder: the next date that is after the
    /// current one and not before today (an overdue weekly chore jumps to the
    /// coming week instead of the past ones). nil = no more occurrences.
    public static func nextDue(after due: Date, rule: RepeatRule, now: Date, calendar: Calendar) -> Date? {
        guard rule.frequency != .never else { return nil }
        let today = calendar.startOfDay(for: now)
        var candidate = rule.next(after: due, calendar: calendar)
        var guardCount = 0
        while let c = candidate, c < today, guardCount < 10_000 {
            candidate = rule.next(after: c, calendar: calendar)
            guardCount += 1
        }
        return candidate
    }
}

// MARK: - Calendar events

public struct EventSpec: Equatable, Sendable {
    public var id: UUID
    public var start: Date
    /// Exclusive end. All-day events: start of the day after the last day.
    public var end: Date
    public var isAllDay: Bool
    public var frequency: RepeatFrequency
    public var repeatEnd: Date?

    public init(id: UUID, start: Date, end: Date, isAllDay: Bool, frequency: RepeatFrequency = .never, repeatEnd: Date? = nil) {
        self.id = id
        self.start = start
        self.end = max(end, start)
        self.isAllDay = isAllDay
        self.frequency = frequency
        self.repeatEnd = repeatEnd
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public struct EventOccurrence: Identifiable, Equatable, Sendable {
    public let eventID: UUID
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public var id: String { "\(eventID.uuidString)-\(Int(start.timeIntervalSince1970))" }
}

public enum EventCalendar {
    /// Every occurrence that overlaps `interval`; all-day first, then by time.
    public static func occurrences(of specs: [EventSpec], in interval: DateInterval, calendar: Calendar) -> [EventOccurrence] {
        var result: [EventOccurrence] = []
        for spec in specs {
            let duration = spec.duration
            let rule = RepeatRule(frequency: spec.frequency, start: spec.start, end: spec.repeatEnd)
            let searchFrom = interval.start.addingTimeInterval(-max(duration, 1))
            for start in rule.occurrences(from: searchFrom, to: interval.end, calendar: calendar) {
                let end = start.addingTimeInterval(duration)
                let effectiveEnd = end > start ? end : start.addingTimeInterval(1)
                if start < interval.end && effectiveEnd > interval.start {
                    result.append(EventOccurrence(eventID: spec.id, start: start, end: end, isAllDay: spec.isAllDay))
                }
            }
        }
        return result.sorted { a, b in
            let dayA = calendar.startOfDay(for: a.start), dayB = calendar.startOfDay(for: b.start)
            if dayA != dayB { return dayA < dayB }
            if a.isAllDay != b.isAllDay { return a.isAllDay }
            if a.start != b.start { return a.start < b.start }
            return a.eventID.uuidString < b.eventID.uuidString
        }
    }

    /// Start of each day the occurrence covers (a 3-day trip -> 3 days).
    public static func days(of occurrence: EventOccurrence, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: occurrence.start)
        let last = occurrence.end > occurrence.start ? occurrence.end.addingTimeInterval(-1) : occurrence.start
        while day <= last, days.count < 366 {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// Cells of a month view (weeks start with calendar.firstWeekday);
    /// nil = empty cell before the 1st / after the last day.
    public static func monthGrid(for date: Date, calendar: Calendar) -> [Date?] {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        let first = month.start
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: offset)
        for i in 0..<count {
            cells.append(calendar.date(byAdding: .day, value: i, to: first))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }
}

// MARK: - Notifications

/// What each iPhone schedules as local notifications. Pure logic: the app
/// turns these into texts and UNNotificationRequests.
public struct PlannedAlert: Equatable, Sendable {
    public enum Kind: String, Sendable { case reminder, event, bill, deadline }
    public let kind: Kind
    /// Stable identifier, e.g. "fq.e.<uuid>.<epoch>".
    public let id: String
    public let sourceID: String
    public let fireDate: Date
    /// Due date / event start the alert is about.
    public let date: Date
}

public enum NotificationPlanner {
    public struct Reminder: Sendable {
        public var id: UUID
        public var due: Date
        public var hasTime: Bool
        public var assignees: Set<UUID>
        public init(id: UUID, due: Date, hasTime: Bool, assignees: Set<UUID>) {
            self.id = id; self.due = due; self.hasTime = hasTime; self.assignees = assignees
        }
    }

    public struct Event: Sendable {
        public var spec: EventSpec
        /// Minutes before the start; for all-day events 0 = 9:00 on the day,
        /// 1440 = 9:00 the day before. nil = no alert.
        public var alertMinutes: Int?
        public var participants: Set<UUID>
        public init(spec: EventSpec, alertMinutes: Int?, participants: Set<UUID>) {
            self.spec = spec; self.alertMinutes = alertMinutes; self.participants = participants
        }
    }

    public struct Bill: Sendable {
        public var id: String
        public var date: Date
        public init(id: String, date: Date) { self.id = id; self.date = date }
    }

    /// Contract cancellation deadlines, warranty ends: 9:00 on each of the
    /// given days before (0 = on the day itself).
    public struct Deadline: Sendable {
        public var id: String
        public var date: Date
        public var daysBefore: [Int]
        public init(id: String, date: Date, daysBefore: [Int]) { self.id = id; self.date = date; self.daysBefore = daysBefore }
    }

    /// Everyone (no one chosen) or me among the chosen people.
    static func concernsMe(_ people: Set<UUID>, me: Set<UUID>) -> Bool {
        people.isEmpty || !people.isDisjoint(with: me)
    }

    /// - Parameters:
    ///   - me: the current user's member IDs (one per family on this iPhone)
    ///   - limit: iOS keeps at most 64 pending notifications per app
    public static func plan(reminders: [Reminder], events: [Event], bills: [Bill], deadlines: [Deadline] = [], me: Set<UUID>,
                            now: Date, calendar: Calendar, horizonDays: Int = 35, morningHour: Int = 9,
                            eveningHour: Int = 18, limit: Int = 60) -> [PlannedAlert] {
        var alerts: [PlannedAlert] = []
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: now) ?? now.addingTimeInterval(Double(horizonDays) * 86_400)

        func at(_ hour: Int, on day: Date) -> Date {
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.startOfDay(for: day)) ?? day
        }

        for reminder in reminders where concernsMe(reminder.assignees, me: me) {
            let fire = reminder.hasTime ? reminder.due : at(morningHour, on: reminder.due)
            guard fire > now, fire <= horizon else { continue }
            alerts.append(PlannedAlert(kind: .reminder, id: "fq.r.\(reminder.id.uuidString)", sourceID: reminder.id.uuidString,
                                       fireDate: fire, date: reminder.due))
        }

        let window = DateInterval(start: now, end: max(now, horizon.addingTimeInterval(2 * 86_400)))
        for event in events where concernsMe(event.participants, me: me) {
            guard let minutes = event.alertMinutes else { continue }
            for occurrence in EventCalendar.occurrences(of: [event.spec], in: window, calendar: calendar) {
                let fire: Date
                if occurrence.isAllDay {
                    let day = minutes >= 1440 ? (calendar.date(byAdding: .day, value: -(minutes / 1440), to: occurrence.start) ?? occurrence.start) : occurrence.start
                    fire = at(morningHour, on: day)
                } else {
                    fire = occurrence.start.addingTimeInterval(-Double(minutes) * 60)
                }
                guard fire > now, fire <= horizon else { continue }
                alerts.append(PlannedAlert(kind: .event, id: "fq.e.\(event.spec.id.uuidString).\(Int(occurrence.start.timeIntervalSince1970))",
                                           sourceID: event.spec.id.uuidString, fireDate: fire, date: occurrence.start))
            }
        }

        for bill in bills {
            guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: bill.date) else { continue }
            let fire = at(eveningHour, on: dayBefore)
            guard fire > now, fire <= horizon else { continue }
            alerts.append(PlannedAlert(kind: .bill, id: "fq.b.\(bill.id)", sourceID: bill.id, fireDate: fire, date: bill.date))
        }

        for deadline in deadlines {
            for days in Set(deadline.daysBefore) {
                guard let day = calendar.date(byAdding: .day, value: -days, to: deadline.date) else { continue }
                let fire = at(morningHour, on: day)
                guard fire > now, fire <= horizon else { continue }
                alerts.append(PlannedAlert(kind: .deadline, id: "fq.d.\(deadline.id).\(days)", sourceID: deadline.id, fireDate: fire, date: deadline.date))
            }
        }

        return Array(alerts.sorted { $0.fireDate != $1.fireDate ? $0.fireDate < $1.fireDate : $0.id < $1.id }.prefix(limit))
    }
}
