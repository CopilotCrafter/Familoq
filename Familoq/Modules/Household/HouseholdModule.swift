import Foundation
import SwiftData
import PDFKit
import UIKit
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

@MainActor
enum DocumentService {
    static func pages(of documentID: UUID, context: ModelContext) -> [DocumentPage] {
        let did = documentID
        return (try? context.fetch(FetchDescriptor<DocumentPage>(predicate: #Predicate { $0.documentID == did },
                                                                 sortBy: [SortDescriptor(\DocumentPage.sortOrder)]))) ?? []
    }

    /// Adds scanned or imported pages after the existing ones.
    static func addPages(_ items: [(format: String, data: Data)], to document: FamilyDocument, context: ModelContext) {
        var order = (pages(of: document.id, context: context).map(\.sortOrder).max() ?? -1) + 1
        for item in items {
            let page = DocumentPage(familyID: document.familyID, documentID: document.id, format: item.format, data: item.data, sortOrder: order)
            page.isPrivate = document.isPrivate
            context.insert(page)
            order += 1
        }
        document.updatedAt = Date()
    }

    /// Keeps the pages' privacy in step with the document.
    static func setPrivate(_ document: FamilyDocument, _ value: Bool, context: ModelContext) {
        document.isPrivate = value
        document.updatedAt = Date()
        for page in pages(of: document.id, context: context) { page.isPrivate = value }
    }

    static func delete(_ document: FamilyDocument, context: ModelContext) {
        for page in pages(of: document.id, context: context) { context.delete(page) }
        context.delete(document)
        try? context.save()
        Task { await PlannerNotifications.reschedule(context: context) }
    }

    /// Stores a photo as a sharp but small colour JPEG (documents need
    /// colour and must stay readable when printed).
    static func storageJPEG(_ image: UIImage, maxSide: CGFloat = 2200) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.72)
    }

    /// All pages as one PDF - for "Download / Share".
    static func pdf(of pages: [DocumentPage]) -> Data? {
        let result = PDFDocument()
        for page in pages {
            guard let data = page.data else { continue }
            if page.isPDF {
                guard let source = PDFDocument(data: data) else { continue }
                for index in 0..<source.pageCount {
                    if let p = source.page(at: index) { result.insert(p, at: result.pageCount) }
                }
            } else if let image = UIImage(data: data), let p = PDFPage(image: image) {
                result.insert(p, at: result.pageCount)
            }
        }
        guard result.pageCount > 0 else { return nil }
        return result.dataRepresentation()
    }

    /// Writes the PDF to a temporary file named after the document.
    static func exportFile(_ document: FamilyDocument, pages: [DocumentPage]) -> URL? {
        guard let data = pdf(of: pages) else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        var name = String(document.displayTitle.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        if !document.personName.isEmpty { name += " - " + String(document.personName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FamiloqExport", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent((name.isEmpty ? "Document" : name) + ".pdf")
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }

    /// Removes exported copies (they are only needed while sharing).
    static func clearExports() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FamiloqExport", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
    }
}
