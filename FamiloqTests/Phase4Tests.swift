import XCTest
import SwiftData
import FamiloqCore
import FamiloqBudget
@testable import Familoq

/// Phase 4: what the iCloud sync sends and applies (CloudKit itself is only
/// reachable on a signed device, so these tests cover everything around it).
@MainActor
final class SyncMappingTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var family: Family!

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        context = container.mainContext
        family = try FamilyBootstrapper.createFamily(named: "Martin & Carol", ownerName: "Martin", baseCurrency: "EUR",
                                                     ownerCloudUserRecordName: "_martin", in: context)
        let repo = FamilyRepository(context: context, familyID: family.id)
        let groceries = try XCTUnwrap(try repo.categories().first { $0.systemKey == "groceries" })

        let receipt = ReceiptRecord(familyID: family.id, merchant: "Lidl", date: Date(timeIntervalSince1970: 1_790_000_000.4567), total: Decimal(string: "12.34")!, currencyCode: "EUR")
        receipt.rawText = "Lidl\nBananen 2,20"
        receipt.imageData = Data([1, 2, 3])
        context.insert(receipt)
        context.insert(ReceiptItemRecord(familyID: family.id, receiptID: receipt.id, name: "Bananen", amount: Decimal(string: "2.20")!,
                                         categoryID: groceries.id, subcategoryID: nil, sortOrder: 0))

        let expense = Expense(familyID: family.id, amount: Decimal(string: "19.99")!, currencyCode: "USD", baseCurrencyCode: "EUR",
                              merchant: "Diner", date: Date(timeIntervalSince1970: 1_790_100_000.1234))
        expense.baseAmount = Decimal(string: "18.10")!
        expense.exchangeRateText = "0.9055"
        expense.conversionStatus = .converted
        expense.categoryID = groceries.id
        expense.receiptID = receipt.id
        expense.note = "Lunch \"special\" – ü"
        context.insert(expense)
        context.insert(Budget(familyID: family.id, period: .monthly, scope: .category, categoryID: groceries.id, amount: 400, currencyCode: "EUR"))
        try context.save()
    }

    override func tearDown() async throws {
        family = nil
        context = nil
        container = nil
    }

    /// Every record survives payload -> JSON -> other iPhone -> payload unchanged
    /// (otherwise received records would look "changed" and bounce back).
    func testEveryRecordRoundTripsThroughAnotherDevice() throws {
        let otherContainer = try PersistenceController.makeContainer(inMemory: true)
        let other = otherContainer.mainContext
        var count = 0
        for handler in SyncRegistry.handlers {
            for record in try handler.all(context, family.id) {
                let json = record.syncPayload().jsonString
                let copy = handler.make(other, record.syncID, family.id)
                copy.applySyncPayload(try XCTUnwrap(SyncPayload(json: json)))
                XCTAssertEqual(copy.syncPayload().fingerprint, record.syncPayload().fingerprint, "\(handler.kind)")
                XCTAssertEqual(copy.syncID, record.syncID)
                count += 1
            }
        }
        XCTAssertGreaterThan(count, 50, "family, member, categories, subcategories, rules, receipt, item, expense, budget")
        XCTAssertEqual(try SyncRegistry.currentFingerprints(familyID: family.id, context: other),
                       try SyncRegistry.currentFingerprints(familyID: family.id, context: context))
    }

    func testCurrentUserIsNotSynced() throws {
        let member = try XCTUnwrap(FamilyRepository(context: context, familyID: family.id).currentMember())
        XCTAssertNil(member.syncPayload().optionalString("isCurrentUser"))
        XCTAssertEqual(member.syncPayload().string("cloudUserRecordName"), "_martin")
    }

    func testLocalEditChangesOnlyThatFingerprint() throws {
        let before = try SyncRegistry.currentFingerprints(familyID: family.id, context: context)
        let expense = try XCTUnwrap(try context.fetch(FetchDescriptor<Expense>()).first)
        expense.note = "changed"
        let after = try SyncRegistry.currentFingerprints(familyID: family.id, context: context)
        let diff = SyncDiff.compute(current: after, ledger: before)
        XCTAssertEqual(diff.changed, [SyncKind.expense.recordName(for: expense.id)])
        XCTAssertTrue(diff.deleted.isEmpty)
    }

    func testImagesTravelSeparately() throws {
        let receipt = try XCTUnwrap(try context.fetch(FetchDescriptor<ReceiptRecord>()).first)
        XCTAssertEqual(receipt.syncImage, Data([1, 2, 3]))
        XCTAssertNil(receipt.syncPayload().optionalString("imageData"))
        XCTAssertTrue(SyncRegistry.handler(for: .receipt)?.hasImage == true)
        XCTAssertTrue(SyncRegistry.handler(for: .expense)?.hasImage == true)
        XCTAssertFalse(SyncRegistry.handler(for: .budget)?.hasImage == true)
    }

    /// Family isolation: removing one family never touches another one.
    func testDeletingOneFamilyKeepsTheOther() throws {
        let second = try FamilyBootstrapper.createFamily(named: "Other", ownerName: "Carol", in: context)
        context.insert(SyncLedgerEntry(recordName: "family-\(family.id.uuidString)", familyID: family.id, fingerprint: "x"))
        context.insert(SyncZoneRecord(familyID: family.id, zoneName: SyncZone.zoneName(for: family.id), ownerName: "o", isShared: false))
        try context.save()

        let secondBefore = try SyncRegistry.currentFingerprints(familyID: second.id, context: context)
        try SyncRegistry.deleteAll(familyID: family.id, context: context)
        try context.save()

        XCTAssertTrue(try SyncRegistry.currentFingerprints(familyID: family.id, context: context).isEmpty)
        XCTAssertEqual(try SyncRegistry.currentFingerprints(familyID: second.id, context: context), secondBefore)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncLedgerEntry>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncZoneRecord>()).isEmpty)
    }

    func testRecordNamesMatchKinds() throws {
        let names = try SyncRegistry.currentFingerprints(familyID: family.id, context: context).keys
        for name in names {
            XCTAssertNotNil(SyncKind.parse(recordName: name), name)
        }
        XCTAssertTrue(names.contains("family-\(family.id.uuidString)"))
    }
}

