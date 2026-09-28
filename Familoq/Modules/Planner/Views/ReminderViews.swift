import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqPlanner

struct RemindersScreen: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var reminders: [FamilyReminder]
    @Query private var members: [FamilyMember]
    @AppStorage("reminders.onlyMine") private var onlyMine = false
    @State private var showDone = false
    @State private var editing: ReminderEditTarget?

    init(family: Family) {
        self.family = family
        let fid = family.id
        _reminders = Query(filter: #Predicate<FamilyReminder> { $0.familyID == fid }, sort: \FamilyReminder.createdAt)
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid }, sort: \FamilyMember.joinedAt)
    }

    private var visible: [FamilyReminder] {
        guard onlyMine, let me = session.currentMember?.id else { return reminders }
        return reminders.filter { $0.assignees.isEmpty || $0.assignees.contains(me) }
    }

    private var openReminders: [FamilyReminder] {
        visible.filter { !$0.isDone }.sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.createdAt < b.createdAt
            }
        }
    }

    private var doneReminders: [FamilyReminder] {
        visible.filter(\.isDone).sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
    }

    var body: some View {
        let names = MemberNames(members)
        let now = Date()
        let calendar = PlannerDates.calendar
        let groups = Dictionary(grouping: openReminders) {
            ReminderSchedule.bucket(due: $0.dueDate, hasTime: $0.hasTime, now: now, calendar: calendar)
        }
        List {
            if openReminders.isEmpty {
                Section {
                    Text("No open reminders. Add chores, appointments to book or things not to forget - for yourself, someone else or the whole family.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(ReminderSchedule.Bucket.allCases, id: \.self) { bucket in
                if let items = groups[bucket], !items.isEmpty {
                    Section {
                        ForEach(items) { reminder in
                            row(reminder, names: names, overdue: bucket == .overdue)
                        }
                    } header: {
                        Text(LocalizedStringKey(bucket.title))
                            .foregroundStyle(bucket == .overdue ? Color.red : Color.secondary)
                    }
                }
            }
            if !doneReminders.isEmpty {
                Section {
                    if showDone {
                        ForEach(doneReminders.prefix(30)) { reminder in
                            row(reminder, names: names, overdue: false)
                        }
                    }
                } header: {
                    HStack {
                        Text("Done (\(doneReminders.count))")
                        Spacer()
                        Button(showDone ? LocalizedStringKey("Hide") : LocalizedStringKey("Show")) { withAnimation { showDone.toggle() } }
                            .font(.caption)
                            .textCase(nil)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Show", selection: $onlyMine) {
                        Text("Everyone's reminders").tag(false)
                        Text("Only mine").tag(true)
                    }
                } label: {
                    Image(systemName: onlyMine ? "person.crop.circle.fill" : "person.2.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = ReminderEditTarget(reminder: nil)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { target in
            ReminderForm(family: family, target: target, members: members)
        }
    }

    private func row(_ reminder: FamilyReminder, names: MemberNames, overdue: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation {
                    if reminder.isDone {
                        ReminderService.reopen(reminder, context: context)
                    } else {
                        ReminderService.complete(reminder, memberID: session.currentMember?.id, context: context)
                    }
                }
                Task { await PlannerNotifications.reschedule(context: context) }
            } label: {
                Image(systemName: reminder.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(reminder.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)

            Button {
                editing = ReminderEditTarget(reminder: reminder)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: reminder.title)
                        .strikethrough(reminder.isDone)
                        .foregroundStyle(reminder.isDone ? .secondary : .primary)
                    HStack(spacing: 6) {
                        if let due = reminder.dueDate, !reminder.isDone {
                            Label(PlannerDates.dueText(due, hasTime: reminder.hasTime), systemImage: "calendar")
                                .foregroundStyle(overdue ? Color.red : Color.secondary)
                        }
                        if reminder.frequency != .never {
                            Image(systemName: "repeat").foregroundStyle(.secondary)
                        }
                        Label(names.list(reminder.assignees), systemImage: reminder.assignees.isEmpty ? "person.2" : "person")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .labelStyle(.titleAndIcon)
                    if reminder.isDone, let who = names.name(reminder.completedByMemberID) {
                        Text("Done by \(who)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .swipeActions {
            Button(role: .destructive) {
                context.delete(reminder)
                try? context.save()
                Task { await PlannerNotifications.reschedule(context: context) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct ReminderEditTarget: Identifiable {
    let id = UUID()
    let reminder: FamilyReminder?
}

/// New or existing reminder. Keeps its own copy; writes on Save.
private struct ReminderForm: View {
    let family: Family
    let target: ReminderEditTarget
    let members: [FamilyMember]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @State private var title: String
    @State private var notes: String
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var hasTime: Bool
    @State private var frequency: RepeatFrequency
    @State private var assignees: Set<UUID>
    @State private var alert: Bool
    @State private var confirmDelete = false

    init(family: Family, target: ReminderEditTarget, members: [FamilyMember]) {
        self.family = family
        self.target = target
        self.members = members
        let r = target.reminder
        let calendar = PlannerDates.calendar
        let defaultDue = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
        _title = State(initialValue: r?.title ?? "")
        _notes = State(initialValue: r?.notes ?? "")
        _hasDue = State(initialValue: r == nil ? true : r?.dueDate != nil)
        _due = State(initialValue: r?.dueDate ?? defaultDue)
        _hasTime = State(initialValue: r?.hasTime ?? false)
        _frequency = State(initialValue: r?.frequency ?? .never)
        _assignees = State(initialValue: r?.assignees ?? [])
        _alert = State(initialValue: r?.alertEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs doing?", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section {
                    Toggle("Due date", isOn: $hasDue.animation())
                    if hasDue {
                        DatePicker("Date", selection: $due, displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                        Toggle("Time", isOn: $hasTime.animation())
                        Picker("Repeat", selection: $frequency) {
                            ForEach(RepeatFrequency.allCases, id: \.self) { f in
                                Text(LocalizedStringKey(f.displayName)).tag(f)
                            }
                        }
                        Toggle("Notify", isOn: $alert)
                    }
                } footer: {
                    if hasDue && alert {
                        Text(hasTime ? LocalizedStringKey("Notification at the due time.") : LocalizedStringKey("Notification at 9:00 on the day."))
                    }
                }
                Section {
                    MemberChooser(members: members, selection: $assignees, everyoneLabel: "Whole family")
                } header: {
                    Text("For")
                } footer: {
                    Text("Only the chosen people are notified. Anyone in the family can tick it off.")
                }
                if target.reminder != nil {
                    Section {
                        Button("Delete reminder", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(target.reminder == nil ? LocalizedStringKey("New reminder") : LocalizedStringKey("Reminder"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this reminder?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let r = target.reminder {
                        context.delete(r)
                        try? context.save()
                    }
                    reschedule()
                    dismiss()
                }
            }
        }
    }

    private func save() {
        let reminder: FamilyReminder
        if let existing = target.reminder {
            reminder = existing
        } else {
            reminder = FamilyReminder(familyID: family.id, title: "")
            reminder.createdByMemberID = session.currentMember?.id
            context.insert(reminder)
        }
        reminder.title = title.trimmingCharacters(in: .whitespaces)
        reminder.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = PlannerDates.calendar
        let newDue: Date? = hasDue ? (hasTime ? due : calendar.startOfDay(for: due)) : nil
        if newDue != reminder.dueDate || frequency != reminder.frequency {
            reminder.repeatStart = newDue
        }
        reminder.dueDate = newDue
        reminder.hasTime = hasDue && hasTime
        reminder.frequency = hasDue ? frequency : .never
        reminder.alertEnabled = alert
        reminder.assignees = assignees
        reminder.updatedAt = Date()
        try? context.save()
        let wantsAlert = hasDue && alert
        Task {
            if wantsAlert { await PlannerNotifications.requestPermissionIfNeeded() }
            await PlannerNotifications.reschedule(context: context)
        }
        dismiss()
    }

    private func reschedule() {
        Task { await PlannerNotifications.reschedule(context: context) }
    }
}
