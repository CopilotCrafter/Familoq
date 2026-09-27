import SwiftUI
import SwiftData
import UIKit
import FamiloqCore
import FamiloqBudget

/// Confirmation screen: everything recognised can be corrected before saving.
struct ReceiptReviewView: View {
    let family: Family
    @Binding var draft: ReceiptDraft
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var rates: ExchangeRateService
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @State private var errorMessage: String?
    @State private var showImage = false
    @State private var showDiscard = false

    init(family: Family, draft: Binding<ReceiptDraft>, onDone: @escaping () -> Void) {
        self.family = family
        _draft = draft
        self.onDone = onDone
        let fid = family.id
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid }, sort: \ExpenseCategory.sortOrder)
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid }, sort: \ExpenseSubcategory.sortOrder)
    }

    private var lookup: CategoryLookup { CategoryLookup(categories: categories, subcategories: subcategories) }
    private var groceriesID: UUID? { categories.first { $0.systemKey == "groceries" }?.id }

    var body: some View {
        Form {
            if !draft.warnings.isEmpty {
                Section {
                    ForEach(draft.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                } footer: {
                    Text("Please check these fields.")
                }
            }

            Section("Receipt") {
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
                        CurrencyPickerView(selection: $draft.currencyCode)
                    } label: {
                        Text(draft.currencyCode).font(.headline)
                    }
                    .fixedSize()
                }
                if !draft.vatSummary.isEmpty {
                    LabeledContent("VAT", value: draft.vatSummary).font(.footnote)
                }
                if CurrencyInfo.normalize(draft.currencyCode) != family.baseCurrencyCode {
                    Text("Converted to \(family.baseCurrencyCode) with the ECB rate of \(draft.date.formatted(date: .abbreviated, time: .omitted)).")
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
                Text(draft.categorizeWholeReceipt
                     ? "Faster: one expense for the whole receipt."
                     : "Item level: each item gets its own subcategory - e.g. chicken → Meat & Poultry, bananas → Fruits.")
            }

            if !draft.categorizeWholeReceipt {
                Section {
                    if draft.items.isEmpty {
                        Text("No items were recognised. Add them below or categorize the entire receipt.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach($draft.items) { $item in
                        ReceiptItemEditor(item: $item, lookup: lookup, currencyCode: draft.currencyCode)
                    }
                    .onDelete { draft.items.remove(atOffsets: $0) }
                    Button {
                        draft.items.append(ReceiptDraftItem(name: "", amountText: "", categoryID: groceriesID,
                                                            subcategoryID: subcategories.first { $0.systemKey == "groceries.other" }?.id))
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
                Section { Text(errorMessage).foregroundStyle(.red) }
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
        do {
            let expenses = try ReceiptSaver.save(draft, family: family, member: session.currentMember, lookup: lookup, context: context)
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
            Menu {
                ForEach(lookup.activeCategories()) { category in
                    Menu(category.name) {
                        Button(category.name) {
                            item.categoryID = category.id
                            item.subcategoryID = nil
                        }
                        ForEach(lookup.activeSubcategories(of: category.id)) { sub in
                            Button(sub.name) {
                                item.categoryID = category.id
                                item.subcategoryID = sub.id
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if item.confidence > 0 && item.confidence < 0.7 {
                        Image(systemName: "questionmark.circle").foregroundStyle(.orange)
                    }
                    Text(lookup.path(categoryID: item.categoryID, subcategoryID: item.subcategoryID))
                        .font(.caption)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
            }
            .disabled(!item.included)
        }
        .opacity(item.included ? 1 : 0.5)
        .padding(.vertical, 2)
    }
}
