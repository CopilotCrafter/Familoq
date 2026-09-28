import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqBudget

/// Savings goals of the family ("Holiday 2027: €2,000 by June").
struct SavingsGoalsView: View {
    let family: Family

    @Environment(\.modelContext) private var context
    @Query private var goals: [SavingsGoal]
    @Query private var contributions: [SavingsContribution]
    @State private var showNewGoal = false

    init(family: Family) {
        self.family = family
        let fid = family.id
        _goals = Query(filter: #Predicate<SavingsGoal> { $0.familyID == fid }, sort: \SavingsGoal.createdAt)
        _contributions = Query(filter: #Predicate<SavingsContribution> { $0.familyID == fid }, sort: \SavingsContribution.date, order: .reverse)
    }

    private var active: [SavingsGoal] { goals.filter { !$0.isArchived } }
    private var archived: [SavingsGoal] { goals.filter(\.isArchived) }

    var body: some View {
        List {
            if active.isEmpty {
                Section {
                    EmptyStateView(icon: "star.circle", title: "No savings goals yet",
                                   message: "Save together for a holiday, a new car or a rainy-day fund. Familoq shows how much to put aside each month.")
                }
            }
            Section {
                ForEach(active) { goal in
                    NavigationLink {
                        SavingsGoalDetailView(family: family, goal: goal)
                    } label: {
                        SavingsGoalRow(goal: goal, saved: saved(goal), currency: family.baseCurrencyCode)
                    }
                }
                Button {
                    showNewGoal = true
                } label: {
                    Label("New savings goal", systemImage: "plus.circle")
                }
            }
            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived) { goal in
                        NavigationLink {
                            SavingsGoalDetailView(family: family, goal: goal)
                        } label: {
                            SavingsGoalRow(goal: goal, saved: saved(goal), currency: family.baseCurrencyCode)
                        }
                    }
                }
            }
        }
        .navigationTitle("Savings goals")
        .sheet(isPresented: $showNewGoal) {
            NavigationStack {
                SavingsGoalForm(family: family, editing: nil)
            }
        }
    }

    private func saved(_ goal: SavingsGoal) -> Decimal {
        contributions.filter { $0.goalID == goal.id }.reduce(Decimal(0)) { $0 + $1.amount }
    }
}

struct SavingsGoalRow: View {
    let goal: SavingsGoal
    let saved: Decimal
    let currency: String

    var body: some View {
        let progress = SavingsPlanner.progress(target: goal.target, saved: saved, deadline: goal.deadline, now: Date(),
                                               calendar: FamiloqCalendar.make(), currencyCode: currency)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: goal.icon).foregroundStyle(Color.accentColor)
                Text(goal.name)
                Spacer()
                Text("\(saved.currencyShort(currency)) / \(goal.target.currencyShort(currency))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress.fraction)
                .tint(progress.isReached ? Color.green : (progress.isOverdue ? Color.red : Color.accentColor))
            Text(detail(progress))
                .font(.caption)
                .foregroundStyle(progress.isOverdue ? Color.red : Color.secondary)
        }
        .padding(.vertical, 2)
    }

    private func detail(_ p: SavingsProgress) -> String {
        if p.isReached { return "Goal reached 🎉" }
        if p.isOverdue { return "Deadline passed · \(p.remaining.currencyShort(currency)) missing" }
        if let monthly = p.monthlyNeeded, let months = p.monthsLeft, let deadline = goal.deadline {
            return "\(monthly.currency(currency)) per month for \(months) month(s) · by \(deadline.formatted(.dateTime.month(.abbreviated).year()))"
        }
        return "\(p.remaining.currencyShort(currency)) to go"
    }
}

struct SavingsGoalDetailView: View {
    let family: Family
    let goal: SavingsGoal

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var contributions: [SavingsContribution]
    @Query private var members: [FamilyMember]
    @State private var showAdd = false
    @State private var withdraw = false
    @State private var showEdit = false

