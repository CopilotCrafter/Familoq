import Foundation
import SwiftData
import FamiloqCore
import FamiloqBudget

// Household space: the family's cars and the document vault.

/// A family car. Its costs are ordinary expenses with `carID` set.
@Model
final class Car {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var name: String = ""
    /// Number plate ("CHA-FM 123").
    var plate: String = ""
    var fuelTypeRaw: String = FuelType.petrol.rawValue
    /// Next main inspection (HU / "TÜV").
    var nextInspection: Date? = nil
    /// Next service by date and/or km.
    var nextService: Date? = nil
    var nextServiceKm: Int = 0
    /// Remind to change tyres (October / April).
    var tyreReminder: Bool = false
    /// Who drives it (comma-separated member IDs; empty = everyone).
    var driversRaw: String = ""
    var note: String = ""
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var createdByMemberID: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, name: String) {
        self.id = id
        self.familyID = familyID
        self.name = name
    }

    var fuelType: FuelType {
        get { FuelType(rawValue: fuelTypeRaw) ?? .petrol }
        set { fuelTypeRaw = newValue.rawValue }
    }

    var drivers: Set<UUID> {
        get { Set(driversRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) }) }
        set { driversRaw = newValue.map(\.uuidString).sorted().joined(separator: ",") }
    }

    /// "Golf (CHA-FM 123)" or just the name.
    var displayName: String {
        let n = name.isEmpty ? String(localized: "Car") : name
        return plate.isEmpty ? n : "\(n) (\(plate))"
    }
}

/// A document in the family vault (passport, car registration …).
/// Its pages are `DocumentPage`s. "Only on this iPhone" keeps it off iCloud.
@Model
final class FamilyDocument {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var title: String = ""
    var kindRaw: String = DocumentKind.other.rawValue
    /// Whose document (a family member, or a name for a child without the app).
    var memberID: UUID? = nil
    var personName: String = ""
    var carID: UUID? = nil
    /// Passport / policy number.
    var number: String = ""
    var issuedOn: Date? = nil
    var expiresOn: Date? = nil
    var remind: Bool = true
    var note: String = ""
    var isPrivate: Bool = false
    /// Tags ("Car", "Taxes 2026"), comma-separated.
    var tagsRaw: String = ""
    /// Trips it is needed for (travel folder), comma-separated IDs.
    var tripIDsRaw: String = ""
    var createdByMemberID: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, title: String) {
        self.id = id
        self.familyID = familyID
        self.title = title
    }

    var kind: DocumentKind {
        get { DocumentKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var displayTitle: String {
        title.isEmpty ? String(localized: String.LocalizationValue(kind.title)) : title
    }

    var tags: [String] {
        get { DocumentTags.parse(tagsRaw) }
        set { tagsRaw = DocumentTags.encode(newValue) }
    }

    var tripIDs: Set<UUID> {
        get { Set(tripIDsRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) }) }
        set { tripIDsRaw = newValue.map(\.uuidString).sorted().joined(separator: ",") }
    }
}

/// One page (photo) or an imported PDF of a document.
@Model
final class DocumentPage {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var documentID: UUID = UUID()
    /// "jpg" or "pdf".
    var format: String = "jpg"
    @Attribute(.externalStorage) var data: Data? = nil
    var byteCount: Int = 0
    var sortOrder: Int = 0
    /// Copied from the document so the page is never uploaded on its own.
    var isPrivate: Bool = false
    /// "front" / "back" of a card, empty for other pages.
    var sideRaw: String = ""
    /// Quarter turns clockwise (0-3), applied when shown and exported.
    var quarterTurns: Int = 0
    /// Words read from the page on this iPhone (for search only, not synced).
    var text: String = ""
    /// Local: text reading was tried (also when the page has no text).
    var textScanned: Bool = false
    var createdAt: Date = Date()

    init(id: UUID = UUID(), familyID: UUID, documentID: UUID, format: String = "jpg", data: Data? = nil, sortOrder: Int = 0) {
        self.id = id
        self.familyID = familyID
        self.documentID = documentID
        self.format = format
        self.data = data
        self.byteCount = data?.count ?? 0
        self.sortOrder = sortOrder
    }

    var isPDF: Bool { format == "pdf" }

    var side: PageSide {
        get { PageSide(rawValue: sideRaw) ?? .none }
        set { sideRaw = newValue.rawValue }
    }
}
