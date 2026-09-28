import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqBudget

/// "Add" tab: Quick entry (a few seconds) or the detailed form.
struct AddExpenseView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case quick = "Quick"
        case detailed = "Detailed"
        var id: String { rawValue }
    }

    @EnvironmentObject private var session: AppSession
    @State private var mode: Mode = .quick
    @State private var formToken = UUID()
    @State private var savedMessage: String?

    var body: some View {
        NavigationStack {
            if let family = session.family {
                VStack(spacing: 0) {
                    Picker("Entry mode", selection: $mode) {
                        ForEach(Mode.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    switch mode {
                    case .quick:
                        QuickExpenseView(family: family)
                    case .detailed:
                        ExpenseFormView(family: family, onSaved: {
                            savedMessage = "Expense saved"
                            formToken = UUID()
                        })
                        .id(formToken)
                    }
                }
                .navigationTitle("Add expense")
                .navigationBarTitleDisplayMode(.inline)
                .overlay(alignment: .bottom) {
                    if let savedMessage {
                        SavedToast(message: savedMessage)
                            .task {
                                try? await Task.sleep(nanoseconds: 1_800_000_000)
                                self.savedMessage = nil
                            }
                    }
                }
            } else {
                ProgressView()
            }
        }
    }
}

struct SavedToast: View {
    let message: String

    var body: some View {
        Label(LocalizedStringKey(message), systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Fast entry: amount + category (+ optional subcategory / merchant). Spec section 9.
struct QuickExpenseView: View {
    let family: Family

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var rates: ExchangeRateService

    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @Query private var recentExpenses: [Expense]
    @Query private var rules: [MerchantRuleRecord]

    @State private var amountText = ""
    @State private var currencyCode: String
    @State private var merchant = ""
    @State private var categoryID: UUID?
    @State private var subcategoryID: UUID?
    @State private var categoryTouched = false
    @State private var toast: String?
    @FocusState private var amountFocused: Bool

    init(family: Family) {
        self.family = family
        let fid = family.id
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid }, sort: \ExpenseCategory.sortOrder)
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid }, sort: \ExpenseSubcategory.sortOrder)
        var recent = FetchDescriptor<Expense>(
            predicate: #Predicate<Expense> { $0.familyID == fid },
            sortBy: [SortDescriptor(\Expense.createdAt, order: .reverse)]
        )
        recent.fetchLimit = 40
        _recentExpenses = Query(recent)
        _rules = Query(filter: #Predicate<MerchantRuleRecord> { $0.familyID == fid })
        _currencyCode = State(initialValue: family.baseCurrencyCode)
    }

    private var lookup: CategoryLookup {
        CategoryLookup(categories: categories, subcategories: subcategories)
    }

    private var parsedAmount: Decimal? {
        guard let value = DecimalParser.parse(amountText), value > 0 else { return nil }
        return value
    }

    /// Recently used merchant/category combinations (spec: remember recents).
    private var recentCombos: [RecentCombo] {
        var seen = Set<String>()
        var result: [RecentCombo] = []
        for expense in recentExpenses {
            guard let categoryID = expense.categoryID else { continue }
            let key = "\(expense.merchant.lowercased())|\(categoryID)|\(expense.subcategoryID?.uuidString ?? "")"
            if seen.insert(key).inserted {
                result.append(RecentCombo(merchant: expense.merchant, categoryID: categoryID, subcategoryID: expense.subcategoryID))
            }
            if result.count == 8 { break }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                amountField

                if !recentCombos.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(recentCombos) { combo in
                                    Button {
                                        merchant = combo.merchant
                                        categoryID = combo.categoryID
                                        subcategoryID = combo.subcategoryID
                                        categoryTouched = true
                                    } label: {
                                        chip(title: combo.merchant.isEmpty ? lookup.path(categoryID: combo.categoryID, subcategoryID: combo.subcategoryID) : combo.merchant,
                                             icon: lookup.category(combo.categoryID)?.icon ?? "clock",
                                             selected: categoryID == combo.categoryID && subcategoryID == combo.subcategoryID && merchant == combo.merchant)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Category").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 10)], spacing: 10) {
                        ForEach(lookup.activeCategories()) { category in
                            Button {
                                categoryTouched = true
                                if categoryID != category.id {
                                    categoryID = category.id
                                    subcategoryID = nil
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    CategoryIcon(icon: category.icon, colorHex: category.colorHex, size: 40)
                                    Text(category.name)
                                        .font(.caption2)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 78)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(categoryID == category.id ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: categoryID == category.id ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(category.name)
                            .accessibilityAddTraits(categoryID == category.id ? .isSelected : [])
                        }
                    }
                }

                if !lookup.activeSubcategories(of: categoryID).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Subcategory (optional)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(lookup.activeSubcategories(of: categoryID)) { sub in
                                    Button {
                                        subcategoryID = (subcategoryID == sub.id) ? nil : sub.id
                                    } label: {
                                        chip(title: sub.name, icon: nil, selected: subcategoryID == sub.id)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                TextField("Merchant (optional)", text: $merchant)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: merchant) { _, newValue in
                        guard !categoryTouched, let suggestion = CategorizationService.suggestion(for: newValue, rules: rules) else { return }
                        categoryID = suggestion.categoryID
                        subcategoryID = suggestion.subcategoryID
                    }

                Button {
                    save()
                } label: {
                    Text(saveTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(parsedAmount == nil || categoryID == nil)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { amountFocused = true }
        .overlay(alignment: .bottom) {
            if let toast {
                SavedToast(message: toast)
                    .task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        self.toast = nil
                    }
            }
        }
    }

    private var amountField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField("0,00", text: $amountText)
                .keyboardType(.decimalPad)
                .focused($amountFocused)
                .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.5)
                .accessibilityLabel("Amount")
            Menu {
                ForEach(currencyMenuCodes, id: \.self) { code in
                    Button("\(code) - \(CurrencyNames.name(for: code))") { currencyCode = code }
                }
            } label: {
                Text(currencyCode)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            .accessibilityLabel("Currency \(currencyCode)")
        }
    }

    private var currencyMenuCodes: [String] {
        var codes = [family.baseCurrencyCode]
        for code in CurrencyInfo.commonCurrencies where !codes.contains(code) {
            codes.append(code)
        }
        return codes
    }

    private var saveTitle: String {
        guard let amount = parsedAmount else { return "Save" }
        let path = categoryID == nil ? "" : " · \(lookup.path(categoryID: categoryID, subcategoryID: subcategoryID))"
        return "Save \(amount.currency(currencyCode))\(path)"
    }

    private func chip(title: String, icon: String?, selected: Bool) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.caption) }
            Text(LocalizedStringKey(title)).font(.subheadline).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1), in: Capsule())
        .overlay(Capsule().stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5))
    }

    private func save() {
        guard let amount = parsedAmount, let categoryID else { return }
        let base = family.baseCurrencyCode
        let expense = Expense(
            familyID: family.id,
            amount: amount,
            currencyCode: currencyCode,
            baseCurrencyCode: base,
            merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            date: Date()
        )
        expense.categoryID = categoryID
        expense.subcategoryID = subcategoryID
        expense.memberID = session.currentMember?.id
        expense.createdByMemberID = session.currentMember?.id
        expense.entryMethod = .quick
        expense.resetConversion()

        do {
            try FamilyRepository(context: context, familyID: family.id).insert(expense)
            try context.save()
        } catch {
            toast = "Could not save"
            return
        }
        if expense.conversionStatus.needsRefresh {
            Task { await rates.convert(expense, baseCurrency: base, context: context) }
        }

        toast = "Saved \(amount.currency(currencyCode)) · \(lookup.path(categoryID: categoryID, subcategoryID: subcategoryID))"
        amountText = ""
        merchant = ""
        subcategoryID = nil
        self.categoryID = nil
        categoryTouched = false
        amountFocused = true
    }
}

struct RecentCombo: Identifiable {
    let merchant: String
    let categoryID: UUID
    let subcategoryID: UUID?
    var id: String { "\(merchant)|\(categoryID)|\(subcategoryID?.uuidString ?? "")" }
}