    init(family: Family, goal: SavingsGoal) {
        self.family = family
        self.goal = goal
        let gid = goal.id
        let fid = family.id
        _contributions = Query(filter: #Predicate<SavingsContribution> { $0.goalID == gid }, sort: \SavingsContribution.date, order: .reverse)
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid })
    }

    private var saved: Decimal { contributions.reduce(Decimal(0)) { $0 + $1.amount } }
    private var currency: String { family.baseCurrencyCode }

    var body: some View {
        List {
            Section {
                SavingsGoalRow(goal: goal, saved: saved, currency: currency)
                HStack {
                    Button {
                        withdraw = false
                        showAdd = true
                    } label: {
                        Label("Add money", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Button {
                        withdraw = true
                        showAdd = true
                    } label: {
                        Label("Take out", systemImage: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(saved <= 0)
                }
            } footer: {
                Text(LocalizedStringKey(goal.reserveInSafeToSpend
                     ? "The monthly amount is reserved in Safe to spend until it is saved."
                     : "Not reserved in Safe to spend."))
            }

            Section("History") {
                if contributions.isEmpty {
                    Text("Nothing saved yet.").foregroundStyle(.secondary)
                }
                ForEach(contributions) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                            let who = members.first { $0.id == entry.memberID }?.displayName
                            let line = [who, entry.note.isEmpty ? nil : entry.note].compactMap { $0 }.joined(separator: " · ")
                            if !line.isEmpty {
                                Text(line).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(entry.amount.currency(currency))
                            .monospacedDigit()
                            .foregroundStyle(entry.amount < 0 ? Color.red : Color.primary)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(contributions[index]) }
                    try? context.save()
                }
            }
        }
        .navigationTitle(goal.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                ContributionForm(family: family, goal: goal, withdraw: withdraw)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                SavingsGoalForm(family: family, editing: goal)
            }
        }
    }
}

struct SavingsGoalForm: View {
    let family: Family
    private let editing: SavingsGoal?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: String
    @State private var targetText: String
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var reserve: Bool
    @State private var archived: Bool
    @State private var message: String?

    static let icons = ["star.fill", "airplane", "car.fill", "house.fill", "gift.fill", "graduationcap.fill", "cross.case.fill", "umbrella.fill", "bicycle", "pawprint.fill"]

    init(family: Family, editing: SavingsGoal?) {
        self.family = family
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _icon = State(initialValue: editing?.icon ?? "star.fill")
        _targetText = State(initialValue: editing.map { "\($0.target)" } ?? "")
        _hasDeadline = State(initialValue: editing?.deadline != nil || editing == nil)
        let defaultDeadline = FamiloqCalendar.make().date(byAdding: .month, value: 12, to: Date()) ?? Date()
        _deadline = State(initialValue: editing?.deadline ?? defaultDeadline)
        _reserve = State(initialValue: editing?.reserveInSafeToSpend ?? true)
        _archived = State(initialValue: editing?.isArchived ?? false)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name, e.g. Holiday 2027", text: $name)
                HStack {
                    TextField("Target amount", text: $targetText)
                        .keyboardType(.decimalPad)
                        .font(.title3.weight(.semibold).monospacedDigit())
                    Text(family.baseCurrencyCode).font(.headline).foregroundStyle(.secondary)
                }
            }
            Section("Symbol") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Self.icons, id: \.self) { symbol in
                            Button {
                                icon = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .frame(width: 40, height: 40)
                                    .background(icon == symbol ? Color.accentColor.opacity(0.25) : Color.clear, in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                Toggle("Deadline", isOn: $hasDeadline)
                if hasDeadline {
                    DatePicker("Reach it by", selection: $deadline, in: Date()..., displayedComponents: [.date])
                }
                Toggle("Reserve in Safe to spend", isOn: $reserve)
                if editing != nil {
                    Toggle("Archived", isOn: $archived)
                }
            } footer: {
                Text("With a deadline Familoq works out how much to put aside each month. Reserved amounts lower Safe to spend until they are saved.")
            }
            if let message {
                Section { Text(LocalizedStringKey(message)).foregroundStyle(.red) }
            }
        }
        .navigationTitle(editing == nil ? "New savings goal" : "Edit goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold) }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { message = "Enter a name."; return }
        guard let target = DecimalParser.parse(targetText), target > 0 else { message = "Enter the target amount."; return }
        let goal = editing ?? {
            let new = SavingsGoal(familyID: family.id, name: trimmed, target: target, deadline: nil)
            context.insert(new)
            return new
        }()
        goal.name = trimmed
        goal.icon = icon
        goal.target = target
        goal.deadline = hasDeadline ? deadline : nil
        goal.reserveInSafeToSpend = reserve
        goal.isArchived = archived
        goal.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}

private struct ContributionForm: View {
    let family: Family
    let goal: SavingsGoal
    let withdraw: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("0,00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold).monospacedDigit())
                    Text(family.baseCurrencyCode).font(.headline).foregroundStyle(.secondary)
                }
                DatePicker("Date", selection: $date, displayedComponents: [.date])
                TextField("Note (optional)", text: $note)
            }
        }
        .navigationTitle(withdraw ? "Take out" : "Add money")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let value = DecimalParser.parse(amountText), value > 0 else { return }
                    let entry = SavingsContribution(familyID: family.id, goalID: goal.id, amount: withdraw ? -value : value,
                                                    date: date, memberID: session.currentMember?.id)
                    entry.note = note
                    context.insert(entry)
                    try? context.save()
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }
}
