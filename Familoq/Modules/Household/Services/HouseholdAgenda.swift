import Foundation
import SwiftData
import FamiloqCore
import FamiloqPlanner
import FamiloqBudget

/// What is coming up for the cars (TÜV, service, tyres) and documents
/// (passports, ID cards, insurance running out).
@MainActor
enum HouseholdAgenda {
    enum Kind: String {
        case inspection, service, tyres, document
    }

    struct Item: Identifiable {
        let id: String
        let kind: Kind
        let date: Date
        let title: String
        let subtitle: String
        let daysBefore: [Int]
        /// Whose iPhones ring (empty = everyone).
        let people: Set<UUID>

        var icon: String {
            switch kind {
            case .inspection: return "checkmark.seal.fill"
            case .service: return "wrench.and.screwdriver.fill"
            case .tyres: return "snowflake"
            case .document: return "doc.text.fill"
            }
        }
    }

    static func carItems(_ cars: [Car], now: Date, calendar: Calendar) -> [Item] {
        var result: [Item] = []
        for car in cars where !car.isArchived {
            if let date = car.nextInspection {
                result.append(Item(id: "ti-" + car.id.uuidString, kind: .inspection, date: date,
                                   title: String(localized: "TÜV / inspection"), subtitle: car.displayName,
                                   daysBefore: [30, 7], people: car.drivers))
            }
            if let date = car.nextService {
                result.append(Item(id: "sv-" + car.id.uuidString, kind: .service, date: date,
                                   title: String(localized: "Service"), subtitle: car.displayName,
                                   daysBefore: [14], people: car.drivers))
            }
            if car.tyreReminder, let next = TyreSeason.nextChange(after: now, calendar: calendar) {
                result.append(Item(id: "ty-" + car.id.uuidString + (next.toWinter ? "-w" : "-s"), kind: .tyres, date: next.date,
                                   title: next.toWinter ? String(localized: "Winter tyres") : String(localized: "Summer tyres"),
                                   subtitle: car.displayName, daysBefore: [0], people: car.drivers))
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    static func documentItems(_ documents: [FamilyDocument]) -> [Item] {
        documents.compactMap { doc in
            guard doc.remind, let expires = doc.expiresOn else { return nil }
            let whose = doc.personName.isEmpty ? "" : doc.personName
            return Item(id: "dx-" + doc.id.uuidString, kind: .document, date: expires,
                        title: doc.displayTitle, subtitle: whose,
                        daysBefore: doc.kind.reminderDays, people: doc.memberID.map { Set([$0]) } ?? Set<UUID>())
        }
        .sorted { $0.date < $1.date }
    }

    /// Deadlines for the notification plan.
    static func deadlines(familyIDs: Set<UUID>, me: Set<UUID>, context: ModelContext, now: Date, calendar: Calendar)
        -> (deadlines: [NotificationPlanner.Deadline], content: [String: (title: String, body: String)]) {
        var deadlines: [NotificationPlanner.Deadline] = []
        var content: [String: (title: String, body: String)] = [:]
        var items: [Item] = []
        if PlannerNotifications.Setting.cars.isOn {
            let cars = ((try? context.fetch(FetchDescriptor<Car>(predicate: #Predicate { $0.isArchived == false })))) ?? []
            items += carItems(cars.filter { familyIDs.contains($0.familyID) }, now: now, calendar: calendar)
        }
        if PlannerNotifications.Setting.documents.isOn {
            let documents = ((try? context.fetch(FetchDescriptor<FamilyDocument>(predicate: #Predicate { $0.remind == true })))) ?? []
            items += documentItems(documents.filter { familyIDs.contains($0.familyID) })
        }
        for item in items where item.date > now && (item.people.isEmpty || !item.people.isDisjoint(with: me)) {
            deadlines.append(.init(id: item.id, date: item.date, daysBefore: item.daysBefore))
            let day = item.date.formatted(date: .long, time: .omitted)
            switch item.kind {
            case .inspection:
                content[item.id] = (String(localized: "TÜV due: \(item.subtitle)"), String(localized: "Due on \(day) - book the inspection."))
            case .service:
                content[item.id] = (String(localized: "Service due: \(item.subtitle)"), String(localized: "Planned for \(day) - book the garage."))
            case .tyres:
                content[item.id] = (String(localized: "\(item.title): \(item.subtitle)"), String(localized: "Time to change the tyres."))
            case .document:
                let title = item.subtitle.isEmpty ? item.title : "\(item.title) (\(item.subtitle))"
                content[item.id] = (String(localized: "Expires soon: \(title)"), String(localized: "Valid until \(day) - renew it in time."))
            }
        }
        return (deadlines, content)
    }
}
