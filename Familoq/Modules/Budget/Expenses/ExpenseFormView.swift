import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import FamiloqCore
import FamiloqBudget

/// Detailed expense entry / editing (spec section 8).
/// Receipt photo is always optional.
struct ExpenseFormView: View {
    let family: Family
    private let editing: Expense?
    private let onSaved: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var rates: ExchangeRateService

    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @Query private var members: [FamilyMember]
    @Query private var rules: [MerchantRuleRecord]
    @Query private var cars: [Car]

    @State private var amountText: String
    @State private var currencyCode: String
    @State private var merchant: String
    @State private var date: Date
    @State private var categoryID: UUID?
    @State private var subcategoryID: UUID?
    @State private var memberID: UUID?
    @State private var paymentMethod: PaymentMethod
    @State private var note: String
    @State private var receiptData: Data?
    @State private var photoChanged = false
    @State private var keepPhoto: Bool
    @State private var photoItem: PhotosPickerItem?
    @State private var useManualRate: Bool
    @State private var manualRateText: String
    @State private var carID: UUID?
    @State private var carCost: CarCostKind
    @State private var fuelText: String
    @State private var odometerText: String

    @State private var suggestion: CategorySuggestion?
    @State private var categoryTouched: Bool
    @State private var showRulePrompt = false
    @State private var showDeleteConfirm = false
    @State private var validationMessage: String?

