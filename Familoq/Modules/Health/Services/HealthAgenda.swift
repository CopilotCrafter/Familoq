import Foundation
import SwiftData
import UserNotifications
import FamiloqCore
import FamiloqPlanner
import FamiloqHealth

/// What is coming up in the family's health: check-ups, children's exams,
/// vaccinations and medication refills.
@MainActor
enum HealthAgenda {
    enum Kind: String {
        case checkup, childExam, appointment, vaccination, refill
    }

    struct Item: Identifiable {
        let id: String
        let kind: Kind
        let date: Date
        let title: String
        let personID: UUID
        let personName: String
        /// For notifications: days before the date (0 = on the day).
        let daysBefore: [Int]
        /// Children's exams: last day of the age window.
        var windowEnd: Date? = nil

        var icon: String {
            switch kind {
            case .checkup: return "stethoscope"
            case .childExam: return "figure.and.child.holdinghands"
            case .appointment: return "calendar.badge.clock"
            case .vaccination: return "syringe.fill"
            case .refill: return "pills.fill"
            }
        }
    }

    static func items(familyIDs: Set<UUID>, context: ModelContext, now: Date = Date(), calendar: Calendar = FamiloqCalendar.make()) -> [Item] {
        let people = ((try? context.fetch(FetchDescriptor<HealthPerson>())) ?? []).filter { familyIDs.contains($0.familyID) }
        let byID = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var result: [Item] = []

        for checkup in ((try? context.fetch(FetchDescriptor<Checkup>())) ?? []) where familyIDs.contains(checkup.familyID) && checkup.remind {
            guard let person = byID[checkup.personID] else { continue }
            if let appointment = checkup.appointment, appointment >= calendar.startOfDay(for: now) {
                result.append(Item(id: "a-" + checkup.id.uuidString, kind: .appointment, date: appointment,
                                   title: checkup.displayTitle, personID: person.id, personName: person.name, daysBefore: [1]))
                continue
            }
            if checkup.kind == .childExam {
                guard let birth = person.birthDate,
                      let next = ChildExam.next(birthDate: birth, done: checkup.doneExams, now: now, calendar: calendar) else { continue }
                result.append(Item(id: "u-" + checkup.id.uuidString + "-" + next.exam.name, kind: .childExam, date: next.from,
                                   title: next.exam.name, personID: person.id, personName: person.name, daysBefore: [14, 0],
                                   windowEnd: next.to))
                continue
            }
            guard let last = checkup.lastDate, let due = HealthDue.next(after: last, months: checkup.intervalMonths, calendar: calendar) else { continue }
            result.append(Item(id: "h-" + checkup.id.uuidString, kind: .checkup, date: due,
                               title: checkup.displayTitle, personID: person.id, personName: person.name, daysBefore: [14, 0]))
        }

        // Latest vaccination per person and vaccine decides the next booster.
        let vaccinations = ((try? context.fetch(FetchDescriptor<Vaccination>())) ?? []).filter { familyIDs.contains($0.familyID) }
        let latest = Dictionary(grouping: vaccinations) { "\($0.personID.uuidString)|\($0.kindRaw)|\($0.kind == .custom ? $0.title : "")" }
            .compactMapValues { $0.max { $0.date < $1.date } }
        for vaccination in latest.values {
            guard let person = byID[vaccination.personID] else { continue }
            let due: Date?
            if vaccination.kind == .flu && vaccination.nextDue == nil {
                due = HealthDue.nextFluSeason(after: vaccination.date, now: now, calendar: calendar)
            } else {
                due = vaccination.due(calendar: calendar)
            }
            guard let due else { continue }
            result.append(Item(id: "v-" + vaccination.id.uuidString, kind: .vaccination, date: due,
                               title: vaccination.displayTitle, personID: person.id, personName: person.name, daysBefore: [30, 0]))
        }

        for medication in ((try? context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.isActive == true }))) ?? [])
        where familyIDs.contains(medication.familyID) && medication.remindRefill {
            guard let person = byID[medication.personID], let runOut = medication.runOut(calendar: calendar) else { continue }
            result.append(Item(id: "rf-" + medication.id.uuidString, kind: .refill, date: runOut,
                               title: medication.name, personID: person.id, personName: person.name, daysBefore: [7]))
        }
        return result.sorted { $0.date < $1.date }
    }

    /// Whether this iPhone should ring for a person's reminders.
    static func concernsMe(_ person: HealthPerson?, me: Set<UUID>) -> Bool {
        guard let person else { return true }
        let targets = person.reminderTargets
        return targets.isEmpty || !targets.isDisjoint(with: me)
    }

    // MARK: Notifications

    /// Deadlines for the notification plan (health items and pantry use-by dates).
    static func deadlines(familyIDs: Set<UUID>, me: Set<UUID>, context: ModelContext, now: Date, calendar: Calendar)
        -> (deadlines: [NotificationPlanner.Deadline], content: [String: (title: String, body: String)]) {
        var deadlines: [NotificationPlanner.Deadline] = []
        var content: [String: (title: String, body: String)] = [:]
        if PlannerNotifications.Setting.health.isOn {
            let people = ((try? context.fetch(FetchDescriptor<HealthPerson>())) ?? []).filter { familyIDs.contains($0.familyID) }
            let byID = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for item in items(familyIDs: familyIDs, context: context, now: now, calendar: calendar)
            where concernsMe(byID[item.personID], me: me) {
                let day = item.date.formatted(date: .long, time: .omitted)
                var fireDate = item.date
                var daysBefore = item.daysBefore
                var overdue = false
                if item.date <= now {
                    if item.kind == .childExam, let end = item.windowEnd, end > now {
                        // Window already open: remind a week before it closes.
                        fireDate = end
                        daysBefore = [7, 1]
                    } else if item.kind == .checkup || item.kind == .vaccination {
                        // Overdue: a gentle reminder once a week (next Saturday).
                        overdue = true
                        fireDate = calendar.nextDate(after: now, matching: DateComponents(weekday: 7), matchingPolicy: .nextTime) ?? now
                        daysBefore = [0]
                    } else {
                        continue
                    }
                }
                deadlines.append(.init(id: item.id, date: fireDate, daysBefore: daysBefore))
                switch item.kind {
                case .checkup:
                    content[item.id] = (String(localized: "Check-up due: \(item.title) (\(item.personName))"),
                                        overdue ? String(localized: "Overdue since \(day) - time to book an appointment.")
                                                : String(localized: "Due around \(day) - time to book an appointment."))
                case .childExam:
                    let end = (item.windowEnd ?? item.date).formatted(date: .long, time: .omitted)
                    content[item.id] = (String(localized: "\(item.title) check-up for \(item.personName)"),
                                        String(localized: "Between \(day) and \(end) - book it with the paediatrician."))
                case .appointment:
                    content[item.id] = (String(localized: "Appointment: \(item.title) (\(item.personName))"),
                                        item.date.formatted(date: .long, time: .shortened))
                case .vaccination:
                    content[item.id] = (String(localized: "Vaccination due: \(item.title) (\(item.personName))"),
                                        overdue ? String(localized: "Overdue since \(day).") : String(localized: "Due around \(day)."))
                case .refill:
                    content[item.id] = (String(localized: "Medication running out: \(item.title) (\(item.personName))"),
                                        String(localized: "It lasts until about \(day) - get a new pack or prescription."))
                }
            }
        }
        if PlannerNotifications.Setting.pantry.isOn {
            let items = ((try? context.fetch(FetchDescriptor<PantryItem>())) ?? []).filter { familyIDs.contains($0.familyID) && $0.useBy != nil }
            for item in items {
                guard let useBy = item.useBy, useBy > now else { continue }
                let key = "p-" + item.id.uuidString
                deadlines.append(.init(id: key, date: useBy, daysBefore: [1]))
                content[key] = (String(localized: "Use soon: \(item.name)"), String(localized: "Use by tomorrow."))
            }
        }
        return (deadlines, content)
    }

    /// Daily repeating dose reminders (only on the iPhones of the person / carers).
    static func doseRequests(familyIDs: Set<UUID>, me: Set<UUID>, context: ModelContext) -> [UNNotificationRequest] {
        guard PlannerNotifications.Setting.medications.isOn else { return [] }
        let people = ((try? context.fetch(FetchDescriptor<HealthPerson>())) ?? []).filter { familyIDs.contains($0.familyID) }
        let byID = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let meds = ((try? context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.isActive == true && $0.remindDoses == true }))) ?? [])
            .filter { familyIDs.contains($0.familyID) }
        var requests: [UNNotificationRequest] = []
        for med in meds {
            let person = byID[med.personID]
            guard concernsMe(person, me: me) else { continue }
            for time in med.times {
                let content = UNMutableNotificationContent()
                content.sound = .default
                content.title = String(localized: "Medication: \(med.name)")
                content.body = [med.dose, person?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: time.hour, minute: time.minute), repeats: true)
                let id = "fq.m.\(med.id.uuidString).\(String(format: "%02d%02d", time.hour, time.minute))"
                requests.append(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
        return Array(requests.prefix(20))
    }
}
