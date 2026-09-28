import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import FamiloqCore

/// Family → Export & backup: CSV for Excel, full backup file, restore.
struct ExportBackupView: View {
    let family: Family

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var sync: SyncCoordinator
    @Query private var expenses: [Expense]
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @Query private var members: [FamilyMember]

    @State private var csvPeriod: FilterPeriod = .thisYear
    @State private var csvURL: URL?
    @State private var includePhotos = false
    @State private var backupURL: URL?
    @State private var showImporter = false
    @State private var pendingRestore: FamilyBackup?
    @State private var message: String?

    init(family: Family) {
        self.family = family
        let fid = family.id
        _expenses = Query(filter: #Predicate<Expense> { $0.familyID == fid }, sort: \Expense.date)
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid })
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid })
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid })
    }

    private var periodExpenses: [Expense] {
        guard let range = csvPeriod.range() else { return expenses }
        return expenses.filter { $0.date >= range.0 && $0.date < range.1 }
    }

    var body: some View {
        Form {
            Section {
                Picker("Period", selection: $csvPeriod) {
                    ForEach(FilterPeriod.allCases.filter { $0 != .custom }) { Text(LocalizedStringKey($0.title)).tag($0) }
                }
                .onChange(of: csvPeriod) { _, _ in csvURL = nil }
                if let csvURL {
                    ShareLink(item: csvURL) {
                        Label("Share or save CSV (\(periodExpenses.count) expenses)", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        makeCSV()
                    } label: {
                        Label("Create CSV", systemImage: "tablecells")
                    }
                    .disabled(periodExpenses.isEmpty)
                }
            } header: {
                Text("Expenses for Excel / Numbers")
            } footer: {
                Text("One row per expense with category, original amount and currency, amount in \(family.baseCurrencyCode), exchange rate, member and note. Opens directly in Excel (also German Excel).")
            }

            Section {
                Toggle("Include receipt photos", isOn: $includePhotos)
                    .onChange(of: includePhotos) { _, _ in backupURL = nil }
                if let backupURL {
                    ShareLink(item: backupURL) {
                        Label("Save backup file", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        makeBackup()
                    } label: {
                        Label("Create backup", systemImage: "externaldrive.badge.checkmark")
                    }
                }
            } header: {
                Text("Full backup")
            } footer: {
                Text("Everything of this family - expenses, receipts, categories, budgets, recurring expenses, savings goals, members - in one file. Save it in Files or iCloud Drive. Photos make the file much larger. Your data is already kept in iCloud; this is an extra copy you control.")
            }

            if session.isOwner {
                Section {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Restore from backup…", systemImage: "arrow.counterclockwise")
                    }
                } footer: {
                    Text("Adds the backup's records to this family; records that already exist are replaced by the backup's version. Other families are never changed.")
                }
            }

            if let message {
                Section { Text(LocalizedStringKey(message)) }
            }
        }
        .navigationTitle("Export & backup")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            readBackup(result)
        }
        .confirmationDialog(restoreTitle, isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                            titleVisibility: .visible) {
            Button("Restore into \(family.name)") { restore() }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            Text(restoreMessage)
        }
    }

    private var restoreTitle: String {
        guard let backup = pendingRestore else { return "Restore" }
        return "Restore backup of \(backup.familyName)?"
    }

    private var restoreMessage: String {
        guard let backup = pendingRestore else { return "" }
        let counts = backup.counts
        return "From \(backup.exportedAt.formatted(date: .abbreviated, time: .shortened)): \(counts["expense"] ?? 0) expenses, \(counts["receipt"] ?? 0) receipts, \(counts["category"] ?? 0) categories, \(counts["budget"] ?? 0) budgets, \(counts["scheduled"] ?? 0) recurring/planned, \(counts["goal"] ?? 0) savings goals."
    }

    private func makeCSV() {
        message = nil
        do {
            let data = CSVExport.expenses(periodExpenses, lookup: CategoryLookup(categories: categories, subcategories: subcategories),
                                          members: members, baseCurrency: family.baseCurrencyCode)
            csvURL = try CSVExport.writeFile(data, familyName: family.name, label: csvPeriod.title)
        } catch {
            message = "Could not create the CSV: \(error.localizedDescription)"
        }
    }

    private func makeBackup() {
        message = nil
        do {
            let backup = try BackupService.makeBackup(family: family, context: context, includePhotos: includePhotos)
            backupURL = try BackupService.writeFile(backup)
        } catch {
            message = "Could not create the backup: \(error.localizedDescription)"
        }
    }

    private func readBackup(_ result: Result<URL, Error>) {
        message = nil
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            pendingRestore = try FamilyBackup.decode(try Data(contentsOf: url))
        } catch FamilyBackup.ReadError.newerFormat {
            message = "This backup was made by a newer Familoq. Please update Familoq first."
        } catch {
            message = "This is not a Familoq backup file."
        }
    }

    private func restore() {
        guard let backup = pendingRestore else { return }
        pendingRestore = nil
        do {
            let summary = try BackupService.restore(backup, into: family, context: context,
                                                    currentUserRecordName: account.account?.userRecordName ?? "")
            sync.scanNow()
            message = "Restored: \(summary.added) added, \(summary.updated) updated" + (summary.skipped > 0 ? ", \(summary.skipped) skipped." : ".")
        } catch {
            message = "Restore failed: \(error.localizedDescription)"
        }
    }
}
