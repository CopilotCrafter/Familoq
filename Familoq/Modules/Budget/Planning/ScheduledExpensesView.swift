import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqBudget

/// Recurring bills and planned one-offs of the family.
struct ScheduledExpensesView: View {
    let family: Family

    @Environment(\.modelContext) private var context
    @Query private var schedules: [ScheduledExpense]
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @State private var editing: ScheduledExpense?
    @State private var creatingPlanned: Bool?

    init(family: Family) {
        self.family = family
        let fid = family.id
        _schedules = Query(filter: #Predicate<ScheduledExpense> { $0.familyID == fid }, sort: \ScheduledExpense.startDate)
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid }, sort: \ExpenseCategory.sortOrder)
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid }, sort: \ExpenseSubcategory.sortOrder)
    }

    private var lookup: CategoryLookup { CategoryLookup(categories: categories, subcategories: subcategories) }
    private var recurring: [ScheduledExpense] { schedules.filter { $0.isActive && !$0.isPlanned } }
    private var planned: [ScheduledExpense] {
        schedules.filter { $0.isActive && $0.isPlanned && $0.bookedThrough == nil }
    }
    private var inactive: [ScheduledExpense] {
        schedules.filter { !$0.isActive || ($0.isPlanned && $0.bookedThrough != nil) }
    }

    private var monthlyTotal: Decimal {
        recurring.reduce(Decimal(0)) { total, s in
            total + PlanningService.approximateInBase(s.amount, currency: s.currencyCode, base: family.baseCurrencyCode, context: context) * s.frequency.perMonth
        }
    }

    var body: some View {
        List {
            Section {
                if recurring.isEmpty {
                    Text("Rent, insurance, phone, subscriptions … enter them once and Familoq books them on the due date.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(recurring) { row($0) }
                    .onDelete { delete($0, from: recurring) }
                Button {
                    creatingPlanned = false
                } label: {
                    Label("Add recurring expense", systemImage: "repeat")
                }
            } header: {
                Text("Recurring")
            } footer: {
                if !recurring.isEmpty {
                    Text("About \(monthlyTotal.currency(family.baseCurrencyCode)) per month.")
                }
            }

            Section {
                if planned.isEmpty {
                    Text("Known future costs, e.g. car service in November. They are reserved in Safe to spend in their month.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(planned) { row($0) }
                    .onDelete { delete($0, from: planned) }
                Button {
                    creatingPlanned = true
                } label: {
                    Label("Add planned expense", systemImage: "calendar.badge.plus")
                }
            } header: {
                Text("Planned")
            }

            if !inactive.isEmpty {
                Section("Paused or done") {
                    ForEach(inactive) { row($0) }
                        .onDelete { delete($0, from: inactive) }
                }
            }
        }
        .navigationTitle("Recurring & planned")
        .sheet(item: $editing) { schedule in
            NavigationStack {
                ScheduledExpenseForm(family: family, lookup: lookup, editing: schedule, planned: schedule.isPlanned)
            }
        }
        .sheet(isPresented: Binding(get: { creatingPlanned != nil }, set: { if !$0 { creatingPlanned = nil } })) {
            NavigationStack {
                ScheduledExpenseForm(family: family, lookup: lookup, editing: nil, planned: creatingPlanned ?? false)
            }
        }
    }

    private func row(_ schedule: ScheduledExpense) -> some View {
        Button {
            editing = schedule
        } label: {
            HStack(spacing: 12) {
                let category = lookup.category(schedule.categoryID)
                CategoryIcon(icon: category?.icon ?? "calendar", colorHex: category?.colorHex ?? "#9E9E9E", size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(schedule.title.isEmpty ? String(localized: "Untitled") : schedule.title)
                        .foregroundStyle(.primary)
                    Text(subtitle(schedule))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(schedule.amount.currency(schedule.currencyCode))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
    }

    private func subtitle(_ schedule: ScheduledExpense) -> String {
        if schedule.isPlanned {
            return schedule.bookedThrough == nil
                ? "Due \(schedule.startDate.formatted(date: .abbreviated, time: .omitted))"
                : "Booked \(schedule.startDate.formatted(date: .abbreviated, time: .omitted))"
        }
        let next = PlanningService.upcoming([schedule], now: Date(), until: Date().addingTimeInterval(400 * 86_400)).first?.date
        let nextText = next.map { " · next \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
        return schedule.frequency.displayName + (schedule.isActive ? nextText : " · paused")
    }

    private func delete(_ offsets: IndexSet, from list: [ScheduledExpense]) {
        for index in offsets { context.delete(list[index]) }
        try? context.save()
    }
}

/// Add / edit a recurring or planned expense.
struct ScheduledExpenseForm: View {
    let family: Family
    let lookup: CategoryLookup
    private let editing: ScheduledExpense?
    private let planned: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var rates: ExchangeRateService
    @Query private var members: [FamilyMember]

    @State private var title: String
    @State private var amountText: String
    @State private var currencyCode: String
    @State private var categoryID: UUID?
    @State private var subcategoryID: UUID?
    @State private var memberID: UUID?
    @State private var paymentMethod: PaymentMethod
    @State private var note: String
    @State private var frequency: RecurrenceFrequency
    @State private var startDate: Date
    @State private var hasEnd: Bool
    @State private var endDate: Date
    @State private var isActive: Bool
    @State private var message: String?

    init(family: Family, lookup: CategoryLookup, editing: ScheduledExpense?, planned: Bool) {
        self.family = family
        self.lookup = lookup
        self.editing = editing
        self.planned = planned
        let fid = family.id
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid && $0.isActive == true }, sort: \FamilyMember.joinedAt)
        let calendar = FamiloqCalendar.make()
        let defaultStart = calendar.startOfDay(for: Date())
        _title = State(initialValue: editing?.title ?? "")
        _amountText = State(initialValue: editing.map { "\($0.amount)" } ?? "")
        _currencyCode = State(initialValue: editing?.currencyCode ?? family.baseCurrencyCode)
        _categoryID = State(initialValue: editing?.categoryID)
        _subcategoryID = State(initialValue: editing?.subcategoryID)
        _memberID = State(initialValue: editing?.memberID)
        _paymentMethod = State(initialValue: editing.flatMap { PaymentMethod(rawValue: $0.paymentMethodRaw) } ?? .bankTransfer)
        _note = State(initialValue: editing?.note ?? "")
        _frequency = State(initialValue: editing?.frequency ?? (planned ? .once : .monthly))
        _startDate = State(initialValue: editing?.startDate ?? defaultStart)
        _hasEnd = State(initialValue: editing?.endDate != nil)
        _endDate = State(initialValue: editing?.endDate ?? calendar.date(byAdding: .year, value: 1, to: defaultStart) ?? defaultStart)
        _isActive = State(initialValue: editing?.isActive ?? true)
    }

    private var isPlanned: Bool { frequency == .once }

    var body: some View {
        Form {
            Section {
                TextField(isPlanned ? "What, e.g. Car service" : "What, e.g. Rent", text: $title)
                    .textInputAutocapitalization(.sentences)
                HStack {
                    TextField("0,00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.title3.weight(.semibold).monospacedDigit())
                    NavigationLink {
                        CurrencyPickerView(selection: $currencyCode)
                    } label: {
                        Text(currencyCode).font(.headline)
                    }
                    .fixedSize()
                }
            }

            Section {
                Picker("Repeats", selection: $frequency) {
                    ForEach(RecurrenceFrequency.allCases, id: \.self) { Text(LocalizedStringKey($0.displayName)).tag($0) }
                }
                DatePicker(isPlanned ? "Due on" : "First due date", selection: $startDate, displayedComponents: [.date])
                if !isPlanned {
                    Toggle("Ends", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("Last due date", selection: $endDate, in: startDate..., displayedComponents: [.date])
                    }
                }
            } footer: {
                Text(LocalizedStringKey(isPlanned
                     ? "On the due date Familoq adds it as an expense. Until then it is reserved in Safe to spend for its month."
                     : "Each due date is added as an expense automatically (for the whole family). Upcoming dates this month are reserved in Safe to spend."))
            }

            Section("Category") {
                Picker("Category", selection: $categoryID) {
                    Text("Choose…").tag(UUID?.none)
                    ForEach(lookup.activeCategories()) { Label($0.name, systemImage: $0.icon).tag(Optional($0.id)) }
                }
                Picker("Subcategory", selection: $subcategoryID) {
                    Text("None").tag(UUID?.none)
                    ForEach(lookup.activeSubcategories(of: categoryID)) { Text($0.name).tag(Optional($0.id)) }
                }
            }

            Section("More") {
                Picker("Member", selection: $memberID) {
                    Text("Family").tag(UUID?.none)
                    ForEach(members) { Text(LocalizedStringKey($0.displayName)).tag(Optional($0.id)) }
                }
                Picker("Payment", selection: $paymentMethod) {
                    ForEach(PaymentMethod.allCases) { Text(LocalizedStringKey($0.displayName)).tag($0) }
                }
                TextField("Note", text: $note)
                if editing != nil {
                    Toggle("Active", isOn: $isActive)
                }
            }

            if let message {
                Section { Text(LocalizedStringKey(message)).foregroundStyle(.red) }
            }
        }
        .navigationTitle(editing == nil ? (planned ? "Planned expense" : "Recurring expense") : "Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.fontWeight(.semibold)
            }
        }
        .onChange(of: categoryID) { _, newValue in
            if !lookup.activeSubcategories(of: newValue).contains(where: { $0.id == subcategoryID }) {
                subcategoryID = nil
            }
        }
    }

    private func save() {
        message = nil
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { message = "Enter what it is for."; return }
        guard let amount = DecimalParser.parse(amountText), amount > 0 else { message = "Enter the amount."; return }
        let schedule = editing ?? {
            let new = ScheduledExpense(familyID: family.id, title: name, amount: amount, currencyCode: currencyCode, frequency: frequency, startDate: startDate)
            new.createdByMemberID = session.currentMember?.id
            context.insert(new)
            return new
        }()
        // Changing when it is due starts the booking afresh from the new date.
        if schedule.startDate != startDate || schedule.frequency != frequency {
            schedule.bookedThrough = nil
        }
        schedule.title = name
        schedule.amount = amount
        schedule.currencyCode = CurrencyInfo.normalize(currencyCode)
        schedule.frequency = frequency
        schedule.startDate = startDate
        schedule.endDate = (!isPlanned && hasEnd) ? endDate : nil
        schedule.categoryID = categoryID
        schedule.subcategoryID = subcategoryID
        schedule.memberID = memberID
        schedule.paymentMethodRaw = paymentMethod.rawValue
        schedule.note = note
        schedule.isActive = isActive
        schedule.updatedAt = Date()
        try? context.save()
        // Due already (e.g. rent that was due on the 1st)? Book it now.
        let booked = PlanningService.bookDue(familyID: family.id, baseCurrency: family.baseCurrencyCode, context: context)
        if !booked.isEmpty {
            let base = family.baseCurrencyCode
            Task { for expense in booked { await rates.convert(expense, baseCurrency: base, context: context) } }
        }
        dismiss()
    }
}
