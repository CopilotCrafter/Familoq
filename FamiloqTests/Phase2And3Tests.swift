import XCTest
import SwiftData
import FamiloqCore
import FamiloqBudget
@testable import Familoq

// MARK: - Phase 3: App Invitation / account (CloudKit backend stubbed)

final class StubAccessBackend: AccessBackend {
    var userRecordName = "_user1"
    var noICloud = false
    var admin = false
    var offline = false
    /// codeHash -> status
    var invitations: [String: AppInvitationStatus] = [:]
    /// codeHash -> user who redeemed
    var redemptions: [String: String] = [:]
    var revoked: Set<String> = []
    var requests: [(String, String, String)] = []
    private(set) var createdCodes: [String] = []

    private func checkOnline() throws {
        if offline { throw AccessError.offline }
    }

    func currentUserRecordName() async throws -> String {
        try checkOnline()
        if noICloud { throw AccessError.noICloudAccount }
        return userRecordName
    }
    func isAdministrator() async -> Bool { admin && !offline }
    func invitationStatus(codeHash: String, now: Date) async throws -> AppInvitationStatus {
        try checkOnline()
        return invitations[codeHash] ?? .notFound
    }
    func redeem(codeHash: String, userRecordName: String) async throws -> RedemptionOutcome {
        try checkOnline()
        if let existing = redemptions[codeHash] {
            return existing == userRecordName ? .alreadyMine : .usedBySomeoneElse
        }
        redemptions[codeHash] = userRecordName
        return .redeemed
    }
    func hasRedemption(userRecordName: String) async throws -> Bool {
        try checkOnline()
        return redemptions.values.contains(userRecordName)
    }
    func isRevoked(userRecordName: String) async throws -> Bool {
        try checkOnline()
        return revoked.contains(userRecordName)
    }
    func submitRequest(name: String, contact: String, message: String) async throws {
        try checkOnline()
        requests.append((name, contact, message))
    }
    func createInvitations(count: Int, validityDays: Int, note: String) async throws -> [String] {
        guard admin else { throw AccessError.notAdministrator }
        let codes = (0..<count).map { _ in InvitationCode.generate() }
        for code in codes { invitations[InvitationHashing.codeHash(code)] = .active }
        createdCodes += codes
        return codes
    }
    func adminOverview() async throws -> AdminOverview {
        guard admin else { throw AccessError.notAdministrator }
        return AdminOverview(invitations: [], accounts: [], requests: [])
    }
    func revokeInvitation(codeHash: String) async throws { invitations[codeHash] = .revoked }
    func setUserRevoked(_ isRevoked: Bool, userRecordName: String) async throws {
        if isRevoked { revoked.insert(userRecordName) } else { revoked.remove(userRecordName) }
    }
    func markRequestHandled(id: String) async throws {}

    /// Helper: an active invitation code.
    func makeCode(status: AppInvitationStatus = .active) -> String {
        let code = InvitationCode.generate()
        invitations[InvitationHashing.codeHash(code)] = status
        return code
    }
}

@MainActor
final class AccountServiceTests: XCTestCase {
    private func makeService(_ backend: StubAccessBackend, storage: InMemoryAccountStorage = InMemoryAccountStorage()) -> AccountService {
        AccountService(backend: backend, storage: storage)
    }

    func testWithoutInvitationTheAppIsLocked() async {
        let service = makeService(StubAccessBackend())
        await service.load()
        XCTAssertEqual(service.state, .needsInvitation)
        XCTAssertFalse(service.isActive)
    }

    func testValidInvitationActivates() async {
        let backend = StubAccessBackend()
        let storage = InMemoryAccountStorage()
        let service = makeService(backend, storage: storage)
        await service.load()
        let ok = await service.redeem(code: backend.makeCode())
        XCTAssertTrue(ok)
        XCTAssertTrue(service.isActive)
        XCTAssertEqual(storage.account?.userRecordName, "_user1")
        XCTAssertFalse(service.isAdmin)
    }

    func testTypoIsRejectedBeforeAnyLookup() async {
        let backend = StubAccessBackend()
        let service = makeService(backend)
        await service.load()
        let ok = await service.redeem(code: "MBF7-K92X-4QP8")
        XCTAssertFalse(ok)
        XCTAssertEqual(service.errorMessage, AccessError.invalidCode.localizedDescription)
    }

