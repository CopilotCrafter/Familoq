import SwiftUI
import SwiftData
import UserNotifications
import FamiloqCore
import FamiloqPlanner

enum PlannerSegment: String, CaseIterable, Identifiable {
    case shopping, meals, reminders, calendar, timeOff, travel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shopping: return "Shopping"
        case .reminders: return "Reminders"
        case .calendar: return "Calendar"
        case .timeOff: return "Time off"
        case .meals: return "Meals"
        case .travel: return "Travel"
        }
    }

    var icon: String {
        switch self {
        case .shopping: return "cart"
        case .meals: return "fork.knife"
        case .reminders: return "checklist"
        case .calendar: return "calendar"
        case .timeOff: return "sun.max"
        case .travel: return "airplane"
        }
    }

    static let storageKey = "planner.segment"
}

/// Planner tab: shopping list, reminders and calendar of the family.
///
/// iOS 27 note: every screen below owns its own queries and edits happen in
/// sheets that keep their own state (no pushed screens with queries) - the
/// pattern that fixed the receipt and category crashes.
struct PlannerView: View {
    @EnvironmentObject private var session: AppSession
    @AppStorage(PlannerSegment.storageKey) private var segmentRaw = PlannerSegment.shopping.rawValue

    private var segment: PlannerSegment { PlannerSegment(rawValue: segmentRaw) ?? .shopping }

    var body: some View {
        NavigationStack {
            if let family = session.family {
                Group {
                    switch segment {
                    case .shopping: ShoppingListScreen(family: family)
                    case .reminders: RemindersScreen(family: family)
                    case .calendar: CalendarScreen(family: family)
                    case .timeOff: TimeOffScreen(family: family)
                    case .meals: MealsScreen(family: family)
                    case .travel: TravelScreen(family: family)
                    }
                }
                .id(segment)
                .safeAreaInset(edge: .top, spacing: 0) {
                    // Six parts: scrollable chips instead of a cramped segmented control.
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(PlannerSegment.allCases) { s in
                                    Button {
                                        withAnimation { segmentRaw = s.rawValue }
                                    } label: {
                                        Label(LocalizedStringKey(s.title), systemImage: s.icon)
                                            .font(.subheadline.weight(s == segment ? .semibold : .regular))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(s == segment ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                                            .foregroundStyle(s == segment ? Color.white : Color.primary)
                                    }
                                    .buttonStyle(.plain)
                                    .id(s)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        .onAppear { proxy.scrollTo(segment, anchor: .center) }
                    }
                    .background(.bar)
                }
                .navigationTitle(LocalizedStringKey(segment.title))
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ProgressView()
            }
        }
    }
}

// MARK: - Shared pieces

/// Names of the family's people for rows ("Carol", "Martin & Carol").
struct MemberNames {
    let byID: [UUID: String]

