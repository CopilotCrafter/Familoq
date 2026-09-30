import Foundation
import SwiftData
import FamiloqCore
import FamiloqBudget

/// Household space: cars (with their costs from the budget) and the family
/// document vault.
@MainActor
enum HouseholdModule: FamiloqModule {
    static let space: FamiloqSpace = .cars

    static let models: [any PersistentModel.Type] = [
        Car.self,
        FamilyDocument.self,
        DocumentPage.self
    ]

    static func seedDefaults(familyID: UUID, in context: ModelContext) {}

    static var syncHandlers: [SyncHandler] {
        [
            .of(Car.self,
                inFamily: { fid in #Predicate<Car> { $0.familyID == fid } },
                withID: { id in #Predicate<Car> { $0.id == id } },
                make: { id, fid in Car(id: id, familyID: fid, name: "") }),
            .of(FamilyDocument.self,
                inFamily: { fid in #Predicate<FamilyDocument> { $0.familyID == fid && $0.isPrivate == false } },
                withID: { id in #Predicate<FamilyDocument> { $0.id == id } },
                inFamilyForBackup: { fid in #Predicate<FamilyDocument> { $0.familyID == fid } },
                make: { id, fid in FamilyDocument(id: id, familyID: fid, title: "") }),
            .of(DocumentPage.self, hasImage: true,
                inFamily: { fid in #Predicate<DocumentPage> { $0.familyID == fid && $0.isPrivate == false } },
                withID: { id in #Predicate<DocumentPage> { $0.id == id } },
                inFamilyForBackup: { fid in #Predicate<DocumentPage> { $0.familyID == fid } },
                make: { id, fid in DocumentPage(id: id, familyID: fid, documentID: UUID()) })
        ]
    }
}

@MainActor
enum CarService {
    /// Transport category and the built-in subcategory of a car cost.
    static func transportIDs(_ kind: CarCostKind, lookup: CategoryLookup) -> (categoryID: UUID?, subcategoryID: UUID?) {
        let category = lookup.categories.first { $0.systemKey == "transport" }
        let sub = lookup.subcategories.first { $0.categoryID == category?.id && $0.systemKey == kind.subcategoryKey }
        return (category?.id, sub?.id)
    }

    static func entries(_ expenses: [Expense]) -> [CarLogEntry] {
        expenses.map { e in
            CarLogEntry(date: e.date, amount: e.baseAmount ?? e.amount,
                        kind: e.carCost ?? .other,
                        quantity: e.fuelQuantity, odometer: e.odometer > 0 ? e.odometer : nil)
        }
    }

    static func cars(familyID: UUID, context: ModelContext) -> [Car] {
        let fid = familyID
        return (try? context.fetch(FetchDescriptor<Car>(predicate: #Predicate { $0.familyID == fid && $0.isArchived == false },
                                                        sortBy: [SortDescriptor(\Car.sortOrder), SortDescriptor(\Car.createdAt)]))) ?? []
    }

    /// The car this person used last (default on the next fuel receipt).
    static func lastCarKey(memberID: UUID?) -> String { "car.last.\(memberID?.uuidString ?? "me")" }

    static func lastCar(memberID: UUID?, cars: [Car]) -> UUID? {
        if let text = UserDefaults.standard.string(forKey: lastCarKey(memberID: memberID)),
           let id = UUID(uuidString: text), cars.contains(where: { $0.id == id }) {
            return id
        }
        if let memberID, let driven = cars.first(where: { $0.drivers.contains(memberID) }) { return driven.id }
        return cars.count == 1 ? cars.first?.id : nil
    }

    static func rememberCar(_ carID: UUID?, memberID: UUID?) {
        guard let carID else { return }
        UserDefaults.standard.set(carID.uuidString, forKey: lastCarKey(memberID: memberID))
    }

    /// Removes the car; its costs stay in the budget (without the car).
    static func delete(_ car: Car, context: ModelContext) {
        let cid: UUID? = car.id
        for expense in (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.carID == cid }))) ?? [] {
            expense.carID = nil
            expense.updatedAt = Date()
        }
        for schedule in (try? context.fetch(FetchDescriptor<ScheduledExpense>(predicate: #Predicate { $0.carID == cid }))) ?? [] {
            schedule.carID = nil
            schedule.updatedAt = Date()
        }
        for contract in (try? context.fetch(FetchDescriptor<Contract>(predicate: #Predicate { $0.carID == cid }))) ?? [] {
            contract.carID = nil
            contract.updatedAt = Date()
        }
        for document in (try? context.fetch(FetchDescriptor<FamilyDocument>(predicate: #Predicate { $0.carID == cid }))) ?? [] {
            document.carID = nil
            document.updatedAt = Date()
        }
        context.delete(car)
        try? context.save()
        Task { await PlannerNotifications.reschedule(context: context) }
    }
}
