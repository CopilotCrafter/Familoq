import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqBudget

// MARK: - Fixed costs

@MainActor
enum FixedCostsService {
    /// Recurring expenses + contracts that do not book their payments
    /// through a recurring expense (no double counting). Base currency.
    static func items(familyID: UUID, baseCurrency: String, context: ModelContext) -> [FixedCostItem] {
        let fid = familyID
        let schedules = (try? context.fetch(FetchDescriptor<ScheduledExpense>(predicate: #Predicate { $0.familyID == fid && $0.isActive == true }))) ?? []
        let contracts = (try? context.fetch(FetchDescriptor<Contract>(predicate: #Predicate { $0.familyID == fid && $0.isCancelled == false }))) ?? []
        var items = schedules.filter { $0.frequency != .once }.map { s in
            FixedCostItem(id: "s-" + s.id.uuidString, title: s.title,
                          amount: PlanningService.approximateInBase(s.amount, currency: s.currencyCode, base: baseCurrency, context: context),
                          frequency: s.frequency, categoryID: s.categoryID, memberID: s.memberID)
        }
        for contract in contracts where contract.scheduledExpenseID == nil || !schedules.contains(where: { $0.id == contract.scheduledExpenseID }) {
            items.append(FixedCostItem(id: "c-" + contract.id.uuidString, title: contract.name,
                                       amount: PlanningService.approximateInBase(contract.amount, currency: contract.currencyCode, base: baseCurrency, context: context),
                                       frequency: contract.frequency, categoryID: contract.categoryID, memberID: contract.memberID))
        }
        return items
    }
}

/// Dashboard: fixed costs per month, next contract deadline, warranties
/// ending soon. Plain fetches (no @Query) so the dashboard stays calm.
struct FixedCostsSection: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var sync: SyncCoordinator
    @State private var perMonth: Decimal = 0
    @State private var itemCount = 0
    @State private var nextDeadline: (name: String, date: Date)?
    @State private var contractCount = 0
    @State private var warrantiesEnding = 0
    @State private var warrantyCount = 0

    var body: some View {
        Section {
            NavigationLink {
                LazyView(FixedCostsView(family: family))
            } label: {
                HStack {
                    Label("Fixed costs", systemImage: "calendar.badge.clock")
                    Spacer()
                    Text("\(perMonth.currency(family.baseCurrencyCode)) / month").monospacedDigit().foregroundStyle(.secondary)
                }
            }
            NavigationLink {
                LazyView(ContractsView(family: family))
            } label: {
                HStack {
                    Label("Contracts", systemImage: "doc.text.fill")
                    Spacer()
                    if let nextDeadline {
                        let days = PlannerDaysLeft.days(until: nextDeadline.date)
                        Text("\(nextDeadline.name): \(nextDeadline.date.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.caption)
                            .foregroundStyle(days <= 30 ? Color.red : Color.secondary)
                    } else {
                        Text("\(contractCount)").foregroundStyle(.secondary)
                    }
                }
            }
            NavigationLink {
                LazyView(WarrantiesView(family: family))
            } label: {
                HStack {
                    Label("Warranties", systemImage: "checkmark.shield.fill")
                    Spacer()
                    if warrantiesEnding > 0 {
                        Text("\(warrantiesEnding) ending soon").font(.caption).foregroundStyle(.orange)
                    } else {
                        Text("\(warrantyCount)").foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Fixed costs & contracts")
        }
        .task(id: sync.remoteChangeCount) { load() }
        .onAppear { load() }
    }

    private func load() {
        let calendar = FamiloqCalendar.make()
        let summary = FixedCosts.summary(FixedCostsService.items(familyID: family.id, baseCurrency: family.baseCurrencyCode, context: context))
        perMonth = summary.perMonth
        itemCount = summary.items.count
        let fid = family.id
        let contracts = (try? context.fetch(FetchDescriptor<Contract>(predicate: #Predicate { $0.familyID == fid && $0.isCancelled == false }))) ?? []
        contractCount = contracts.count
        nextDeadline = contracts.compactMap { c in ContractSchedule.next(c.terms, now: Date(), calendar: calendar).map { (c.name, $0.deadline) } }
            .min { $0.1 < $1.1 }
            .map { (name: $0.0, date: $0.1) }
        let warranties = (try? context.fetch(FetchDescriptor<Warranty>(predicate: #Predicate { $0.familyID == fid }))) ?? []
        warrantyCount = warranties.filter { WarrantyTerms.daysLeft(purchase: $0.purchaseDate, months: $0.months, now: Date(), calendar: calendar) >= 0 }.count
        warrantiesEnding = warranties.filter {
            let left = WarrantyTerms.daysLeft(purchase: $0.purchaseDate, months: $0.months, now: Date(), calendar: calendar)
            return left >= 0 && left <= 60
        }.count
    }
}

enum PlannerDaysLeft {
    static func days(until date: Date) -> Int {
        let calendar = FamiloqCalendar.make()
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
    }
}

struct FixedCostsView: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @Query private var members: [FamilyMember]
    @Query private var budgets: [Budget]
    @State private var summary: FixedCostSummary?

    init(family: Family) {
        self.family = family
        let fid = family.id
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid }, sort: \ExpenseCategory.sortOrder)
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid })
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid })
        _budgets = Query(filter: #Predicate<Budget> { $0.familyID == fid && $0.isActive == true })
    }

    private var currency: String { family.baseCurrencyCode }

    var body: some View {
        let lookup = CategoryLookup(categories: categories, subcategories: subcategories)
        List {
            if let summary {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.perMonth.currency(currency))
                            .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                        Text("per month · \(summary.perYear.currency(currency)) per year").font(.footnote).foregroundStyle(.secondary)
                        if let monthly = budgets.first(where: { $0.scope == .overall && $0.period == .monthly }), monthly.amount > 0 {
                            let share = NSDecimalNumber(decimal: summary.perMonth / monthly.amount * 100).doubleValue
                            Text("\(Int(share.rounded())) % of the monthly family budget (\(monthly.amount.currency(currency)))")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Recurring expenses and contracts. Yearly and quarterly payments are spread over the months; planned one-offs are not included.")
                }

                if !summary.byCategory.isEmpty {
                    Section("By category") {
                        ForEach(summary.byCategory.sorted { $0.value > $1.value }, id: \.key) { entry in
                            HStack {
                                let category = lookup.category(entry.key)
                                CategoryIcon(icon: category?.icon ?? "tag", colorHex: category?.colorHex ?? "#9E9E9E", size: 26)
                                Text(verbatim: category?.name ?? String(localized: "Uncategorized"))
                                Spacer()
                                Text(entry.value.currency(currency)).monospacedDigit()
                            }
                        }
                    }
                }

                if summary.byMember.count > 1 || summary.byMember.keys.contains(where: { $0 != nil }) {
                    Section("By person") {
                        ForEach(summary.byMember.sorted { $0.value > $1.value }, id: \.key) { entry in
                            HStack {
                                Text(verbatim: entry.key.flatMap { id in members.first { $0.id == id }?.displayName } ?? String(localized: "Family / not assigned"))
                                Spacer()
                                Text(entry.value.currency(currency)).monospacedDigit()
                            }
                        }
                    }
                }

                Section {
                    ForEach(summary.items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: item.title)
                                Text(LocalizedStringKey(item.frequency.displayName)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(item.perMonth.currency(currency)).monospacedDigit()
                                if item.frequency != .monthly {
                                    Text(item.amount.currency(currency)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("All fixed costs (per month)")
                }

                Section {
                    NavigationLink {
                        LazyView(ScheduledExpensesView(family: family))
                    } label: {
                        Label("Recurring expenses", systemImage: "repeat")
                    }
                    NavigationLink {
                        LazyView(ContractsView(family: family))
                    } label: {
                        Label("Contracts", systemImage: "doc.text.fill")
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Fixed costs")
        .task {
            summary = FixedCosts.summary(FixedCostsService.items(familyID: family.id, baseCurrency: family.baseCurrencyCode, context: context))
        }
    }
}

// MARK: - Contracts

struct ContractsView: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @Query private var contracts: [Contract]
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @State private var editing: ContractEditTarget?

    init(family: Family) {
        self.family = family
        let fid = family.id
        _contracts = Query(filter: #Predicate<Contract> { $0.familyID == fid }, sort: \Contract.name)
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid }, sort: \ExpenseCategory.sortOrder)
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid }, sort: \ExpenseSubcategory.sortOrder)
    }

    var body: some View {
        let calendar = FamiloqCalendar.make()
        let lookup = CategoryLookup(categories: categories, subcategories: subcategories)
        let active = contracts.filter { !$0.isCancelled }
            .map { (contract: $0, next: ContractSchedule.next($0.terms, now: Date(), calendar: calendar)) }
            .sorted { ($0.next?.deadline ?? .distantFuture) < ($1.next?.deadline ?? .distantFuture) }
        let cancelled = contracts.filter(\.isCancelled)
        List {
            if contracts.isEmpty {
                Section {
                    Text("Add insurance, phone, internet, streaming, gym or energy contracts. Familoq reminds you before the cancellation deadline, so nothing renews by accident.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if !active.isEmpty {
                Section("Active") {
                    ForEach(active, id: \.contract.id) { entry in
                        Button {
                            editing = ContractEditTarget(contract: entry.contract)
                        } label: {
                            row(entry.contract, next: entry.next, lookup: lookup)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !cancelled.isEmpty {
                Section("Cancelled") {
                    ForEach(cancelled) { contract in
                        Button {
                            editing = ContractEditTarget(contract: contract)
                        } label: {
                            row(contract, next: nil, lookup: lookup).opacity(0.6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Contracts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = ContractEditTarget(contract: nil) } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { target in
            ContractForm(family: family, target: target, lookup: lookup)
        }
    }

    private func row(_ contract: Contract, next: ContractDeadline?, lookup: CategoryLookup) -> some View {
        let category = lookup.category(contract.categoryID)
        return HStack(spacing: 12) {
            CategoryIcon(icon: category?.icon ?? "doc.text.fill", colorHex: category?.colorHex ?? "#546E7A", size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: contract.name).foregroundStyle(.primary)
                Text(verbatim: "\(contract.amount.currency(contract.currencyCode)) · \(String(localized: String.LocalizationValue(contract.frequency.displayName)))")
                    .font(.caption).foregroundStyle(.secondary)
                if let next {
                    let days = PlannerDaysLeft.days(until: next.deadline)
                    Text("Cancel by \(next.deadline.formatted(date: .abbreviated, time: .omitted)) (\(days) days)")
                        .font(.caption)
                        .foregroundStyle(days <= 30 ? Color.red : Color.secondary)
                } else if contract.isCancelled, let on = contract.cancelledOn {
                    Text("Cancelled on \(on.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

struct ContractEditTarget: Identifiable {
    let id = UUID()
    let contract: Contract?
    /// New car contract (insurance, tax) from the car screen.
    var carID: UUID? = nil
    var carCost: CarCostKind? = nil
}

struct ContractForm: View {
    let family: Family
    let target: ContractEditTarget
    let lookup: CategoryLookup
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @State private var name: String
    @State private var provider: String
    @State private var amountText: String
    @State private var currencyCode: String
    @State private var frequency: RecurrenceFrequency
    @State private var categoryID: UUID?
    @State private var subcategoryID: UUID?
    @State private var startDate: Date
    @State private var minimumTerm: Int
    @State private var renewal: Int
    @State private var noticeValue: Int
    @State private var noticeUnit: NoticeUnit
    @State private var remind30: Bool
    @State private var remind14: Bool
    @State private var remind7: Bool
    @State private var customerNumber: String
    @State private var note: String
    @State private var bookPayments: Bool
    @State private var isCancelled: Bool
    @State private var cancelledOn: Date
    @State private var confirmDelete = false
    @State private var carID: UUID?
    @State private var carCost: CarCostKind
    @Query private var cars: [Car]

    init(family: Family, target: ContractEditTarget, lookup: CategoryLookup) {
        self.family = family
        self.target = target
        self.lookup = lookup
        let c = target.contract
        _name = State(initialValue: c?.name ?? "")
        _provider = State(initialValue: c?.provider ?? "")
        _amountText = State(initialValue: c.map { "\($0.amount)" } ?? "")
        _currencyCode = State(initialValue: c?.currencyCode ?? family.baseCurrencyCode)
        _frequency = State(initialValue: c?.frequency ?? .monthly)
        let insurance = lookup.categories.first { $0.systemKey == "subscriptions" }?.id
        _categoryID = State(initialValue: c?.categoryID ?? insurance)
        _subcategoryID = State(initialValue: c?.subcategoryID)
        _startDate = State(initialValue: c?.startDate ?? Date())
        _minimumTerm = State(initialValue: c?.minimumTermMonths ?? 12)
        _renewal = State(initialValue: c?.renewalMonths ?? 1)
        _noticeValue = State(initialValue: c?.noticeValue ?? 1)
        _noticeUnit = State(initialValue: c?.noticeUnit ?? .months)
        let days = Set(c?.reminderDays ?? [30, 7])
        _remind30 = State(initialValue: days.contains(30))
        _remind14 = State(initialValue: days.contains(14))
        _remind7 = State(initialValue: days.contains(7))
        _customerNumber = State(initialValue: c?.customerNumber ?? "")
        _note = State(initialValue: c?.note ?? "")
        _bookPayments = State(initialValue: c?.scheduledExpenseID != nil)
        _isCancelled = State(initialValue: c?.isCancelled ?? false)
        _cancelledOn = State(initialValue: c?.cancelledOn ?? Date())
        let fid = family.id
        _cars = Query(filter: #Predicate<Car> { $0.familyID == fid && $0.isArchived == false }, sort: \Car.sortOrder)
        _carID = State(initialValue: c?.carID ?? target.carID)
        let kind = c.flatMap { CarCostKind(rawValue: $0.carCostRaw) } ?? target.carCost ?? .insurance
        _carCost = State(initialValue: kind)
        if c == nil, let carKind = target.carCost {
            let ids = CarService.transportIDs(carKind, lookup: lookup)
            _categoryID = State(initialValue: ids.categoryID ?? insurance)
            _subcategoryID = State(initialValue: ids.subcategoryID)
            _name = State(initialValue: String(localized: String.LocalizationValue(carKind.title)))
            _bookPayments = State(initialValue: true)
            _frequency = State(initialValue: .yearly)
            _renewal = State(initialValue: 12)
        }
    }

    private var terms: ContractTerms {
        ContractTerms(start: startDate, minimumTermMonths: minimumTerm, renewalMonths: renewal, noticeValue: noticeValue, noticeUnit: noticeUnit)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Mobile phone", text: $name)
                    TextField("Provider, e.g. Telekom", text: $provider)
                    HStack {
                        TextField("Amount", text: $amountText).keyboardType(.decimalPad)
                        Picker("Currency", selection: $currencyCode) {
                            ForEach(CurrencyNames.allCodes.prefix(40), id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }
                    Picker("Payment", selection: $frequency) {
                        ForEach(RecurrenceFrequency.allCases.filter { $0 != .once }, id: \.self) { f in
                            Text(LocalizedStringKey(f.displayName)).tag(f)
                        }
                    }
                    Picker("Category", selection: $categoryID) {
                        Text("None").tag(UUID?.none)
                        ForEach(lookup.activeCategories()) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                    }
                    if !lookup.activeSubcategories(of: categoryID).isEmpty {
                        Picker("Subcategory", selection: $subcategoryID) {
                            Text("None").tag(UUID?.none)
                            ForEach(lookup.activeSubcategories(of: categoryID)) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                        }
                    }
                }

                if !cars.isEmpty {
                    Section {
                        Picker("Car", selection: $carID) {
                            Text("None").tag(UUID?.none)
                            ForEach(cars) { car in Text(verbatim: car.displayName).tag(Optional(car.id)) }
                        }
                        if carID != nil {
                            Picker("For", selection: $carCost) {
                                ForEach(CarCostKind.allCases) { kind in
                                    Label(LocalizedStringKey(kind.title), systemImage: kind.icon).tag(kind)
                                }
                            }
                        }
                    } footer: {
                        Text("Booked payments count as costs of this car.")
                    }
                }

                Section {
                    DatePicker("Start", selection: $startDate, displayedComponents: [.date])
                    Stepper(value: $minimumTerm, in: 0...60) {
                        Text(minimumTerm == 0 ? LocalizedStringKey("No minimum term") : LocalizedStringKey("Minimum term: \(minimumTerm) months"))
                    }
                    Picker("Afterwards", selection: $renewal) {
                        Text("Renews monthly").tag(1)
                        Text("Renews every 3 months").tag(3)
                        Text("Renews yearly").tag(12)
                        Text("Renews every 2 years").tag(24)
                        Text("Ends").tag(0)
                    }
                    Stepper(value: $noticeValue, in: 0...24) {
                        Text("Notice: \(noticeValue) \(String(localized: String.LocalizationValue(noticeUnit.title)))")
                    }
                    Picker("Notice in", selection: $noticeUnit) {
                        ForEach(NoticeUnit.allCases, id: \.self) { Text(LocalizedStringKey($0.title)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Term & notice")
                } footer: {
                    if let next = ContractSchedule.next(terms, now: Date(), calendar: FamiloqCalendar.make()) {
                        Text("Next cancellation deadline: \(next.deadline.formatted(date: .long, time: .omitted)) - the term ends on \(next.termEnd.formatted(date: .long, time: .omitted)).")
                    } else {
                        Text("No more deadlines - the contract ends.")
                    }
                }

                Section {
                    Toggle("30 days before", isOn: $remind30)
                    Toggle("14 days before", isOn: $remind14)
                    Toggle("7 days before", isOn: $remind7)
                } header: {
                    Text("Remind me")
                } footer: {
                    Text("Also on the deadline day. Notifications: Family → Notifications.")
                }

                Section {
                    Toggle("Book payments as a recurring expense", isOn: $bookPayments)
                    TextField("Customer / contract number", text: $customerNumber)
                    TextField("Note", text: $note, axis: .vertical).lineLimit(1...4)
                } footer: {
                    Text("Booked payments appear in the budget automatically. The contract counts once in the fixed costs either way.")
                }

                Section {
                    Toggle("Cancelled", isOn: $isCancelled)
                    if isCancelled {
                        DatePicker("Cancelled on", selection: $cancelledOn, displayedComponents: [.date])
                    }
                    ShareLink(item: cancellationLetter) {
                        Label("Cancellation letter", systemImage: "envelope")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                } footer: {
                    Text("A ready-to-send text to cancel on time (send it by e-mail, letter or the provider's online form, and keep the confirmation).")
                }

                if target.contract != nil {
                    Section {
                        Button("Delete contract", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(target.contract == nil ? LocalizedStringKey("New contract") : LocalizedStringKey("Contract"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this contract?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            }
        }
    }

    /// Ready-to-send cancellation text in the app's language.
    private var cancellationLetter: String {
        let calendar = FamiloqCalendar.make()
        let end = ContractSchedule.next(terms, now: Date(), calendar: calendar)?.termEnd.formatted(date: .long, time: .omitted)
        let owner = session.currentMember?.displayName ?? ""
        let german = (Bundle.main.preferredLocalizations.first ?? "en") == "de"
        if german {
            return """
            Kündigung meines Vertrags „\(name)“

            Sehr geehrte Damen und Herren,

            hiermit kündige ich meinen Vertrag „\(name)“\(provider.isEmpty ? "" : " bei \(provider)") fristgerecht zum nächstmöglichen Zeitpunkt\(end.map { " (\($0))" } ?? "").
            \(customerNumber.isEmpty ? "" : "Kunden-/Vertragsnummer: \(customerNumber)\n")
            Bitte bestätigen Sie mir die Kündigung und das Vertragsende schriftlich.

            Mit freundlichen Grüßen
            \(owner)
            """
        }
        return """
        Cancellation of my contract "\(name)"

        Dear Sir or Madam,

        I hereby cancel my contract "\(name)"\(provider.isEmpty ? "" : " with \(provider)") at the next possible date\(end.map { " (\($0))" } ?? "").
        \(customerNumber.isEmpty ? "" : "Customer / contract number: \(customerNumber)\n")
        Please confirm the cancellation and the end date in writing.

        Kind regards
        \(owner)
        """
    }

    private func save() {
        let contract: Contract
        if let existing = target.contract {
            contract = existing
        } else {
            contract = Contract(familyID: family.id, name: "")
            contract.createdByMemberID = session.currentMember?.id
            context.insert(contract)
        }
        contract.name = name.trimmingCharacters(in: .whitespaces)
        contract.provider = provider.trimmingCharacters(in: .whitespaces)
        contract.amount = DecimalParser.parse(amountText) ?? 0
        contract.currencyCode = currencyCode
        contract.frequency = frequency
        contract.categoryID = categoryID
        contract.subcategoryID = subcategoryID
        contract.startDate = startDate
        contract.minimumTermMonths = minimumTerm
        contract.renewalMonths = renewal
        contract.noticeValue = noticeValue
        contract.noticeUnit = noticeUnit
        contract.reminderDays = [remind30 ? 30 : nil, remind14 ? 14 : nil, remind7 ? 7 : nil].compactMap { $0 }
        contract.customerNumber = customerNumber.trimmingCharacters(in: .whitespaces)
        contract.note = note
        contract.isCancelled = isCancelled
        contract.cancelledOn = isCancelled ? cancelledOn : nil
        contract.carID = carID
        contract.carCostRaw = carID == nil ? "" : carCost.rawValue
        contract.updatedAt = Date()
        syncSchedule(contract)
        try? context.save()
        Task { await PlannerNotifications.reschedule(context: context) }
        dismiss()
    }

    /// Creates, updates or stops the recurring expense of the contract.
    private func syncSchedule(_ contract: Contract) {
        var schedule: ScheduledExpense?
        if let id = contract.scheduledExpenseID {
            var d = FetchDescriptor<ScheduledExpense>(predicate: #Predicate { $0.id == id })
            d.fetchLimit = 1
            schedule = try? context.fetch(d).first
        }
        guard bookPayments else {
            schedule?.isActive = false
            schedule?.updatedAt = Date()
            contract.scheduledExpenseID = nil
            return
        }
        let s = schedule ?? {
            let new = ScheduledExpense(familyID: family.id, title: contract.name, amount: contract.amount, currencyCode: contract.currencyCode,
                                       frequency: contract.frequency, startDate: max(contract.startDate, FamiloqCalendar.make().startOfDay(for: Date())))
            new.createdByMemberID = session.currentMember?.id
            context.insert(new)
            return new
        }()
        s.title = contract.name
        s.amount = contract.amount
        s.currencyCode = contract.currencyCode
        s.frequency = contract.frequency
        s.categoryID = contract.categoryID
        s.subcategoryID = contract.subcategoryID
        s.carID = contract.carID
        s.carCostRaw = contract.carCostRaw
        s.isActive = !contract.isCancelled
        s.updatedAt = Date()
        contract.scheduledExpenseID = s.id
    }

    private func delete() {
        if let contract = target.contract {
            if let id = contract.scheduledExpenseID {
                var d = FetchDescriptor<ScheduledExpense>(predicate: #Predicate { $0.id == id })
                d.fetchLimit = 1
                if let schedule = try? context.fetch(d).first { schedule.isActive = false }
            }
            context.delete(contract)
            try? context.save()
        }
        dismiss()
    }
}

// MARK: - Warranties

struct WarrantiesView: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @Query private var warranties: [Warranty]
    @State private var editing: WarrantyEditTarget?

    init(family: Family) {
        self.family = family
        let fid = family.id
        _warranties = Query(filter: #Predicate<Warranty> { $0.familyID == fid }, sort: \Warranty.purchaseDate, order: .reverse)
    }

    var body: some View {
        let calendar = FamiloqCalendar.make()
        let rows = warranties.map { (warranty: $0, left: WarrantyTerms.daysLeft(purchase: $0.purchaseDate, months: $0.months, now: Date(), calendar: calendar)) }
        let running = rows.filter { $0.left >= 0 }.sorted { $0.left < $1.left }
        let ended = rows.filter { $0.left < 0 }
        List {
            if warranties.isEmpty {
                Section {
                    Text("Keep track of warranties (usually 2 years). Add one here or from a receipt (Scan → receipt → Add warranty). Familoq reminds you 30 days before it ends.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if !running.isEmpty {
                Section("Running") {
                    ForEach(running, id: \.warranty.id) { entry in
                        row(entry.warranty, left: entry.left, calendar: calendar)
                    }
                }
            }
            if !ended.isEmpty {
                Section("Ended") {
                    ForEach(ended, id: \.warranty.id) { entry in
                        row(entry.warranty, left: entry.left, calendar: calendar).opacity(0.6)
                    }
                }
            }
        }
        .navigationTitle("Warranties")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = WarrantyEditTarget(warranty: nil, prefill: nil) } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { target in
            WarrantyForm(family: family, target: target)
        }
    }

    private func row(_ warranty: Warranty, left: Int, calendar: Calendar) -> some View {
        Button {
            editing = WarrantyEditTarget(warranty: warranty, prefill: nil)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill").font(.title3).foregroundStyle(left <= 60 && left >= 0 ? Color.orange : Color.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: warranty.itemName).foregroundStyle(.primary)
                    let end = WarrantyTerms.end(purchase: warranty.purchaseDate, months: warranty.months, calendar: calendar)
                    Text(verbatim: [warranty.merchant, String(localized: "until \(end.formatted(date: .abbreviated, time: .omitted))")]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if left >= 0 {
                    Text("\(left) days").font(.caption).foregroundStyle(left <= 60 ? Color.orange : Color.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct WarrantyPrefill {
    var itemName: String
    var merchant: String
    var date: Date
    var amount: Decimal
    var currencyCode: String
    var receiptID: UUID?
    var expenseID: UUID?
}

struct WarrantyEditTarget: Identifiable {
    let id = UUID()
    let warranty: Warranty?
    let prefill: WarrantyPrefill?
}

struct WarrantyForm: View {
    let family: Family
    let target: WarrantyEditTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var itemName: String
    @State private var merchant: String
    @State private var purchaseDate: Date
    @State private var months: Int
    @State private var note: String

    init(family: Family, target: WarrantyEditTarget) {
        self.family = family
        self.target = target
        let w = target.warranty
        _itemName = State(initialValue: w?.itemName ?? target.prefill?.itemName ?? "")
        _merchant = State(initialValue: w?.merchant ?? target.prefill?.merchant ?? "")
        _purchaseDate = State(initialValue: w?.purchaseDate ?? target.prefill?.date ?? Date())
        _months = State(initialValue: w?.months ?? 24)
        _note = State(initialValue: w?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item, e.g. Washing machine", text: $itemName)
                    TextField("Shop", text: $merchant)
                    DatePicker("Bought on", selection: $purchaseDate, displayedComponents: [.date])
                    Stepper(value: $months, in: 1...120) {
                        Text("Warranty: \(months) months")
                    }
                    TextField("Note, e.g. serial number", text: $note)
                } footer: {
                    let end = WarrantyTerms.end(purchase: purchaseDate, months: months, calendar: FamiloqCalendar.make())
                    Text("Ends on \(end.formatted(date: .long, time: .omitted)). In the EU the statutory warranty is 2 years; the manufacturer's guarantee can be longer.")
                }
                if let warranty = target.warranty {
                    Section {
                        Button("Delete warranty", role: .destructive) {
                            context.delete(warranty)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(target.warranty == nil ? LocalizedStringKey("New warranty") : LocalizedStringKey("Warranty"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(itemName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let warranty: Warranty
        if let existing = target.warranty {
            warranty = existing
        } else {
            warranty = Warranty(familyID: family.id, itemName: "", purchaseDate: purchaseDate)
            if let prefill = target.prefill {
                warranty.amount = prefill.amount
                warranty.currencyCode = prefill.currencyCode
                warranty.receiptID = prefill.receiptID
                warranty.expenseID = prefill.expenseID
            }
            context.insert(warranty)
        }
        warranty.itemName = itemName.trimmingCharacters(in: .whitespaces)
        warranty.merchant = merchant.trimmingCharacters(in: .whitespaces)
        warranty.purchaseDate = purchaseDate
        warranty.months = months
        warranty.note = note
        warranty.updatedAt = Date()
        try? context.save()
        Task { await PlannerNotifications.reschedule(context: context) }
        dismiss()
    }
}
