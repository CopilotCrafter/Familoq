import XCTest
import SwiftData
import FamiloqCore
import FamiloqBudget
@testable import Familoq

@MainActor
final class PlanningServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var family: Family!
    private let calendar = FamiloqCalendar.make()

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        context = container.mainContext
        family = try FamilyBootstrapper.createFamily(named: "Test", ownerName: "Me", in: context)
    }

    override func tearDown() async throws {
        family = nil
        context = nil
        container = nil
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testBookingIsIdempotentAndUsesFixedIDs() throws {
        let rent = ScheduledExpense(familyID: family.id, title: "Rent", amount: 950, currencyCode: "EUR", frequency: .monthly, startDate: day(2026, 7, 1))
        context.insert(rent)
        try context.save()

        let first = PlanningService.bookDue(familyID: family.id, baseCurrency: "EUR", context: context, now: day(2026, 9, 28, 12), calendar: calendar)
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(first.map(\.entryMethod), [.scheduled, .scheduled, .scheduled])
        XCTAssertEqual(rent.bookedThrough, day(2026, 9, 1))

        // Second iPhone of the family books the same dates -> same IDs.
        XCTAssertEqual(first.first?.id, PlanningService.expenseID(scheduleID: rent.id, date: day(2026, 7, 1)))
        rent.bookedThrough = nil
        let again = PlanningService.bookDue(familyID: family.id, baseCurrency: "EUR", context: context, now: day(2026, 9, 28, 12), calendar: calendar)
        XCTAssertTrue(again.isEmpty, "already booked expenses are not duplicated")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Expense>()).count, 3)
    }

    func testCommittedAmountsForSafeToSpend() throws {
        let now = day(2026, 9, 10, 12)
        let monthEnd = day(2026, 10, 1)
        let weekly = ScheduledExpense(familyID: family.id, title: "Cleaner", amount: 40, currencyCode: "EUR", frequency: .weekly, startDate: day(2026, 9, 3))
        weekly.bookedThrough = day(2026, 9, 3)
        let planned = ScheduledExpense(familyID: family.id, title: "Car service", amount: 300, currencyCode: "EUR", frequency: .once, startDate: day(2026, 9, 25))
        let nextMonth = ScheduledExpense(familyID: family.id, title: "Insurance", amount: 500, currencyCode: "EUR", frequency: .once, startDate: day(2026, 10, 5))
        [weekly, planned, nextMonth].forEach { context.insert($0) }

        let goal = SavingsGoal(familyID: family.id, name: "Holiday", target: 1200, deadline: day(2027, 8, 31))
        context.insert(goal)
        let paid = SavingsContribution(familyID: family.id, goalID: goal.id, amount: 20, date: day(2026, 9, 5), memberID: nil)
        context.insert(paid)
        try context.save()

        let result = PlanningService.committedForRestOfMonth(schedules: [weekly, planned, nextMonth], goals: [goal], contributions: [paid],
                                                             baseCurrency: "EUR", now: now, monthEnd: monthEnd, context: context, calendar: calendar)
        // Cleaner 17 + 24 Sep (10 Sep is already due), car service 25 Sep; insurance is in October.
        XCTAssertEqual(result.bills, 380)
        // Holiday: 1,200 over 12 months = 100/month, 20 already saved this month.
        XCTAssertEqual(result.savings, 80)
    }
}

@MainActor
final class BackupAndExportTests: XCTestCase {
    func testBackupRestoresDeletedRecordsAndKeepsOtherFamiliesUntouched() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let family = try FamilyBootstrapper.createFamily(named: "Ours", ownerName: "Me", ownerCloudUserRecordName: "_me", in: context)
        let other = try FamilyBootstrapper.createFamily(named: "Other", ownerName: "Someone", in: context)
        let expense = Expense(familyID: family.id, amount: 12, currencyCode: "EUR", baseCurrencyCode: "EUR", merchant: "Bakery", date: Date())
        expense.receiptImageData = Data([9, 9, 9])
        context.insert(expense)
        context.insert(SavingsGoal(familyID: family.id, name: "Holiday", target: 1000, deadline: nil))
        try context.save()