    func testUnknownExpiredAndRevokedInvitationsStayLocked() async {
        let cases: [(AppInvitationStatus?, AccessError)] = [(nil, .invitationNotFound), (.expired, .expired), (.revoked, .revoked)]
        for (status, expected) in cases {
            let backend = StubAccessBackend()
            let code = status.map { backend.makeCode(status: $0) } ?? InvitationCode.generate()
            let service = makeService(backend)
            await service.load()
            let ok = await service.redeem(code: code)
            XCTAssertFalse(ok)
            XCTAssertEqual(service.state, .needsInvitation)
            XCTAssertEqual(service.errorMessage, expected.localizedDescription)
        }
    }

    func testUsedInvitationCannotBeUsedByAnotherPerson() async {
        let backend = StubAccessBackend()
        let code = backend.makeCode()
        let martin = makeService(backend)
        await martin.load()
        _ = await martin.redeem(code: code)

        backend.userRecordName = "_stranger"
        let stranger = makeService(backend)
        await stranger.load()
        let ok = await stranger.redeem(code: code)
        XCTAssertFalse(ok)
        XCTAssertEqual(stranger.errorMessage, AccessError.used.localizedDescription)
    }

    func testReinstallRestoresAutomatically() async {
        let backend = StubAccessBackend()
        let first = makeService(backend)
        await first.load()
        _ = await first.redeem(code: backend.makeCode())

        // Fresh install: empty storage, same iCloud account.
        let reinstalled = makeService(backend)
        await reinstalled.load()
        XCTAssertTrue(reinstalled.isActive)
    }

    func testAdministratorIsActivatedWithoutCode() async {
        let backend = StubAccessBackend()
        backend.admin = true
        let service = makeService(backend)
        await service.load()
        XCTAssertTrue(service.isActive)
        XCTAssertTrue(service.isAdmin)
    }

    func testNoICloudAccountExplainsWhatToDo() async {
        let backend = StubAccessBackend()
        backend.noICloud = true
        let service = makeService(backend)
        await service.load()
        let ok = await service.redeem(code: backend.makeCode())
        XCTAssertFalse(ok)
        XCTAssertEqual(service.errorMessage, AccessError.noICloudAccount.localizedDescription)
    }

    func testRevokedAccountIsSignedOutOnDailyCheck() async {
        let backend = StubAccessBackend()
        let storage = InMemoryAccountStorage()
        let service = makeService(backend, storage: storage)
        await service.load()
        _ = await service.redeem(code: backend.makeCode())
        backend.revoked.insert("_user1")
        await service.refreshIfDue(force: true)
        XCTAssertEqual(service.state, .needsInvitation)
        XCTAssertNil(storage.account)
        // and cannot come back via restore
        let again = await service.restore()
        XCTAssertFalse(again)
    }

    func testOfflineCheckKeepsUserSignedIn() async {
        let backend = StubAccessBackend()
        let service = makeService(backend)
        await service.load()
        _ = await service.redeem(code: backend.makeCode())
        backend.offline = true
        await service.refreshIfDue(force: true)
        XCTAssertTrue(service.isActive)
    }

    func testDifferentICloudAccountNeedsOwnInvitation() async {
        let backend = StubAccessBackend()
        let service = makeService(backend)
        await service.load()
        _ = await service.redeem(code: backend.makeCode())
        backend.userRecordName = "_someoneElse"
        await service.refreshIfDue(force: true)
        XCTAssertEqual(service.state, .needsInvitation)
    }

    func testAdminCreatesCodesThatWork() async throws {
        let backend = StubAccessBackend()
        backend.admin = true
        let codes = try await backend.createInvitations(count: 2, validityDays: 14, note: "Friends")
        XCTAssertEqual(codes.count, 2)
        XCTAssertTrue(codes.allSatisfy { InvitationCode.isWellFormed($0) })

        backend.admin = false
        backend.userRecordName = "_friend"
        let friend = makeService(backend)
        await friend.load()
        let ok = await friend.redeem(code: codes[0])
        XCTAssertTrue(ok)
    }

