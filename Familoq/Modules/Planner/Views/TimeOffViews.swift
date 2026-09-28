import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqPlanner

/// Planner → Time off: job holidays per person, allowance, days used in a
/// chosen period and days the family is off together.
struct TimeOffScreen: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var leaves: [LeaveEntry]
    @Query private var allowances: [LeaveAllowance]
    @Query private var members: [FamilyMember]
    @ObservedObject private var holidaySettings = HolidaySettings.shared
    @AppStorage("timeoff.period") private var periodRaw = TimeOffPeriod.thisYear.rawValue
    @State private var customFrom = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: Date()), month: 1, day: 1)) ?? Date()
    @State private var customTo = Date()
    @State private var editing: LeaveEditTarget?
    @State private var allowanceEditing: AllowanceTarget?

    enum TimeOffPeriod: String, CaseIterable, Identifiable {
        case thisMonth, thisYear, nextYear, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .thisMonth: return "This month"
            case .thisYear: return "This year"
            case .nextYear: return "Next year"
            case .custom: return "Custom range"
            }
        }
    }

    struct AllowanceTarget: Identifiable {
        let memberID: UUID
        let name: String
        let year: Int
        let days: Double
        var id: String { "\(memberID)-\(year)" }
    }

    init(family: Family) {
        self.family = family
        let fid = family.id
        _leaves = Query(filter: #Predicate<LeaveEntry> { $0.familyID == fid }, sort: \LeaveEntry.firstDay)
        _allowances = Query(filter: #Predicate<LeaveAllowance> { $0.familyID == fid })
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid && $0.isActive == true }, sort: \FamilyMember.joinedAt)
    }

    private var period: TimeOffPeriod { TimeOffPeriod(rawValue: periodRaw) ?? .thisYear }

    private func interval(calendar: Calendar) -> DateInterval {
        let now = Date()
        switch period {
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 86_400)
        case .thisYear:
            return calendar.dateInterval(of: .year, for: now) ?? DateInterval(start: now, duration: 86_400)
        case .nextYear:
            let next = calendar.date(byAdding: .year, value: 1, to: now) ?? now
            return calendar.dateInterval(of: .year, for: next) ?? DateInterval(start: next, duration: 86_400)
        case .custom:
            let start = calendar.startOfDay(for: min(customFrom, customTo))
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(customFrom, customTo))) ?? start
            return DateInterval(start: start, end: end)
        }
    }

    private func holidays(for interval: DateInterval, calendar: Calendar) -> Set<Date> {
        let first = calendar.component(.year, from: interval.start)
        let last = calendar.component(.year, from: interval.end.addingTimeInterval(-1))
        var result = Set<Date>()
        for year in first...max(first, last) {
            let middle = calendar.date(from: DateComponents(year: year, month: 7, day: 1)) ?? interval.start
            result.formUnion(holidaySettings.holidays(around: middle, calendar: calendar).keys)
        }
        return result
    }

    private func allowance(memberID: UUID, year: Int) -> Double? {
        allowances.first { $0.memberID == memberID && $0.year == year }?.days
    }

    var body: some View {
        let calendar = PlannerDates.calendar
        let range = interval(calendar: calendar)
        let holidaySet = holidays(for: range, calendar: calendar)
        let year = calendar.component(.year, from: range.start)
        let yearRange = calendar.dateInterval(of: .year, for: range.start) ?? range
        let yearHolidays = holidays(for: yearRange, calendar: calendar)
        let names = MemberNames(members)
        let inPeriod = leaves.filter { calendar.startOfDay(for: $0.lastDay) >= range.start && calendar.startOfDay(for: $0.firstDay) < range.end }
        let overlaps = TimeOffCalculator.overlaps(leaves.map(\.span), in: range, calendar: calendar)

        List {
            Section {
                Picker("Period", selection: $periodRaw) {
                    ForEach(TimeOffPeriod.allCases) { Text(LocalizedStringKey($0.title)).tag($0.rawValue) }
                }
                .pickerStyle(.menu)
                if period == .custom {
                    DatePicker("From", selection: $customFrom, displayedComponents: [.date])
                    DatePicker("To", selection: $customTo, in: customFrom..., displayedComponents: [.date])
                }
            } footer: {
                Text("Weekends and public holidays (\(holidaySettings.countryName)\(holidaySettings.stateName.map { ", " + $0 } ?? "")) are not counted. Half day = 0.5; training is not taken from the allowance.")
            }

            Section("Per person") {
                ForEach(members) { member in
                    let spans = leaves.filter { $0.memberID == member.id }.map(\.span)
                    let used = TimeOffCalculator.usedDays(spans, in: range, holidays: holidaySet, calendar: calendar)
                    let usedYear = TimeOffCalculator.usedDays(spans, in: yearRange, holidays: yearHolidays, calendar: calendar)
                    let training = TimeOffCalculator.trainingDays(spans, in: range, holidays: holidaySet, calendar: calendar)
                    let total = allowance(memberID: member.id, year: year)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Circle().fill(Color(hex: MemberColors.hex(for: member.id, members: members))).frame(width: 10, height: 10)
                            Text(verbatim: member.displayName).font(.headline)
                            Spacer()
                            Text("\(Self.days(used)) day(s)").monospacedDigit()
                        }
                        if training > 0 {
                            Text("+ \(training) training day(s)").font(.caption).foregroundStyle(.secondary)
                        }
                        Button {
                            allowanceEditing = AllowanceTarget(memberID: member.id, name: member.displayName, year: year, days: total ?? 30)
                        } label: {
                            if let total {
                                let left = total - usedYear
                                HStack {
                                    Text("Allowance \(String(year)): \(Self.days(total)) · used \(Self.days(usedYear)) · left \(Self.days(left))")
                                        .font(.caption)
                                        .foregroundStyle(left < 0 ? Color.red : Color.secondary)
                                    Spacer()
                                    Image(systemName: "pencil").font(.caption)
                                }
                            } else {
                                Label("Set yearly allowance for \(String(year))", systemImage: "plus.circle").font(.caption)
                            }
                        }
                        .buttonStyle(.borderless)
                        if total != nil {
                            ProgressView(value: min(max(usedYear, 0), total ?? 1), total: max(total ?? 1, 0.5))
                                .tint(Color(hex: MemberColors.hex(for: member.id, members: members)))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if !overlaps.isEmpty {
                Section {
                    ForEach(Array(overlaps.enumerated()), id: \.offset) { _, overlap in
                        HStack {
                            Image(systemName: "person.2.fill").foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: rangeText(overlap.first, overlap.last, calendar: calendar))
                                Text(verbatim: names.list(overlap.people)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            let count = (calendar.dateComponents([.day], from: overlap.first, to: overlap.last).day ?? 0) + 1
                            Text("\(count) day(s)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Off together")
                } footer: {
                    Text("Days on which at least two of you are off - good for trips.")
                }
            }

            Section {
                if inPeriod.isEmpty {
                    Text("No time off in this period. Tap + to add vacation, a half day, a bridge day, company closure or training.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(inPeriod) { leave in
                    Button {
                        editing = LeaveEditTarget(entry: leave, day: nil)
                    } label: {
                        HStack(spacing: 12) {
                            CategoryIcon(icon: leave.type.icon, colorHex: MemberColors.hex(for: leave.memberID, members: members), size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: (names.name(leave.memberID) ?? "-") + " · " + String(localized: String.LocalizationValue(leave.type.title)))
                                    .foregroundStyle(.primary)
                                Text(verbatim: rangeText(leave.firstDay, leave.lastDay, calendar: calendar) + (leave.note.isEmpty ? "" : " · " + leave.note))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            let days = TimeOffCalculator.usedDays([leave.span], in: range, holidays: holidaySet, calendar: calendar)
                            Text(verbatim: Self.days(days)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            context.delete(leave)
                            try? context.save()
                        }
                    }
                }
            } header: {
                Text("Entries")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = LeaveEditTarget(entry: nil, day: nil)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { target in
            LeaveForm(family: family, target: target, members: members)
        }
        .sheet(item: $allowanceEditing) { target in
            AllowanceSheet(family: family, target: target)
        }
    }

    static func days(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : value.formatted(.number.precision(.fractionLength(1)))
    }

    private func rangeText(_ first: Date, _ last: Date, calendar: Calendar) -> String {
        if calendar.isDate(first, inSameDayAs: last) {
            return first.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        return "\(first.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
    }
}

struct LeaveEditTarget: Identifiable {
    let id = UUID()
    let entry: LeaveEntry?
    /// Day to prefill for a new entry.
    let day: Date?
}

/// New or existing time off. Own copy; writes on Save.
struct LeaveForm: View {
    let family: Family
    let target: LeaveEditTarget
    let members: [FamilyMember]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @State private var memberID: UUID?
    @State private var type: LeaveType
    @State private var first: Date
    @State private var last: Date
    @State private var note: String

    init(family: Family, target: LeaveEditTarget, members: [FamilyMember]) {
        self.family = family
        self.target = target
        self.members = members.filter(\.isActive)
        let day = PlannerDates.calendar.startOfDay(for: target.day ?? Date())
        _memberID = State(initialValue: target.entry?.memberID ?? members.first(where: \.isCurrentUser)?.id ?? members.first?.id)
        _type = State(initialValue: target.entry?.type ?? .vacation)
        _first = State(initialValue: target.entry?.firstDay ?? day)
        _last = State(initialValue: target.entry?.lastDay ?? day)
        _note = State(initialValue: target.entry?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Who", selection: $memberID) {
                        ForEach(members) { member in
                            Text(verbatim: member.displayName).tag(Optional(member.id))
                        }
                    }
                    Picker("Type", selection: $type) {
                        ForEach(LeaveType.allCases, id: \.self) { t in
                            Label(LocalizedStringKey(t.title), systemImage: t.icon).tag(t)
                        }
                    }
                }
                Section {
                    DatePicker(type == .halfDay ? LocalizedStringKey("Day") : LocalizedStringKey("First day"), selection: $first, displayedComponents: [.date])
                        .onChange(of: first) { _, value in if last < value || type == .halfDay { last = value } }
                    if type != .halfDay {
                        DatePicker("Last day", selection: $last, in: first..., displayedComponents: [.date])
                    }
                    TextField("Note (optional)", text: $note)
                } footer: {
                    let calendar = PlannerDates.calendar
                    let holidays = HolidaySettings.shared.holidays(around: first, calendar: calendar)
                    let span = LeaveSpan(memberID: memberID ?? UUID(), type: type, first: first, last: type == .halfDay ? first : last)
                    let all = DateInterval(start: calendar.startOfDay(for: first), end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: span.last)) ?? first)
                    let used = TimeOffCalculator.usedDays([span], in: all, holidays: Set(holidays.keys), calendar: calendar)
                    Text(type == .training ? LocalizedStringKey("Not taken from the vacation allowance.") : LocalizedStringKey("Uses \(TimeOffScreen.days(used)) vacation day(s) (weekends and public holidays not counted)."))
                }
                if target.entry != nil {
                    Section {
                        Button("Delete", role: .destructive) {
                            if let entry = target.entry {
                                context.delete(entry)
                                try? context.save()
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(target.entry == nil ? LocalizedStringKey("New time off") : LocalizedStringKey("Time off"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(memberID == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let memberID else { return }
        let calendar = PlannerDates.calendar
        let firstDay = calendar.startOfDay(for: first)
        let lastDay = calendar.startOfDay(for: type == .halfDay ? first : max(first, last))
        let entry: LeaveEntry
        if let existing = target.entry {
            entry = existing
        } else {
            entry = LeaveEntry(familyID: family.id, memberID: memberID, type: type, firstDay: firstDay, lastDay: lastDay)
            entry.createdByMemberID = session.currentMember?.id
            context.insert(entry)
        }
        entry.memberID = memberID
        entry.type = type
        entry.firstDay = firstDay
        entry.lastDay = lastDay
        entry.note = note.trimmingCharacters(in: .whitespaces)
        entry.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}

private struct AllowanceSheet: View {
    let family: Family
    let target: TimeOffScreen.AllowanceTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var days: Double

    init(family: Family, target: TimeOffScreen.AllowanceTarget) {
        self.family = family
        self.target = target
        _days = State(initialValue: target.days)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $days, in: 0...60, step: 0.5) {
                        Text("\(TimeOffScreen.days(days)) day(s)").monospacedDigit()
                    }
                } header: {
                    Text(verbatim: "\(target.name) · \(target.year)")
                } footer: {
                    Text("Vacation days per year, e.g. 30. Include days carried over from last year if you like.")
                }
            }
            .navigationTitle("Yearly allowance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let id = LeaveAllowance.allowanceID(familyID: family.id, memberID: target.memberID, year: target.year)
        var descriptor = FetchDescriptor<LeaveAllowance>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.days = days
            existing.updatedAt = Date()
        } else {
            context.insert(LeaveAllowance(id: id, familyID: family.id, memberID: target.memberID, year: target.year, days: days))
        }
        try? context.save()
        dismiss()
    }
}

/// Country (App Store country by default) and state for public holidays.
struct HolidaySettingsSheet: View {
    @ObservedObject private var settings = HolidaySettings.shared
    @Environment(\.dismiss) private var dismiss

    private var storeCountryName: String {
        guard let code = settings.storeCountry, let country = PublicHolidays.countries.first(where: { $0.code == code }) else { return "–" }
        return String(localized: String.LocalizationValue(country.name))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Country", selection: Binding(get: { settings.isAutomatic ? "" : settings.country },
                                                         set: { settings.setCountry($0.isEmpty ? nil : $0) })) {
                        Text("Automatic (App Store: \(storeCountryName))").tag("")
                        ForEach(PublicHolidays.countries) { country in
                            Text(LocalizedStringKey(country.name)).tag(country.code)
                        }
                    }
                    let states = PublicHolidays.states(of: settings.country)
                    if !states.isEmpty {
                        Picker("State / region", selection: Binding(get: { settings.state ?? "" }, set: { settings.setState($0.isEmpty ? nil : $0) })) {
                            Text("Not set - nationwide holidays only").tag("")
                            ForEach(states) { state in
                                Text(LocalizedStringKey(state.name)).tag(state.code)
                            }
                        }
                    }
                } footer: {
                    Text("Public holidays are shown in red like Saturday and Sunday and are not counted as vacation days. Calculated on the iPhone - no internet needed. Set on each iPhone.")
                }
            }
            .navigationTitle("Public holidays")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