    init(family: Family, editing: Expense? = nil, onSaved: (() -> Void)? = nil) {
        self.family = family
        self.editing = editing
        self.onSaved = onSaved

        let fid = family.id
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid }, sort: \ExpenseCategory.sortOrder)
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid }, sort: \ExpenseSubcategory.sortOrder)
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid }, sort: \FamilyMember.joinedAt)
        _rules = Query(filter: #Predicate<MerchantRuleRecord> { $0.familyID == fid })
        _cars = Query(filter: #Predicate<Car> { $0.familyID == fid && $0.isArchived == false }, sort: \Car.sortOrder)
        _carID = State(initialValue: editing?.carID)
        _carCost = State(initialValue: editing?.carCost ?? .fuel)
        _fuelText = State(initialValue: editing?.fuelQuantity.map { $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) } ?? "")
        _odometerText = State(initialValue: (editing?.odometer ?? 0) > 0 ? "\(editing?.odometer ?? 0)" : "")

        if let e = editing {
            _amountText = State(initialValue: "\(e.amount)")
            _currencyCode = State(initialValue: e.currencyCode)
            _merchant = State(initialValue: e.merchant)
            _date = State(initialValue: e.date)
            _categoryID = State(initialValue: e.categoryID)
            _subcategoryID = State(initialValue: e.subcategoryID)
            _memberID = State(initialValue: e.memberID)
            _paymentMethod = State(initialValue: e.paymentMethod)
            _note = State(initialValue: e.note)
            _receiptData = State(initialValue: e.receiptImageData)
            _keepPhoto = State(initialValue: e.keepPhoto)
            _useManualRate = State(initialValue: e.conversionStatus == .manual)
            _manualRateText = State(initialValue: e.conversionStatus == .manual ? (e.exchangeRateText ?? "") : "")
            _categoryTouched = State(initialValue: true)
        } else {
            _amountText = State(initialValue: "")
            _currencyCode = State(initialValue: family.baseCurrencyCode)
            _merchant = State(initialValue: "")
            _date = State(initialValue: Date())
            _categoryID = State(initialValue: nil)
            _subcategoryID = State(initialValue: nil)
            _memberID = State(initialValue: nil)
            _paymentMethod = State(initialValue: .debitCard)
            _note = State(initialValue: "")
            _receiptData = State(initialValue: nil)
            _keepPhoto = State(initialValue: false)
            _useManualRate = State(initialValue: false)
            _manualRateText = State(initialValue: "")
            _categoryTouched = State(initialValue: false)
        }
    }

    private var lookup: CategoryLookup {
        CategoryLookup(categories: categories, subcategories: subcategories)
    }

    private var isReadOnly: Bool {
        guard let editing else { return false }
        return !session.canEdit(editing)
    }

    private var isForeign: Bool {
        CurrencyInfo.normalize(currencyCode) != CurrencyInfo.normalize(family.baseCurrencyCode)
    }

    var body: some View {
        Form {
            Section("Amount") {
                HStack {
                    TextField("0,00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold).monospacedDigit())
                    NavigationLink {
                        CurrencyPickerView(selection: $currencyCode)
                    } label: {
                        Text(currencyCode).font(.headline)
                    }
                    .fixedSize()
                }
                if isForeign {
                    conversionSection
                }
            }

            Section("Details") {
                TextField("Merchant / description", text: $merchant)
                    .textInputAutocapitalization(.words)
                    .onChange(of: merchant) { _, newValue in
                        applySuggestion(for: newValue)
                    }
                DatePicker("Date & time", selection: $date, displayedComponents: [.date, .hourAndMinute])
            }

            Section("Category") {
                Picker("Category", selection: categoryBinding) {
                    Text("Choose…").tag(UUID?.none)
                    ForEach(lookup.activeCategories()) { category in
                        Label(category.name, systemImage: category.icon).tag(Optional(category.id))
                    }
                }
                Picker("Subcategory", selection: subcategoryBinding) {
                    Text("None").tag(UUID?.none)
                    ForEach(lookup.activeSubcategories(of: categoryID)) { sub in
                        Text(sub.name).tag(Optional(sub.id))
                    }
                }
                .disabled(categoryID == nil)
                if let suggestion, !categoryTouched || (suggestion.categoryID == categoryID && suggestion.subcategoryID == subcategoryID) {
                    Label("Suggested from merchant: \(lookup.path(categoryID: suggestion.categoryID, subcategoryID: suggestion.subcategoryID))", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Who & how") {
                Picker("Family member", selection: $memberID) {
                    Text("Not set").tag(UUID?.none)
                    ForEach(members.filter(\.isActive)) { member in
                        Text(LocalizedStringKey(member.displayName)).tag(Optional(member.id))
                    }
                }
                Picker("Payment method", selection: $paymentMethod) {
                    ForEach(PaymentMethod.allCases) { method in
                        Label(LocalizedStringKey(method.displayName), systemImage: method.icon).tag(method)
                    }
                }
            }

            if !cars.isEmpty || carID != nil {
                carSection
            }

            Section("Optional") {
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(1...4)
                if let receiptID = editing?.receiptID {
                    ReceiptLinkRow(receiptID: receiptID)
                } else {
                    receiptPicker
                }
            }

            if let validationMessage {
                Section {
                    Text(LocalizedStringKey(validationMessage)).foregroundStyle(.red)
                }
            }

            if editing != nil && !isReadOnly {
                Section {
                    Button("Delete expense", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
        }
        .disabled(isReadOnly)
        .navigationTitle(editing == nil ? "New expense" : "Edit expense")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editing != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            if !isReadOnly {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { attemptSave() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if memberID == nil && editing == nil {
                memberID = session.currentMember?.id
            }
        }
        .onChange(of: photoItem) { _, newItem in
            Task { await loadPhoto(newItem) }
        }
        .confirmationDialog("Always categorize this merchant this way?", isPresented: $showRulePrompt, titleVisibility: .visible) {
            Button("Always use \(lookup.path(categoryID: categoryID, subcategoryID: subcategoryID))") {
                save(createRule: true)
            }
            Button("Only this time") {
                save(createRule: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Future expenses at “\(merchant.trimmingCharacters(in: .whitespaces))” will be suggested in this category.")
        }
        .confirmationDialog("Delete this expense?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteExpense() }
        }
    }

    // MARK: Subviews

    @ViewBuilder
    private var conversionSection: some View {
        Toggle("Enter exchange rate manually", isOn: $useManualRate)
        if useManualRate {
            HStack {
                Text("1 \(currencyCode) =")
                TextField("rate", text: $manualRateText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text(family.baseCurrencyCode)
            }
            Text("Use the rate from your bank or card statement. It will never be overwritten.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Converted to \(family.baseCurrencyCode) with the ECB reference rate of the expense date (previous business day on weekends/holidays). Works offline - the rate is filled in when you're back online.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let editing, editing.isForeignCurrency, let base = editing.baseAmount {
            LabeledContent("Current value", value: base.currency(editing.baseCurrencyCode))
                .font(.caption)
            if let rateDate = editing.exchangeRateDateKey, let rate = editing.exchangeRate {
                Text("\(editing.conversionStatus.displayName): 1 \(editing.currencyCode) = \(rate.formatted(.number.precision(.fractionLength(2...6)))) \(editing.baseCurrencyCode) (\(rateDate))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var carSection: some View {
        Section {
            Picker("Car", selection: carBinding) {
                Text("None").tag(UUID?.none)
                ForEach(cars) { Text(verbatim: $0.displayName).tag(Optional($0.id)) }
            }
            if carID != nil {
                Picker("For", selection: $carCost) {
                    ForEach(CarCostKind.allCases) { k in
                        Label(LocalizedStringKey(k.title), systemImage: k.icon).tag(k)
                    }
                }
                if carCost.hasQuantity {
                    TextField(carCost == .charging ? LocalizedStringKey("kWh") : LocalizedStringKey("Liters"), text: $fuelText)
                        .keyboardType(.decimalPad)
                }
                TextField("km reading (optional)", text: $odometerText).keyboardType(.numberPad)
            }
        } header: {
            Text("Car")
        }
    }

    /// Choosing a car suggests Transport and what the cost was for.
    private var carBinding: Binding<UUID?> {
        Binding(
            get: { carID },
            set: { newValue in
                carID = newValue
                guard newValue != nil else { return }
                let subKey = lookup.subcategory(subcategoryID)?.systemKey
                if let guess = CarCostKind.guess(subcategoryKey: subKey) {
                    carCost = guess
                } else if categoryID == nil || !categoryTouched {
                    let ids = CarService.transportIDs(carCost, lookup: lookup)
                    if let cat = ids.categoryID {
                        categoryID = cat
                        subcategoryID = ids.subcategoryID
                    }
                }
            }
        )
    }

    @ViewBuilder
    private var receiptPicker: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            Label(receiptData == nil ? "Attach receipt photo" : "Replace receipt photo", systemImage: "paperclip")
        }
        if let data = receiptData, let image = UIImage(data: data) {
            HStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Spacer()
                Button("Remove", role: .destructive) {
                    receiptData = nil
                    photoItem = nil
                    photoChanged = true
                }
            }
            Toggle(isOn: $keepPhoto) {
                Label("Keep photo (warranty or tax)", systemImage: "pin.fill")
            }
        }
    }

    // MARK: Logic

    /// Bindings that remember the user picked a category themselves, so a
    /// merchant suggestion never overwrites a manual choice.
    private var categoryBinding: Binding<UUID?> {
        Binding(
            get: { categoryID },
            set: { newValue in
                categoryTouched = true
                categoryID = newValue
                if !lookup.activeSubcategories(of: newValue).contains(where: { $0.id == subcategoryID }) {
                    subcategoryID = nil
                }
            }
        )
    }

    private var subcategoryBinding: Binding<UUID?> {
        Binding(
            get: { subcategoryID },
            set: { newValue in
                categoryTouched = true
                subcategoryID = newValue
            }
        )
    }

    private func applySuggestion(for merchantText: String) {
        let newSuggestion = CategorizationService.suggestion(for: merchantText, rules: rules)
        suggestion = newSuggestion
        if !categoryTouched, let newSuggestion {
            categoryID = newSuggestion.categoryID
            subcategoryID = newSuggestion.subcategoryID
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        // Store a small grayscale JPEG (like scanned receipts) to keep the
        // database, iCloud and backups small.
        if let image = UIImage(data: data), let jpeg = ReceiptOCRService.storageJPEG(from: image) {
            receiptData = jpeg
        } else {
            receiptData = data
        }
        photoChanged = true
    }

    private func attemptSave() {
        validationMessage = nil
        guard let amount = DecimalParser.parse(amountText), amount > 0 else {
            validationMessage = "Enter an amount greater than zero."
            return
        }
        guard CurrencyInfo.isValidCode(currencyCode) else {
            validationMessage = "Choose a valid currency."
            return
        }
        guard let categoryID else {
            validationMessage = "Choose a category."
            return
        }
        if isForeign && useManualRate {
            guard (DecimalParser.parse(manualRateText) ?? 0) > 0 else {
                validationMessage = "Enter a valid exchange rate, e.g. 0,92."
                return
            }
        }
        let chosen = CategorySuggestion(categoryID: categoryID, subcategoryID: subcategoryID)
        let current = CategorizationService.suggestion(for: merchant, rules: rules)
        if CategorizationService.shouldOfferRule(merchant: merchant, suggested: current, chosen: chosen, rules: rules) {
            showRulePrompt = true
        } else {
            save(createRule: false)
        }
    }

    private func save(createRule: Bool) {
        guard let amount = DecimalParser.parse(amountText), let categoryID else { return }
        let base = family.baseCurrencyCode
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)

        let expense: Expense
        if let editing {
            expense = editing
            expense.amount = amount
            expense.currencyCode = CurrencyInfo.normalize(currencyCode)
            expense.merchant = trimmedMerchant
            expense.date = date
        } else {
            expense = Expense(familyID: family.id, amount: amount, currencyCode: currencyCode, baseCurrencyCode: base, merchant: trimmedMerchant, date: date)
            expense.createdByMemberID = session.currentMember?.id
            expense.entryMethod = .manual
        }
        expense.categoryID = categoryID
        expense.subcategoryID = subcategoryID
        expense.memberID = memberID
        expense.paymentMethod = paymentMethod
        expense.note = note
        expense.carID = carID
        expense.carCostRaw = carID == nil ? "" : carCost.rawValue
        expense.fuelQuantity = carID != nil && carCost.hasQuantity
            ? DecimalParser.parse(fuelText).map { NSDecimalNumber(decimal: $0).doubleValue } : nil
        expense.odometer = carID == nil ? 0 : (Int(odometerText.filter(\.isNumber)) ?? 0)
        if carID != nil { CarService.rememberCar(carID, memberID: memberID ?? session.currentMember?.id) }
        if photoChanged || editing == nil {
            expense.syncImage = receiptData
            if editing != nil { expense.photoRevision += 1 }
        }
        expense.keepPhoto = receiptData != nil && keepPhoto
        expense.baseCurrencyCode = base
        expense.updatedAt = Date()

        if isForeign && useManualRate, let rate = DecimalParser.parse(manualRateText) {
            expense.exchangeRateText = "\(rate)"
            expense.exchangeRateDateKey = DateKey.string(from: date, calendar: FamiloqCalendar.make())
            expense.exchangeRateSource = "Manual"
            expense.conversionStatus = .manual
            expense.baseAmount = (amount * rate).rounded(scale: CurrencyInfo.minorUnits(for: base))
        } else {
            expense.resetConversion()
        }

        do {
            if editing == nil {
                try FamilyRepository(context: context, familyID: family.id).insert(expense)
            }
            if createRule {
                CategorizationService.saveRule(
                    merchant: trimmedMerchant,
                    choice: CategorySuggestion(categoryID: categoryID, subcategoryID: subcategoryID),
                    familyID: family.id,
                    rules: rules,
                    context: context
                )
            }
            try context.save()
        } catch {
            validationMessage = "Could not save: \(error.localizedDescription)"
            return
        }

        if expense.conversionStatus.needsRefresh {
            Task { await rates.convert(expense, baseCurrency: base, context: context) }
        }

        onSaved?()
        if editing != nil {
            dismiss()
        }
    }

    private func deleteExpense() {
        guard let editing, session.canEdit(editing) else { return }
        context.delete(editing)
        try? context.save()
        dismiss()
    }
}

/// Opens the scanned receipt an expense was created from.
private struct ReceiptLinkRow: View {
    @Query private var receipts: [ReceiptRecord]

    init(receiptID: UUID) {
        _receipts = Query(filter: #Predicate<ReceiptRecord> { $0.id == receiptID })
    }

    var body: some View {
        if let receipt = receipts.first {
            NavigationLink {
                LazyView(ReceiptDetailView(receipt: receipt, allowsEditing: false))
            } label: {
                Label("Scanned receipt (\(receipt.merchant))", systemImage: "doc.text.viewfinder")
            }
        }
    }
}
