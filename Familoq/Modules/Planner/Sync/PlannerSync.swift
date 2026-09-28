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
                make: { id, fid in FamilyEvent(id: id, familyID: fid, title: "", start: Date(), end: Date(), isAllDay: false) })
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
