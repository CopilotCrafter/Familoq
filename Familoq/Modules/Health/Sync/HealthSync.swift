import Foundation
import SwiftData
import FamiloqCore

// Health records shared with the family through iCloud (unless private).
// `isPrivate` itself is never synced: a private record is not sent at all.

extension HealthPerson: SyncableRecord {
    static var syncKind: SyncKind { .healthPerson }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("name", name)
        p.set("memberID", memberID)
        p.set("birthDate", birthDate)
        p.set("conditions", conditionsRaw)
        p.set("allergens", allergensRaw)
        p.set("bloodType", bloodType)
        p.set("emergencyName", emergencyName)
        p.set("emergencyPhone", emergencyPhone)
        p.set("notes", notes)
        p.set("remindMembers", remindMembersRaw)
        p.set("sortOrder", sortOrder)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        // Only ever set in backups (private records are not synced).
        if isPrivate { p.set("private", true) }
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        name = p.string("name")
        memberID = p.uuid("memberID")
        birthDate = p.date("birthDate")
        conditionsRaw = p.string("conditions")
        allergensRaw = p.string("allergens")
        bloodType = p.string("bloodType")
        emergencyName = p.string("emergencyName")
        emergencyPhone = p.string("emergencyPhone")
        notes = p.string("notes")
        remindMembersRaw = p.string("remindMembers")
        sortOrder = p.int("sortOrder")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
        isPrivate = p.bool("private")
    }
}

extension Checkup: SyncableRecord {
    static var syncKind: SyncKind { .checkup }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("personID", personID)
        p.set("kind", kindRaw)
        p.set("title", title)
        p.set("lastDate", lastDate)
        p.set("intervalMonths", intervalMonths)
        p.set("appointment", appointment)
        p.set("doneExams", doneExamsRaw)
        p.set("note", note)
        p.set("remind", remind)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        // Only ever set in backups (private records are not synced).
        if isPrivate { p.set("private", true) }
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        personID = p.uuid("personID") ?? personID
        kindRaw = p.string("kind", default: "custom")
        title = p.string("title")
        lastDate = p.date("lastDate")
        intervalMonths = p.int("intervalMonths", default: 12)
        appointment = p.date("appointment")
        doneExamsRaw = p.string("doneExams")
        note = p.string("note")
        remind = p.bool("remind", default: true)
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
        isPrivate = p.bool("private")
    }
}

extension Vaccination: SyncableRecord {
    static var syncKind: SyncKind { .vaccination }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("personID", personID)
        p.set("kind", kindRaw)
        p.set("title", title)
        p.set("date", date)
        p.set("boosterMonths", boosterMonths)
        p.set("nextDue", nextDue)
        p.set("batch", batch)
        p.set("note", note)
        p.set("tripID", tripID)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        // Only ever set in backups (private records are not synced).
        if isPrivate { p.set("private", true) }
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        personID = p.uuid("personID") ?? personID
        kindRaw = p.string("kind", default: "custom")
        title = p.string("title")
        date = p.date("date", default: date)
        boosterMonths = p.int("boosterMonths")
        nextDue = p.date("nextDue")
        batch = p.string("batch")
        note = p.string("note")
        tripID = p.uuid("tripID")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
        isPrivate = p.bool("private")
    }
}

extension Medication: SyncableRecord {
    static var syncKind: SyncKind { .medication }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("personID", personID)
        p.set("name", name)
        p.set("dose", dose)
        p.set("times", timesRaw)
        p.set("perDay", String(perDay))
        p.set("stock", String(stock))
        p.set("stockDate", stockDate)
        p.set("remindDoses", remindDoses)
        p.set("remindRefill", remindRefill)
        p.set("isActive", isActive)
        p.set("note", note)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        // Only ever set in backups (private records are not synced).
        if isPrivate { p.set("private", true) }
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        personID = p.uuid("personID") ?? personID
        name = p.string("name")
        dose = p.string("dose")
        timesRaw = p.string("times")
        perDay = Double(p.string("perDay")) ?? 1
        stock = Double(p.string("stock")) ?? 0
        stockDate = p.date("stockDate", default: stockDate)
        remindDoses = p.bool("remindDoses", default: true)
        remindRefill = p.bool("remindRefill", default: true)
        isActive = p.bool("isActive", default: true)
        note = p.string("note")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
        isPrivate = p.bool("private")
    }
}

extension HealthMeasurement: SyncableRecord {
    static var syncKind: SyncKind { .measurement }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("personID", personID)
        p.set("type", typeRaw)
        p.set("value", String(value))
        p.set("value2", String(value2))
        p.set("date", date)
        p.set("note", note)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        // Only ever set in backups (private records are not synced).
        if isPrivate { p.set("private", true) }
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        personID = p.uuid("personID") ?? personID
        typeRaw = p.string("type", default: "weight")
        value = Double(p.string("value")) ?? 0
        value2 = Double(p.string("value2")) ?? 0
        date = p.date("date", default: date)
        note = p.string("note")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
        isPrivate = p.bool("private")
    }
}

extension HealthContact: SyncableRecord {
    static var syncKind: SyncKind { .healthContact }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("name", name)
        p.set("specialty", specialty)
        p.set("phone", phone)
        p.set("address", address)
        p.set("note", note)
        p.set("personIDs", personIDsRaw)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        name = p.string("name")
        specialty = p.string("specialty")
        phone = p.string("phone")
        address = p.string("address")
        note = p.string("note")
        personIDsRaw = p.string("personIDs")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
    }
}

extension InsuranceClaim: SyncableRecord {
    static var syncKind: SyncKind { .claim }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("personID", personID)
        p.set("title", title)
        p.set("insurer", insurer)
        p.set("expenseID", expenseID)
        p.set("amountValue", amountValue)
        p.set("currencyCode", currencyCode)
        p.set("submittedOn", submittedOn)
        p.set("refundedValue", refundedValue)
        p.set("refundedOn", refundedOn)
        p.set("note", note)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        // Only ever set in backups (private records are not synced).
        if isPrivate { p.set("private", true) }
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        personID = p.uuid("personID")
        title = p.string("title")
        insurer = p.string("insurer")
        expenseID = p.uuid("expenseID")
        amountValue = p.int64("amountValue")
        currencyCode = p.string("currencyCode", default: "EUR")
        submittedOn = p.date("submittedOn")
        refundedValue = p.int64("refundedValue")
        refundedOn = p.date("refundedOn")
        note = p.string("note")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
        isPrivate = p.bool("private")
    }
}

extension PlateLog: SyncableRecord {
    static var syncKind: SyncKind { .plate }
    var syncID: UUID { id }

    func syncPayload() -> SyncPayload {
        var p = SyncPayload()
        p.set("personID", personID)
        p.set("date", date)
        p.set("slot", slotRaw)
        p.set("parts", partsRaw)
        p.set("score", score)
        p.set("note", note)
        p.set("createdAt", createdAt)
        p.set("updatedAt", updatedAt)
        // Only ever set in backups (private records are not synced).
        if isPrivate { p.set("private", true) }
        return p
    }

    func applySyncPayload(_ p: SyncPayload) {
        personID = p.uuid("personID")
        date = p.date("date", default: date)
        slotRaw = p.string("slot", default: "dinner")
        partsRaw = p.string("parts")
        score = p.int("score")
        note = p.string("note")
        createdAt = p.date("createdAt", default: createdAt)
        updatedAt = p.date("updatedAt", default: updatedAt)
        isPrivate = p.bool("private")
    }
}
