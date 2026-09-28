import XCTest
import SwiftData
import FamiloqCore
import FamiloqPlanner
@testable import Familoq

@MainActor
final class PlannerAppTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var family: Family!
    private var me: FamilyMember!

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        context = container.mainContext
        family = try FamilyBootstrapper.createFamily(named: "Test", ownerName: "Martin", in: context)
        me = try XCTUnwrap(context.fetch(FetchDescriptor<FamilyMember>()).first)
    }

    override func tearDown() async throws {
        me = nil
        family = nil
        context = nil
        container = nil
    }

    func testDefaultListHasTheSameIDOnEveryIPhone() {
        let lists = ShoppingService.lists(familyID: family.id, context: context)
        XCTAssertEqual(lists.count, 1)
        XCTAssertEqual(lists.first?.id, ShoppingService.defaultListID(familyID: family.id))
        XCTAssertEqual(ShoppingService.lists(familyID: family.id, context: context).count, 1)
    }

    func testAddingMergesSameItemAndSortsIntoAisle() throws {
        let list = try XCTUnwrap(ShoppingService.lists(familyID: family.id, context: context).first)
        let milk = try XCTUnwrap(ShoppingService.add("Milch", listID: list.id, familyID: family.id, memberID: me.id, context: context))
        XCTAssertEqual(milk.aisleKey, "groceries.dairy")
        ShoppingService.add("2x milch", listID: list.id, familyID: family.id, memberID: me.id, context: context)
        let all = try context.fetch(FetchDescriptor<ShoppingItem>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.quantity, "2")
    }

    func testReceiptTicksOffAndClearKeepsHistory() throws {
        let list = try XCTUnwrap(ShoppingService.lists(familyID: family.id, context: context).first)
        for text in ["Milch", "Bananen", "Seife"] {
            ShoppingService.add(text, listID: list.id, familyID: family.id, memberID: me.id, context: context)
        }
        let ticked = ShoppingService.tickOff(receiptLines: ["H-VOLLMILCH 1L", "BANANEN 1,2KG"], familyID: family.id, memberID: me.id, context: context)
        XCTAssertEqual(Set(ticked), ["Milch", "Bananen"])
        ShoppingService.clearBought(listID: list.id, context: context)
        let items = try context.fetch(FetchDescriptor<ShoppingItem>())
        XCTAssertEqual(items.filter { !$0.isCleared }.map(\.name), ["Seife"])
        XCTAssertEqual(items.count, 3, "bought items stay for 'Buy again'")
    }

    func testRecordsSyncRoundTrip() throws {
        let event = FamilyEvent(familyID: family.id, title: "Swimming", start: Date(timeIntervalSince1970: 1_800_000_000),
                                end: Date(timeIntervalSince1970: 1_800_003_600), isAllDay: false)
        event.frequency = .weekly
        event.participants = [me.id]
        event.alertMinutes = 30
        let copy = FamilyEvent(id: event.id, familyID: family.id, title: "", start: Date(), end: Date(), isAllDay: true)
        copy.applySyncPayload(SyncPayload(values: event.syncPayload().values))
        XCTAssertEqual(copy.syncPayload(), event.syncPayload())
        XCTAssertEqual(copy.participants, [me.id])

        let reminder = FamilyReminder(familyID: family.id, title: "Recycling")
        reminder.dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        reminder.frequency = .weekly
        reminder.assignees = [me.id, UUID()]
        let reminderCopy = FamilyReminder(id: reminder.id, familyID: family.id, title: "")
        reminderCopy.applySyncPayload(SyncPayload(values: reminder.syncPayload().values))
        XCTAssertEqual(reminderCopy.syncPayload(), reminder.syncPayload())

        XCTAssertNotNil(SyncRegistry.handler(for: .shoppingItem))
        XCTAssertNotNil(SyncRegistry.handler(for: .event))
    }

    func testCompletingRepeatingReminderMovesItForward() {
        let calendar = FamiloqCalendar.make()
        let today = calendar.startOfDay(for: Date())
        let reminder = FamilyReminder(familyID: family.id, title: "Recycling")
        reminder.dueDate = today
        reminder.frequency = .weekly
        context.insert(reminder)
        ReminderService.complete(reminder, memberID: me.id, context: context)
        XCTAssertFalse(reminder.isDone)
        XCTAssertEqual(reminder.dueDate, calendar.date(byAdding: .day, value: 7, to: today))
        XCTAssertEqual(reminder.completedByMemberID, me.id)

        let once = FamilyReminder(familyID: family.id, title: "Call school")
        once.dueDate = today
        context.insert(once)
        ReminderService.complete(once, memberID: me.id, context: context)
        XCTAssertTrue(once.isDone)
    }

    func testNotificationRequestsForMe() throws {
        let calendar = FamiloqCalendar.make()
        let now = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let mine = FamilyReminder(familyID: family.id, title: "Mine")
        mine.dueDate = tomorrow
        mine.assignees = [me.id]
        let someoneElse = FamilyReminder(familyID: family.id, title: "Carol's")
        someoneElse.dueDate = tomorrow
        someoneElse.assignees = [UUID()]
        context.insert(mine)
        context.insert(someoneElse)
        try context.save()
        let requests = PlannerNotifications.plannedRequests(context: context, now: now)
        XCTAssertEqual(requests.map(\.content.title), ["Mine"])
        XCTAssertEqual(requests.first?.identifier, "fq.r.\(mine.id.uuidString)")
    }
}