    init(_ members: [FamilyMember]) {
        byID = Dictionary(members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
    }

    func name(_ id: UUID?) -> String? {
        id.flatMap { byID[$0] }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Empty set = the whole family.
    func list(_ ids: Set<UUID>) -> String {
        if ids.isEmpty { return String(localized: "Everyone") }
        return ids.compactMap { byID[$0] }.sorted().joined(separator: ", ")
    }
}

/// Choose people; nobody chosen = the whole family.
struct MemberChooser: View {
    let members: [FamilyMember]
    @Binding var selection: Set<UUID>
    let everyoneLabel: String

    var body: some View {
        Button {
            selection = []
        } label: {
            HStack {
                Text(LocalizedStringKey(everyoneLabel)).foregroundStyle(.primary)
                Spacer()
                if selection.isEmpty { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
        }
        ForEach(members.filter(\.isActive)) { member in
            Button {
                if selection.contains(member.id) { selection.remove(member.id) } else { selection.insert(member.id) }
            } label: {
                HStack {
                    Text(verbatim: member.displayName).foregroundStyle(.primary)
                    if member.isCurrentUser { Text("(you)").foregroundStyle(.secondary) }
                    Spacer()
                    if selection.contains(member.id) { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                }
            }
        }
    }
}

enum PlannerDates {
    static var calendar: Calendar {
        var c = FamiloqCalendar.make()
        c.locale = Locale.current
        return c
    }

    /// "Today, 15:00", "Tomorrow", "Fri 3 Oct".
    static func dueText(_ date: Date, hasTime: Bool) -> String {
        let calendar = calendar
        let day: String
        if calendar.isDateInToday(date) {
            day = String(localized: "Today")
        } else if calendar.isDateInTomorrow(date) {
            day = String(localized: "Tomorrow")
        } else if calendar.isDateInYesterday(date) {
            day = String(localized: "Yesterday")
        } else {
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
            day = sameYear ? date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                           : date.formatted(.dateTime.day().month(.abbreviated).year())
        }
        return hasTime ? "\(day), \(date.formatted(date: .omitted, time: .shortened))" : day
    }
}

/// Small banner at the top ("Ticked off: Milk, Bananas").
struct NoticeBanner: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 4, y: 2)
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Dashboard "Today"

/// Today's events and reminders and the shopping list size, on the
/// dashboard. Loads with plain fetches (no @Query) so it cannot disturb the
/// dashboard's own queries.
struct FamilyTodaySection: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var sync: SyncCoordinator
    @State private var summary = TodaySummary()

    struct TodaySummary: Equatable {
        struct Line: Equatable, Identifiable {
            let id: String
            let icon: String
            let colorHex: String
            let title: String
            let detail: String
        }
        var events: [Line] = []
        var reminders: [Line] = []
        var openShopping = 0
        var isEmpty: Bool { events.isEmpty && reminders.isEmpty && openShopping == 0 }
    }

    var body: some View {
        Section {
                if summary.isEmpty {
                    Button { show(.calendar) } label: {
                        HStack {
                            CategoryIcon(icon: "checklist", colorHex: "#9E9E9E", size: 26)
                            Text("Nothing planned today").foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                    ForEach(summary.events + summary.reminders) { line in
                        Button { show(line.id.hasPrefix("r") ? .reminders : .calendar) } label: {
                            HStack {
                                CategoryIcon(icon: line.icon, colorHex: line.colorHex, size: 26)
                                Text(verbatim: line.title).foregroundStyle(.primary).lineLimit(1)
                                Spacer()
                                Text(verbatim: line.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if summary.openShopping > 0 {
                        Button { show(.shopping) } label: {
                            HStack {
                                CategoryIcon(icon: "cart.fill", colorHex: "#34A853", size: 26)
                                Text("\(summary.openShopping) item(s) on the shopping list").foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
        } header: {
            Text("Today")
        }
        .task(id: sync.remoteChangeCount) { load() }
        .onAppear { load() }
    }

    private func show(_ segment: PlannerSegment) {
        UserDefaults.standard.set(segment.rawValue, forKey: PlannerSegment.storageKey)
        session.selectedTab = .planner
    }

    private func load() {
        let calendar = PlannerDates.calendar
        let now = Date()
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now
        let fid = family.id
        let me = session.currentMember?.id

        var result = TodaySummary()
        let events = (try? context.fetch(FetchDescriptor<FamilyEvent>(predicate: #Predicate { $0.familyID == fid }))) ?? []
        let byID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for occurrence in EventCalendar.occurrences(of: events.map(\.spec), in: DateInterval(start: dayStart, end: dayEnd), calendar: calendar).prefix(4) {
            guard let event = byID[occurrence.eventID] else { continue }
            let detail = occurrence.isAllDay ? String(localized: "All day") : occurrence.start.formatted(date: .omitted, time: .shortened)
            result.events.append(.init(id: "e\(occurrence.id)", icon: event.kind.icon, colorHex: event.kind.colorHex, title: event.title, detail: detail))
        }

        let reminders = (try? context.fetch(FetchDescriptor<FamilyReminder>(predicate: #Predicate { $0.familyID == fid && $0.isDone == false }))) ?? []
        let due = reminders
            .filter { r in
                guard let date = r.dueDate, date < dayEnd else { return false }
                return r.assignees.isEmpty || me.map { r.assignees.contains($0) } == true
            }
            .sorted { ($0.dueDate ?? now) < ($1.dueDate ?? now) }
        for r in due.prefix(4) {
            let overdue = ReminderSchedule.isOverdue(due: r.dueDate ?? now, hasTime: r.hasTime, now: now, calendar: calendar)
            let detail = overdue ? String(localized: "Overdue") : (r.hasTime ? (r.dueDate ?? now).formatted(date: .omitted, time: .shortened) : String(localized: "Today"))
            result.reminders.append(.init(id: "r\(r.id.uuidString)", icon: "bell.fill", colorHex: overdue ? "#EA4335" : "#FB8C00", title: r.title, detail: detail))
        }

        result.openShopping = (try? context.fetchCount(FetchDescriptor<ShoppingItem>(predicate: #Predicate {
            $0.familyID == fid && $0.isBought == false && $0.isCleared == false
        }))) ?? 0
        if result != summary { summary = result }
    }
}

// MARK: - Notification settings (Family tab)

struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var toggles: [PlannerNotifications.Setting: Bool] = [:]

    var body: some View {
        Form {
            Section {
                switch status {
                case .authorized, .provisional, .ephemeral:
                    Label("Notifications are allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .denied:
                    Label("Notifications are turned off for Familoq", systemImage: "bell.slash")
                    Button("Open iPhone Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                default:
                    Button {
                        Task {
                            await PlannerNotifications.requestPermissionIfNeeded()
                            await refresh()
                            await PlannerNotifications.reschedule(context: context)
                        }
                    } label: {
                        Label("Allow notifications", systemImage: "bell.badge")
                    }
                }
            } footer: {
                Text("Alerts are prepared on this iPhone from the family's data. iOS also checks for new family entries in the background now and then, so they can alert you without opening Familoq.")
            }

            Section("Notify me about") {
                ForEach(PlannerNotifications.Setting.allCases, id: \.self) { setting in
                    Toggle(LocalizedStringKey(setting.title), isOn: Binding(
                        get: { toggles[setting] ?? setting.isOn },
                        set: { value in
                            setting.isOn = value
                            toggles[setting] = value
                            Task { await PlannerNotifications.reschedule(context: context) }
                        }))
                }
            }
        }
        .navigationTitle("Notifications")
        .task { await refresh() }
    }

    private func refresh() async {
        status = await PlannerNotifications.status()
    }
}