    func testCodeHashIsStableAndIgnoresFormatting() {
        XCTAssertEqual(InvitationHashing.codeHash("mbf7 k92x-4qp7"), InvitationHashing.codeHash("MBF7-K92X-4QP7"))
        XCTAssertEqual(InvitationHashing.codeHash("MBF7K92X4QP7").count, 64)
        XCTAssertNotEqual(InvitationHashing.codeHash("MBF7K92X4QP7"), "MBF7K92X4QP7")
    }
}

// MARK: - Phase 3: families, roles

@MainActor
final class FamilySetupTests: XCTestCase {
    func testNewUserHasNoFamilyUntilCreated() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let session = AppSession()
        session.start(context: context)
        XCTAssertTrue(session.needsFamilySetup)

        try session.createFamily(name: "Martin & Carol", ownerName: "Martin", baseCurrency: "EUR", context: context)
        XCTAssertFalse(session.needsFamilySetup)
        XCTAssertEqual(session.family?.name, "Martin & Carol")
        XCTAssertEqual(session.currentMember?.role, .owner)
        XCTAssertTrue(session.can(.manageBudgets))
        XCTAssertTrue(session.can(.inviteMembers))
    }

    func testOwnerPermissionsVsMember() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let family = try FamilyBootstrapper.createFamily(named: "A", ownerName: "Owner", in: context)
        // Simulate this device belonging to a member instead of the owner.
        let repo = FamilyRepository(context: context, familyID: family.id)
        let owner = try XCTUnwrap(repo.currentMember())
        owner.isCurrentUser = false
        context.insert(FamilyMember(familyID: family.id, displayName: "Carol", role: .member, isCurrentUser: true))
        try context.save()

        let session = AppSession()
        session.start(context: context)
        XCTAssertEqual(session.currentMember?.displayName, "Carol")
        XCTAssertFalse(session.can(.manageBudgets))
        XCTAssertFalse(session.can(.inviteMembers))
        XCTAssertFalse(session.can(.manageCategories))
        XCTAssertTrue(session.can(.addExpenses))
    }

    func testFamilyInvitationExpiry() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let family = try FamilyBootstrapper.createFamily(named: "A", ownerName: "Owner", in: context)
        let invitation = FamilyInvitationRecord(familyID: family.id, code: InvitationCode.generate(),
                                                expiresAt: Date().addingTimeInterval(-60), createdByMemberID: nil)
        context.insert(invitation)
        XCTAssertEqual(FamilyInvitationRules.status(of: invitation.terms, now: Date(), activeMembers: 1, maxMembers: 6), .expired)
        XCTAssertTrue(InvitationCode.isWellFormed(invitation.code))
    }
}

// MARK: - Phase 2: receipts

