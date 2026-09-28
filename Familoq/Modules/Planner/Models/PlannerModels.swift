import Foundation
import SwiftData
import FamiloqCore
import FamiloqPlanner

// Planner space: shopping lists, family reminders, family calendar.
// Same storage conventions as every module (familyID on each record, UUID
// references, defaults on every property) - see Core/Models/FamilyModels.swift.

@Model
final class ShoppingList {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var name: String = ""
    var icon: String = "cart"
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, name: String, icon: String = "cart", sortOrder: Int = 0) {
        self.id = id
        self.familyID = familyID
        self.name = name
        self.icon = icon
        self.sortOrder = sortOrder
    }
}

@Model
final class ShoppingItem {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var listID: UUID = UUID()
    var name: String = ""
    /// Free text: "2", "500 g", "1,5 kg".
    var quantity: String = ""
    var note: String = ""
    /// Supermarket section, e.g. "groceries.dairy" (ShoppingAisles).
    var aisleKey: String = ""
    var isBought: Bool = false
    var boughtAt: Date? = nil
    var boughtByMemberID: UUID? = nil
    /// Bought items are cleared from the list but kept for "Buy again".
    var isCleared: Bool = false
    var addedByMemberID: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, listID: UUID, name: String, quantity: String = "", addedByMemberID: UUID? = nil) {
        self.id = id
        self.familyID = familyID
        self.listID = listID
        self.name = name
        self.quantity = quantity
        self.addedByMemberID = addedByMemberID
        self.aisleKey = ShoppingAisles.aisleKey(for: name)
    }
}

@Model
final class FamilyReminder {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    /// Current due date (for repeating reminders: the next occurrence).
    var dueDate: Date? = nil
    var hasTime: Bool = false
    var repeatRaw: String = RepeatFrequency.never.rawValue
    /// First due date; repeats are computed from it (no drift).
    var repeatStart: Date? = nil
    /// Member IDs, comma-separated; empty = everyone.
    var assigneesRaw: String = ""
    var alertEnabled: Bool = true
    var isDone: Bool = false
    var completedAt: Date? = nil
    var completedByMemberID: UUID? = nil
    var createdByMemberID: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, title: String) {
        self.id = id
        self.familyID = familyID
        self.title = title
    }

    var frequency: RepeatFrequency {
        get { RepeatFrequency(rawValue: repeatRaw) ?? .never }
        set { repeatRaw = newValue.rawValue }
    }

    var assignees: Set<UUID> {
        get { MemberIDList.parse(assigneesRaw) }
        set { assigneesRaw = MemberIDList.encode(newValue) }
    }

    var rule: RepeatRule? {
        guard let dueDate, frequency != .never else { return nil }
        return RepeatRule(frequency: frequency, start: repeatStart ?? dueDate)
    }
}

enum EventKind: String, CaseIterable, Identifiable {
    case event, appointment, birthday, school, trip

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .event: return "Event"
        case .appointment: return "Appointment"
        case .birthday: return "Birthday"
        case .school: return "School"
        case .trip: return "Trip"
        }
    }

    var icon: String {
        switch self {
        case .event: return "calendar"
        case .appointment: return "stethoscope"
        case .birthday: return "gift.fill"
        case .school: return "graduationcap.fill"
        case .trip: return "airplane"
        }
    }

    var colorHex: String {
        switch self {
        case .event: return "#4285F4"
        case .appointment: return "#EA4335"
        case .birthday: return "#E91E63"
        case .school: return "#FB8C00"
        case .trip: return "#00897B"
        }
    }
}

@Model
final class FamilyEvent {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var title: String = ""
    var kindRaw: String = EventKind.event.rawValue
    var location: String = ""
    var notes: String = ""
    var start: Date = Date()
    /// Exclusive end. All-day: start of the day after the last day.
    var end: Date = Date()
    var isAllDay: Bool = false
    var repeatRaw: String = RepeatFrequency.never.rawValue
    var repeatEnd: Date? = nil
    /// Member IDs, comma-separated; empty = the whole family.
    var participantsRaw: String = ""
    /// Minutes before; all-day: 0 = 9:00 on the day, 1440 = 9:00 the day before. -1 = no alert.
    var alertMinutes: Int = -1
    var createdByMemberID: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, title: String, start: Date, end: Date, isAllDay: Bool) {
        self.id = id
        self.familyID = familyID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }

    var kind: EventKind {
        get { EventKind(rawValue: kindRaw) ?? .event }
        set { kindRaw = newValue.rawValue }
    }

    var frequency: RepeatFrequency {
        get { RepeatFrequency(rawValue: repeatRaw) ?? .never }
        set { repeatRaw = newValue.rawValue }
    }

    var participants: Set<UUID> {
        get { MemberIDList.parse(participantsRaw) }
        set { participantsRaw = MemberIDList.encode(newValue) }
    }

    var spec: EventSpec {
        EventSpec(id: id, start: start, end: end, isAllDay: isAllDay, frequency: frequency, repeatEnd: repeatEnd)
    }
}

/// Member IDs stored as text (stable order, so sync fingerprints are stable).
enum MemberIDList {
    static func parse(_ raw: String) -> Set<UUID> {
        Set(raw.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    static func encode(_ ids: Set<UUID>) -> String {
        ids.map(\.uuidString).sorted().joined(separator: ",")
    }
}

/// Time off from work (Urlaub) of one person, days inclusive.
@Model
final class LeaveEntry {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var memberID: UUID = UUID()
    var typeRaw: String = LeaveType.vacation.rawValue
    var firstDay: Date = Date()
    var lastDay: Date = Date()
    var note: String = ""
    var createdByMemberID: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, memberID: UUID, type: LeaveType, firstDay: Date, lastDay: Date) {
        self.id = id
        self.familyID = familyID
        self.memberID = memberID
        self.typeRaw = type.rawValue
        self.firstDay = firstDay
        self.lastDay = lastDay
    }

    var type: LeaveType {
        get { LeaveType(rawValue: typeRaw) ?? .vacation }
        set { typeRaw = newValue.rawValue }
    }

    var span: LeaveSpan { LeaveSpan(memberID: memberID, type: type, first: firstDay, last: lastDay) }
}

/// Vacation days a person has per year (e.g. 30).
@Model
final class LeaveAllowance {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var memberID: UUID = UUID()
    var year: Int = 2026
    /// Tenths of a day (30 days = 300) so half days are exact.
    var tenthDays: Int = 300
    var updatedAt: Date = Date()

    init(id: UUID, familyID: UUID, memberID: UUID, year: Int, days: Double) {
        self.id = id
        self.familyID = familyID
        self.memberID = memberID
        self.year = year
        self.tenthDays = Int((days * 10).rounded())
    }

    var days: Double {
        get { Double(tenthDays) / 10 }
        set { tenthDays = Int((newValue * 10).rounded()) }
    }

    /// One allowance per person and year - the same ID on every iPhone.
    static func allowanceID(familyID: UUID, memberID: UUID, year: Int) -> UUID {
        DeterministicID.uuid("leave-allowance|\(familyID.uuidString)|\(memberID.uuidString)|\(year)")
    }
}
