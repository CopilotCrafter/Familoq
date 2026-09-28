import SwiftUI
import SwiftData
import UIKit
import FamiloqCore
import FamiloqBudget

/// Confirmation screen: everything recognised can be corrected before saving.
struct ReceiptReviewView: View {
    let family: Family
    /// The screen owns its copy of the receipt: edits never touch the Scan
    /// screen behind it (iOS 27 froze re-building both in a loop).
    @State private var draft: ReceiptDraft
    /// Categories are handed in (no @Query here - a query inside a
    /// presented screen is re-created whenever its parent is rebuilt).
    let lookup: CategoryLookup
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var rates: ExchangeRateService
    @State private var errorMessage: String?
    @State private var showImage = false
    @State private var showDiscard = false
    /// Item whose category is being chosen (sheet).
    @State private var categoryPickerItemID: UUID?

    init(family: Family, draft: ReceiptDraft, lookup: CategoryLookup, onDone: @escaping () -> Void) {
        self.family = family
        _draft = State(initialValue: draft)
        self.lookup = lookup
        self.onDone = onDone
    }

    private var groceriesID: UUID? { lookup.categories.first { $0.systemKey == "groceries" }?.id }

    /// Currency problems are shown in the currency question instead.
    private var otherWarnings: [String] {
        draft.warnings.filter { !$0.localizedCaseInsensitiveContains("currency") }
    }

    private func chooseCurrency(_ code: String) {
        ScanBreadcrumb.set("the check screen - choosing currency \(code)")
        // Work on a copy and write it back once (no long write access to the binding).
        var updated = draft
        ReceiptDrafting.applyCurrency(code, to: &updated, lookup: lookup)
        draft = updated
        ScanBreadcrumb.set("the check screen (currency \(code) chosen, \(updated.items.count) items)")
    }

    private var currencyBinding: Binding<String> {
        Binding(get: { draft.currencyCode }, set: { chooseCurrency($0) })
    }

