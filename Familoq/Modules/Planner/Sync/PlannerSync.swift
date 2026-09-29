import Foundation
import SwiftData
import FamiloqCore

// Planner records shared with the family through iCloud. Every member may
// add and change them (no owner-only rules).

extension PlannerModule {
    static var syncHandlers: [SyncHandler] {
        [
            .of(ShoppingList.self,
                inFamily: { fid in #Predicate<ShoppingList> { $0.familyID == fid } },
                withID: { id in #Predicate<ShoppingList> { $0.id == id } },
                make: { id, fid in ShoppingList(id: id, familyID: fid, name: "") }),
            .of(ShoppingItem.self,
                inFamily: { fid in #Predicate<ShoppingItem> { $0.familyID == fid } },
                withID: { id in #Predicate<ShoppingItem> { $0.id == id } },
                make: { id, fid in ShoppingItem(id: id, familyID: fid, listID: UUID(), name: "") }),
            .of(FamilyReminder.self,
                inFamily: { fid in #Predicate<FamilyReminder> { $0.familyID == fid } },
                withID: { id in #Predicate<FamilyReminder> { $0.id == id } },
                make: { id, fid in FamilyReminder(id: id, familyID: fid, title: "") }),
            .of(FamilyEvent.self,
                inFamily: { fid in #Predicate<FamilyEvent> { $0.familyID == fid } },
                withID: { id in #Predicate<FamilyEvent> { $0.id == id } },
                make: { id, fid in FamilyEvent(id: id, familyID: fid, title: "", start: Date(), end: Date(), isAllDay: false) }),
            .of(Recipe.self,
                inFamily: { fid in #Predicate<Recipe> { $0.familyID == fid } },
                withID: { id in #Predicate<Recipe> { $0.id == id } },
                make: { id, fid in Recipe(id: id, familyID: fid, name: "") }),
            .of(MealPlanEntry.self,
                inFamily: { fid in #Predicate<MealPlanEntry> { $0.familyID == fid } },
                withID: { id in #Predicate<MealPlanEntry> { $0.id == id } },
                make: { id, fid in MealPlanEntry(id: id, familyID: fid, day: Date(), slot: .dinner, title: "") }),
            .of(Trip.self,
                inFamily: { fid in #Predicate<Trip> { $0.familyID == fid } },
                withID: { id in #Predicate<Trip> { $0.id == id } },
                make: { id, fid in Trip(id: id, familyID: fid, name: "", startDate: Date(), endDate: Date(), currencyCode: "EUR") }),
            .of(PackingItem.self,
                inFamily: { fid in #Predicate<PackingItem> { $0.familyID == fid } },
                withID: { id in #Predicate<PackingItem> { $0.id == id } },
                make: { id, fid in PackingItem(id: id, familyID: fid, tripID: UUID(), name: "") }),
            .of(LeaveEntry.self,
                inFamily: { fid in #Predicate<LeaveEntry> { $0.familyID == fid } },
                withID: { id in #Predicate<LeaveEntry> { $0.id == id } },
                make: { id, fid in LeaveEntry(id: id, familyID: fid, memberID: UUID(), type: .vacation, firstDay: Date(), lastDay: Date()) }),
            .of(MealPreferences.self,
                inFamily: { fid in #Predicate<MealPreferences> { $0.familyID == fid } },
                withID: { id in #Predicate<MealPreferences> { $0.id == id } },
                make: { id, fid in MealPreferences(id: id, familyID: fid) }),
            .of(MealRating.self,
                inFamily: { fid in #Predicate<MealRating> { $0.familyID == fid } },
                withID: { id in #Predicate<MealRating> { $0.id == id } },
                make: { id, fid in MealRating(id: id, familyID: fid, dishKey: "", memberID: UUID(), value: 0) }),
            .of(PantryItem.self,
                inFamily: { fid in #Predicate<PantryItem> { $0.familyID == fid } },
                withID: { id in #Predicate<PantryItem> { $0.id == id } },
                make: { id, fid in PantryItem(id: id, familyID: fid, name: "") }),
            .of(LeaveAllowance.self,
                inFamily: { fid in #Predicate<LeaveAllowance> { $0.familyID == fid } },
                withID: { id in #Predicate<LeaveAllowance> { $0.id == id } },
                make: { id, fid in LeaveAllowance(id: id, familyID: fid, memberID: UUID(), year: 2026, days: 0) })
        ]
    }
}

extension ShoppingList: SyncableRecord {
    static var syncKind: SyncKind { .shoppingList }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("name", name)
        p.set("icon", icon)
        p.set("sortOrder", sortOrder)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        name = p.string("name")
        icon = p.string("icon", default: "cart")
        sortOrder = p.int("sortOrder")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
    }
}

extension ShoppingItem: SyncableRecord {
    static var syncKind: SyncKind { .shoppingItem }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("listID", listID)
        p.set("name", name)
        p.set("quantity", quantity)
        p.set("note", note)
        p.set("aisleKey", aisleKey)
        p.set("isBought", isBought)
        p.set("boughtAt", boughtAt)
        p.set("boughtByMemberID", boughtByMemberID)
        p.set("isCleared", isCleared)
        p.set("addedByMemberID", addedByMemberID)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        listID = p.uuid("listID") ?? listID
        name = p.string("name")
        quantity = p.string("quantity")
        note = p.string("note")
        aisleKey = p.string("aisleKey")
        isBought = p.bool("isBought")
        boughtAt = p.date("boughtAt")
        boughtByMemberID = p.uuid("boughtByMemberID")
        isCleared = p.bool("isCleared")
        addedByMemberID = p.uuid("addedByMemberID")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
    }
}

extension FamilyReminder: SyncableRecord {
    static var syncKind: SyncKind { .reminder }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("title", title)
        p.set("notes", notes)
        p.set("dueDate", dueDate)
        p.set("hasTime", hasTime)
        p.set("repeatRaw", repeatRaw)
        p.set("repeatStart", repeatStart)
        p.set("assigneesRaw", assigneesRaw)
        p.set("alertEnabled", alertEnabled)
        p.set("isDone", isDone)
        p.set("completedAt", completedAt)
        p.set("completedByMemberID", completedByMemberID)
        p.set("createdByMemberID", createdByMemberID)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        title = p.string("title")
        notes = p.string("notes")
        dueDate = p.date("dueDate")
        hasTime = p.bool("hasTime")
        repeatRaw = p.string("repeatRaw", default: "never")
        repeatStart = p.date("repeatStart")
        assigneesRaw = p.string("assigneesRaw")
        alertEnabled = p.bool("alertEnabled", default: true)
        isDone = p.bool("isDone")
        completedAt = p.date("completedAt")
        completedByMemberID = p.uuid("completedByMemberID")
        createdByMemberID = p.uuid("createdByMemberID")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
    }
}

extension FamilyEvent: SyncableRecord {
    static var syncKind: SyncKind { .event }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("title", title)
        p.set("kindRaw", kindRaw)
        p.set("location", location)
        p.set("notes", notes)
        p.set("start", start)
        p.set("end", end)
        p.set("isAllDay", isAllDay)
        p.set("repeatRaw", repeatRaw)
        p.set("repeatEnd", repeatEnd)
        p.set("participantsRaw", participantsRaw)
        p.set("alertMinutes", alertMinutes)
        p.set("createdByMemberID", createdByMemberID)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        title = p.string("title")
        kindRaw = p.string("kindRaw", default: "event")
        location = p.string("location")
        notes = p.string("notes")
        start = p.date("start", default: start)
        end = p.date("end", default: end)
        isAllDay = p.bool("isAllDay")
        repeatRaw = p.string("repeatRaw", default: "never")
        repeatEnd = p.date("repeatEnd")
        participantsRaw = p.string("participantsRaw")
        alertMinutes = p.int("alertMinutes", default: -1)
        createdByMemberID = p.uuid("createdByMemberID")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
    }
}

extension LeaveEntry: SyncableRecord {
    static var syncKind: SyncKind { .leave }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("memberID", memberID)
        p.set("typeRaw", typeRaw)
        p.set("firstDay", firstDay)
        p.set("lastDay", lastDay)
        p.set("note", note)
        p.set("createdByMemberID", createdByMemberID)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        memberID = p.uuid("memberID") ?? memberID
        typeRaw = p.string("typeRaw", default: "vacation")
        firstDay = p.date("firstDay", default: firstDay)
        lastDay = p.date("lastDay", default: lastDay)
        note = p.string("note")
        createdByMemberID = p.uuid("createdByMemberID")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
    }
}

extension LeaveAllowance: SyncableRecord {
    static var syncKind: SyncKind { .leaveAllowance }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("memberID", memberID)
        p.set("year", year)
        p.set("tenthDays", tenthDays)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        memberID = p.uuid("memberID") ?? memberID
        year = p.int("year", default: year)
        tenthDays = p.int("tenthDays", default: tenthDays)
        updatedAt = p.date("updatedAt", default: updatedAt)
    }
}

extension Recipe: SyncableRecord {
    static var syncKind: SyncKind { .recipe }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("name", name)
        p.set("ingredientsText", ingredientsText)
        p.set("servings", servings)
        p.set("note", note)
        if !stepsText.isEmpty { p.set("stepsText", stepsText) }
        if !sourceURL.isEmpty { p.set("sourceURL", sourceURL) }
        if !dishID.isEmpty { p.set("dishID", dishID) }
        if !cuisineRaw.isEmpty { p.set("cuisine", cuisineRaw) }
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        name = p.string("name")
        ingredientsText = p.string("ingredientsText")
        servings = p.int("servings", default: 4)
        note = p.string("note")
        stepsText = p.string("stepsText")
        sourceURL = p.string("sourceURL")
        dishID = p.string("dishID")
        cuisineRaw = p.string("cuisine")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
    }
}

extension MealPlanEntry: SyncableRecord {
    static var syncKind: SyncKind { .meal }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("day", day)
        p.set("slotRaw", slotRaw)
        p.set("recipeID", recipeID)
        p.set("title", title)
        p.set("note", note)
        if !dishID.isEmpty { p.set("dishID", dishID) }
        if servings > 0 { p.set("servings", servings) }
        if cookDouble { p.set("cookDouble", true) }
        if isLeftover { p.set("isLeftover", true) }
        if isLunchbox { p.set("isLunchbox", true) }
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        day = p.date("day", default: day)
        slotRaw = p.string("slotRaw", default: "dinner")
        recipeID = p.uuid("recipeID")
        title = p.string("title")
        note = p.string("note")
        dishID = p.string("dishID")
        servings = p.int("servings")
        cookDouble = p.bool("cookDouble")
        isLeftover = p.bool("isLeftover")
        isLunchbox = p.bool("isLunchbox")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
    }
}

extension Trip: SyncableRecord {
    static var syncKind: SyncKind { .trip }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("name", name)
        p.set("destination", destination)
        p.set("startDate", startDate)
        p.set("endDate", endDate)
        p.set("currencyCode", currencyCode)
        p.set("budgetValue", budgetValue)
        p.set("participantsRaw", participantsRaw)
        p.set("guestsRaw", guestsRaw)
        p.set("eventID", eventID)
        p.set("isArchived", isArchived)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        name = p.string("name")
        destination = p.string("destination")
        startDate = p.date("startDate", default: startDate)
        endDate = p.date("endDate", default: endDate)
        currencyCode = p.string("currencyCode", default: "EUR")
        budgetValue = p.int64("budgetValue")
        participantsRaw = p.string("participantsRaw")
        guestsRaw = p.string("guestsRaw")
        eventID = p.uuid("eventID")
        isArchived = p.bool("isArchived")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
    }
}

extension PackingItem: SyncableRecord {
    static var syncKind: SyncKind { .packingItem }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("tripID", tripID)
        p.set("name", name)
        p.set("isPacked", isPacked)
        p.set("memberID", memberID)
        p.set("sortOrder", sortOrder)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        tripID = p.uuid("tripID") ?? tripID
        name = p.string("name")
        isPacked = p.bool("isPacked")
        memberID = p.uuid("memberID")
        sortOrder = p.int("sortOrder")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
    }
}

extension MealPreferences: SyncableRecord {
    static var syncKind: SyncKind { .mealPrefs }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("cuisines", cuisinesRaw)
        p.set("avoid", avoidRaw)
        p.set("maxSpice", maxSpice)
        p.set("vegetarianDays", vegetarianDays)
        p.set("weekdayMinutes", weekdayMinutes)
        p.set("kidFriendly", kidFriendly)
        p.set("planLunch", planLunch)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        cuisinesRaw = p.string("cuisines")
        avoidRaw = p.string("avoid")
        maxSpice = p.int("maxSpice", default: 3)
        vegetarianDays = p.int("vegetarianDays", default: 1)
        weekdayMinutes = p.int("weekdayMinutes", default: 40)
        kidFriendly = p.bool("kidFriendly")
        planLunch = p.bool("planLunch")
        updatedAt = p.date("updatedAt", default: updatedAt)
    }
}

extension MealRating: SyncableRecord {
    static var syncKind: SyncKind { .mealRating }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("dishKey", dishKey)
        p.set("memberID", memberID)
        p.set("value", value)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        dishKey = p.string("dishKey")
        memberID = p.uuid("memberID") ?? memberID
        value = p.int("value")
        updatedAt = p.date("updatedAt", default: updatedAt)
    }
}

extension PantryItem: SyncableRecord {
    static var syncKind: SyncKind { .pantry }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("name", name)
        p.set("quantity", quantity)
        p.set("useBy", useBy)
        p.set("fromReceipt", addedFromReceipt)
        p.set("addedBy", addedByMemberID)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        name = p.string("name")
        quantity = p.string("quantity")
        useBy = p.date("useBy")
        addedFromReceipt = p.bool("fromReceipt")
        addedByMemberID = p.uuid("addedBy")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
    }
}
