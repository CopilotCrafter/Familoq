import Foundation
import SwiftData
import FamiloqCore

// Cars and documents shared with the family through iCloud. Documents kept
// "Only on this iPhone" (and their pages) are never sent.

extension Car: SyncableRecord {
    static var syncKind: SyncKind { .car }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("name", name)
        p.set("plate", plate)
        p.set("fuelType", fuelTypeRaw)
        p.set("nextInspection", nextInspection)
        p.set("nextService", nextService)
        p.set("nextServiceKm", nextServiceKm)
        p.set("tyreReminder", tyreReminder)
        p.set("drivers", driversRaw)
        p.set("note", note)
        p.set("isArchived", isArchived)
        p.set("sortOrder", sortOrder)
        p.set("createdByMemberID", createdByMemberID)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        name = p.string("name")
        plate = p.string("plate")
        fuelTypeRaw = p.string("fuelType", default: "petrol")
        nextInspection = p.date("nextInspection")
        nextService = p.date("nextService")
        nextServiceKm = p.int("nextServiceKm")
        tyreReminder = p.bool("tyreReminder")
        driversRaw = p.string("drivers")
        note = p.string("note")
        isArchived = p.bool("isArchived")
        sortOrder = p.int("sortOrder")
        createdByMemberID = p.uuid("createdByMemberID")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
    }
}

extension FamilyDocument: SyncableRecord {
    var isSyncShareable: Bool { !isPrivate }
    static var syncKind: SyncKind { .document }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("title", title)
        p.set("kind", kindRaw)
        p.set("memberID", memberID)
        p.set("personName", personName)
        p.set("carID", carID)
        p.set("number", number)
        p.set("issuedOn", issuedOn)
        p.set("expiresOn", expiresOn)
        p.set("remind", remind)
        p.set("note", note)
        p.set("createdByMemberID", createdByMemberID)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        if !tagsRaw.isEmpty { p.set("tags", tagsRaw) }
        if !tripIDsRaw.isEmpty { p.set("trips", tripIDsRaw) }
        // Only ever set in backups (private records are not synced).
        if isPrivate { p.set("private", true) }
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        title = p.string("title")
        kindRaw = p.string("kind", default: "other")
        memberID = p.uuid("memberID")
        personName = p.string("personName")
        carID = p.uuid("carID")
        number = p.string("number")
        issuedOn = p.date("issuedOn")
        expiresOn = p.date("expiresOn")
        remind = p.bool("remind", default: true)
        note = p.string("note")
        tagsRaw = p.string("tags")
        tripIDsRaw = p.string("trips")
        createdByMemberID = p.uuid("createdByMemberID")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
        // Sync never un-privates a record kept on this iPhone; a backup can mark one private.
        if p.values["private"] != nil { isPrivate = true }
    }
}

extension DocumentPage: SyncableRecord {
    var isSyncShareable: Bool { !isPrivate }
    static var syncKind: SyncKind { .documentPage }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("documentID", documentID)
        p.set("format", format)
        p.set("bytes", byteCount)
        p.set("sortOrder", sortOrder)
        p.set("createdAt", createdAt)
        if !sideRaw.isEmpty { p.set("side", sideRaw) }
        if quarterTurns != 0 { p.set("turns", quarterTurns) }
        if isPrivate { p.set("private", true) }
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        documentID = p.uuid("documentID") ?? documentID
        format = p.string("format", default: "jpg")
        byteCount = p.int("bytes")
        sortOrder = p.int("sortOrder")
        createdAt = p.date("createdAt", default: createdAt)
        sideRaw = p.string("side")
        quarterTurns = p.int("turns")
        if p.values["private"] != nil { isPrivate = true }
    }

    /// The page travels as a file (CKAsset) next to the record.
    var syncImage: Data? {
        get { data }
        set {
            data = newValue
            if let newValue { byteCount = newValue.count }
        }
    }
}
