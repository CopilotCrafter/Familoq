import Foundation
import SwiftData
import FamiloqCore

/// Creates the local family on first launch and lets every enabled module
/// seed its defaults (Budget: categories and merchant rules).
///
/// Phase 1 note: there is exactly one local family ("My Family") and the
/// device user is its owner. Phase 3 replaces this with invitation-based
/// onboarding (App Invitation -> account -> create/join family).
@MainActor
enum FamilyBootstrapper {
    static func ensureFamily(in context: ModelContext) throws -> Family {
        var descriptor = FetchDescriptor<Family>(sortBy: [SortDescriptor(\Family.createdAt)])
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        return try createFamily(named: "My Family", ownerName: "Me", in: context)
    }

    @discardableResult
    static func createFamily(named name: String, ownerName: String, baseCurrency: String = CurrencyInfo.defaultBaseCurrency, in context: ModelContext) throws -> Family {
        let family = Family(name: name, baseCurrencyCode: baseCurrency, maxMembers: FamilyLimits.defaultMaxMembers)
        context.insert(family)

        let owner = FamilyMember(familyID: family.id, displayName: ownerName, role: .owner, isCurrentUser: true)
        context.insert(owner)

        for module in FamiloqModules.enabled {
            module.seedDefaults(familyID: family.id, in: context)
        }

        try context.save()
        return family
    }
}
