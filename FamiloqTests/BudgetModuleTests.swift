import XCTest
import SwiftData
import FamiloqCore
import FamiloqBudget
@testable import Familoq

/// App-level tests that run on the iOS Simulator in GitHub Actions.
/// Pure business logic is tested in Packages/FamiloqCore (also on Linux).
@MainActor
final class PersistenceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        context = container.mainContext
    }

    override func tearDown() async throws {
        context = nil
        container = nil
    }

    func testBootstrapSeedsDefaultCategoriesAndRules() throws {
        let family = try FamilyBootstrapper.ensureFamily(in: context)
        let repo = FamilyRepository(context: context, familyID: family.id)

        XCTAssertEqual(family.baseCurrencyCode, "EUR", "Base currency must default to EUR")
        XCTAssertEqual(family.maxMembers, 6)
        XCTAssertEqual(try repo.categories().count, DefaultCategories.all.count)
        let groceries = try XCTUnwrap(try repo.categories().first { $0.systemKey == "groceries" })
        XCTAssertEqual(try repo.subcategories().filter { $0.categoryID == groceries.id }.count, 18)
        XCTAssertEqual(try repo.merchantRules().count, DefaultMerchantRules.all.count)
        XCTAssertEqual(try repo.currentMember()?.role, .owner)
    }

    func testBootstrapIsIdempotent() throws {
        let first = try FamilyBootstrapper.ensureFamily(in: context)
        let second = try FamilyBootstrapper.ensureFamily(in: context)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Family>()), 1)
    }

    /// Spec section 4 + security test 8: Family A must never see Family B data.
    func testRepositoryIsolatesFamilies() throws {
        let familyA = try FamilyBootstrapper.createFamily(named: "Martin & Carol", ownerName: "Martin", in: context)
        let familyB = try FamilyBootstrapper.createFamily(named: "John & Sarah", ownerName: "John", in: context)

        let repoA = FamilyRepository(context: context, familyID: familyA.id)
        let repoB = FamilyRepository(context: context, familyID: familyB.id)

        try repoA.insert(Expense(familyID: familyA.id, amount: 43.28, currencyCode: "EUR", baseCurrencyCode: "EUR", merchant: "Lidl", date: Date()))
        try repoB.insert(Expense(familyID: familyB.id, amount: 34.72, currencyCode: "EUR", baseCurrencyCode: "EUR", merchant: "REWE", date: Date()))
        try context.save()

        XCTAssertEqual(try repoA.allExpenses().map(\.merchant), ["Lidl"])
        XCTAssertEqual(try repoB.allExpenses().map(\.merchant), ["REWE"])
        XCTAssertTrue(try repoA.categories().allSatisfy { $0.familyID == familyA.id })
        XCTAssertTrue(try repoB.merchantRules().allSatisfy { $0.familyID == familyB.id })
    }

    func testRepositoryRefusesForeignFamilyInsert() throws {
        let familyA = try FamilyBootstrapper.createFamily(named: "A", ownerName: "A", in: context)
        let familyB = try FamilyBootstrapper.createFamily(named: "B", ownerName: "B", in: context)
        let repoA = FamilyRepository(context: context, familyID: familyA.id)
        let intruder = Expense(familyID: familyB.id, amount: 1, currencyCode: "EUR", baseCurrencyCode: "EUR", merchant: "x", date: Date())
        XCTAssertThrowsError(try repoA.insert(intruder))
    }

    func testMoneyIsStoredExactly() throws {
        let family = try FamilyBootstrapper.ensureFamily(in: context)
        let expense = Expense(familyID: family.id, amount: Decimal(string: "0.10")!, currencyCode: "EUR", baseCurrencyCode: "EUR", merchant: "", date: Date())
        context.insert(expense)
        try context.save()
        XCTAssertEqual(expense.amount, Decimal(string: "0.10"))
        XCTAssertEqual(expense.amountValue, 1_000)
    }
}

/// Stub provider so currency tests never touch the network.
final class StubRateProvider: ExchangeRateProviding {
    var rate: Decimal = Decimal(string: "0.85")!
    var publishedDateKey: String? = nil
    var error: Error?
    private(set) var calls = 0

    func fetchRate(from: String, to: String, dateKey: String?) async throws -> ExchangeRate {
        calls += 1
        if let error { throw error }
        return ExchangeRate(base: from, quote: to, rate: rate, rateDateKey: publishedDateKey ?? dateKey ?? "2026-09-25", source: "stub")
    }
}