@MainActor
final class MultiFamilySessionTests: XCTestCase {
    func testSwitchAndRemoveFamilies() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let a = try FamilyBootstrapper.createFamily(named: "A", ownerName: "Me", in: context)
        let b = try FamilyBootstrapper.createFamily(named: "B", ownerName: "Me", in: context)

        let session = AppSession()
        session.start(context: context)
        XCTAssertEqual(session.families.count, 2)

        session.switchTo(familyID: b.id, context: context)
        XCTAssertEqual(session.family?.id, b.id)
        XCTAssertNotNil(session.currentMember)

        session.familyWillBeRemoved(b.id, context: context)
        XCTAssertEqual(session.family?.id, a.id)
        XCTAssertEqual(session.families.map(\.id), [a.id])
    }

    func testJoinedFamilyWithoutMyMemberNeedsName() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        // A family that arrived from iCloud: only the owner's member entry.
        let family = Family(name: "Martin & Carol")
        context.insert(family)
        context.insert(FamilyMember(familyID: family.id, displayName: "Martin", role: .owner, isCurrentUser: false, cloudUserRecordName: "_martin"))
        try context.save()

        let session = AppSession()
        session.start(context: context)
        XCTAssertTrue(session.needsMemberName)
        XCTAssertFalse(session.can(.addExpenses))

        context.insert(FamilyMember(familyID: family.id, displayName: "Carol", role: .member, isCurrentUser: true, cloudUserRecordName: "_carol"))
        try context.save()
        session.refresh(context: context)
        XCTAssertFalse(session.needsMemberName)
        XCTAssertTrue(session.can(.addExpenses))
        XCTAssertFalse(session.can(.manageBudgets))
    }
}

@MainActor
final class ForeignReceiptDraftTests: XCTestCase {
    func testChoosingYenReadsWholeAmounts() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let family = try FamilyBootstrapper.createFamily(named: "Test", ownerName: "Me", in: context)
        let repo = FamilyRepository(context: context, familyID: family.id)
        let lookup = CategoryLookup(categories: try repo.categories(), subcategories: try repo.subcategories())

        let parsed = ReceiptParser.parse(lines: ["Shop", "Ramen 1,280", "Total 1,280"])
        var draft = ReceiptDrafting.draft(from: parsed, family: family, lookup: lookup, rules: [], imageData: nil)
        XCTAssertFalse(draft.currencyConfirmed, "no currency on the receipt -> ask")
        XCTAssertEqual(draft.currencyCandidates.first, "EUR", "family base currency offered first when nothing was found")

        ReceiptDrafting.applyCurrency("JPY", to: &draft, lookup: lookup)
        XCTAssertTrue(draft.currencyConfirmed)
        XCTAssertEqual(draft.currencyCode, "JPY")
        XCTAssertEqual(draft.total, 1280)
        XCTAssertEqual(draft.items.first?.amount, 1280)
        XCTAssertFalse(draft.warnings.contains { $0.contains("urrency") })
    }

    func testCertainCurrencyNeedsNoQuestion() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let family = try FamilyBootstrapper.createFamily(named: "Test", ownerName: "Me", in: context)
        let repo = FamilyRepository(context: context, familyID: family.id)
        let lookup = CategoryLookup(categories: try repo.categories(), subcategories: try repo.subcategories())
        let parsed = ReceiptParser.parse(lines: ["Tesco", "Milk 1.20", "TOTAL £1.20"])
        let draft = ReceiptDrafting.draft(from: parsed, family: family, lookup: lookup, rules: [], imageData: nil)
        XCTAssertTrue(draft.currencyConfirmed)
        XCTAssertEqual(draft.currencyCode, "GBP")
    }
}
