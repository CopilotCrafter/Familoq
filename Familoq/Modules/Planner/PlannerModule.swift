import Foundation
import SwiftData
import FamiloqCore
import FamiloqPlanner

/// Planner space: shared shopping list, family reminders and family calendar.
@MainActor
enum PlannerModule: FamiloqModule {
    static let space: FamiloqSpace = .shopping

    static let models: [any PersistentModel.Type] = [
        ShoppingList.self,
        ShoppingItem.self,
        FamilyReminder.self,
        FamilyEvent.self,
        LeaveEntry.self,
        LeaveAllowance.self,
        Recipe.self,
        MealPlanEntry.self,
        Trip.self,
        PackingItem.self
    ]

    /// The first shopping list is created when it is first needed
    /// (`ShoppingService.lists`), with the same ID on every iPhone.
    static func seedDefaults(familyID: UUID, in context: ModelContext) {}
}

@MainActor
enum ShoppingService {
    /// Same ID on every iPhone, so two members never create two default lists.
    static func defaultListID(familyID: UUID) -> UUID {
        DeterministicID.uuid("shopping-list|\(familyID.uuidString)")
    }

    /// The family's lists; creates the first one ("Shopping") when there is none.
    static func lists(familyID: UUID, context: ModelContext, createIfNeeded: Bool = true) -> [ShoppingList] {
        let fid = familyID
        let descriptor = FetchDescriptor<ShoppingList>(predicate: #Predicate { $0.familyID == fid },
                                                       sortBy: [SortDescriptor(\ShoppingList.sortOrder), SortDescriptor(\ShoppingList.createdAt)])
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty, createIfNeeded else { return existing }
        let list = ShoppingList(id: defaultListID(familyID: familyID), familyID: familyID, name: String(localized: "Shopping"))
        // An old date: if another iPhone renamed the same list meanwhile, its change wins.
        list.createdAt = Date(timeIntervalSince1970: 0)
        list.updatedAt = list.createdAt
        context.insert(list)
        try? context.save()
        return [list]
    }

    /// Adds typed text ("2x Milch"). An item that is already open gets the new
    /// amount instead of a second line. Returns the item.
    @discardableResult
    static func add(_ text: String, listID: UUID, familyID: UUID, memberID: UUID?, context: ModelContext) -> ShoppingItem? {
        add(entry: ShoppingEntryParser.parse(text), listID: listID, familyID: familyID, memberID: memberID, context: context)
    }

    /// Adds an already split entry (name + amount), e.g. from a recipe.
    @discardableResult
    static func add(entry: ShoppingEntry, listID: UUID, familyID: UUID, memberID: UUID?, context: ModelContext) -> ShoppingItem? {
        guard !entry.name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let key = ShoppingEntryParser.key(entry.name)
        let lid = listID
        let openItems = (try? context.fetch(FetchDescriptor<ShoppingItem>(predicate: #Predicate {
            $0.listID == lid && $0.isBought == false && $0.isCleared == false
        }))) ?? []
        if let same = openItems.first(where: { ShoppingEntryParser.key($0.name) == key }) {
            if !entry.quantity.isEmpty { same.quantity = entry.quantity }
            same.updatedAt = Date()
            try? context.save()
            return same
        }
        let item = ShoppingItem(familyID: familyID, listID: listID, name: entry.name, quantity: entry.quantity, addedByMemberID: memberID)
        context.insert(item)
        try? context.save()
        return item
    }

    static func setBought(_ item: ShoppingItem, _ bought: Bool, memberID: UUID?, context: ModelContext) {
        item.isBought = bought
        item.boughtAt = bought ? Date() : nil
        item.boughtByMemberID = bought ? memberID : nil
        item.updatedAt = Date()
        try? context.save()
    }

    /// Hides bought items (kept for "Buy again").
    static func clearBought(listID: UUID, context: ModelContext) {
        let lid = listID
        let bought = (try? context.fetch(FetchDescriptor<ShoppingItem>(predicate: #Predicate {
            $0.listID == lid && $0.isBought == true && $0.isCleared == false
        }))) ?? []
        for item in bought {
            item.isCleared = true
            item.updatedAt = Date()
        }
        try? context.save()
    }

    /// After a receipt was saved: ticks off open items that are on it.
    /// Returns the names that were ticked off.
    @discardableResult
    static func tickOff(receiptLines: [String], familyID: UUID, memberID: UUID?, context: ModelContext) -> [String] {
        let fid = familyID
        let openItems = (try? context.fetch(FetchDescriptor<ShoppingItem>(predicate: #Predicate {
            $0.familyID == fid && $0.isBought == false && $0.isCleared == false
        }, sortBy: [SortDescriptor(\ShoppingItem.createdAt)]))) ?? []
        guard !openItems.isEmpty, !receiptLines.isEmpty else { return [] }
        let bought = Set(ShoppingReceiptMatcher.boughtItems(open: openItems.map { (id: $0.id, name: $0.name) }, receiptLines: receiptLines))
        var names: [String] = []
        for item in openItems where bought.contains(item.id) {
            item.isBought = true
            item.boughtAt = Date()
            item.boughtByMemberID = memberID
            item.updatedAt = Date()
            names.append(item.name)
        }
        if !names.isEmpty { try? context.save() }
        return names
    }

    /// Cleared items older than a year are removed for good.
    static func prune(familyID: UUID, context: ModelContext, now: Date = Date()) {
        let fid = familyID
        let limit = now.addingTimeInterval(-365 * 86_400)
        let old = (try? context.fetch(FetchDescriptor<ShoppingItem>(predicate: #Predicate {
            $0.familyID == fid && $0.isCleared == true && $0.updatedAt < limit
        }))) ?? []
        guard !old.isEmpty else { return }
        for item in old { context.delete(item) }
        try? context.save()
    }
}

