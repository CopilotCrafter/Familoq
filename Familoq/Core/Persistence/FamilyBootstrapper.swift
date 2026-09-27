import Foundation
import SwiftData
import FamiloqCore

/// Creates families and lets every enabled module seed its defaults
/// (Budget: categories and merchant rules).
///
/// Since Phase 3 a family is created explicitly in "Create your family" after
/// the App Invitation was redeemed. `ensureFamily` remains for tests/demo.
@MainActor
enum FamilyBootstrapper {
    /// The family on this device, if one was created or joined.
    static func existingFamily(in context: ModelContext) throws -> Family? {
        var descriptor = FetchDescriptor<Family>(sortBy: [SortDescriptor(\Family.createdAt)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func ensureFamily(in context: ModelContext) throws -> Family {
        var descriptor = FetchDescriptor<Family>(sortBy: [SortDescriptor(\Family.createdAt)])
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        return try createFamily(named: "My Family", ownerName: "Me", in: context)
    }

    @discardableResult
    static func createFamily(named name: String, ownerName: String, baseCurrency: String = CurrencyInfo.defaultBaseCurrency, ownerCloudUserRecordName: String = "", in context: ModelContext) throws -> Family {
        let family = Family(name: name, baseCurrencyCode: baseCurrency, maxMembers: FamilyLimits.defaultMaxMembers)
        context.insert(family)

        let owner = FamilyMember(familyID: family.id, displayName: ownerName, role: .owner, isCurrentUser: true, cloudUserRecordName: ownerCloudUserRecordName)
        context.insert(owner)

        for module in FamiloqModules.enabled {
            module.seedDefaults(familyID: family.id, in: context)
        }

        try context.save()
        return family
    }
}