@MainActor
final class CurrencyConversionFlowTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var family: Family!
    private let calendar = FamiloqCalendar.make(timeZone: TimeZone(identifier: "Europe/Berlin")!)

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        context = ModelContext(container)
        family = try FamilyBootstrapper.ensureFamily(in: context)
    }

    private func date(_ key: String) -> Date {
        DateKey.date(from: key, calendar: calendar)!
    }

    private func service(_ provider: StubRateProvider, today: String = "2026-09-27") -> ExchangeRateService {
        let now = date(today)
        return ExchangeRateService(provider: provider, calendar: calendar, now: { now })
    }

    func testEuroExpenseNeedsNoConversion() async {
        let provider = StubRateProvider()
        let expense = Expense(familyID: family.id, amount: 20, currencyCode: "EUR", baseCurrencyCode: "EUR", merchant: "Restaurant", date: date("2026-09-20"))
        context.insert(expense)
        await service(provider).convert(expense, baseCurrency: "EUR", context: context)
        XCTAssertEqual(expense.conversionStatus, .notNeeded)
        XCTAssertEqual(expense.baseAmount, 20)
        XCTAssertEqual(provider.calls, 0)
    }

    func testUSDExpenseUsesRateOfExpenseDate() async {
        let provider = StubRateProvider()
        let expense = Expense(familyID: family.id, amount: 25, currencyCode: "USD", baseCurrencyCode: "EUR", merchant: "Store", date: date("2026-09-21"))
        context.insert(expense)
        await service(provider).convert(expense, baseCurrency: "EUR", context: context)
        XCTAssertEqual(expense.conversionStatus, .converted)
        XCTAssertEqual(expense.baseAmount, Decimal(string: "21.25"))
        XCTAssertEqual(expense.exchangeRateDateKey, "2026-09-21")
        XCTAssertEqual(expense.amount, 25, "original amount is kept")
    }

    func testRateIsCachedPerDay() async {
        let provider = StubRateProvider()
        let svc = service(provider)
        for _ in 0..<3 {
            let e = Expense(familyID: family.id, amount: 10, currencyCode: "USD", baseCurrencyCode: "EUR", merchant: "", date: date("2026-09-21"))
            context.insert(e)
            await svc.convert(e, baseCurrency: "EUR", context: context)
        }
        XCTAssertEqual(provider.calls, 1)
    }

    func testOfflineWithoutCacheIsPendingAndExcludedFromTotals() async {
        let provider = StubRateProvider()
        provider.error = ExchangeRateError.unavailable
        let expense = Expense(familyID: family.id, amount: 25, currencyCode: "USD", baseCurrencyCode: "EUR", merchant: "", date: date("2026-09-21"))
        context.insert(expense)
        await service(provider).convert(expense, baseCurrency: "EUR", context: context)
        XCTAssertEqual(expense.conversionStatus, .pending)
        XCTAssertNil(expense.baseAmount)
        XCTAssertEqual(SpendingSummary(expenses: [expense]).unconvertedCount, 1)
    }

    func testOfflineUsesNewestCachedRateAsEstimateThenRefreshes() async {
        let provider = StubRateProvider()
        let svc = service(provider)
        let first = Expense(familyID: family.id, amount: 10, currencyCode: "USD", baseCurrencyCode: "EUR", merchant: "", date: date("2026-09-21"))
        context.insert(first)
        await svc.convert(first, baseCurrency: "EUR", context: context)

        provider.error = ExchangeRateError.unavailable
        let offline = Expense(familyID: family.id, amount: 100, currencyCode: "USD", baseCurrencyCode: "EUR", merchant: "", date: date("2026-09-22"))
        context.insert(offline)
        await svc.convert(offline, baseCurrency: "EUR", context: context)
        XCTAssertEqual(offline.conversionStatus, .estimated)
        XCTAssertEqual(offline.baseAmount, 85)

        provider.error = nil
        provider.rate = Decimal(string: "0.9")!
        await svc.refreshPending(familyID: family.id, baseCurrency: "EUR", context: context)
        XCTAssertEqual(offline.conversionStatus, .converted)
        XCTAssertEqual(offline.baseAmount, 90)
    }

    func testUnsupportedCurrencyNeedsManualRate() async {
        let provider = StubRateProvider()
        provider.error = ExchangeRateError.unsupportedCurrency
        let expense = Expense(familyID: family.id, amount: 50, currencyCode: "AED", baseCurrencyCode: "EUR", merchant: "", date: date("2026-09-21"))
        context.insert(expense)
        await service(provider).convert(expense, baseCurrency: "EUR", context: context)
        XCTAssertEqual(expense.conversionStatus, .unsupported)
        XCTAssertNil(expense.baseAmount)
    }

    func testManualRateIsNeverOverwritten() async {
        let provider = StubRateProvider()
        let expense = Expense(familyID: family.id, amount: 100, currencyCode: "USD", baseCurrencyCode: "EUR", merchant: "", date: date("2026-09-21"))
        expense.exchangeRateText = "0.8"
        expense.conversionStatus = .manual
        context.insert(expense)
        await service(provider).convert(expense, baseCurrency: "EUR", context: context)
        XCTAssertEqual(expense.conversionStatus, .manual)
        XCTAssertEqual(expense.baseAmount, 80)
        XCTAssertEqual(provider.calls, 0)
    }

    func testTodayBeforeECBPublicationIsEstimated() async {
        let provider = StubRateProvider()
        provider.publishedDateKey = "2026-09-24"
        let expense = Expense(familyID: family.id, amount: 10, currencyCode: "USD", baseCurrencyCode: "EUR", merchant: "", date: date("2026-09-25"))
        context.insert(expense)
        await service(provider, today: "2026-09-25").convert(expense, baseCurrency: "EUR", context: context)
        XCTAssertEqual(expense.conversionStatus, .estimated)
    }

    func testChangingBaseCurrencyReconvertsExpensesAndBudgets() async throws {
        let provider = StubRateProvider()
        provider.rate = 2   // 1 EUR = 2 USD for the test
        let svc = service(provider)
        let budget = Budget(familyID: family.id, period: .monthly, scope: .overall, amount: 3000, currencyCode: "EUR")
        context.insert(budget)
        let euro = Expense(familyID: family.id, amount: 10, currencyCode: "EUR", baseCurrencyCode: "EUR", merchant: "", date: date("2026-09-21"))
        euro.resetConversion()
        context.insert(euro)
        let dollars = Expense(familyID: family.id, amount: 7, currencyCode: "USD", baseCurrencyCode: "EUR", merchant: "", date: date("2026-09-21"))
        context.insert(dollars)
        try context.save()

        try await BaseCurrencyService.change(to: "USD", family: family, context: context, rates: svc)

        XCTAssertEqual(family.baseCurrencyCode, "USD")
        XCTAssertEqual(budget.amount, 6000)
        XCTAssertEqual(budget.currencyCode, "USD")
        XCTAssertEqual(euro.baseCurrencyCode, "USD")
        XCTAssertEqual(euro.baseAmount, 20)
        XCTAssertEqual(dollars.conversionStatus, .notNeeded)
        XCTAssertEqual(dollars.baseAmount, 7)
    }

    func testBaseCurrencyChangeOfflineChangesNothing() async throws {
        let provider = StubRateProvider()
        provider.error = ExchangeRateError.unavailable
        context.insert(Budget(familyID: family.id, period: .monthly, scope: .overall, amount: 3000, currencyCode: "EUR"))
        try context.save()
        do {
            try await BaseCurrencyService.change(to: "USD", family: family, context: context, rates: service(provider))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(family.baseCurrencyCode, "EUR")
        }
    }
}