@MainActor
enum ReminderService {
    /// Ticks off a reminder. A repeating one moves to its next date instead.
    static func complete(_ reminder: FamilyReminder, memberID: UUID?, context: ModelContext, now: Date = Date()) {
        if let due = reminder.dueDate, let rule = reminder.rule,
           let next = ReminderSchedule.nextDue(after: due, rule: rule, now: now, calendar: FamiloqCalendar.make()) {
            if reminder.repeatStart == nil { reminder.repeatStart = due }
            reminder.dueDate = next
            reminder.isDone = false
        } else {
            reminder.isDone = true
        }
        reminder.completedAt = now
        reminder.completedByMemberID = memberID
        reminder.updatedAt = now
        try? context.save()
    }

    static func reopen(_ reminder: FamilyReminder, context: ModelContext) {
        reminder.isDone = false
        reminder.updatedAt = Date()
        try? context.save()
    }
}

/// Sample planner data for CI screenshots (-seedDemoData YES).
@MainActor
enum PlannerDemoData {
    static func seedIfEmpty(family: Family, member: FamilyMember?, context: ModelContext) {
        let fid = family.id
        let count = (try? context.fetchCount(FetchDescriptor<ShoppingItem>(predicate: #Predicate { $0.familyID == fid }))) ?? 0
        guard count == 0, let list = ShoppingService.lists(familyID: family.id, context: context).first else { return }
        for text in ["2x Milch", "Bananen", "Brot", "500 g Hackfleisch", "Tomaten", "Kaffee", "Spülmittel"] {
            ShoppingService.add(text, listID: list.id, familyID: fid, memberID: member?.id, context: context)
        }
        let calendar = FamiloqCalendar.make()
        let today = calendar.startOfDay(for: Date())
        let trash = FamilyReminder(familyID: fid, title: "Take out the recycling")
        trash.dueDate = today
        trash.frequency = .weekly
        trash.repeatStart = today
        context.insert(trash)
        let dentist = FamilyReminder(familyID: fid, title: "Book dentist appointment")
        dentist.dueDate = calendar.date(byAdding: .day, value: 2, to: today)
        context.insert(dentist)
        let start = calendar.date(bySettingHour: 16, minute: 30, second: 0, of: today) ?? today
        let swim = FamilyEvent(familyID: fid, title: "Swimming lesson", start: start, end: start.addingTimeInterval(3600), isAllDay: false)
        swim.kind = .school
        swim.frequency = .weekly
        swim.alertMinutes = 60
        context.insert(swim)
        let birthdayDay = calendar.date(byAdding: .day, value: 5, to: today) ?? today
        let birthday = FamilyEvent(familyID: fid, title: "Grandma", start: birthdayDay,
                                   end: calendar.date(byAdding: .day, value: 1, to: birthdayDay) ?? birthdayDay, isAllDay: true)
        birthday.kind = .birthday
        birthday.frequency = .yearly
        birthday.alertMinutes = 1440
        context.insert(birthday)
        try? context.save()
    }
}