@MainActor
final class ReceiptSavingTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var family: Family!
    private var lookup: CategoryLookup!

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        context = container.mainContext
        family = try FamilyBootstrapper.createFamily(named: "Test", ownerName: "Me", in: context)
        let repo = FamilyRepository(context: context, familyID: family.id)
        lookup = CategoryLookup(categories: try repo.categories(), subcategories: try repo.subcategories())
    }

    private func parsedLidl() -> ParsedReceipt {
        ReceiptParser.parse(lines: [
            "Lidl", "EUR",
            "Hähnchenbrustfilet 8,50 A", "Bananen 2,20 A", "Äpfel 1,99 A", "Milka Schokolade 2,99 A",
            "zu zahlen 15,68", "26.09.2026 18:42"
        ], now: Date(timeIntervalSince1970: 1_791_000_000))
    }

    private func rules() throws -> [MerchantRuleRecord] {
        try FamilyRepository(context: context, familyID: family.id).merchantRules()
    }

    func testDraftSuggestsItemLevelGroceries() throws {
        let draft = ReceiptDrafting.draft(from: parsedLidl(), family: family, lookup: lookup, rules: try rules(), imageData: nil)
        XCTAssertEqual(draft.merchant, "Lidl")
        XCTAssertFalse(draft.categorizeWholeReceipt)
        XCTAssertEqual(draft.items.count, 4)
        let subKeys = draft.items.map { lookup.subcategory($0.subcategoryID)?.systemKey }
        XCTAssertEqual(subKeys, ["groceries.meat", "groceries.fruits", "groceries.fruits", "groceries.snacks"])
        XCTAssertEqual(draft.difference, 0)
    }

    func testItemLevelSaveGroupsBySubcategory() throws {
        let draft = ReceiptDrafting.draft(from: parsedLidl(), family: family, lookup: lookup, rules: try rules(), imageData: nil)
        let expenses = try ReceiptSaver.save(draft, family: family, member: nil, lookup: lookup, context: context)
        XCTAssertEqual(expenses.count, 3, "meat, fruits (2 items), snacks")
        let total = expenses.map(\.amount).reduce(0, +)
        XCTAssertEqual(total, Decimal(string: "15.68"))
        let fruits = try XCTUnwrap(expenses.first { lookup.subcategory($0.subcategoryID)?.systemKey == "groceries.fruits" })
        XCTAssertEqual(fruits.amount, Decimal(string: "4.19"))
        XCTAssertEqual(fruits.entryMethod, .receipt)
        XCTAssertNotNil(fruits.receiptID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReceiptItemRecord>()), 4)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReceiptRecord>()), 1)
    }

    func testWholeReceiptAsGroceries() throws {
        var draft = ReceiptDrafting.draft(from: parsedLidl(), family: family, lookup: lookup, rules: try rules(), imageData: nil)
        draft.categorizeWholeReceipt = true
        let expenses = try ReceiptSaver.save(draft, family: family, member: nil, lookup: lookup, context: context)
        XCTAssertEqual(expenses.count, 1)
        XCTAssertEqual(expenses.first?.amount, Decimal(string: "15.68"))
        XCTAssertEqual(lookup.category(expenses.first?.categoryID)?.systemKey, "groceries")
    }

    func testDifferenceIsAddedSoExpensesMatchTotal() throws {
        var draft = ReceiptDrafting.draft(from: parsedLidl(), family: family, lookup: lookup, rules: try rules(), imageData: nil)
        draft.items[3].included = false   // user excludes the chocolate line
        let expenses = try ReceiptSaver.save(draft, family: family, member: nil, lookup: lookup, context: context)
        XCTAssertEqual(expenses.map(\.amount).reduce(0, +), Decimal(string: "15.68"))
    }

    func testFuelReceiptDefaultsToWholeReceipt() throws {
        let parsed = ReceiptParser.parse(lines: ["ARAL Tankstelle", "Super E10 45,00", "Summe 45,00", "25.09.2026"],
                                         now: Date(timeIntervalSince1970: 1_791_000_000))
        let draft = ReceiptDrafting.draft(from: parsed, family: family, lookup: lookup, rules: try rules(), imageData: nil)
        XCTAssertTrue(draft.categorizeWholeReceipt)
        XCTAssertEqual(lookup.subcategory(draft.wholeSubcategoryID)?.systemKey, "transport.fuel")
    }

    func testForeignReceiptKeepsItsCurrencyAndDate() throws {
        let parsed = ReceiptParser.parse(lines: ["CORNER STORE", "09/20/2026 3:45 PM", "Apples 3.20", "TOTAL 3.20", "USD"],
                                         now: Date(timeIntervalSince1970: 1_791_000_000))
        let draft = ReceiptDrafting.draft(from: parsed, family: family, lookup: lookup, rules: try rules(), imageData: nil)
        let expenses = try ReceiptSaver.save(draft, family: family, member: nil, lookup: lookup, context: context)
        XCTAssertEqual(expenses.first?.currencyCode, "USD")
        XCTAssertEqual(expenses.first?.conversionStatus, .pending, "converted with the rate of the receipt date")
        XCTAssertEqual(expenses.first?.date, draft.date)
    }

    func testSaveWithoutTotalFails() throws {
        var draft = ReceiptDrafting.draft(from: parsedLidl(), family: family, lookup: lookup, rules: try rules(), imageData: nil)
        draft.totalText = ""
        XCTAssertThrowsError(try ReceiptSaver.save(draft, family: family, member: nil, lookup: lookup, context: context))
    }
}
