import XCTest
import SwiftData
import FamiloqCore
import FamiloqBudget
@testable import Familoq

// MARK: - Phase 3: App Invitation / account

final class StubInvitationService: InvitationServicing {
    var redeemResult: Result<InvitationServiceClient.Session, Error> = .success(.init(status: "active", token: "t1", expiresAt: 2_000_000_000))
    var restoreResult: Result<InvitationServiceClient.Session, Error> = .success(.init(status: "active", token: "t2", expiresAt: 2_000_000_000))
    var refreshResult: Result<InvitationServiceClient.Session, Error> = .success(.init(status: "active", token: "t3", expiresAt: 2_000_000_000))
    private(set) var redeemCalls = 0
    private(set) var refreshCalls = 0

    func redeem(code: String, identityToken: String, nonce: String) async throws -> InvitationServiceClient.Session {
        redeemCalls += 1
        return try redeemResult.get()
    }
    func restore(identityToken: String, nonce: String) async throws -> InvitationServiceClient.Session { try restoreResult.get() }
    func refresh(token: String) async throws -> InvitationServiceClient.Session {
        refreshCalls += 1
        return try refreshResult.get()
    }
    func requestInvitation(name: String, contact: String, message: String) async throws {}
}

@MainActor
final class AccountServiceTests: XCTestCase {
    private let credential = AppleCredential(userID: "apple-1", identityToken: "token", rawNonce: "nonce", displayName: "Martin")
    private let validCode = "MBF7-K92X-4QP7"

    func testWithoutInvitationTheAppIsLocked() {
        let service = AccountService(service: StubInvitationService(), storage: InMemoryAccountStorage())
        service.load()
        XCTAssertEqual(service.state, .needsInvitation)
        XCTAssertFalse(service.isActive)
    }

    func testValidInvitationActivates() async {
        let storage = InMemoryAccountStorage()
        let service = AccountService(service: StubInvitationService(), storage: storage)
        service.load()
        let ok = await service.redeem(code: validCode, credential: credential)
        XCTAssertTrue(ok)
        XCTAssertTrue(service.isActive)
        XCTAssertEqual(storage.account?.sessionToken, "t1")
        XCTAssertEqual(storage.account?.displayName, "Martin")
    }

    func testTypoIsRejectedWithoutNetworkCall() async {
        let stub = StubInvitationService()
        let service = AccountService(service: stub, storage: InMemoryAccountStorage())
        service.load()
        let ok = await service.redeem(code: "MBF7-K92X-4QP8", credential: credential)
        XCTAssertFalse(ok)
        XCTAssertEqual(stub.redeemCalls, 0)
        XCTAssertNotNil(service.errorMessage)
    }

    func testExpiredUsedRevokedInvitationsStayLocked() async {
        for error in [InvitationServiceClient.ServiceError.expired, .used, .revoked] {
            let stub = StubInvitationService()
            stub.redeemResult = .failure(error)
            let service = AccountService(service: stub, storage: InMemoryAccountStorage())
            service.load()
            let ok = await service.redeem(code: validCode, credential: credential)
            XCTAssertFalse(ok)
            XCTAssertEqual(service.state, .needsInvitation)
            XCTAssertEqual(service.errorMessage, error.message)
        }
    }

    func testReinstallRestoresWithAppleID() async {
        let service = AccountService(service: StubInvitationService(), storage: InMemoryAccountStorage())
        service.load()
        let ok = await service.restore(credential: credential)
        XCTAssertTrue(ok)
        XCTAssertTrue(service.isActive)
    }

    func testRevokedAccountIsSignedOutOnRefresh() async {
        let stub = StubInvitationService()
        let storage = InMemoryAccountStorage()
        let service = AccountService(service: stub, storage: storage)
        service.load()
        _ = await service.redeem(code: validCode, credential: credential)
        stub.refreshResult = .failure(InvitationServiceClient.ServiceError.accountRevoked)
        await service.refreshIfDue(force: true)
        XCTAssertEqual(service.state, .needsInvitation)
        XCTAssertNil(storage.account)
    }

    func testOfflineRefreshKeepsUserSignedIn() async {
        let stub = StubInvitationService()
        let service = AccountService(service: stub, storage: InMemoryAccountStorage())
        service.load()
        _ = await service.redeem(code: validCode, credential: credential)
        stub.refreshResult = .failure(InvitationServiceClient.ServiceError.offline)
        await service.refreshIfDue(force: true)
        XCTAssertTrue(service.isActive)
    }

    func testRefreshHappensAtMostDaily() async {
        let stub = StubInvitationService()
        let service = AccountService(service: stub, storage: InMemoryAccountStorage())
        service.load()
        _ = await service.redeem(code: validCode, credential: credential)
        await service.refreshIfDue()
        XCTAssertEqual(stub.refreshCalls, 0, "just activated - no refresh needed")
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
