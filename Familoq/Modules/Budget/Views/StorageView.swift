import SwiftUI
import SwiftData
import UIKit
import FamiloqCore

/// Family → Storage: what Familoq uses on this iPhone and in iCloud, making
/// photos smaller, "Keep receipt photos" and archiving a year.
struct StorageView: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var sync: SyncCoordinator
    @State private var photos: [PhotoStorage.Photo] = []
    @State private var localBytes = 0
    @State private var recordCount = 0
    @State private var loaded = false
    @State private var retention: PhotoStorage.Retention = .forever
    @State private var pendingRetention: PhotoStorage.Retention?
    @State private var compressing: (done: Int, total: Int)?
    @State private var message: String?
    @State private var showArchive = false

    private var receiptPhotos: [PhotoStorage.Photo] { photos.filter { $0.kind == .receipt } }
    private var expensePhotos: [PhotoStorage.Photo] { photos.filter { $0.kind == .expense } }
    private var photoBytes: Int { photos.map(\.bytes).reduce(0, +) }
    /// Records (not photos) take about 1 KB each in iCloud.
    private var dataBytes: Int { recordCount * 1_000 }
    private var isOwnFamily: Bool { sync.zoneRecord(for: family.id)?.isShared != true }

    var body: some View {
        List {
            if !loaded {
                ProgressView("Measuring…")
            } else {
                phoneSection
                iCloudSection
                yearsSection
                largestSection
                if session.isOwner { cleanupSection }
                settingsLinks
            }
        }
        .navigationTitle("Storage")
        .task { load() }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { pendingRetention != nil }, set: { if !$0 { cancelRetention() } }),
                            titleVisibility: .visible) {
            Button("Archive first…") {
                showArchive = true
                cancelRetention()
            }
            Button("Remove old photos", role: .destructive) { confirmRetention() }
            Button("Cancel", role: .cancel) { cancelRetention() }
        } message: {
            Text("Only the photos are removed - shop, date, items and amounts stay, also in reports. Photos marked \"Keep\" are never removed. This happens on every iPhone of the family and frees space in your iCloud.")
        }
        .sheet(isPresented: $showArchive) {
            ArchiveSheet(family: family, photos: photos)
        }
    }

    private func load() {
        photos = PhotoStorage.photos(familyID: family.id, context: context)
        localBytes = PhotoStorage.localBytes()
        let fid = family.id
        recordCount = (try? context.fetchCount(FetchDescriptor<SyncLedgerEntry>(predicate: #Predicate { $0.familyID == fid }))) ?? 0
        retention = PhotoStorage.retention(familyID: family.id)
        loaded = true
    }

    // MARK: Sections

    private var phoneSection: some View {
        Section {
            LabeledContent("Familoq in total", value: PhotoStorage.format(localBytes))
            LabeledContent("Receipt photos (\(receiptPhotos.count))", value: PhotoStorage.format(receiptPhotos.map(\.bytes).reduce(0, +)))
            LabeledContent("Photos on expenses (\(expensePhotos.count))", value: PhotoStorage.format(expensePhotos.map(\.bytes).reduce(0, +)))
            LabeledContent("Everything else", value: PhotoStorage.format(max(0, localBytes - photoBytes)))
        } header: {
            Text("On this iPhone")
        } footer: {
            Text("\"Familoq in total\" covers all families on this iPhone; the photo lines are for \(family.name).")
        }
    }

    private var iCloudSection: some View {
        Section {
            if isOwnFamily {
                LabeledContent("Photos", value: PhotoStorage.format(photoBytes))
                LabeledContent("Data (\(recordCount) entries)", value: "≈ " + PhotoStorage.format(dataBytes))
                LabeledContent("Total in your iCloud", value: "≈ " + PhotoStorage.format(photoBytes + dataBytes))
            } else {
                Label("This family is stored in the owner's iCloud - it does not use your iCloud storage.", systemImage: "icloud")
                    .font(.subheadline)
            }
        } header: {
            Text("In iCloud")
        } footer: {
            Text("Worked out from what Familoq has synced; Apple's own figure (iPhone Settings) can differ slightly.")
        }
    }

    @ViewBuilder
    private var yearsSection: some View {
        let byYear = Dictionary(grouping: photos) { Calendar.current.component(.year, from: $0.date) }
        if !byYear.isEmpty {
            Section("Photos by year") {
                ForEach(byYear.keys.sorted(by: >), id: \.self) { year in
                    let list = byYear[year] ?? []
                    LabeledContent("\(String(year)) · \(list.count) photo(s)", value: PhotoStorage.format(list.map(\.bytes).reduce(0, +)))
                }
            }
        }
    }

    @ViewBuilder
    private var largestSection: some View {
        let largest = photos.sorted { $0.bytes > $1.bytes }.prefix(5)
        if !largest.isEmpty {
            Section("Largest photos") {
                ForEach(Array(largest)) { photo in
                    HStack {
                        if photo.keep { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: photo.merchant)
                            Text(verbatim: photo.date.formatted(date: .abbreviated, time: .omitted) + " · " + photo.total)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(PhotoStorage.format(photo.bytes)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var cleanupSection: some View {
        Section {
            if let compressing {
                ProgressView(value: Double(compressing.done), total: Double(max(compressing.total, 1))) {
                    Text("Making photos smaller… \(compressing.done) of \(compressing.total)")
                }
            } else {
                Button {
                    Task { await compress() }
                } label: {
                    Label("Make photos smaller", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .disabled(photos.isEmpty)
            }
            Picker(selection: Binding(get: { retention }, set: { requestRetention($0) })) {
                ForEach(PhotoStorage.Retention.allCases) { option in
                    Text(LocalizedStringKey(option.title)).tag(option)
                }
            } label: {
                Label("Keep receipt photos", systemImage: "clock.arrow.circlepath")
            }
            Button {
                showArchive = true
            } label: {
                Label("Archive photos (PDF or ZIP)…", systemImage: "archivebox")
            }
            .disabled(photos.isEmpty)
            if let message {
                Text(verbatim: message).font(.footnote).foregroundStyle(.green)
            }
        } header: {
            Text("Clean up")
        } footer: {
            Text("\"Make photos smaller\" re-saves large photos in grayscale (receipts stay readable). \"Keep receipt photos\" removes older photos automatically on your iPhone; the receipts stay. Mark a receipt with \"Keep photo\" for warranty or tax.")
        }
    }

    private var settingsLinks: some View {
        Section {
            Button("Open iPhone Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        } header: {
            Text("All apps")
        } footer: {
            Text("iOS does not let apps see other apps' storage. iPhone: Settings → General → iPhone Storage. iCloud: Settings → your name → iCloud → Manage Account Storage (Familoq is listed there).")
        }
    }

    // MARK: Actions

    private var confirmTitle: String {
        guard let pendingRetention else { return "" }
        let old = PhotoStorage.candidates(photos, retention: pendingRetention)
        return String(localized: "Remove \(old.count) photo(s) older than \(String(localized: String.LocalizationValue(pendingRetention.title))) (\(PhotoStorage.format(old.map(\.bytes).reduce(0, +))))?")
    }

    private func requestRetention(_ value: PhotoStorage.Retention) {
        guard value != retention else { return }
        if value == .forever || PhotoStorage.candidates(photos, retention: value).isEmpty {
            retention = value
            PhotoStorage.setRetention(value, familyID: family.id)
            message = nil
        } else {
            pendingRetention = value
        }
    }

    private func confirmRetention() {
        guard let value = pendingRetention else { return }
        pendingRetention = nil
        retention = value
        PhotoStorage.setRetention(value, familyID: family.id)
        let freed = PhotoStorage.applyRetention(familyID: family.id, context: context)
        sync.scanNow()
        load()
        message = String(localized: "Removed old photos - \(PhotoStorage.format(freed)) freed.")
    }

    private func cancelRetention() {
        pendingRetention = nil
    }

    private func compress() async {
        let list = photos
        compressing = (0, list.count)
        let saved = await PhotoStorage.makeSmaller(list, context: context) { done in
            compressing = (done, list.count)
        }
        compressing = nil
        sync.scanNow()
        load()
        message = saved > 0 ? String(localized: "Photos are \(PhotoStorage.format(saved)) smaller now.") : String(localized: "The photos are already small.")
    }
}

/// Pick a year and a format, then save/share the file.
private struct ArchiveSheet: View {
    let family: Family
    let photos: [PhotoStorage.Photo]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var year: Int
    @State private var format: PhotoStorage.ArchiveFormat = .pdf
    @State private var file: URL?
    @State private var working = false
    @State private var errorText: String?

    private var years: [Int] { Array(Set(photos.map { Calendar.current.component(.year, from: $0.date) })).sorted(by: >) }

    init(family: Family, photos: [PhotoStorage.Photo]) {
        self.family = family
        self.photos = photos
        let years = Set(photos.map { Calendar.current.component(.year, from: $0.date) })
        _year = State(initialValue: years.min() ?? Calendar.current.component(.year, from: Date()))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Year", selection: $year) {
                        ForEach(years, id: \.self) { y in
                            let count = photos.filter { Calendar.current.component(.year, from: $0.date) == y }.count
                            Text(verbatim: "\(y) (\(count))").tag(y)
                        }
                    }
                    Picker("Format", selection: $format) {
                        ForEach(PhotoStorage.ArchiveFormat.allCases) { f in
                            Text(LocalizedStringKey(f.title)).tag(f)
                        }
                    }
                    .pickerStyle(.inline)
                } footer: {
                    Text("Save the file in Files or iCloud Drive (or on a computer) before removing photos from Familoq.")
                }
                Section {
                    if let file {
                        ShareLink(item: file) {
                            Label("Save or share \(file.lastPathComponent)", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            create()
                        } label: {
                            HStack {
                                Label("Create archive", systemImage: "archivebox")
                                if working { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(working || years.isEmpty)
                    }
                    if let errorText {
                        Text(verbatim: errorText).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("Archive photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: year) { _, _ in file = nil }
            .onChange(of: format) { _, _ in file = nil }
        }
    }

    private func create() {
        working = true
        errorText = nil
        defer { working = false }
        let list = photos.filter { Calendar.current.component(.year, from: $0.date) == year }
        do {
            file = try PhotoStorage.archive(list, year: year, familyName: family.name, format: format, context: context)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
