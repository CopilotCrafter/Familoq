import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqBudget
import FamiloqPlanner

/// Planner → Travel: trips with budget, shared costs (who owes whom),
/// packing list, calendar entry and time off.
struct TravelScreen: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @Query private var trips: [Trip]
    @Query private var expenses: [Expense]
    @State private var editing: TripEditTarget?
    @State private var showPast = false
    @State private var deleting: Trip?

    init(family: Family) {
        self.family = family
        let fid = family.id
        _trips = Query(filter: #Predicate<Trip> { $0.familyID == fid }, sort: \Trip.startDate)
        _expenses = Query(filter: #Predicate<Expense> { $0.familyID == fid && $0.tripID != nil })
    }

    var body: some View {
        let today = PlannerDates.calendar.startOfDay(for: Date())
        let upcoming = trips.filter { $0.endDate >= today && !$0.isArchived }
        let past = trips.filter { $0.endDate < today || $0.isArchived }.reversed()
        List {
            Section {
                Button {
                    editing = TripEditTarget(trip: nil)
                } label: {
                    Label("New trip", systemImage: "plus")
                }
            } footer: {
                if trips.isEmpty {
                    Text("Plan a trip: budget, costs shared with friends, packing list, calendar entry and time off in one place.")
                }
            }
            if !upcoming.isEmpty {
                Section("Upcoming") {
                    ForEach(upcoming) { trip in link(trip) }
                }
            }
            if !past.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showPast) {
                        ForEach(Array(past)) { trip in link(trip) }
                    } label: {
                        Text("Past trips (\(past.count))")
                    }
                }
            }
        }
        .sheet(item: $editing) { target in
            TripForm(family: family, target: target)
        }
        .confirmationDialog("Delete this trip?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let trip = deleting { TripService.delete(trip, context: context) }
                deleting = nil
            }
        } message: {
            Text("Trip expenses stay in the budget.")
        }
    }

    private func link(_ trip: Trip) -> some View {
        let spent = expenses.filter { $0.tripID == trip.id }.compactMap(\.baseAmount).reduce(0, +)
        return NavigationLink {
            LazyView(TripDetailView(family: family, trip: trip))
        } label: {
            HStack {
                Image(systemName: "airplane").foregroundStyle(.teal).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: trip.name).font(.body.weight(.medium))
                    Text(verbatim: TravelFormat.range(trip) + (trip.destination.isEmpty ? "" : " · " + trip.destination))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if spent > 0 {
                    Text(spent.currency(family.baseCurrencyCode)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions {
            Button("Delete", role: .destructive) { deleting = trip }
            Button("Edit") { editing = TripEditTarget(trip: trip) }.tint(.blue)
        }
    }
}

enum TravelFormat {
    static func range(_ trip: Trip) -> String {
        let calendar = PlannerDates.calendar
        if calendar.isDate(trip.startDate, inSameDayAs: trip.endDate) {
            return trip.startDate.formatted(date: .abbreviated, time: .omitted)
        }
        return trip.startDate.formatted(.dateTime.day().month(.abbreviated)) + " – " + trip.endDate.formatted(date: .abbreviated, time: .omitted)
    }

    /// Display name for a participant key (member UUID or "guest:Name").
    static func name(_ key: String, members: [FamilyMember]) -> String {
        if key.hasPrefix("guest:") { return String(key.dropFirst(6)) }
        return members.first { $0.id.uuidString == key }?.displayName ?? String(localized: "Former member")
    }
}

struct TripEditTarget: Identifiable {
    let id = UUID()
    let trip: Trip?
}

// MARK: - Trip form

struct TripForm: View {
    let family: Family
    let target: TripEditTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var members: [FamilyMember]
    @State private var name: String
    @State private var destination: String
    @State private var start: Date
    @State private var end: Date
    @State private var currencyCode: String
    @State private var budgetText: String
    @State private var participants: Set<UUID>
    @State private var guestsText: String
    @State private var addToCalendar: Bool

    init(family: Family, target: TripEditTarget) {
        self.family = family
        self.target = target
        let fid = family.id
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid && $0.isActive == true }, sort: \FamilyMember.joinedAt)
        let t = target.trip
        let calendar = PlannerDates.calendar
        let defaultStart = calendar.date(byAdding: .day, value: 14, to: calendar.startOfDay(for: Date())) ?? Date()
        _name = State(initialValue: t?.name ?? "")
        _destination = State(initialValue: t?.destination ?? "")
        _start = State(initialValue: t?.startDate ?? defaultStart)
        _end = State(initialValue: t?.endDate ?? (calendar.date(byAdding: .day, value: 6, to: defaultStart) ?? defaultStart))
        _currencyCode = State(initialValue: t?.currencyCode ?? family.baseCurrencyCode)
        _budgetText = State(initialValue: t.map { $0.budget > 0 ? "\($0.budget)" : "" } ?? "")
        _participants = State(initialValue: t?.participants ?? [])
        _guestsText = State(initialValue: t?.guestsRaw ?? "")
        _addToCalendar = State(initialValue: t == nil || t?.eventID != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Summer holiday", text: $name)
                    TextField("Destination", text: $destination)
                    DatePicker("From", selection: $start, displayedComponents: [.date])
                    DatePicker("To", selection: $end, in: start..., displayedComponents: [.date])
                }
                Section {
                    HStack {
                        TextField("Budget (optional)", text: $budgetText).keyboardType(.decimalPad)
                        Picker("Currency", selection: $currencyCode) {
                            ForEach(CurrencyNames.allCodes.prefix(40), id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }
                } footer: {
                    Text("The currency is suggested for new trip expenses. Everything is also converted to \(family.baseCurrencyCode) for the budget.")
                }
                Section {
                    ForEach(members) { member in
                        Toggle(isOn: Binding(get: { participants.contains(member.id) }, set: { on in
                            if on { participants.insert(member.id) } else { participants.remove(member.id) }
                        })) {
                            Text(verbatim: member.displayName)
                        }
                    }
                    TextField("Friends travelling with you (one name per line)", text: $guestsText, axis: .vertical).lineLimit(1...6)
                } header: {
                    Text("Who is coming")
                } footer: {
                    Text("Friends don't need the app. Their share is shown in Settle up.")
                }
                Section {
                    Toggle("Show in the family calendar", isOn: $addToCalendar)
                }
            }
            .navigationTitle(target.trip == nil ? LocalizedStringKey("New trip") : LocalizedStringKey("Trip"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if target.trip == nil && participants.isEmpty {
                    participants = Set(members.map(\.id))
                }
            }
        }
    }

    private func save() {
        let calendar = PlannerDates.calendar
        let trip: Trip
        if let existing = target.trip {
            trip = existing
        } else {
            trip = Trip(familyID: family.id, name: "", startDate: start, endDate: end, currencyCode: currencyCode)
            context.insert(trip)
        }
        trip.name = name.trimmingCharacters(in: .whitespaces)
        trip.destination = destination.trimmingCharacters(in: .whitespaces)
        trip.startDate = calendar.startOfDay(for: start)
        trip.endDate = calendar.startOfDay(for: max(start, end))
        trip.currencyCode = currencyCode
        trip.budget = DecimalParser.parse(budgetText) ?? 0
        trip.participants = participants
        trip.guests = guestsText.split(whereSeparator: \.isNewline).map(String.init)
        trip.updatedAt = Date()
        syncEvent(trip)
        try? context.save()
        Task { await PlannerNotifications.reschedule(context: context) }
        dismiss()
    }

    /// Keeps the all-day calendar entry of the trip in step.
    private func syncEvent(_ trip: Trip) {
        let calendar = PlannerDates.calendar
        var event: FamilyEvent?
        if let eventID = trip.eventID {
            var d = FetchDescriptor<FamilyEvent>(predicate: #Predicate { $0.id == eventID })
            d.fetchLimit = 1
            event = try? context.fetch(d).first
        }
        guard addToCalendar else {
            if let event { context.delete(event) }
            trip.eventID = nil
            return
        }
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: trip.endDate) ?? trip.endDate
        let target: FamilyEvent
        if let event {
            target = event
        } else {
            target = FamilyEvent(familyID: family.id, title: trip.name, start: trip.startDate, end: endExclusive, isAllDay: true)
            context.insert(target)
            trip.eventID = target.id
        }
        target.title = trip.name
        target.location = trip.destination
        target.start = trip.startDate
        target.end = endExclusive
        target.isAllDay = true
        target.kind = .trip
        target.participants = trip.participants
        target.updatedAt = Date()
    }

}

enum TripService {
    /// Deletes a trip with its calendar entry and packing list. Trip
    /// expenses stay in the budget.
    @MainActor
    static func delete(_ trip: Trip, context: ModelContext) {
        let tid = trip.id
        if let eventID = trip.eventID {
            let events = (try? context.fetch(FetchDescriptor<FamilyEvent>(predicate: #Predicate { $0.id == eventID }))) ?? []
            events.forEach { context.delete($0) }
        }
        let items = (try? context.fetch(FetchDescriptor<PackingItem>(predicate: #Predicate { $0.tripID == tid }))) ?? []
        items.forEach { context.delete($0) }
        let optionalID: UUID? = tid
        let linked = (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.tripID == optionalID }))) ?? []
        for expense in linked {
            expense.tripID = nil
            expense.tripPaidBy = ""
            expense.tripSplit = ""
            expense.updatedAt = Date()
        }
        context.delete(trip)
        try? context.save()
        Task { await PlannerNotifications.reschedule(context: context) }
    }
}

// MARK: - Trip detail

struct TripDetailView: View {
    let family: Family
    let trip: Trip
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var expenses: [Expense]
    @Query private var packing: [PackingItem]
    @Query private var members: [FamilyMember]
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @State private var editingTrip: TripEditTarget?
    @State private var expenseTarget: TripExpenseTarget?
    @State private var leaveTarget: LeaveEditTarget?
    @State private var newItem = ""
    @State private var hidePacked = false

    init(family: Family, trip: Trip) {
        self.family = family
        self.trip = trip
        let fid = family.id
        let tid: UUID? = trip.id
        let packTID = trip.id
        _expenses = Query(filter: #Predicate<Expense> { $0.familyID == fid && $0.tripID == tid }, sort: \Expense.date, order: .reverse)
        _packing = Query(filter: #Predicate<PackingItem> { $0.tripID == packTID }, sort: \PackingItem.sortOrder)
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid }, sort: \FamilyMember.joinedAt)
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid }, sort: \ExpenseCategory.sortOrder)
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid }, sort: \ExpenseSubcategory.sortOrder)
    }

    private var base: String { family.baseCurrencyCode }
    private var keys: [String] { trip.participantKeys }

    var body: some View {
        List {
            overviewSection
            expensesSection
            settleSection
            packingSection
            Section {
                Button {
                    leaveTarget = LeaveEditTarget(entry: nil, day: trip.startDate, lastDay: trip.endDate)
                } label: {
                    Label("Add time off for this trip", systemImage: "sun.max")
                }
            }
        }
        .navigationTitle(trip.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editingTrip = TripEditTarget(trip: trip) }
            }
        }
        .sheet(item: $editingTrip) { target in
            TripForm(family: family, target: target)
        }
        .sheet(item: $expenseTarget) { target in
            TripExpenseForm(family: family, trip: trip, target: target, members: members,
                            lookup: CategoryLookup(categories: categories, subcategories: subcategories))
        }
        .sheet(item: $leaveTarget) { target in
            LeaveForm(family: family, target: target, members: members)
        }
    }

    // MARK: Overview

    /// Spent in the trip currency: direct amounts, or the base amounts
    /// converted with the rate seen on this trip's expenses.
    private var spentInTripCurrency: Decimal? {
        let direct = expenses.filter { $0.currencyCode == trip.currencyCode }
        if trip.currencyCode == base {
            return expenses.compactMap(\.baseAmount).reduce(0, +)
        }
        let withBase = direct.filter { ($0.baseAmount ?? 0) > 0 }
        let sumTrip = withBase.map(\.amount).reduce(0, +)
        let sumBase = withBase.compactMap(\.baseAmount).reduce(0, +)
        if direct.count == expenses.count { return direct.map(\.amount).reduce(0, +) }
        guard sumBase > 0 else { return nil }
        let rate = sumTrip / sumBase
        let others = expenses.filter { $0.currencyCode != trip.currencyCode }.compactMap(\.baseAmount).reduce(0, +)
        return (direct.map(\.amount).reduce(0, +) + others * rate).rounded(scale: 2)
    }

    private var overviewSection: some View {
        let totalBase = expenses.compactMap(\.baseAmount).reduce(0, +)
        let days = (PlannerDates.calendar.dateComponents([.day], from: trip.startDate, to: trip.endDate).day ?? 0) + 1
        return Section {
            LabeledContent("When", value: TravelFormat.range(trip))
            if !trip.destination.isEmpty {
                LabeledContent("Where", value: trip.destination)
            }
            LabeledContent {
                Text(totalBase.currency(base)).monospacedDigit()
            } label: {
                Text("Spent")
            }
            if days > 0, totalBase > 0 {
                LabeledContent {
                    Text((totalBase / Decimal(days)).rounded(scale: 2).currency(base)).monospacedDigit()
                } label: {
                    Text("Per day")
                }
            }
            if trip.budget > 0 {
                if let spent = spentInTripCurrency {
                    let ratio = min(1, NSDecimalNumber(decimal: spent / trip.budget).doubleValue)
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: ratio)
                            .tint(spent > trip.budget ? .red : (ratio > 0.8 ? .orange : .green))
                        Text("\(spent.currency(trip.currencyCode)) of \(trip.budget.currency(trip.currencyCode))")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        if spent <= trip.budget {
                            Text("\((trip.budget - spent).currency(trip.currencyCode)) left")
                                .font(.caption).foregroundStyle(.green)
                        } else {
                            Text("\((spent - trip.budget).currency(trip.currencyCode)) over budget")
                                .font(.caption).foregroundStyle(.red)
                        }
                    }
                } else {
                    LabeledContent("Budget", value: trip.budget.currency(trip.currencyCode))
                }
            }
            let people = keys.map { TravelFormat.name($0, members: members) }
            if !people.isEmpty {
                Text(verbatim: people.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Expenses

    private var expensesSection: some View {
        Section {
            Button {
                expenseTarget = TripExpenseTarget(expense: nil)
            } label: {
                Label("Add trip expense", systemImage: "plus")
            }
            ForEach(expenses) { expense in
                Button {
                    expenseTarget = TripExpenseTarget(expense: expense)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: expense.merchant).foregroundStyle(.primary)
                            Text(verbatim: paidLine(expense)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(expense.amount.currency(expense.currencyCode)).monospacedDigit().foregroundStyle(.primary)
                            if expense.isForeignCurrency, let b = expense.baseAmount {
                                Text(b.currency(base)).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        context.delete(expense)
                        try? context.save()
                    }
                }
            }
        } header: {
            Text("Expenses (\(expenses.count))")
        } footer: {
            Text("Trip expenses are normal expenses: they also appear in the budget and reports.")
        }
    }

    private func paidLine(_ expense: Expense) -> String {
        let payer = expense.tripPaidBy.isEmpty ? "" : TravelFormat.name(expense.tripPaidBy, members: members)
        let split = expense.tripSplit.split(separator: ",").map(String.init)
        let date = expense.date.formatted(.dateTime.day().month(.abbreviated))
        var parts = [date]
        if !payer.isEmpty { parts.append(String(localized: "paid by \(payer)")) }
        if !split.isEmpty && split.count < keys.count {
            parts.append(String(localized: "for \(split.map { TravelFormat.name($0, members: members) }.joined(separator: ", "))"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Settle up

    @ViewBuilder
    private var settleSection: some View {
        if keys.count > 1 {
            let payments = expenses.compactMap { expense -> TripPayment? in
                guard !expense.tripPaidBy.isEmpty, let amount = expense.baseAmount else { return nil }
                let split = expense.tripSplit.split(separator: ",").map(String.init)
                return TripPayment(amount: amount, paidBy: expense.tripPaidBy, splitAmong: split)
            }
            let balances = TripSettlement.balances(payments, participants: keys)
            let transfers = TripSettlement.transfers(balances)
            Section {
                if payments.isEmpty {
                    Text("Add expenses with who paid to see who owes whom.").foregroundStyle(.secondary)
                } else if transfers.isEmpty {
                    Label("All settled", systemImage: "checkmark.circle").foregroundStyle(.green)
                } else {
                    ForEach(Array(transfers.enumerated()), id: \.offset) { _, transfer in
                        HStack {
                            Text(verbatim: TravelFormat.name(transfer.from, members: members))
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            Text(verbatim: TravelFormat.name(transfer.to, members: members))
                            Spacer()
                            Text(transfer.amount.currency(base)).monospacedDigit().fontWeight(.semibold)
                        }
                    }
                }
                if !payments.isEmpty {
                    DisclosureGroup("Balances") {
                        ForEach(keys, id: \.self) { key in
                            let value = balances[key] ?? 0
                            LabeledContent {
                                Text(value.currency(base)).monospacedDigit()
                                    .foregroundStyle(value < 0 ? .red : (value > 0 ? .green : .secondary))
                            } label: {
                                Text(verbatim: TravelFormat.name(key, members: members))
                            }
                        }
                    }
                    ShareLink(item: settleText(transfers)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("Settle up")
            } footer: {
                Text("In \(base). Plus = gets money back, minus = owes.")
            }
        }
    }

    private func settleText(_ transfers: [TripTransfer]) -> String {
        var lines = [trip.name + " – " + String(localized: "Settle up")]
        for t in transfers {
            lines.append("\(TravelFormat.name(t.from, members: members)) → \(TravelFormat.name(t.to, members: members)): \(t.amount.currency(base))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Packing

    private var packingSection: some View {
        let packed = packing.filter(\.isPacked).count
        let visible = hidePacked ? packing.filter { !$0.isPacked } : packing
        return Section {
            HStack {
                TextField("Add item", text: $newItem)
                    .onSubmit(addItem)
                    .submitLabel(.done)
                Button(action: addItem) { Image(systemName: "plus.circle.fill") }
                    .buttonStyle(.borderless)
                    .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if packing.isEmpty {
                Button {
                    addStandardItems()
                } label: {
                    Label("Add a basic packing list", systemImage: "list.bullet.clipboard")
                }
            }
            ForEach(visible) { item in
                Button {
                    item.isPacked.toggle()
                    item.updatedAt = Date()
                    try? context.save()
                } label: {
                    HStack {
                        Image(systemName: item.isPacked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isPacked ? Color.green : Color.secondary)
                        Text(verbatim: item.name)
                            .strikethrough(item.isPacked)
                            .foregroundStyle(item.isPacked ? Color.secondary : Color.primary)
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        context.delete(item)
                        try? context.save()
                    }
                }
            }
            if packed > 0 {
                Toggle("Hide packed", isOn: $hidePacked)
            }
        } header: {
            Text("Packing list (\(packed)/\(packing.count))")
        }
    }

    private func addItem() {
        let text = newItem.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        insertItem(text, order: (packing.map(\.sortOrder).max() ?? 0) + 1)
        newItem = ""
        try? context.save()
    }

    private func insertItem(_ name: String, order: Int) {
        let item = PackingItem(familyID: family.id, tripID: trip.id, name: name)
        item.sortOrder = order
        context.insert(item)
    }

    private func addStandardItems() {
        let items: [String.LocalizationValue] = [
            "Passports / ID cards", "Tickets & bookings", "Wallet & cards", "Phone chargers", "Medicines",
            "Toiletries", "Sunscreen", "Clothes", "Swimwear", "Snacks for the journey"
        ]
        for (index, key) in items.enumerated() {
            insertItem(String(localized: key), order: index + 1)
        }
        try? context.save()
    }
}

// MARK: - Trip expense form

struct TripExpenseTarget: Identifiable {
    let id = UUID()
    let expense: Expense?
}

struct TripExpenseForm: View {
    let family: Family
    let trip: Trip
    let target: TripExpenseTarget
    let members: [FamilyMember]
    let lookup: CategoryLookup
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var rates: ExchangeRateService
    @EnvironmentObject private var sync: SyncCoordinator
    @State private var what: String
    @State private var amountText: String
    @State private var currencyCode: String
    @State private var date: Date
    @State private var categoryID: UUID?
    @State private var paidBy: String
    @State private var splitAll: Bool
    @State private var split: Set<String>

    init(family: Family, trip: Trip, target: TripExpenseTarget, members: [FamilyMember], lookup: CategoryLookup) {
        self.family = family
        self.trip = trip
        self.target = target
        self.members = members
        self.lookup = lookup
        let e = target.expense
        _what = State(initialValue: e?.merchant ?? "")
        _amountText = State(initialValue: e.map { "\($0.amount)" } ?? "")
        _currencyCode = State(initialValue: e?.currencyCode ?? trip.currencyCode)
        let today = Date()
        let lastMoment: Date = PlannerDates.calendar.date(byAdding: .day, value: 1, to: trip.endDate) ?? trip.endDate
        var suggested: Date = today
        if today < trip.startDate { suggested = trip.startDate } else if today > lastMoment { suggested = trip.endDate }
        _date = State(initialValue: e?.date ?? suggested)
        _categoryID = State(initialValue: e?.categoryID ?? lookup.categories.first { $0.systemKey == "travel" }?.id)
        let keys = trip.participantKeys
        _paidBy = State(initialValue: e.map { $0.tripPaidBy.isEmpty ? keys.first ?? "" : $0.tripPaidBy } ?? "")
        let existingSplit = Set((e?.tripSplit ?? "").split(separator: ",").map(String.init))
        _splitAll = State(initialValue: existingSplit.isEmpty)
        _split = State(initialValue: existingSplit.isEmpty ? Set(keys) : existingSplit)
    }

    private var keys: [String] { trip.participantKeys }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What, e.g. Hotel, Dinner, Fuel", text: $what)
                    HStack {
                        TextField("Amount", text: $amountText).keyboardType(.decimalPad)
                        Picker("Currency", selection: $currencyCode) {
                            ForEach(currencyChoices, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                    Picker("Category", selection: $categoryID) {
                        Text("None").tag(UUID?.none)
                        ForEach(lookup.activeCategories()) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                    }
                } footer: {
                    if currencyCode != family.baseCurrencyCode {
                        Text("Converted to \(family.baseCurrencyCode) with the exchange rate of the day.")
                    }
                }
                if !keys.isEmpty {
                    Section {
                        Picker("Paid by", selection: $paidBy) {
                            ForEach(keys, id: \.self) { key in
                                Text(verbatim: TravelFormat.name(key, members: members)).tag(key)
                            }
                        }
                        Toggle("Split between everyone", isOn: $splitAll)
                        if !splitAll {
                            ForEach(keys, id: \.self) { key in
                                Toggle(isOn: Binding(get: { split.contains(key) }, set: { on in
                                    if on { split.insert(key) } else { split.remove(key) }
                                })) {
                                    Text(verbatim: TravelFormat.name(key, members: members))
                                }
                            }
                        }
                    } header: {
                        Text("Shared costs")
                    }
                }
            }
            .navigationTitle(target.expense == nil ? LocalizedStringKey("Trip expense") : LocalizedStringKey("Edit trip expense"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled((DecimalParser.parse(amountText) ?? 0) <= 0)
                }
            }
            .onAppear {
                if paidBy.isEmpty {
                    let mine = session.currentMember?.id.uuidString
                    paidBy = keys.first { $0 == mine } ?? keys.first ?? ""
                }
            }
        }
    }

    private var currencyChoices: [String] {
        var list = [trip.currencyCode, family.baseCurrencyCode]
        for code in CurrencyNames.allCodes.prefix(40) where !list.contains(code) { list.append(code) }
        if !list.contains(currencyCode) { list.append(currencyCode) }
        return list
    }

    private func save() {
        guard let amount = DecimalParser.parse(amountText), amount > 0 else { return }
        let base = family.baseCurrencyCode
        let expense: Expense
        if let existing = target.expense {
            expense = existing
        } else {
            expense = Expense(familyID: family.id, amount: amount, currencyCode: currencyCode, baseCurrencyCode: base, merchant: "", date: date)
            expense.createdByMemberID = session.currentMember?.id
            expense.entryMethod = .manual
            context.insert(expense)
        }
        let name = what.trimmingCharacters(in: .whitespaces)
        let newCode: String = CurrencyInfo.normalize(currencyCode)
        var changedMoney: Bool = target.expense == nil
        if expense.amount != amount { changedMoney = true }
        if expense.currencyCode != newCode { changedMoney = true }
        if !PlannerDates.calendar.isDate(expense.date, inSameDayAs: date) { changedMoney = true }
        expense.merchant = name.isEmpty ? trip.name : name
        expense.amount = amount
        expense.currencyCode = CurrencyInfo.normalize(currencyCode)
        expense.baseCurrencyCode = base
        expense.date = date
        if expense.categoryID != categoryID || target.expense == nil { expense.subcategoryID = nil }
        expense.categoryID = categoryID
        expense.tripID = trip.id
        expense.tripPaidBy = paidBy
        let chosen = keys.filter { split.contains($0) }
        expense.tripSplit = splitAll || chosen.count == keys.count ? "" : chosen.joined(separator: ",")
        // A family member who paid is also who the expense belongs to.
        if let member = UUID(uuidString: paidBy), members.contains(where: { $0.id == member }) {
            expense.memberID = member
        } else if expense.memberID == nil {
            expense.memberID = session.currentMember?.id
        }
        expense.updatedAt = Date()
        if changedMoney {
            expense.resetConversion()
        }
        try? context.save()
        if changedMoney && expense.isForeignCurrency {
            Task { await rates.convert(expense, baseCurrency: base, context: context) }
        }
        sync.scanNow()
        dismiss()
    }
}
