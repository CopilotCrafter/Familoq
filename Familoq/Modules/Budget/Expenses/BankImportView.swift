import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import FamiloqCore
import FamiloqBudget

/// Family → Import bank statement: read a CSV export of any bank, map the
/// columns once, see what is new and add it as expenses.
struct BankImportView: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var sync: SyncCoordinator
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @Query private var rules: [MerchantRuleRecord]

    @State private var showImporter = false
    @State private var fileName = ""
    @State private var rows: [[String]] = []
    @State private var mapping: BankColumnMapping?
    @State private var entries: [Entry] = []
    @State private var showAlreadyRecorded = false
    @State private var message: String?
    @State private var errorText: String?

    struct Entry: Identifiable {
        let transaction: BankTransaction
        let alreadyRecorded: Bool
        var include: Bool
        var categoryID: UUID?
        var subcategoryID: UUID?
        var id: Int { transaction.id }
    }

    init(family: Family) {
        self.family = family
        let fid = family.id
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid }, sort: \ExpenseCategory.sortOrder)
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid }, sort: \ExpenseSubcategory.sortOrder)
        _rules = Query(filter: #Predicate<MerchantRuleRecord> { $0.familyID == fid })
    }

    private var lookup: CategoryLookup { CategoryLookup(categories: categories, subcategories: subcategories) }
    private var header: [String] { mapping.flatMap { $0.headerRow < rows.count ? rows[$0.headerRow] : nil } ?? [] }

    var body: some View {
        List {
            Section {
                Button {
                    showImporter = true
                } label: {
                    Label(rows.isEmpty ? "Choose CSV file…" : "Choose another file…", systemImage: "doc.badge.plus")
                }
                if !fileName.isEmpty {
                    LabeledContent("File", value: fileName)
                }
                if let errorText {
                    Text(verbatim: errorText).foregroundStyle(.red).font(.footnote)
                }
                if let message {
                    Text(verbatim: message).foregroundStyle(.green).font(.footnote)
                }
            } footer: {
                Text("In your online banking, export the account transactions as CSV (Excel) and save the file in Files. Only payments going out are imported; payments already in Familoq are skipped. Importing the same file again does not create duplicates.")
            }

            if mapping != nil, !header.isEmpty {
                mappingSection
            }

            if !entries.isEmpty {
                previewSection
            }
        }
        .navigationTitle("Bank import")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]) { result in
            switch result {
            case .success(let url): load(url)
            case .failure(let error): errorText = error.localizedDescription
            }
        }
    }

    // MARK: Sections

    private var mappingSection: some View {
        Section {
            columnPicker("Date", value: Binding(get: { mapping?.date }, set: { if let v = $0 { mapping?.date = v; refresh() } }), optional: false)
            columnPicker("Amount", value: Binding(get: { mapping?.amount }, set: { mapping?.amount = $0; refresh() }), optional: true)
            if mapping?.amount == nil {
                columnPicker("Debit (out)", value: Binding(get: { mapping?.debit }, set: { mapping?.debit = $0; refresh() }), optional: true)
                columnPicker("Credit (in)", value: Binding(get: { mapping?.credit }, set: { mapping?.credit = $0; refresh() }), optional: true)
            }
            columnPicker("Payee", value: Binding(get: { mapping?.payee }, set: { if let v = $0 { mapping?.payee = v; refresh() } }), optional: false)
            columnPicker("Purpose", value: Binding(get: { mapping?.purpose }, set: { mapping?.purpose = $0; refresh() }), optional: true)
        } header: {
            Text("Columns")
        } footer: {
            Text("Familoq guessed the columns - correct them if needed. The choice is remembered for files of this bank.")
        }
    }

    private func columnPicker(_ title: LocalizedStringKey, value: Binding<Int?>, optional: Bool) -> some View {
        Picker(title, selection: value) {
            if optional { Text("None").tag(Int?.none) }
            ForEach(Array(header.enumerated()), id: \.offset) { index, name in
                Text(verbatim: name.isEmpty ? "#\(index + 1)" : name).tag(Optional(index))
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        let fresh = entries.filter { !$0.alreadyRecorded }
        let known = entries.filter(\.alreadyRecorded)
        let selected = entries.filter { $0.include && !$0.alreadyRecorded }
        Section {
            Button {
                importSelected()
            } label: {
                Label("Import \(selected.count) payment(s) · \(selected.map { abs($0.transaction.amount) }.reduce(0, +).currency(family.baseCurrencyCode))",
                      systemImage: "square.and.arrow.down")
            }
            .disabled(selected.isEmpty)
            Toggle("Show payments already in Familoq (\(known.count))", isOn: $showAlreadyRecorded)
        }
        Section {
            ForEach(fresh) { entry in
                row(entry)
            }
            if showAlreadyRecorded {
                ForEach(known) { entry in
                    row(entry).opacity(0.45)
                }
            }
        } header: {
            Text("New payments (\(fresh.count))")
        }
    }

    private func row(_ entry: Entry) -> some View {
        let index = entries.firstIndex { $0.id == entry.id }
        return HStack(alignment: .top, spacing: 10) {
            Button {
                if let index, !entry.alreadyRecorded { entries[index].include.toggle() }
            } label: {
                Image(systemName: entry.alreadyRecorded ? "checkmark.seal" : (entry.include ? "checkmark.circle.fill" : "circle"))
                    .foregroundStyle(entry.alreadyRecorded ? Color.secondary : (entry.include ? Color.accentColor : Color.secondary))
            }
            .buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.transaction.displayName).lineLimit(1)
                if !entry.transaction.purpose.isEmpty {
                    Text(verbatim: entry.transaction.purpose).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Menu {
                    ForEach(lookup.activeCategories()) { category in
                        Button {
                            if let index {
                                entries[index].categoryID = category.id
                                entries[index].subcategoryID = nil
                            }
                        } label: {
                            Label(category.name, systemImage: category.icon)
                        }
                    }
                } label: {
                    Text(verbatim: lookup.path(categoryID: entry.categoryID, subcategoryID: entry.subcategoryID)).font(.caption)
                }
                .disabled(entry.alreadyRecorded)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(abs(entry.transaction.amount).currency(family.baseCurrencyCode)).monospacedDigit()
                Text(verbatim: entry.transaction.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Loading

    private func load(_ url: URL) {
        errorText = nil
        message = nil
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorText = String(localized: "The file could not be read.")
            return
        }
        // German banks often export in Windows-1252 instead of UTF-8.
        var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        fileName = url.lastPathComponent
        rows = CSVReader.rows(text)
        let headerIndex = BankStatement.headerRow(rows)
        let signature = headerIndex < rows.count ? BankStatement.signature(rows[headerIndex]) : ""
        if let saved = Self.savedMapping(signature), saved.headerRow < rows.count {
            mapping = saved
        } else {
            mapping = BankStatement.guessMapping(rows)
        }
        if mapping == nil {
            errorText = String(localized: "No date and amount columns found. Is this a CSV export of account transactions?")
            entries = []
            return
        }
        refresh()
    }

    private static func savedMapping(_ signature: String) -> BankColumnMapping? {
        // Key: the header text itself (same bank = same header).
        guard let data = UserDefaults.standard.data(forKey: "bank.mapping." + signature) else { return nil }
        return try? JSONDecoder().decode(BankColumnMapping.self, from: data)
    }

    private func saveMapping() {
        guard let mapping, mapping.headerRow < rows.count else { return }
        let signature = BankStatement.signature(rows[mapping.headerRow])
        if let data = try? JSONEncoder().encode(mapping) {
            UserDefaults.standard.set(data, forKey: "bank.mapping." + signature)
        }
    }

    /// Re-reads the transactions with the current mapping.
    private func refresh() {
        guard let mapping else { return }
        let calendar = FamiloqCalendar.make()
        let outgoing = BankStatement.transactions(rows, mapping: mapping, calendar: calendar).filter { $0.amount < 0 }
        guard let first = outgoing.map(\.date).min(), let last = outgoing.map(\.date).max() else {
            entries = []
            return
        }
        let fid = family.id
        let from = calendar.date(byAdding: .day, value: -4, to: first) ?? first
        let to = calendar.date(byAdding: .day, value: 5, to: last) ?? last
        let existing = ((try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.familyID == fid && $0.date >= from && $0.date < to }))) ?? [])
        let known = existing.map { (date: $0.date, amount: $0.baseAmount ?? $0.amount, merchant: $0.merchant) }
        let ids = Set(existing.map(\.id))
        let otherID = lookup.categories.first { $0.systemKey == "other" }?.id
        entries = outgoing.map { tx in
            let recorded = ids.contains(Self.expenseID(tx, familyID: family.id))
                || BankStatement.isAlreadyRecorded(tx, existing: known, calendar: calendar)
            let suggestion = CategorizationService.suggestion(for: tx.displayName, rules: rules)
                ?? CategorizationService.suggestion(for: tx.purpose, rules: rules)
            return Entry(transaction: tx, alreadyRecorded: recorded, include: !recorded,
                         categoryID: suggestion?.categoryID ?? otherID, subcategoryID: suggestion?.subcategoryID)
        }
        .sorted { $0.transaction.date > $1.transaction.date }
    }

    static func expenseID(_ transaction: BankTransaction, familyID: UUID) -> UUID {
        DeterministicID.uuid(familyID.uuidString + "|" + transaction.stableKey)
    }

    private func importSelected() {
        let base = family.baseCurrencyCode
        var added = 0
        for entry in entries where entry.include && !entry.alreadyRecorded {
            let tx = entry.transaction
            let id = Self.expenseID(tx, familyID: family.id)
            var existing = FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id })
            existing.fetchLimit = 1
            if let found = try? context.fetch(existing), !found.isEmpty { continue }
            let expense = Expense(familyID: family.id, amount: abs(tx.amount), currencyCode: base, baseCurrencyCode: base,
                                  merchant: tx.displayName, date: tx.date)
            expense.id = id
            expense.categoryID = entry.categoryID
            expense.subcategoryID = entry.subcategoryID
            expense.memberID = session.currentMember?.id
            expense.createdByMemberID = session.currentMember?.id
            expense.paymentMethodRaw = "bankTransfer"
            expense.note = String(tx.purpose.prefix(140))
            expense.entryMethod = .bankImport
            expense.resetConversion()
            context.insert(expense)
            added += 1
        }
        try? context.save()
        saveMapping()
        sync.scanNow()
        message = String(localized: "\(added) payment(s) imported.")
        refresh()
    }
}
