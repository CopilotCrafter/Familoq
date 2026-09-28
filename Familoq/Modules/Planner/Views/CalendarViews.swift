import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqPlanner

struct CalendarScreen: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var events: [FamilyEvent]
    @Query private var reminders: [FamilyReminder]
    @Query private var members: [FamilyMember]
    @Query private var leaves: [LeaveEntry]
    @ObservedObject private var holidaySettings = HolidaySettings.shared
    @State private var month: Date
    @State private var selectedDay: Date
    @State private var editing: EventEditTarget?
    @State private var leaveEditing: LeaveEditTarget?
    @State private var showSettings = false

    init(family: Family) {
        self.family = family
        let fid = family.id
        _events = Query(filter: #Predicate<FamilyEvent> { $0.familyID == fid }, sort: \FamilyEvent.start)
        _reminders = Query(filter: #Predicate<FamilyReminder> { $0.familyID == fid && $0.isDone == false })
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid }, sort: \FamilyMember.joinedAt)
        _leaves = Query(filter: #Predicate<LeaveEntry> { $0.familyID == fid }, sort: \LeaveEntry.firstDay)
        let today = PlannerDates.calendar.startOfDay(for: Date())
        _month = State(initialValue: today)
        _selectedDay = State(initialValue: today)
    }

    var body: some View {
        let calendar = PlannerDates.calendar
        let names = MemberNames(members)
        let byID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let specs = events.map(\.spec)
        let monthInterval = calendar.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 31 * 86_400)
        let monthOccurrences = EventCalendar.occurrences(of: specs, in: monthInterval, calendar: calendar)
        let marked = Set(monthOccurrences.flatMap { EventCalendar.days(of: $0, calendar: calendar) })
            .union(reminders.compactMap { $0.dueDate.map { calendar.startOfDay(for: $0) } })
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
        let dayOccurrences = EventCalendar.occurrences(of: specs, in: DateInterval(start: selectedDay, end: dayEnd), calendar: calendar)
        let dayReminders = reminders.filter { $0.dueDate.map { calendar.isDate($0, inSameDayAs: selectedDay) } == true }
        let upcomingStart = max(dayEnd, calendar.startOfDay(for: Date()))
        let upcomingEnd = calendar.date(byAdding: .day, value: 30, to: upcomingStart) ?? upcomingStart
        let upcoming = EventCalendar.occurrences(of: specs, in: DateInterval(start: upcomingStart, end: upcomingEnd), calendar: calendar)
            .filter { $0.start >= upcomingStart }
            .prefix(12)
        let holidayNames = holidaySettings.holidays(around: month, calendar: calendar)
        let leaveColors = leaveColors(in: monthInterval, calendar: calendar)
        let dayHoliday = holidayNames[calendar.startOfDay(for: selectedDay)]
        let dayLeaves = leaves.filter { calendar.startOfDay(for: $0.firstDay) <= selectedDay && calendar.startOfDay(for: $0.lastDay) >= selectedDay }
        let nextHolidays = holidayNames.filter { $0.key >= calendar.startOfDay(for: Date()) }.sorted { $0.key < $1.key }.prefix(3)

        List {
            Section {
                MonthGrid(month: $month, selectedDay: $selectedDay, marked: marked, holidays: Set(holidayNames.keys),
                          leaveColors: leaveColors, calendar: calendar)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }

            Section {
                if let dayHoliday {
                    Label(LocalizedStringKey(dayHoliday), systemImage: "flag.fill")
                        .foregroundStyle(CalendarColors.holidayRed)
                }
                ForEach(dayLeaves) { leave in
                    Button {
                        leaveEditing = LeaveEditTarget(entry: leave, day: nil)
                    } label: {
                        HStack(spacing: 12) {
                            CategoryIcon(icon: leave.type.icon, colorHex: MemberColors.hex(for: leave.memberID, members: members), size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: names.name(leave.memberID) ?? "-").foregroundStyle(.primary)
                                Text(LocalizedStringKey(leave.type.title)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if dayOccurrences.isEmpty && dayReminders.isEmpty && dayHoliday == nil && dayLeaves.isEmpty {
                    Text("Nothing planned.").foregroundStyle(.secondary)
                }
                ForEach(dayOccurrences) { occurrence in
                    if let event = byID[occurrence.eventID] {
                        eventRow(event, occurrence: occurrence, names: names, showDate: false)
                    }
                }
                ForEach(dayReminders) { reminder in
                    HStack(spacing: 12) {
                        CategoryIcon(icon: "bell.fill", colorHex: "#FB8C00", size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: reminder.title)
                            Text(verbatim: reminder.hasTime ? (reminder.dueDate ?? selectedDay).formatted(date: .omitted, time: .shortened) : String(localized: "Reminder"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button {
                    editing = EventEditTarget(event: nil, day: selectedDay)
                } label: {
                    Label("Add event", systemImage: "plus")
                }
            } header: {
                Text(verbatim: selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            }

            if !nextHolidays.isEmpty {
                Section {
                    ForEach(nextHolidays.map { HolidayRow(date: $0.key, name: $0.value) }) { holiday in
                        HStack {
                            Text(LocalizedStringKey(holiday.name)).foregroundStyle(CalendarColors.holidayRed)
                            Spacer()
                            Text(verbatim: PlannerDates.dueText(holiday.date, hasTime: false)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Public holidays")
                } footer: {
                    Button {
                        showSettings = true
                    } label: {
                        Text(verbatim: holidaySettings.countryName + (holidaySettings.stateName.map { " · " + $0 } ?? ""))
                            .font(.caption)
                    }
                }
            }

            if !upcoming.isEmpty {
                Section("Coming up") {
                    ForEach(Array(upcoming)) { occurrence in
                        if let event = byID[occurrence.eventID] {
                            eventRow(event, occurrence: occurrence, names: names, showDate: true)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Today") {
                    let today = calendar.startOfDay(for: Date())
                    withAnimation {
                        month = today
                        selectedDay = today
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        editing = EventEditTarget(event: nil, day: selectedDay)
                    } label: {
                        Label("Event", systemImage: "calendar.badge.plus")
                    }
                    Button {
                        leaveEditing = LeaveEditTarget(entry: nil, day: selectedDay)
                    } label: {
                        Label("Time off", systemImage: "sun.max.fill")
                    }
                    Divider()
                    Button {
                        showSettings = true
                    } label: {
                        Label("Public holidays…", systemImage: "flag")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { target in
            EventForm(family: family, target: target, members: members)
        }
        .sheet(item: $leaveEditing) { target in
            LeaveForm(family: family, target: target, members: members)
        }
        .sheet(isPresented: $showSettings) {
            HolidaySettingsSheet()
        }
    }

    private struct HolidayRow: Identifiable {
        let date: Date
        let name: String
        var id: Date { date }
    }

    /// Day -> colours of the people off work (one entry per person).
    private func leaveColors(in interval: DateInterval, calendar: Calendar) -> [Date: [String]] {
        var result: [Date: [String]] = [:]
        for leave in leaves {
            let hex = MemberColors.hex(for: leave.memberID, members: members)
            for day in TimeOffCalculator.days(of: leave.span, calendar: calendar) where interval.contains(day) {
                if !(result[day] ?? []).contains(hex) { result[day, default: []].append(hex) }
            }
        }
        return result
    }

    private func eventRow(_ event: FamilyEvent, occurrence: EventOccurrence, names: MemberNames, showDate: Bool) -> some View {
        Button {
            editing = EventEditTarget(event: event, day: nil)
        } label: {
            HStack(spacing: 12) {
                CategoryIcon(icon: event.kind.icon, colorHex: event.kind.colorHex, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: event.title).foregroundStyle(.primary)
                    Text(verbatim: timeText(occurrence, showDate: showDate))
                        .font(.caption).foregroundStyle(.secondary)
                    let extra = [event.location, event.participants.isEmpty ? "" : names.list(event.participants)]
                        .filter { !$0.isEmpty }.joined(separator: " · ")
                    if !extra.isEmpty {
                        Text(verbatim: extra).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if event.frequency != .never {
                    Image(systemName: "repeat").font(.caption).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func timeText(_ o: EventOccurrence, showDate: Bool) -> String {
        let calendar = PlannerDates.calendar
        let date = showDate ? PlannerDates.dueText(o.start, hasTime: false) : ""
        let time: String
        if o.isAllDay {
            let days = EventCalendar.days(of: o, calendar: calendar).count
            time = days > 1 ? String(localized: "\(days) days") : String(localized: "All day")
        } else {
            time = "\(o.start.formatted(date: .omitted, time: .shortened)) – \(o.end.formatted(date: .omitted, time: .shortened))"
        }
        return date.isEmpty ? time : "\(date) · \(time)"
    }
}

/// Month view with a dot on days that have events or reminders.
private struct MonthGrid: View {
    @Binding var month: Date
    @Binding var selectedDay: Date
    let marked: Set<Date>
    /// Public holidays (start of day) - red like Saturday and Sunday.
    var holidays: Set<Date> = []
    /// Colours of the people off work that day.
    var leaveColors: [Date: [String]] = [:]
    let calendar: Calendar

    var body: some View {
        let cells = EventCalendar.monthGrid(for: month, calendar: calendar)
        let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        let symbols = weekdaySymbols
        VStack(spacing: 6) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Text(verbatim: month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 8)
            HStack(spacing: 0) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                    // Weekday number (1 = Sunday, 7 = Saturday) of this column.
                    let weekday = (calendar.firstWeekday - 1 + index) % 7 + 1
                    Text(verbatim: symbol).font(.caption2)
                        .foregroundStyle(weekday == 1 || weekday == 7 ? CalendarColors.holidayRed : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, day in
                        cell(day).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    @ViewBuilder
    private func cell(_ day: Date?) -> some View {
        if let day {
            let start = calendar.startOfDay(for: day)
            let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
            let isToday = calendar.isDateInToday(day)
            let isRedDay = calendar.isDateInWeekend(day) || holidays.contains(start)
            let people = leaveColors[start] ?? []
            Button {
                withAnimation(.snappy) { selectedDay = day }
            } label: {
                VStack(spacing: 2) {
                    Text(verbatim: "\(calendar.component(.day, from: day))")
                        .font(.callout.weight(isToday ? .bold : .regular))
                        .foregroundStyle(isSelected ? Color.white : (isRedDay ? CalendarColors.holidayRed : (isToday ? Color.accentColor : Color.primary)))
                        .frame(width: 34, height: 34)
                        .background {
                            if isSelected {
                                Circle().fill(isRedDay ? CalendarColors.holidayRed : Color.accentColor)
                            } else if isToday {
                                Circle().stroke(Color.accentColor, lineWidth: 1.5)
                            }
                        }
                    HStack(spacing: 2) {
                        if people.isEmpty {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 5, height: 5)
                                .opacity(marked.contains(start) ? 1 : 0)
                        } else {
                            // Time off: one short bar per person, in their colour.
                            ForEach(people.prefix(3), id: \.self) { hex in
                                Capsule().fill(Color(hex: hex)).frame(width: people.count > 1 ? 8 : 16, height: 4)
                            }
                            if marked.contains(start) {
                                Circle().fill(Color.accentColor).frame(width: 4, height: 4)
                            }
                        }
                    }
                    .frame(height: 5)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(height: 41)
        }
    }

    private func shift(_ months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: month) else { return }
        withAnimation {
            month = next
            if !calendar.isDate(selectedDay, equalTo: next, toGranularity: .month) {
                selectedDay = calendar.isDate(Date(), equalTo: next, toGranularity: .month)
                    ? calendar.startOfDay(for: Date())
                    : (calendar.dateInterval(of: .month, for: next)?.start ?? next)
            }
        }
    }
}

struct EventEditTarget: Identifiable {
    let id = UUID()
    let event: FamilyEvent?
    /// Day to prefill for a new event.
    let day: Date?
}

/// New or existing event (changes apply to all repeats). Own copy; writes on Save.
private struct EventForm: View {
    let family: Family
    let target: EventEditTarget
    let members: [FamilyMember]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @State private var title: String
    @State private var kind: EventKind
    @State private var isAllDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var frequency: RepeatFrequency
    @State private var participants: Set<UUID>
    @State private var location: String
    @State private var notes: String
    @State private var alertMinutes: Int
    @State private var confirmDelete = false

    init(family: Family, target: EventEditTarget, members: [FamilyMember]) {
        self.family = family
        self.target = target
        self.members = members
        let calendar = PlannerDates.calendar
        if let e = target.event {
            _title = State(initialValue: e.title)
            _kind = State(initialValue: e.kind)
            _isAllDay = State(initialValue: e.isAllDay)
            _start = State(initialValue: e.start)
            // All-day end is stored exclusive; show the last day.
            _end = State(initialValue: e.isAllDay ? (calendar.date(byAdding: .day, value: -1, to: e.end) ?? e.start) : e.end)
            _frequency = State(initialValue: e.frequency)
            _participants = State(initialValue: e.participants)
            _location = State(initialValue: e.location)
            _notes = State(initialValue: e.notes)
            _alertMinutes = State(initialValue: e.alertMinutes)
        } else {
            let day = target.day ?? Date()
            let now = Date()
            var startDate = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
            if calendar.isDateInToday(day) {
                let nextHour = calendar.dateInterval(of: .hour, for: now)?.end ?? now
                startDate = nextHour
            }
            _title = State(initialValue: "")
            _kind = State(initialValue: .event)
            _isAllDay = State(initialValue: false)
            _start = State(initialValue: startDate)
            _end = State(initialValue: startDate.addingTimeInterval(3600))
            _frequency = State(initialValue: .never)
            _participants = State(initialValue: [])
            _location = State(initialValue: "")
            _notes = State(initialValue: "")
            _alertMinutes = State(initialValue: 60)
        }
    }

    struct AlertChoice: Hashable {
        let minutes: Int
        let label: String
    }

    private var alertChoices: [AlertChoice] {
        let list: [(Int, String)] = isAllDay
            ? [(-1, "None"), (0, "On the day (9:00)"), (1440, "1 day before (9:00)"), (10080, "1 week before (9:00)")]
            : [(-1, "None"), (0, "At start"), (15, "15 minutes before"), (30, "30 minutes before"),
               (60, "1 hour before"), (120, "2 hours before"), (1440, "1 day before")]
        return list.map { AlertChoice(minutes: $0.0, label: $0.1) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(kind == .birthday ? LocalizedStringKey("Whose birthday?") : LocalizedStringKey("Title"), text: $title)
                    Picker("Type", selection: $kind) {
                        ForEach(EventKind.allCases) { k in
                            Label(LocalizedStringKey(k.displayName), systemImage: k.icon).tag(k)
                        }
                    }
                    .onChange(of: kind) { _, newKind in
                        if newKind == .birthday {
                            isAllDay = true
                            frequency = .yearly
                            alertMinutes = 1440
                        }
                    }
                }
                Section {
                    Toggle("All day", isOn: $isAllDay.animation())
                        .onChange(of: isAllDay) { _, allDay in
                            if !alertChoices.contains(where: { $0.minutes == alertMinutes }) {
                                alertMinutes = allDay ? 1440 : 60
                            }
                        }
                    DatePicker(isAllDay ? LocalizedStringKey("Day") : LocalizedStringKey("Starts"), selection: $start, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                        .onChange(of: start) { old, new in
                            // Keep the length when the start moves.
                            end = end.addingTimeInterval(new.timeIntervalSince(old))
                        }
                    if isAllDay {
                        DatePicker("Last day", selection: $end, in: start..., displayedComponents: [.date])
                    } else {
                        DatePicker("Ends", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                    }
                    Picker("Repeat", selection: $frequency) {
                        ForEach(RepeatFrequency.allCases, id: \.self) { f in
                            Text(LocalizedStringKey(f.displayName)).tag(f)
                        }
                    }
                    Picker("Alert", selection: $alertMinutes) {
                        ForEach(alertChoices, id: \.minutes) { choice in
                            Text(LocalizedStringKey(choice.label)).tag(choice.minutes)
                        }
                    }
                } footer: {
                    if target.event != nil && frequency != .never {
                        Text("Changes apply to every repeat.")
                    }
                }
                Section {
                    MemberChooser(members: members, selection: $participants, everyoneLabel: "Whole family")
                } header: {
                    Text("Who")
                } footer: {
                    Text("Alerts go to the chosen people's iPhones. Everyone in the family sees the event.")
                }
                Section {
                    TextField("Location", text: $location)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...5)
                }
                if target.event != nil {
                    Section {
                        Button("Delete event", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(target.event == nil ? LocalizedStringKey("New event") : LocalizedStringKey("Event"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this event?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let e = target.event {
                        context.delete(e)
                        try? context.save()
                    }
                    Task { await PlannerNotifications.reschedule(context: context) }
                    dismiss()
                }
            } message: {
                if frequency != .never { Text("All repeats are deleted.") }
            }
        }
    }

    private func save() {
        let calendar = PlannerDates.calendar
        let event: FamilyEvent
        if let existing = target.event {
            event = existing
        } else {
            event = FamilyEvent(familyID: family.id, title: "", start: start, end: end, isAllDay: isAllDay)
            event.createdByMemberID = session.currentMember?.id
            context.insert(event)
        }
        event.title = title.trimmingCharacters(in: .whitespaces)
        event.kind = kind
        event.isAllDay = isAllDay
        if isAllDay {
            let first = calendar.startOfDay(for: start)
            let last = max(calendar.startOfDay(for: end), first)
            event.start = first
            event.end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        } else {
            event.start = start
            event.end = end > start ? end : start.addingTimeInterval(3600)
        }
        event.frequency = frequency
        event.participants = participants
        event.location = location.trimmingCharacters(in: .whitespaces)
        event.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        event.alertMinutes = alertMinutes
        event.updatedAt = Date()
        try? context.save()
        let wantsAlert = alertMinutes >= 0
        Task {
            if wantsAlert { await PlannerNotifications.requestPermissionIfNeeded() }
            await PlannerNotifications.reschedule(context: context)
        }
        dismiss()
    }
}
