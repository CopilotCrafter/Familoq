import Foundation
import SwiftData
import FamiloqCore

/// The ONLY way services read family data. Every query is scoped to one
/// `familyID`, so code that goes through the repository cannot accidentally
/// read another family's records (spec section 4).
@MainActor
struct FamilyRepository {
    let context: ModelContext
    let familyID: UUID

    // MARK: Family (shared by every module)

    func family() throws -> Family? {
        let fid = familyID
        var descriptor = FetchDescriptor<Family>(predicate: #Predicate<Family> { $0.id == fid })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func members(includeInactive: Bool = false) throws -> [FamilyMember] {
        let fid = familyID
        let descriptor = FetchDescriptor<FamilyMember>(
            predicate: #Predicate<FamilyMember> { $0.familyID == fid },
            sortBy: [SortDescriptor(\FamilyMember.joinedAt)]
        )
        let all = try context.fetch(descriptor)
        return includeInactive ? all : all.filter(\.isActive)
    }

    func currentMember() throws -> FamilyMember? {
        try members().first(where: \.isCurrentUser)
    }
}

enum RepositoryError: LocalizedError {
    case wrongFamily

    var errorDescription: String? {
        switch self {
        case .wrongFamily: return "This record belongs to a different family."
        }
    }
}