@MainActor
final class CategorizationFlowTests: XCTestCase {
    func testMerchantSuggestionAndUserRule() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let family = try FamilyBootstrapper.ensureFamily(in: context)
        let repo = FamilyRepository(context: context, familyID: family.id)
        let categories = try repo.categories()
        let subs = try repo.subcategories()
        let groceries = try XCTUnwrap(categories.first { $0.systemKey == "groceries" })
        let fuel = try XCTUnwrap(subs.first { $0.systemKey == "transport.fuel" })

        var rules = try repo.merchantRules()
        XCTAssertEqual(CategorizationService.suggestion(for: "LIDL", rules: rules)?.categoryID, groceries.id)
        XCTAssertEqual(CategorizationService.suggestion(for: "Aral Station", rules: rules)?.subcategoryID, fuel.id)

        // User decides Amazon purchases are groceries -> rule is saved and wins.
        let choice = CategorySuggestion(categoryID: groceries.id, subcategoryID: nil)
        XCTAssertTrue(CategorizationService.shouldOfferRule(merchant: "Amazon", suggested: CategorizationService.suggestion(for: "Amazon", rules: rules), chosen: choice, rules: rules))
        CategorizationService.saveRule(merchant: "Amazon", choice: choice, familyID: family.id, rules: rules, context: context)
        try context.save()
        rules = try repo.merchantRules()
        XCTAssertEqual(CategorizationService.suggestion(for: "Amazon Marketplace", rules: rules), choice)
        XCTAssertFalse(CategorizationService.shouldOfferRule(merchant: "Amazon", suggested: CategorizationService.suggestion(for: "Amazon", rules: rules), chosen: choice, rules: rules))
    }
}
