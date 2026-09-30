import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqBudget

/// Planner → Cars: every family car with its costs (fuel with km and
/// l/100 km, service, repairs, tyres, TÜV, insurance, tax, parking, tolls,
/// washing) and reminders. Costs are normal budget expenses.
struct CarsScreen: View {
    let family: Family
    @Query private var cars: [Car]
    @Query private var expenses: [Expense]
    @State private var editing: CarEditTarget?
    @State private var addingCost: CarCostTarget?
    @State private var showArchived = false

    init(family: Family) {
        self.family = family
        let fid = family.id
        _cars = Query(filter: #Predicate<Car> { $0.familyID == fid }, sort: [SortDescriptor(\Car.sortOrder), SortDescriptor(\Car.createdAt)])
        _expenses = Query(filter: #Predicate<Expense> { $0.familyID == fid && $0.carID != nil })
    }

    var body: some View {
        let calendar = FamiloqCalendar.make()
        let active = cars.filter { !$0.isArchived }
        let archived = cars.filter(\.isArchived)
        let upcoming = HouseholdAgenda.carItems(active, now: Date(), calendar: calendar)
            .filter { PlannerDaysLeft.days(until: $0.date) <= 60 }
        List {
            Section {
                Button {
                    editing = CarEditTarget(car: nil)
                } label: {
                    Label("Add car", systemImage: "plus")
                }
                if !active.isEmpty {
                    Button {
                        addingCost = CarCostTarget(expense: nil, carID: nil, kind: .fuel)
                    } label: {
                        Label("Add fuel", systemImage: "fuelpump")
                    }
                    Button {
                        addingCost = CarCostTarget(expense: nil, carID: nil, kind: .service)
                    } label: {
                        Label("Add car cost", systemImage: "wrench.and.screwdriver")
                    }
                }
            } footer: {
                if cars.isEmpty {
                    Text("Add your cars to see what each one really costs: fuel with km and consumption, service, repairs, tyres, TÜV, insurance, tax, parking, tolls and washing. Scanned fuel receipts ask which car.")
                }
            }
            if !upcoming.isEmpty {
                Section("Coming up") {
                    ForEach(upcoming) { item in
                        AgendaRow(item: item)
                    }
                }
            }
            if !active.isEmpty {
                Section("Cars") {
                    ForEach(active) { car in link(car, calendar: calendar) }
                }
            }
            if !archived.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showArchived) {
                        ForEach(archived) { car in link(car, calendar: calendar) }
                    } label: {
                        Text("Sold or archived (\(archived.count))")
                    }
                }
            }
        }
        .sheet(item: $editing) { target in
            CarForm(family: family, target: target)
        }
        .sheet(item: $addingCost) { target in
            CarCostSheet(family: family, target: target)
        }
    }

    private func link(_ car: Car, calendar: Calendar) -> some View {
        let year = calendar.component(.year, from: Date())
        let mine = expenses.filter { $0.carID == car.id }
        let thisYear = CarService.entries(mine.filter { calendar.component(.year, from: $0.date) == year })
        let consumption = CarStats.consumption(CarService.entries(mine))
        return NavigationLink {
            LazyView(CarDetailView(family: family, car: car))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: car.fuelType == .electric ? "bolt.car.fill" : "car.fill")
                    .foregroundStyle(.blue).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: car.displayName).font(.body.weight(.medium))
                    HStack(spacing: 6) {
                        Text("This year: \(CarStats.total(thisYear).currency(family.baseCurrencyCode))")
                        if let consumption {
                            Text(verbatim: "· " + CarFormat.consumption(consumption, car.fuelType))
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct AgendaRow: View {
    let item: HouseholdAgenda.Item

    var body: some View {
        let days = PlannerDaysLeft.days(until: item.date)
        HStack(spacing: 12) {
            Image(systemName: item.icon).foregroundStyle(days < 0 ? .red : .orange).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.subtitle.isEmpty ? item.title : "\(item.title) · \(item.subtitle)")
                Text(verbatim: item.date.formatted(date: .long, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(days < 0 ? LocalizedStringKey("Overdue") : LocalizedStringKey("in \(days) days"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(days <= 14 ? Color.red : Color.secondary)
        }
    }
}

enum CarFormat {
    static func consumption(_ value: Double, _ fuel: FuelType) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " " + fuel.unit + "/100 km"
    }

    static func km(_ value: Int) -> String {
        value.formatted(.number) + " km"
    }
}

struct CarEditTarget: Identifiable {
    let id = UUID()
    let car: Car?
}

struct CarCostTarget: Identifiable {
    let id = UUID()
    let expense: Expense?
    let carID: UUID?
    let kind: CarCostKind
}

// MARK: - Car detail

struct CarDetailView: View {
    let family: Family
    let car: Car
    @Query private var expenses: [Expense]
    @Query private var contracts: [Contract]
    @Query private var documents: [FamilyDocument]
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @State private var editing: CarEditTarget?
    @State private var costTarget: CarCostTarget?
    @State private var contractTarget: ContractEditTarget?
    @State private var allYears = false

    init(family: Family, car: Car) {
        self.family = family
        self.car = car
        let cid: UUID? = car.id
        let fid = family.id
        _expenses = Query(filter: #Predicate<Expense> { $0.carID == cid }, sort: \Expense.date, order: .reverse)
        _contracts = Query(filter: #Predicate<Contract> { $0.carID == cid }, sort: \Contract.name)
        _documents = Query(filter: #Predicate<FamilyDocument> { $0.carID == cid && $0.isPrivate == false })
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid }, sort: \ExpenseCategory.sortOrder)
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid }, sort: \ExpenseSubcategory.sortOrder)
    }

    var body: some View {
        let calendar = FamiloqCalendar.make()
        let now = Date()
        let year = calendar.component(.year, from: now)
        let shown = allYears ? expenses : expenses.filter { calendar.component(.year, from: $0.date) == year }
        let entries = CarService.entries(shown)
        let allEntries = CarService.entries(expenses)
        let months = max(1, calendar.component(.month, from: now))
        let currency = family.baseCurrencyCode
        List {
            Section {
                Picker("Period", selection: $allYears) {
                    Text(verbatim: String(year)).tag(false)
                    Text("All time").tag(true)
                }
                .pickerStyle(.segmented)
                LabeledContent("Total", value: CarStats.total(entries).currency(currency))
                if !allYears {
                    LabeledContent("Per month (average)", value: (CarStats.total(entries) / Decimal(months)).rounded(scale: 2).currency(currency))
                }
                if let perKm = CarStats.costPerKm(entries) {
                    LabeledContent("Cost per km", value: perKm.currency(currency))
                }
                if let km = CarStats.distance(entries) {
                    LabeledContent("Driven", value: CarFormat.km(km))
                }
                if let consumption = CarStats.consumption(allEntries) {
                    LabeledContent("Consumption", value: CarFormat.consumption(consumption, car.fuelType))
                }
                if let price = CarStats.averagePrice(entries) {
                    LabeledContent(car.fuelType == .electric ? LocalizedStringKey("Average price per kWh") : LocalizedStringKey("Average price per liter"),
                                   value: price.formatted(.currency(code: currency).precision(.fractionLength(3))))
                }
                if let odometer = CarStats.lastOdometer(allEntries) {
                    LabeledContent("Last km reading", value: CarFormat.km(odometer))
                }
            } footer: {
                Text("Consumption needs full fill-ups with the km reading.")
            }

            Section {
                Button {
                    costTarget = CarCostTarget(expense: nil, carID: car.id, kind: car.fuelType == .electric ? .charging : .fuel)
                } label: {
                    Label(car.fuelType == .electric ? "Add charging" : "Add fuel", systemImage: car.fuelType == .electric ? "bolt.fill" : "fuelpump")
                }
                Button {
                    costTarget = CarCostTarget(expense: nil, carID: car.id, kind: .service)
                } label: {
                    Label("Add car cost", systemImage: "wrench.and.screwdriver")
                }
            }

            let totals = CarStats.totals(entries)
            if !totals.isEmpty {
                Section("Costs") {
                    ForEach(totals, id: \.kind) { entry in
                        HStack {
                            Label(LocalizedStringKey(entry.kind.title), systemImage: entry.kind.icon)
                            Spacer()
                            Text(entry.amount.currency(currency)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                reminderRow("TÜV / inspection", icon: "checkmark.seal.fill", date: car.nextInspection)
                reminderRow("Service", icon: "wrench.and.screwdriver.fill", date: car.nextService)
                if car.nextServiceKm > 0 {
                    let last = CarStats.lastOdometer(allEntries)
                    LabeledContent {
                        Text(verbatim: serviceKm(last: last))
                    } label: {
                        Label("Service at", systemImage: "gauge.with.dots.needle.67percent")
                    }
                }
                if car.tyreReminder, let next = TyreSeason.nextChange(after: now, calendar: calendar) {
                    LabeledContent {
                        Text(verbatim: next.date.formatted(date: .long, time: .omitted))
                    } label: {
                        Label(next.toWinter ? LocalizedStringKey("Winter tyres") : LocalizedStringKey("Summer tyres"), systemImage: next.toWinter ? "snowflake" : "sun.max")
                    }
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Change dates in Edit. Notifications: Family → Notifications.")
            }

            Section {
                ForEach(contracts) { contract in
                    Button {
                        contractTarget = ContractEditTarget(contract: contract)
                    } label: {
                        HStack {
                            Label(LocalizedStringKey(CarCostKind(rawValue: contract.carCostRaw)?.title ?? "Contract"),
                                  systemImage: CarCostKind(rawValue: contract.carCostRaw)?.icon ?? "doc.text")
                            Text(verbatim: contract.name).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Text(verbatim: "\(contract.amount.currency(contract.currencyCode)) · \(String(localized: String.LocalizationValue(contract.frequency.displayName)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    contractTarget = ContractEditTarget(contract: nil, carID: car.id, carCost: .insurance)
                } label: {
                    Label("Add car insurance", systemImage: "shield")
                }
                Button {
                    contractTarget = ContractEditTarget(contract: nil, carID: car.id, carCost: .tax)
                } label: {
                    Label("Add vehicle tax", systemImage: "building.columns")
                }
            } header: {
                Text("Insurance, tax & leasing")
            } footer: {
                Text("Booked yearly or monthly - with a reminder before the cancellation deadline.")
            }

            if !documents.isEmpty {
                Section("Documents") {
                    ForEach(documents) { doc in
                        Label {
                            Text(verbatim: doc.displayTitle)
                        } icon: {
                            Image(systemName: doc.kind.icon)
                        }
                    }
                }
            }

            if !shown.isEmpty {
                Section("Log") {
                    ForEach(shown.prefix(60)) { expense in
                        Button {
                            costTarget = CarCostTarget(expense: expense, carID: car.id, kind: expense.carCost ?? .other)
                        } label: {
                            logRow(expense, currency: currency)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: car.displayName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = CarEditTarget(car: car) }
            }
        }
        .sheet(item: $editing) { target in
            CarForm(family: family, target: target)
        }
        .sheet(item: $costTarget) { target in
            CarCostSheet(family: family, target: target)
        }
        .sheet(item: $contractTarget) { target in
            ContractForm(family: family, target: target, lookup: CategoryLookup(categories: categories, subcategories: subcategories))
        }
    }

    private func reminderRow(_ title: String, icon: String, date: Date?) -> some View {
        LabeledContent {
            if let date {
                let days = PlannerDaysLeft.days(until: date)
                Text(verbatim: date.formatted(date: .long, time: .omitted))
                    .foregroundStyle(days < 0 ? Color.red : days <= 30 ? Color.orange : Color.secondary)
            } else {
                Text("Not set").foregroundStyle(.secondary)
            }
        } label: {
            Label(LocalizedStringKey(title), systemImage: icon)
        }
    }

    private func serviceKm(last: Int?) -> String {
        var text = CarFormat.km(car.nextServiceKm)
        if let last {
            let left = max(0, car.nextServiceKm - last)
            text += " (" + String(localized: "\(left) km to go") + ")"
        }
        return text
    }

    private func details(_ expense: Expense) -> String {
        var parts = [expense.date.formatted(date: .abbreviated, time: .omitted)]
        if let q = expense.fuelQuantity {
            parts.append(q.formatted(.number.precision(.fractionLength(0...2))) + " " + car.fuelType.unit)
        }
        if expense.odometer > 0 { parts.append(CarFormat.km(expense.odometer)) }
        return parts.joined(separator: " · ")
    }

    private func logRow(_ expense: Expense, currency: String) -> some View {
        let kind = expense.carCost ?? .other
        return HStack(spacing: 12) {
            Image(systemName: kind.icon).foregroundStyle(.blue).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: expense.merchant.isEmpty ? String(localized: String.LocalizationValue(kind.title)) : expense.merchant)
                Text(verbatim: details(expense)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text((expense.baseAmount ?? expense.amount).currency(currency)).monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Car form

struct CarForm: View {
    let family: Family
    let target: CarEditTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @Query private var members: [FamilyMember]
    @State private var name: String
    @State private var plate: String
    @State private var fuelType: FuelType
    @State private var hasInspection: Bool
    @State private var inspection: Date
    @State private var hasService: Bool
    @State private var service: Date
    @State private var serviceKmText: String
    @State private var tyreReminder: Bool
    @State private var drivers: Set<UUID>
    @State private var note: String
    @State private var archived: Bool
    @State private var confirmDelete = false

    init(family: Family, target: CarEditTarget) {
        self.family = family
        self.target = target
        let fid = family.id
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid && $0.isActive == true }, sort: \FamilyMember.joinedAt)
        let c = target.car
        let inAYear = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        _name = State(initialValue: c?.name ?? "")
        _plate = State(initialValue: c?.plate ?? "")
        _fuelType = State(initialValue: c?.fuelType ?? .petrol)
        _hasInspection = State(initialValue: c?.nextInspection != nil)
        _inspection = State(initialValue: c?.nextInspection ?? inAYear)
        _hasService = State(initialValue: c?.nextService != nil)
        _service = State(initialValue: c?.nextService ?? inAYear)
        _serviceKmText = State(initialValue: (c?.nextServiceKm ?? 0) > 0 ? "\(c?.nextServiceKm ?? 0)" : "")
        _tyreReminder = State(initialValue: c?.tyreReminder ?? true)
        _drivers = State(initialValue: c?.drivers ?? [])
        _note = State(initialValue: c?.note ?? "")
        _archived = State(initialValue: c?.isArchived ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Golf", text: $name)
                    TextField("Number plate", text: $plate)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Picker("Drive", selection: $fuelType) {
                        ForEach(FuelType.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                    }
                }
                Section {
                    Toggle("TÜV / inspection date", isOn: $hasInspection.animation())
                    if hasInspection {
                        DatePicker("Next TÜV", selection: $inspection, displayedComponents: [.date])
                    }
                    Toggle("Service date", isOn: $hasService.animation())
                    if hasService {
                        DatePicker("Next service", selection: $service, displayedComponents: [.date])
                    }
                    TextField("Next service at km (optional)", text: $serviceKmText).keyboardType(.numberPad)
                    Toggle("Remind to change tyres", isOn: $tyreReminder)
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("TÜV: 30 and 7 days before. Service: 14 days before. Tyres: 10 October and 10 April (\"O bis O\").")
                }
                Section {
                    MemberChooser(members: members, selection: $drivers, everyoneLabel: "Everyone")
                } header: {
                    Text("Who drives it")
                } footer: {
                    Text("Only they get this car's reminders, and their fuel receipts suggest this car.")
                }
                Section {
                    TextField("Note", text: $note, axis: .vertical).lineLimit(1...4)
                    if target.car != nil {
                        Toggle("Sold or archived", isOn: $archived)
                    }
                }
                if target.car != nil {
                    Section {
                        Button("Delete car", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Its costs stay in the budget.")
                    }
                }
            }
            .navigationTitle(target.car == nil ? LocalizedStringKey("New car") : LocalizedStringKey("Edit car"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty && plate.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this car?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let car = target.car { CarService.delete(car, context: context) }
                    dismiss()
                }
            }
        }
    }

    private func save() {
        let car: Car
        if let existing = target.car {
            car = existing
        } else {
            car = Car(familyID: family.id, name: "")
            car.createdByMemberID = session.currentMember?.id
            car.sortOrder = (CarService.cars(familyID: family.id, context: context).map(\.sortOrder).max() ?? -1) + 1
            context.insert(car)
        }
        car.name = name.trimmingCharacters(in: .whitespaces)
        car.plate = plate.trimmingCharacters(in: .whitespaces).uppercased()
        car.fuelType = fuelType
        car.nextInspection = hasInspection ? inspection : nil
        car.nextService = hasService ? service : nil
        car.nextServiceKm = Int(serviceKmText.filter(\.isNumber)) ?? 0
        car.tyreReminder = tyreReminder
        car.drivers = drivers
        car.note = note
        car.isArchived = archived
        car.updatedAt = Date()
        try? context.save()
        Task {
            _ = await PlannerNotifications.requestPermissionIfNeeded()
            await PlannerNotifications.reschedule(context: context)
        }
        dismiss()
    }
}

// MARK: - Add fuel / cost

struct CarCostSheet: View {
    let family: Family
    let target: CarCostTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var rates: ExchangeRateService
    @Query private var cars: [Car]
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @State private var carID: UUID?
    @State private var kind: CarCostKind
    @State private var what: String
    @State private var amountText: String
    @State private var date: Date
    @State private var quantityText: String
    @State private var odometerText: String
    @State private var note: String
    @State private var updateReminder = true
    @State private var confirmDelete = false

    init(family: Family, target: CarCostTarget) {
        self.family = family
        self.target = target
        let fid = family.id
        _cars = Query(filter: #Predicate<Car> { $0.familyID == fid && $0.isArchived == false },
                      sort: [SortDescriptor(\Car.sortOrder), SortDescriptor(\Car.createdAt)])
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid }, sort: \ExpenseCategory.sortOrder)
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid }, sort: \ExpenseSubcategory.sortOrder)
        let e = target.expense
        _carID = State(initialValue: e?.carID ?? target.carID)
        _kind = State(initialValue: e?.carCost ?? target.kind)
        _what = State(initialValue: e?.merchant ?? "")
        _amountText = State(initialValue: e.map { "\($0.amount)" } ?? "")
        _date = State(initialValue: e?.date ?? Date())
        _quantityText = State(initialValue: e?.fuelQuantity.map { $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) } ?? "")
        _odometerText = State(initialValue: (e?.odometer ?? 0) > 0 ? "\(e?.odometer ?? 0)" : "")
        _note = State(initialValue: e?.note ?? "")
    }

    private var car: Car? { cars.first { $0.id == carID } }

    private var canEdit: Bool {
        guard let expense = target.expense else { return true }
        return session.canEdit(expense)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Car", selection: $carID) {
                        if carID == nil { Text("Choose…").tag(UUID?.none) }
                        ForEach(cars) { Text(verbatim: $0.displayName).tag(Optional($0.id)) }
                    }
                    Picker("For", selection: $kind) {
                        ForEach(CarCostKind.allCases) { k in
                            Label(LocalizedStringKey(k.title), systemImage: k.icon).tag(k)
                        }
                    }
                    TextField("Amount (\(family.baseCurrencyCode))", text: $amountText).keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                    TextField("Where / what, e.g. Aral", text: $what)
                }
                Section {
                    if kind.hasQuantity {
                        TextField(car?.fuelType == .electric || kind == .charging ? LocalizedStringKey("kWh") : LocalizedStringKey("Liters"), text: $quantityText)
                            .keyboardType(.decimalPad)
                    }
                    TextField("km reading (optional)", text: $odometerText).keyboardType(.numberPad)
                    if let price = pricePerUnit {
                        LabeledContent(kind == .charging || car?.fuelType == .electric ? LocalizedStringKey("Price per kWh") : LocalizedStringKey("Price per liter"),
                                       value: price.formatted(.currency(code: family.baseCurrencyCode).precision(.fractionLength(3))))
                    }
                } footer: {
                    if kind.hasQuantity {
                        Text("Fill up to full and enter the km reading - then Familoq works out the consumption.")
                    }
                }
                if kind == .inspection || kind == .service {
                    Section {
                        Toggle(kind == .inspection ? LocalizedStringKey("Next TÜV in 2 years") : LocalizedStringKey("Next service in 1 year"), isOn: $updateReminder)
                    }
                }
                Section {
                    TextField("Note", text: $note, axis: .vertical).lineLimit(1...3)
                }
                if target.expense != nil && canEdit {
                    Section {
                        Button("Delete", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .disabled(!canEdit)
            .navigationTitle(LocalizedStringKey(kind.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if canEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(carID == nil || (DecimalParser.parse(amountText) ?? 0) <= 0)
                    }
                }
            }
            .onAppear {
                if carID == nil { carID = CarService.lastCar(memberID: session.currentMember?.id, cars: cars) }
            }
            .confirmationDialog("Delete this cost?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let expense = target.expense {
                        context.delete(expense)
                        try? context.save()
                    }
                    dismiss()
                }
            }
        }
    }

    private var pricePerUnit: Decimal? {
        guard kind.hasQuantity, let amount = DecimalParser.parse(amountText), amount > 0,
              let quantity = DecimalParser.parse(quantityText), quantity > 0 else { return nil }
        return (amount / quantity).rounded(scale: 3)
    }

    private func save() {
        guard let amount = DecimalParser.parse(amountText), amount > 0, let carID else { return }
        let base = family.baseCurrencyCode
        let expense: Expense
        let isNew = target.expense == nil
        if let existing = target.expense {
            expense = existing
        } else {
            expense = Expense(familyID: family.id, amount: amount, currencyCode: base, baseCurrencyCode: base, merchant: "", date: date)
            expense.createdByMemberID = session.currentMember?.id
            expense.memberID = session.currentMember?.id
            expense.entryMethod = .manual
            context.insert(expense)
        }
        let changedMoney = isNew || expense.amount != amount || !Calendar.current.isDate(expense.date, inSameDayAs: date)
        let lookup = CategoryLookup(categories: categories, subcategories: subcategories)
        if isNew || expense.carCost != kind {
            let ids = CarService.transportIDs(kind, lookup: lookup)
            if let categoryID = ids.categoryID {
                expense.categoryID = categoryID
                expense.subcategoryID = ids.subcategoryID
            }
        }
        let name = what.trimmingCharacters(in: .whitespaces)
        expense.merchant = name.isEmpty ? String(localized: String.LocalizationValue(kind.title)) : name
        expense.amount = amount
        expense.date = date
        expense.carID = carID
        expense.carCost = kind
        expense.fuelQuantity = kind.hasQuantity ? DecimalParser.parse(quantityText).map { NSDecimalNumber(decimal: $0).doubleValue } : nil
        expense.odometer = Int(odometerText.filter(\.isNumber)) ?? 0
        expense.note = note
        expense.updatedAt = Date()
        if changedMoney { expense.resetConversion() }
        if updateReminder, let car = self.car {
            let calendar = FamiloqCalendar.make()
            if kind == .inspection, let next = CarInspection.next(after: date, calendar: calendar), next > (car.nextInspection ?? .distantPast) {
                car.nextInspection = next
                car.updatedAt = Date()
            } else if kind == .service, let next = calendar.date(byAdding: .year, value: 1, to: date), next > (car.nextService ?? .distantPast) {
                car.nextService = next
                car.updatedAt = Date()
            }
        }
        CarService.rememberCar(carID, memberID: session.currentMember?.id)
        try? context.save()
        if changedMoney && expense.isForeignCurrency {
            Task { await rates.convert(expense, baseCurrency: base, context: context) }
        }
        if kind == .inspection || kind == .service {
            Task { await PlannerNotifications.reschedule(context: context) }
        }
        dismiss()
    }
}

// MARK: - Dashboard

/// Dashboard: monthly cost per car and documents that expire soon.
struct HouseholdDashboardSection: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var sync: SyncCoordinator
    @State private var rows: [CarRow] = []
    @State private var documentCount = 0
    @State private var expiringCount = 0

    struct CarRow: Identifiable {
        let car: Car
        let perMonth: Decimal
        let due: HouseholdAgenda.Item?
        var id: UUID { car.id }
    }

    var body: some View {
        Group {
            if !rows.isEmpty || documentCount > 0 {
                Section {
                    ForEach(rows) { row in
                        NavigationLink {
                            LazyView(CarDetailView(family: family, car: row.car))
                        } label: {
                            HStack {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: row.car.displayName).lineLimit(1)
                                        if let due = row.due {
                                            Text(verbatim: "\(due.title): \(due.date.formatted(.dateTime.day().month(.abbreviated)))")
                                                .font(.caption)
                                                .foregroundStyle(PlannerDaysLeft.days(until: due.date) <= 14 ? Color.red : Color.orange)
                                        }
                                    }
                                } icon: {
                                    Image(systemName: row.car.fuelType == .electric ? "bolt.car.fill" : "car.fill")
                                }
                                Spacer()
                                Text("\(row.perMonth.currency(family.baseCurrencyCode)) / month").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                    if documentCount > 0 {
                        NavigationLink {
                            LazyView(DocumentsScreen(family: family).navigationTitle("Documents"))
                        } label: {
                            HStack {
                                Label("Documents", systemImage: "doc.text.fill")
                                Spacer()
                                if expiringCount > 0 {
                                    Text("\(expiringCount) expiring").font(.caption).foregroundStyle(.orange)
                                } else {
                                    Text("\(documentCount)").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Cars & documents")
                } footer: {
                    if !rows.isEmpty {
                        Text("Car costs per month: average of this year.")
                    }
                }
            }
        }
        .task(id: sync.remoteChangeCount) { load() }
        .onAppear { load() }
    }

    private func load() {
        let calendar = FamiloqCalendar.make()
        let now = Date()
        let year = calendar.component(.year, from: now)
        let months = Decimal(max(1, calendar.component(.month, from: now)))
        let fid = family.id
        let cars = CarService.cars(familyID: fid, context: context)
        let expenses = (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.familyID == fid && $0.carID != nil }))) ?? []
        rows = cars.map { car in
            let thisYear = expenses.filter { $0.carID == car.id && calendar.component(.year, from: $0.date) == year }
            let total = CarStats.total(CarService.entries(thisYear))
            let due = HouseholdAgenda.carItems([car], now: now, calendar: calendar)
                .first { $0.kind != .tyres && PlannerDaysLeft.days(until: $0.date) <= 45 }
            return CarRow(car: car, perMonth: (total / months).rounded(scale: 2), due: due)
        }
        let documents = (try? context.fetch(FetchDescriptor<FamilyDocument>(predicate: #Predicate { $0.familyID == fid }))) ?? []
        documentCount = documents.count
        expiringCount = documents.filter {
            switch DocumentExpiry.state(expiresOn: $0.expiresOn, now: now, calendar: calendar) {
            case .soon?, .expired?: return true
            default: return false
            }
        }.count
    }
}
