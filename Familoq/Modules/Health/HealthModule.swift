import Foundation
import SwiftData
import FamiloqCore
import FamiloqHealth

/// Health space: people's health profiles (for the menu), check-ups,
/// vaccinations, medications, measurements, contacts, insurance refunds and
/// plate checks. Records marked "Only on this iPhone" are never synced.
@MainActor
enum HealthModule: FamiloqModule {
    static let space: FamiloqSpace = .health

    static let models: [any PersistentModel.Type] = [
        HealthPerson.self,
        Checkup.self,
        Vaccination.self,
        Medication.self,
        HealthMeasurement.self,
        HealthContact.self,
        InsuranceClaim.self,
        PlateLog.self
    ]

    static func seedDefaults(familyID: UUID, in context: ModelContext) {}

    /// Private records are left out here, so they are never uploaded - and a
    /// record switched to private is removed from iCloud by the next sync.
    static var syncHandlers: [SyncHandler] {
        [
            .of(HealthPerson.self,
                inFamily: { fid in #Predicate<HealthPerson> { $0.familyID == fid && $0.isPrivate == false } },
                withID: { id in #Predicate<HealthPerson> { $0.id == id } },
                inFamilyForBackup: { fid in #Predicate<HealthPerson> { $0.familyID == fid } },
                make: { id, fid in HealthPerson(id: id, familyID: fid, name: "") }),
            .of(Checkup.self,
                inFamily: { fid in #Predicate<Checkup> { $0.familyID == fid && $0.isPrivate == false } },
                withID: { id in #Predicate<Checkup> { $0.id == id } },
                inFamilyForBackup: { fid in #Predicate<Checkup> { $0.familyID == fid } },
                make: { id, fid in Checkup(id: id, familyID: fid, personID: UUID(), kind: .custom) }),
            .of(Vaccination.self,
                inFamily: { fid in #Predicate<Vaccination> { $0.familyID == fid && $0.isPrivate == false } },
                withID: { id in #Predicate<Vaccination> { $0.id == id } },
                inFamilyForBackup: { fid in #Predicate<Vaccination> { $0.familyID == fid } },
                make: { id, fid in Vaccination(id: id, familyID: fid, personID: UUID(), kind: .custom, date: Date()) }),
            .of(Medication.self,
                inFamily: { fid in #Predicate<Medication> { $0.familyID == fid && $0.isPrivate == false } },
                withID: { id in #Predicate<Medication> { $0.id == id } },
                inFamilyForBackup: { fid in #Predicate<Medication> { $0.familyID == fid } },
                make: { id, fid in Medication(id: id, familyID: fid, personID: UUID(), name: "") }),
            .of(HealthMeasurement.self,
                inFamily: { fid in #Predicate<HealthMeasurement> { $0.familyID == fid && $0.isPrivate == false } },
                withID: { id in #Predicate<HealthMeasurement> { $0.id == id } },
                inFamilyForBackup: { fid in #Predicate<HealthMeasurement> { $0.familyID == fid } },
                make: { id, fid in HealthMeasurement(id: id, familyID: fid, personID: UUID(), type: .weight, value: 0, date: Date()) }),
            .of(HealthContact.self,
                inFamily: { fid in #Predicate<HealthContact> { $0.familyID == fid } },
                withID: { id in #Predicate<HealthContact> { $0.id == id } },
                make: { id, fid in HealthContact(id: id, familyID: fid, name: "") }),
            .of(InsuranceClaim.self,
                inFamily: { fid in #Predicate<InsuranceClaim> { $0.familyID == fid && $0.isPrivate == false } },
                withID: { id in #Predicate<InsuranceClaim> { $0.id == id } },
                inFamilyForBackup: { fid in #Predicate<InsuranceClaim> { $0.familyID == fid } },
                make: { id, fid in InsuranceClaim(id: id, familyID: fid, title: "") }),
            .of(PlateLog.self,
                inFamily: { fid in #Predicate<PlateLog> { $0.familyID == fid && $0.isPrivate == false } },
                withID: { id in #Predicate<PlateLog> { $0.id == id } },
                inFamilyForBackup: { fid in #Predicate<PlateLog> { $0.familyID == fid } },
                make: { id, fid in PlateLog(id: id, familyID: fid, date: Date()) })
        ]
    }
}

@MainActor
enum HealthService {
    static func people(familyID: UUID, context: ModelContext) -> [HealthPerson] {
        let fid = familyID
        return (try? context.fetch(FetchDescriptor<HealthPerson>(predicate: #Predicate { $0.familyID == fid },
                                                                sortBy: [SortDescriptor(\HealthPerson.sortOrder), SortDescriptor(\HealthPerson.createdAt)]))) ?? []
    }

    /// The current user's own health profile (created when they tap "Add my
    /// health profile" - only on their own iPhone, so "Only on this iPhone" is
    /// never undone by another iPhone recreating it).
    static func ensureMe(family: Family, member: FamilyMember?, context: ModelContext) {
        guard let member else { return }
        let existing = people(familyID: family.id, context: context)
        guard !existing.contains(where: { $0.memberID == member.id }) else { return }
        let person = HealthPerson(id: DeterministicID.uuid("health-person|\(family.id.uuidString)|\(member.id.uuidString)"),
                                  familyID: family.id, name: member.displayName)
        person.memberID = member.id
        person.sortOrder = (existing.map(\.sortOrder).min() ?? 1) - 1
        context.insert(person)
        try? context.save()
    }

    /// The family's diet profile for meal suggestions (everyone's conditions
    /// that are on this iPhone, plus the family's meal settings).
    static func dietProfile(familyID: UUID, context: ModelContext) -> DietProfile {
        let people = people(familyID: familyID, context: context)
        let prefs = MealSettingsService.existing(familyID: familyID, context: context)
        return DietProfile(people: people.map(\.dietPerson), avoidWords: prefs?.avoidWords ?? [],
                           maxSpice: prefs?.maxSpice ?? 3, kidFriendly: prefs?.kidFriendly ?? false)
    }

    /// Makes a person and everything of theirs private (or shared again).
    static func setPrivate(_ person: HealthPerson, _ value: Bool, context: ModelContext) {
        let pid = person.id
        let optionalPID: UUID? = pid
        person.isPrivate = value
        person.updatedAt = Date()
        let now = Date()
        for item in (try? context.fetch(FetchDescriptor<Checkup>(predicate: #Predicate { $0.personID == pid }))) ?? [] { item.isPrivate = value; item.updatedAt = now }
        for item in (try? context.fetch(FetchDescriptor<Vaccination>(predicate: #Predicate { $0.personID == pid }))) ?? [] { item.isPrivate = value; item.updatedAt = now }
        if value {
            for item in (try? context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.personID == pid }))) ?? [] { item.isPrivate = true; item.updatedAt = now }
            for item in (try? context.fetch(FetchDescriptor<HealthMeasurement>(predicate: #Predicate { $0.personID == pid }))) ?? [] { item.isPrivate = true; item.updatedAt = now }
            for item in (try? context.fetch(FetchDescriptor<InsuranceClaim>(predicate: #Predicate { $0.personID == optionalPID }))) ?? [] { item.isPrivate = true; item.updatedAt = now }
            for item in (try? context.fetch(FetchDescriptor<PlateLog>(predicate: #Predicate { $0.personID == optionalPID }))) ?? [] { item.isPrivate = true; item.updatedAt = now }
        }
        try? context.save()
    }

    /// Deletes a person and all their health records.
    static func delete(_ person: HealthPerson, context: ModelContext) {
        let pid = person.id
        let optionalPID: UUID? = pid
        for item in (try? context.fetch(FetchDescriptor<Checkup>(predicate: #Predicate { $0.personID == pid }))) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<Vaccination>(predicate: #Predicate { $0.personID == pid }))) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.personID == pid }))) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<HealthMeasurement>(predicate: #Predicate { $0.personID == pid }))) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<InsuranceClaim>(predicate: #Predicate { $0.personID == optionalPID }))) ?? [] { item.personID = nil }
        for item in (try? context.fetch(FetchDescriptor<PlateLog>(predicate: #Predicate { $0.personID == optionalPID }))) ?? [] { context.delete(item) }
        context.delete(person)
        try? context.save()
        Task { await PlannerNotifications.reschedule(context: context) }
    }
}