        let backup = try BackupService.makeBackup(family: family, context: context, includePhotos: true)
        XCTAssertEqual(backup.counts["expense"], 1)
        XCTAssertEqual(backup.counts["goal"], 1)
        let decoded = try FamilyBackup.decode(try backup.encoded())

        let expenseID = expense.id
        context.delete(expense)
        try context.save()
        let otherBefore = try SyncRegistry.currentFingerprints(familyID: other.id, context: context)

        let summary = try BackupService.restore(decoded, into: family, context: context, currentUserRecordName: "_me")
        XCTAssertEqual(summary.added, 1)
        XCTAssertGreaterThan(summary.updated, 10)
        let restored = try XCTUnwrap(try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.id == expenseID })).first)
        XCTAssertEqual(restored.merchant, "Bakery")
        XCTAssertEqual(restored.receiptImageData, Data([9, 9, 9]))
        XCTAssertEqual(try SyncRegistry.currentFingerprints(familyID: other.id, context: context), otherBefore)
        XCTAssertEqual(try FamilyRepository(context: context, familyID: family.id).currentMember()?.displayName, "Me")
    }

    func testRestoringIntoAnotherFamilyDoesNotStealRecords() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let a = try FamilyBootstrapper.createFamily(named: "A", ownerName: "Me", in: context)
        let b = try FamilyBootstrapper.createFamily(named: "B", ownerName: "Me", in: context)
        let backupOfA = try BackupService.makeBackup(family: a, context: context, includePhotos: false)
        let aBefore = try SyncRegistry.currentFingerprints(familyID: a.id, context: context)
        let summary = try BackupService.restore(backupOfA, into: b, context: context, currentUserRecordName: "")
        XCTAssertEqual(summary.added, 0)
        XCTAssertGreaterThan(summary.skipped, 10, "A's records exist on this iPhone in family A - never moved or changed")
        XCTAssertEqual(try SyncRegistry.currentFingerprints(familyID: a.id, context: context), aBefore)
    }

    func testCSVHasHeaderAndRows() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let family = try FamilyBootstrapper.createFamily(named: "Test", ownerName: "Me", in: context)
        let expense = Expense(familyID: family.id, amount: Decimal(string: "329")!, currencyCode: "CZK", baseCurrencyCode: "EUR", merchant: "Asia Center; Česká Kubice", date: Date())
        expense.baseAmount = Decimal(string: "13.52")
        context.insert(expense)
        let data = CSVExport.expenses([expense], lookup: CategoryLookup(categories: [], subcategories: []), members: [],
                                      baseCurrency: "EUR", locale: Locale(identifier: "de_DE"))
        let text = String(decoding: data.dropFirst(3), as: UTF8.self)
        let lines = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasPrefix("Date;Time;Merchant"))
        XCTAssertTrue(lines[1].contains("\"Asia Center; Česká Kubice\""))
        XCTAssertTrue(lines[1].contains(";329,00;CZK;13,52;"))
    }

    func testFilterOnRealExpenses() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let family = try FamilyBootstrapper.createFamily(named: "Test", ownerName: "Me", in: context)
        let expense = Expense(familyID: family.id, amount: 5, currencyCode: "EUR", baseCurrencyCode: "EUR", merchant: "REWE", date: Date())
        expense.baseAmount = 5
        expense.entryMethod = .receipt
        var filter = ExpenseFilter()
        filter.text = "rewe"
        filter.entryMethods = [EntryMethod.receipt.rawValue]
        let lookup = CategoryLookup(categories: [], subcategories: [])
        XCTAssertTrue(filter.matches(expense.facts(lookup: lookup), baseCurrency: "EUR"))
        filter.entryMethods = [EntryMethod.scheduled.rawValue]
        XCTAssertFalse(filter.matches(expense.facts(lookup: lookup), baseCurrency: "EUR"))
    }
}