    var body: some View {
        Form {
            if !draft.currencyConfirmed {
                CurrencyQuestionSection(
                    guess: draft.currencyCode,
                    candidates: draft.currencyCandidates,
                    baseCurrency: family.baseCurrencyCode,
                    selection: currencyBinding,
                    onChoose: chooseCurrency
                )
            }

            if !otherWarnings.isEmpty {
                Section {
                    ForEach(otherWarnings, id: \.self) { warning in
                        Label(LocalizedStringKey(warning), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                } footer: {
                    Text("Please check these fields.")
                }
            }

            Section("Receipt") {
                let _ = ScanBreadcrumb.render("the check screen - building receipt section")
                TextField("Merchant", text: $draft.merchant)
                DatePicker("Date & time", selection: $draft.date, displayedComponents: [.date, .hourAndMinute])
                HStack {
                    Text("Total")
                    Spacer()
                    TextField("0,00", text: $draft.totalText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.body.monospacedDigit().weight(.semibold))
                    NavigationLink {
                        CurrencyPickerView(selection: currencyBinding)
                    } label: {
                        Text(draft.currencyCode).font(.headline)
                    }
                    .fixedSize()
                }
                if !draft.vatSummary.isEmpty {
                    LabeledContent("VAT", value: draft.vatSummary).font(.footnote)
                }
                if CurrencyInfo.normalize(draft.currencyCode) != family.baseCurrencyCode {
                    Text(LocalizedStringKey(CurrencyInfo.canAutoConvert(from: draft.currencyCode, to: family.baseCurrencyCode)
                         ? "Converted to \(family.baseCurrencyCode) with the ECB rate of \(draft.date.formatted(date: .abbreviated, time: .omitted))."
                         : "No automatic rate for \(draft.currencyCode). After saving, open the expense and enter the rate to \(family.baseCurrencyCode)."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let data = draft.imageData, let image = UIImage(data: data) {
                    Button {
                        showImage = true
                    } label: {
                        HStack {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                            Text("View scanned receipt")
                        }
                    }
                }
            }

            Section {
                Toggle("Categorize entire receipt as one category", isOn: $draft.categorizeWholeReceipt)
                if draft.categorizeWholeReceipt {
                    Picker("Category", selection: wholeCategoryBinding) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(lookup.activeCategories()) { Label($0.name, systemImage: $0.icon).tag(Optional($0.id)) }
                    }
                    Picker("Subcategory", selection: $draft.wholeSubcategoryID) {
                        Text("None").tag(UUID?.none)
                        ForEach(lookup.activeSubcategories(of: draft.wholeCategoryID)) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if draft.wholeCategoryID != groceriesID, groceriesID != nil {
                        Button("Categorize entire receipt as Groceries") {
                            draft.wholeCategoryID = groceriesID
                            draft.wholeSubcategoryID = nil
                        }
                    }
                }
            } footer: {
                Text(LocalizedStringKey(draft.categorizeWholeReceipt
                     ? "Faster: one expense for the whole receipt."
                     : "Item level: each item gets its own subcategory - e.g. chicken → Meat & Poultry, bananas → Fruits."))
            }

            if !draft.categorizeWholeReceipt {
                Section {
                    let _ = ScanBreadcrumb.render("the check screen - building items (\(draft.items.count))")
                    if draft.items.isEmpty {
                        Text("No items were recognised. Add them below or categorize the entire receipt.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach($draft.items) { $item in
                        ReceiptItemEditor(item: $item, lookup: lookup, currencyCode: draft.currencyCode) {
                            categoryPickerItemID = item.id
                        }
                    }
                    .onDelete { draft.items.remove(atOffsets: $0) }
                    Button {
                        draft.items.append(ReceiptDraftItem(name: "", amountText: "", categoryID: groceriesID,
                                                            subcategoryID: lookup.subcategories.first { $0.systemKey == "groceries.other" }?.id))
                    } label: {
                        Label("Add item", systemImage: "plus")
                    }
                } header: {
                    Text("Items (\(draft.items.filter(\.included).count))")
                } footer: {
                    differenceFooter
                }
            }

            if let errorMessage {
                Section { Text(LocalizedStringKey(errorMessage)).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Check receipt")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Discard") { showDiscard = true }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.fontWeight(.semibold)
            }
        }
        .onAppear { ScanBreadcrumb.set("the check screen - shown (currency \(draft.currencyCode), \(draft.items.count) items)") }
        .sheet(isPresented: Binding(get: { categoryPickerItemID != nil }, set: { if !$0 { categoryPickerItemID = nil } })) {
            if let id = categoryPickerItemID, let index = draft.items.firstIndex(where: { $0.id == id }) {
                CategoryChoiceList(lookup: lookup,
                                   categoryID: draft.items[index].categoryID,
                                   subcategoryID: draft.items[index].subcategoryID) { categoryID, subcategoryID in
                    var updated = draft
                    updated.items[index].categoryID = categoryID
                    updated.items[index].subcategoryID = subcategoryID
                    draft = updated
                    categoryPickerItemID = nil
                } onCancel: {
                    categoryPickerItemID = nil
                }
            }
        }
        .confirmationDialog("Discard this scan?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { onDone() }
        }
        .sheet(isPresented: $showImage) {
            if let data = draft.imageData, let image = UIImage(data: data) {
                NavigationStack {
                    ScrollView { Image(uiImage: image).resizable().scaledToFit() }
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showImage = false } } }
                }
            }
        }
    }

    @ViewBuilder
    private var differenceFooter: some View {
        let code = draft.currencyCode
        if let total = draft.total {
            let diff = total - draft.includedItemsSum
            if diff == 0 {
                Label("Items match the total \(total.currency(code))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Items: \(draft.includedItemsSum.currency(code)) · Total: \(total.currency(code)) · Difference \(diff.currency(code)) will be added to the largest group so your expenses match what you paid.")
            }
        }
    }

    private var wholeCategoryBinding: Binding<UUID?> {
        Binding(
            get: { draft.wholeCategoryID },
            set: { newValue in
                draft.wholeCategoryID = newValue
                if !lookup.activeSubcategories(of: newValue).contains(where: { $0.id == draft.wholeSubcategoryID }) {
                    draft.wholeSubcategoryID = nil
                }
            }
        )
    }

    private func save() {
        errorMessage = nil
        guard draft.currencyConfirmed else {
            errorMessage = "Please choose the currency of this receipt first (top of the screen)."
            return
        }
        ScanBreadcrumb.set("saving the receipt (\(draft.currencyCode), total \(draft.totalText), \(draft.items.filter(\.included).count) items, whole receipt: \(draft.categorizeWholeReceipt))")
        do {
            let expenses = try ReceiptSaver.save(draft, family: family, member: session.currentMember, lookup: lookup, context: context)
            // Items on the shopping list that are on this receipt are ticked off.
            let ticked = ShoppingService.tickOff(receiptLines: draft.items.filter(\.included).map(\.name),
                                                 familyID: family.id, memberID: session.currentMember?.id, context: context)
            if !ticked.isEmpty {
                session.notice = String(localized: "Ticked off the shopping list: \(ticked.joined(separator: ", "))")
            }
            let base = family.baseCurrencyCode
            if expenses.contains(where: { $0.conversionStatus.needsRefresh }) {
                Task {
                    for expense in expenses {
                        await rates.convert(expense, baseCurrency: base, context: context)
                    }
                }
            }
            onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ReceiptItemEditor: View {
    @Binding var item: ReceiptDraftItem
    let lookup: CategoryLookup
    let currencyCode: String
    let onPickCategory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    item.included.toggle()
                } label: {
                    Image(systemName: item.included ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.included ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(item.included ? "Included" : "Excluded")
                TextField("Item", text: $item.name)
                TextField("0,00", text: $item.amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .font(.body.monospacedDigit())
            }
            Button {
                onPickCategory()
            } label: {
                HStack(spacing: 4) {
                    if item.confidence > 0 && item.confidence < 0.7 {
                        Image(systemName: "questionmark.circle").foregroundStyle(.orange)
                    }
                    Text(lookup.path(categoryID: item.categoryID, subcategoryID: item.subcategoryID))
                        .font(.caption)
                    Image(systemName: "chevron.right").font(.caption2)
                }
            }
            .buttonStyle(.borderless)
            .disabled(!item.included)
        }
        .opacity(item.included ? 1 : 0.5)
        .padding(.vertical, 2)
    }
}

/// "Which currency is this receipt in?" - shown when the receipt shows no
/// currency, only a shared symbol ("$", "kr", "¥") or two currencies.
/// Plain list rows (no grid) - the simplest, most robust form layout.
private struct CurrencyQuestionSection: View {
    let guess: String
    let candidates: [String]
    let baseCurrency: String
    @Binding var selection: String
    let onChoose: (String) -> Void

    var body: some View {
        Section {
            ForEach(candidates, id: \.self) { code in
                Button {
                    onChoose(code)
                } label: {
                    HStack {
                        Text(code)
                            .font(.body.monospaced().weight(.semibold))
                            .frame(width: 52, alignment: .leading)
                        Text(CurrencyNames.name(for: code))
                            .foregroundStyle(.primary)
                        Spacer()
                        if code == guess {
                            Text("best guess").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
            NavigationLink {
                CurrencyPickerView(selection: $selection, title: "Receipt currency")
            } label: {
                Label("Other currency…", systemImage: "globe")
            }
        } header: {
            Label("Which currency is this receipt in?", systemImage: "questionmark.circle.fill")
                .foregroundStyle(.orange)
        } footer: {
            Text("The receipt does not say clearly. Amounts in other currencies are converted to \(baseCurrency) with the exchange rate of the receipt date.")
        }
    }
}

/// Category + subcategory for one receipt item (plain list; replaces the
/// nested menus of 0.2/0.3 that are the prime suspect for the iOS 27 crash).
private struct CategoryChoiceList: View {
    let lookup: CategoryLookup
    let categoryID: UUID?
    let subcategoryID: UUID?
    let onChoose: (UUID, UUID?) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(lookup.activeCategories()) { category in
                    Section(category.name) {
                        row(title: "\(category.name) (general)", selected: category.id == categoryID && subcategoryID == nil) {
                            onChoose(category.id, nil)
                        }
                        ForEach(lookup.activeSubcategories(of: category.id)) { sub in
                            row(title: sub.name, selected: sub.id == subcategoryID) {
                                onChoose(category.id, sub.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private func row(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(LocalizedStringKey(title)).foregroundStyle(.primary)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
            .contentShape(Rectangle())
        }
    }
}
