import Foundation
import SwiftData
import UserNotifications
import BackgroundTasks
import FamiloqCore
import FamiloqPlanner

/// Local notifications for reminders, events and bills. Each iPhone works out
/// its own alerts from the synced data - no push service, no server, no
/// extra Apple certificate.
@MainActor
enum PlannerNotifications {
    static let prefix = "fq."

    enum Setting: String, CaseIterable {
        case reminders = "notify.reminders"
        case events = "notify.events"
        case bills = "notify.bills"

        var title: String {
            switch self {
            case .reminders: return "Reminders for me"
            case .events: return "Calendar alerts"
            case .bills: return "Bills due tomorrow"
            }
        }

        var isOn: Bool {
            get { UserDefaults.standard.object(forKey: rawValue) as? Bool ?? true }
            nonmutating set { UserDefaults.standard.set(newValue, forKey: rawValue) }
        }
    }

    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks once ("Allow notifications?"); later calls return the answer.
    @discardableResult
    static func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await status() {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    /// Replaces all Familoq notifications with the current plan.
    static func reschedule(context: ModelContext, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        switch await status() {
        case .authorized, .provisional, .ephemeral: break
        default: return
        }
        let requests = plannedRequests(context: context, now: now)
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for request in requests {
            try? await center.add(request)
        }
    }

    static func plannedRequests(context: ModelContext, now: Date = Date()) -> [UNNotificationRequest] {
        let calendar = FamiloqCalendar.make()
        let mine = (try? context.fetch(FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.isCurrentUser == true && $0.isActive == true }))) ?? []
        let me = Set(mine.map(\.id))
        let families = Set(mine.map(\.familyID))
        guard !families.isEmpty else { return [] }

        let reminders = Setting.reminders.isOn
            ? ((try? context.fetch(FetchDescriptor<FamilyReminder>(predicate: #Predicate { $0.isDone == false && $0.alertEnabled == true }))) ?? [])
                .filter { families.contains($0.familyID) && $0.dueDate != nil }
            : []
        let events = Setting.events.isOn
            ? ((try? context.fetch(FetchDescriptor<FamilyEvent>(predicate: #Predicate { $0.alertMinutes >= 0 }))) ?? [])
                .filter { families.contains($0.familyID) }
            : []
        let schedules = Setting.bills.isOn
            ? ((try? context.fetch(FetchDescriptor<ScheduledExpense>(predicate: #Predicate { $0.isActive == true }))) ?? [])
                .filter { families.contains($0.familyID) }
            : []
        let horizon = calendar.date(byAdding: .day, value: 36, to: now) ?? now
        let upcomingBills = PlanningService.upcoming(schedules, now: now, until: horizon, calendar: calendar)

        let plan = NotificationPlanner.plan(
            reminders: reminders.compactMap { r in
                r.dueDate.map { NotificationPlanner.Reminder(id: r.id, due: $0, hasTime: r.hasTime, assignees: r.assignees) }
            },
            events: events.map { NotificationPlanner.Event(spec: $0.spec, alertMinutes: $0.alertMinutes, participants: $0.participants) },
            bills: upcomingBills.map { NotificationPlanner.Bill(id: $0.id, date: $0.date) },
            me: me, now: now, calendar: calendar)

        let remindersByID = Dictionary(reminders.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        let eventsByID = Dictionary(events.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        let billsByID = Dictionary(upcomingBills.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        return plan.compactMap { alert in
            let content = UNMutableNotificationContent()
            content.sound = .default
            switch alert.kind {
            case .reminder:
                guard let reminder = remindersByID[alert.sourceID] else { return nil }
                content.title = reminder.title
                content.body = reminder.notes.isEmpty ? String(localized: "Family reminder") : reminder.notes
            case .event:
                guard let event = eventsByID[alert.sourceID] else { return nil }
                content.title = event.title
                var when = event.isAllDay
                    ? alert.date.formatted(.dateTime.weekday(.wide).day().month())
                    : alert.date.formatted(.dateTime.weekday(.wide).day().month().hour().minute())
                if !event.location.isEmpty { when += " · \(event.location)" }
                content.body = when
            case .bill:
                guard let bill = billsByID[alert.sourceID] else { return nil }
                content.title = String(localized: "Due tomorrow: \(bill.schedule.title)")
                content.body = bill.schedule.amount.formatted(.currency(code: bill.schedule.currencyCode))
            }
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: alert.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            return UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger)
        }
    }
}

/// iOS wakes Familoq now and then (it decides when) to fetch family changes
/// and update the alerts - so a reminder Carol adds also rings on Martin's
/// iPhone without opening the app. Info.plist only, no extra capability.
enum BackgroundRefresh {
    static var identifier: String { (Bundle.main.bundleIdentifier ?? "com.carolandmartin.familoq") + ".refresh" }

    /// Set by the running app (sync + notifications).
    @MainActor static var work: (@MainActor () async -> Void)?

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handle(task)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGTask) {
        schedule()
        let job = Task { @MainActor in
            if let work { await work() }
        }
        task.expirationHandler = { job.cancel() }
        Task {
            await job.value
            task.setTaskCompleted(success: !job.isCancelled)
        }
    }
}
