import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import PDFKit
import UniformTypeIdentifiers
import FamiloqCore
import FamiloqBudget

/// Planner → Documents: the family's document vault (passports, ID cards,
/// birth certificates, insurance policies, car registration …). Always
/// behind Face ID. Shared with the family through iCloud, or kept "Only on
/// this iPhone". Every document can be downloaded as a PDF.
struct DocumentsScreen: View {
    let family: Family

    var body: some View {
        VaultGate {
            DocumentsList(family: family)
        }
    }
}

/// Unlocked once for the list, its documents and their pages; locked again
/// as soon as Familoq goes to the background.
@MainActor
final class VaultLock: ObservableObject {
    static let shared = VaultLock()
    @Published var unlocked = false
}

/// Asks for Face ID / the passcode before showing the vault, and locks again
/// when the app goes to the background.
struct VaultGate<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var lock = VaultLock.shared

    private var unlocked: Bool { lock.unlocked }

    var body: some View {
        Group {
            if unlocked || !AppLock.shared.canUse {
                content()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "lock.doc.fill").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("Documents are protected").font(.headline)
                    Button {
                        Task { await unlock() }
                    } label: {
                        Label("Unlock with \(AppLock.shared.biometryName)", systemImage: "faceid")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await unlock() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                lock.unlocked = false
                DocumentService.clearExports()
            }
        }
    }

    private func unlock() async {
        guard !lock.unlocked else { return }
        if await AppLock.shared.authenticate(reason: String(localized: "Open the family documents")) {
            lock.unlocked = true
        }
    }
}

// MARK: - List

private struct DocumentsList: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @Query private var documents: [FamilyDocument]
    @Query private var members: [FamilyMember]
    @Query private var pages: [DocumentPage]
    @State private var editing: DocumentEditTarget?
    @State private var search = ""
    @State private var tag: String?
    @State private var selecting = false
    @State private var selected: [UUID] = []
    @State private var combining: ExportRequest?
    @State private var requesting: DocumentRequestTarget?

    init(family: Family) {
        self.family = family
        let fid = family.id
        _documents = Query(filter: #Predicate<FamilyDocument> { $0.familyID == fid }, sort: \FamilyDocument.title)
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid }, sort: \FamilyMember.joinedAt)
        _pages = Query(filter: #Predicate<DocumentPage> { $0.familyID == fid }, sort: \DocumentPage.sortOrder)
    }

    var body: some View {
        let calendar = FamiloqCalendar.make()
        let now = Date()
        let names = MemberNames(members)
        let texts = search.isEmpty ? [:] : pageTexts()
        let filtered = documents.filter { doc in
            (tag == nil || doc.tags.contains { $0.caseInsensitiveCompare(tag ?? "") == .orderedSame })
                && matches(doc, names: names, texts: texts)
        }
        let expiring = filtered.filter {
            switch DocumentExpiry.state(expiresOn: $0.expiresOn, now: now, calendar: calendar) {
            case .soon?, .expired?: return true
            default: return false
            }
        }
        let groups = Dictionary(grouping: filtered) { owner($0, names: names) }
        let owners = groups.keys.sorted { a, b in
            if a.isEmpty != b.isEmpty { return b.isEmpty }
            return a < b
        }
        let allTags = Array(Set(documents.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        List {
            if !selecting {
                Section {
                    Button {
                        editing = DocumentEditTarget(document: nil)
                    } label: {
                        Label("Add document", systemImage: "plus")
                    }
                } footer: {
                    if documents.isEmpty {
                        Text("Scan passports, ID cards, birth certificates, insurance policies or the car registration - or import a PDF. Familoq reminds you before a document expires. Mark a document \"Only on this iPhone\" to keep it off iCloud.")
                    }
                }
            } else {
                Section {
                    Text("Tap documents in the order they should appear in the PDF.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if !allTags.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            TagChip(title: String(localized: "All"), isOn: tag == nil) { tag = nil }
                            ForEach(allTags, id: \.self) { name in
                                TagChip(title: name, isOn: tag == name) { tag = tag == name ? nil : name }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
            }
            if !expiring.isEmpty && search.isEmpty && tag == nil && !selecting {
                Section("Expiring") {
                    ForEach(expiring) { doc in row(doc, names: names, calendar: calendar, now: now) }
                }
            }
            ForEach(owners, id: \.self) { key in
                Section {
                    ForEach(groups[key] ?? []) { doc in row(doc, names: names, calendar: calendar, now: now) }
                } header: {
                    if key.isEmpty { Text("Household") } else { Text(verbatim: key) }
                }
            }
        }
        .searchable(text: $search, prompt: Text("Search documents and their text"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if selecting {
                    Button("Cancel") {
                        selecting = false
                        selected = []
                    }
                } else {
                    Menu {
                        Button {
                            selecting = true
                        } label: {
                            Label("Combine into one PDF", systemImage: "doc.on.doc")
                        }
                        Button {
                            requesting = DocumentRequestTarget(document: nil)
                        } label: {
                            Label("Request a document", systemImage: "person.crop.circle.badge.questionmark")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                Button {
                    combine()
                } label: {
                    Label("Combine \(selected.count) into one PDF", systemImage: "doc.on.doc.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
                .padding()
                .background(.bar)
            }
        }
        .sheet(item: $editing) { target in
            DocumentForm(family: family, target: target)
        }
        .sheet(item: $combining) { request in
            DocumentExportSheet(request: request)
        }
        .sheet(item: $requesting) { target in
            DocumentRequestSheet(family: family, target: target)
        }
        .task {
            DocumentService.splitStoredPDFs(familyID: family.id, context: context)
            await DocumentText.readMissing(familyID: family.id, context: context)
        }
    }

    private func pageTexts() -> [UUID: String] {
        var result: [UUID: String] = [:]
        for page in pages where !page.text.isEmpty {
            result[page.documentID, default: ""] += " " + page.text
        }
        return result
    }

    private func owner(_ doc: FamilyDocument, names: MemberNames) -> String {
        names.name(doc.memberID) ?? doc.personName
    }

    private func matches(_ doc: FamilyDocument, names: MemberNames, texts: [UUID: String]) -> Bool {
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
        return DocumentSearch.matches(query: search, in: [
            doc.displayTitle, owner(doc, names: names), doc.number, doc.note, doc.tagsRaw,
            String(localized: String.LocalizationValue(doc.kind.title)), texts[doc.id] ?? ""
        ])
    }

    private func combine() {
        let chosen = selected.compactMap { id in documents.first { $0.id == id } }
        var exportPages: [ExportPage] = []
        for doc in chosen {
            exportPages += DocumentExporter.exportPages(pages.filter { $0.documentID == doc.id }, cardLike: doc.kind.isTwoSided)
        }
        let name = chosen.count == 1 ? chosen[0].displayTitle : String(localized: "Documents")
        combining = ExportRequest(pages: exportPages, name: DocumentService.fileName(name),
                                  cardLike: chosen.contains { $0.kind.isTwoSided })
        selecting = false
        selected = []
    }

    @ViewBuilder
    private func row(_ doc: FamilyDocument, names: MemberNames, calendar: Calendar, now: Date) -> some View {
        if selecting {
            Button {
                if let index = selected.firstIndex(of: doc.id) { selected.remove(at: index) } else { selected.append(doc.id) }
            } label: {
                HStack {
                    if let index = selected.firstIndex(of: doc.id) {
                        Text(verbatim: "\(index + 1)")
                            .font(.caption.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 24, height: 24).background(Circle().fill(Color.accentColor))
                    } else {
                        Image(systemName: "circle").font(.title3).foregroundStyle(.secondary).frame(width: 24)
                    }
                    rowLabel(doc, names: names, calendar: calendar, now: now)
                }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                LazyView(DocumentDetailView(family: family, document: doc))
            } label: {
                rowLabel(doc, names: names, calendar: calendar, now: now)
            }
        }
    }

    private func rowLabel(_ doc: FamilyDocument, names: MemberNames, calendar: Calendar, now: Date) -> some View {
        let whose = owner(doc, names: names)
        return HStack(spacing: 12) {
            Image(systemName: doc.kind.icon).foregroundStyle(.indigo).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(verbatim: doc.displayTitle).font(.body.weight(.medium))
                    if doc.isPrivate { Image(systemName: "iphone").font(.caption).foregroundStyle(.secondary) }
                }
                if !whose.isEmpty || doc.expiresOn != nil || !doc.tags.isEmpty {
                    HStack(spacing: 4) {
                        if !whose.isEmpty { Text(verbatim: whose) }
                        if let expires = doc.expiresOn {
                            Text("valid until \(expires.formatted(date: .abbreviated, time: .omitted))")
                        }
                        if !doc.tags.isEmpty { Text(verbatim: "· " + doc.tags.joined(separator: ", ")).lineLimit(1) }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            ExpiryBadge(expiresOn: doc.expiresOn, now: now, calendar: calendar)
        }
        .contentShape(Rectangle())
    }
}

struct TagChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.subheadline.weight(isOn ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

struct ExpiryBadge: View {
    let expiresOn: Date?
    let now: Date
    let calendar: Calendar

    var body: some View {
        switch DocumentExpiry.state(expiresOn: expiresOn, now: now, calendar: calendar) {
        case .expired?:
            Text("Expired").font(.caption.weight(.semibold)).foregroundStyle(.red)
        case .soon(let days)?:
            Text("\(days) days").font(.caption.weight(.semibold)).foregroundStyle(days <= 30 ? .red : .orange)
        default:
            EmptyView()
        }
    }
}

struct DocumentEditTarget: Identifiable {
    let id = UUID()
    let document: FamilyDocument?
}

// MARK: - Detail

struct DocumentDetailView: View {
    let family: Family
    let document: FamilyDocument
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sync: SyncCoordinator
    @Query private var pages: [DocumentPage]
    @Query private var members: [FamilyMember]
    @Query private var cars: [Car]
    @Query private var trips: [Trip]
    @State private var editing: DocumentEditTarget?
    @State private var exportRequest: ExportRequest?
    @State private var scanMode: ScanMode?
    @State private var guide: ScanMode?
    @State private var importing = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var viewing: DocumentPage?
    @State private var editingPages = false
    @State private var requesting: DocumentRequestTarget?
    @State private var message: String?

    init(family: Family, document: FamilyDocument) {
        self.family = family
        self.document = document
        let did = document.id
        let fid = family.id
        _pages = Query(filter: #Predicate<DocumentPage> { $0.documentID == did }, sort: \DocumentPage.sortOrder)
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid })
        _cars = Query(filter: #Predicate<Car> { $0.familyID == fid })
        _trips = Query(filter: #Predicate<Trip> { $0.familyID == fid })
    }

    var body: some View {
        // Deleted in the edit sheet: never touch the deleted document, go back.
        if document.isDeleted || document.modelContext == nil {
            Color.clear.onAppear { dismiss() }
        } else {
            VaultGate { content }
        }
    }

    private var hasBack: Bool { pages.contains { $0.side == .back } }

    private var content: some View {
        let calendar = FamiloqCalendar.make()
        let missing = pages.filter { $0.data == nil }.count
        return List {
            Section {
                if pages.isEmpty {
                    Text("No pages yet - scan the document or import a photo or PDF.").foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(pages) { page in
                                Button {
                                    viewing = page
                                } label: {
                                    PageThumbnail(page: page)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if document.kind.isTwoSided && !hasBack && !pages.isEmpty {
                    Button {
                        guide = .back
                    } label: {
                        Label("Add back side", systemImage: "rectangle.on.rectangle.angled")
                    }
                }
                AddPagesMenu(twoSided: document.kind.isTwoSided, onScan: { guide = $0 },
                             importing: $importing, photoItems: $photoItems)
                if pages.count > 0 {
                    Button {
                        editingPages = true
                    } label: {
                        Label("Edit pages", systemImage: "square.grid.2x2")
                    }
                }
            } header: {
                Text("Pages")
            } footer: {
                if missing > 0 {
                    Text("\(missing) pages are still downloading from iCloud.")
                }
            }

            Section {
                Button {
                    exportRequest = ExportRequest(pages: DocumentExporter.exportPages(pages, cardLike: document.kind.isTwoSided),
                                                  name: exportName, cardLike: document.kind.isTwoSided)
                } label: {
                    Label("Download / Share as PDF", systemImage: "square.and.arrow.down")
                }
                .disabled(pages.isEmpty)
            } footer: {
                Text("Save in Files, print, mail or send to an office - as a copy with a stamp, blacked-out numbers, a password or smaller if you like.")
            }

            Section {
                LabeledContent("Type") {
                    Label(LocalizedStringKey(document.kind.title), systemImage: document.kind.icon)
                }
                let owner = MemberNames(members).name(document.memberID) ?? document.personName
                if !owner.isEmpty { LabeledContent("Belongs to") { Text(verbatim: owner) } }
                if let car = cars.first(where: { $0.id == document.carID }) {
                    LabeledContent("Car") { Text(verbatim: car.displayName) }
                }
                if !document.number.isEmpty {
                    LabeledContent("Number") {
                        Text(verbatim: document.number).textSelection(.enabled)
                    }
                    .contextMenu {
                        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = document.number }
                    }
                }
                if let issued = document.issuedOn {
                    LabeledContent("Issued", value: issued.formatted(date: .long, time: .omitted))
                }
                if let expires = document.expiresOn {
                    LabeledContent {
                        HStack {
                            Text(verbatim: expires.formatted(date: .long, time: .omitted))
                            ExpiryBadge(expiresOn: expires, now: Date(), calendar: calendar)
                        }
                    } label: {
                        Text("Valid until")
                    }
                }
                if !document.tags.isEmpty {
                    LabeledContent("Tags") { Text(verbatim: document.tags.joined(separator: ", ")) }
                }
                let tripNames = trips.filter { document.tripIDs.contains($0.id) }.map(\.name)
                if !tripNames.isEmpty {
                    LabeledContent("Trips") { Text(verbatim: tripNames.joined(separator: ", ")) }
                }
                if !document.note.isEmpty { Text(verbatim: document.note).font(.callout) }
                Label(document.isPrivate ? LocalizedStringKey("Only on this iPhone") : LocalizedStringKey("Shared with the family"),
                      systemImage: document.isPrivate ? "iphone" : "person.2.fill")
                    .foregroundStyle(.secondary)
            }
            if let message {
                Section { Text(LocalizedStringKey(message)).foregroundStyle(.red) }
            }
        }
        .navigationTitle(Text(verbatim: document.displayTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        editing = DocumentEditTarget(document: document)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button {
                        requesting = DocumentRequestTarget(document: document)
                    } label: {
                        Label("Ask a family member", systemImage: "person.crop.circle.badge.questionmark")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $editing) { target in
            DocumentForm(family: family, target: target)
        }
        .sheet(item: $exportRequest) { request in
            DocumentExportSheet(request: request)
        }
        .sheet(item: $requesting) { target in
            DocumentRequestSheet(family: family, target: target)
        }
        .sheet(isPresented: $editingPages) {
            PageEditorView(family: family, document: document)
        }
        .sheet(item: $viewing) { page in
            VaultGate { PageViewer(page: page) }
        }
        .scanGuide(mode: $guide, scanning: $scanMode)
        .fullScreenCover(item: $scanMode) { mode in
            DocumentScannerView(onFinish: { images in
                scanMode = nil
                let new = DocumentService.pages(from: images, twoSided: mode != .pages, firstSide: mode == .back ? .back : .front)
                if mode == .back {
                    guard !new.isEmpty else { return }
                    DocumentService.addBack(Array(new.prefix(1)), to: document, context: context)
                    try? context.save()
                    sync.scanNow()
                    Task { await DocumentText.readMissing(familyID: family.id, context: context) }
                } else {
                    add(new)
                }
            }, onCancel: { scanMode = nil })
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                let imported = PageImport.files(urls)
                message = imported.tooLarge ? "This PDF is too large (max. 20 MB)." : nil
                add(imported.pages)
            }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                let new = await PageImport.photos(items)
                photoItems = []
                add(new)
            }
        }
    }

    private var exportName: String {
        let owner = MemberNames(members).name(document.memberID) ?? document.personName
        return DocumentService.fileName(owner.isEmpty ? document.displayTitle : "\(document.displayTitle) - \(owner)")
    }

    private func add(_ items: [NewPage]) {
        guard !items.isEmpty else { return }
        DocumentService.addPages(items, to: document, context: context)
        try? context.save()
        sync.scanNow()
        Task { await DocumentText.readMissing(familyID: family.id, context: context) }
    }
}

// MARK: - Form

struct DocumentForm: View {
    let family: Family
    let target: DocumentEditTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var sync: SyncCoordinator
    @Query private var members: [FamilyMember]
    @Query private var cars: [Car]
    @Query private var trips: [Trip]
    @Query private var allDocuments: [FamilyDocument]
    @State private var title: String
    @State private var kind: DocumentKind
    @State private var memberID: UUID?
    @State private var personName: String
    @State private var carID: UUID?
    @State private var number: String
    @State private var hasIssued: Bool
    @State private var issued: Date
    @State private var hasExpiry: Bool
    @State private var expires: Date
    @State private var remind: Bool
    @State private var note: String
    @State private var isPrivate: Bool
    @State private var tags: [String]
    @State private var newTag = ""
    @State private var tripIDs: Set<UUID>
    @State private var pending: [NewPage] = []
    @State private var scanMode: ScanMode?
    @State private var guide: ScanMode?
    @State private var importing = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var confirmDelete = false
    @State private var message: String?

    init(family: Family, target: DocumentEditTarget) {
        self.family = family
        self.target = target
        let fid = family.id
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid && $0.isActive == true }, sort: \FamilyMember.joinedAt)
        _cars = Query(filter: #Predicate<Car> { $0.familyID == fid && $0.isArchived == false }, sort: \Car.sortOrder)
        _trips = Query(filter: #Predicate<Trip> { $0.familyID == fid && $0.isArchived == false }, sort: \Trip.startDate)
        _allDocuments = Query(filter: #Predicate<FamilyDocument> { $0.familyID == fid })
        let d = target.document
        let inFiveYears = Calendar.current.date(byAdding: .year, value: 5, to: Date()) ?? Date()
        _title = State(initialValue: d?.title ?? "")
        _kind = State(initialValue: d?.kind ?? .passport)
        _memberID = State(initialValue: d?.memberID)
        _personName = State(initialValue: d?.personName ?? "")
        _carID = State(initialValue: d?.carID)
        _number = State(initialValue: d?.number ?? "")
        _hasIssued = State(initialValue: d?.issuedOn != nil)
        _issued = State(initialValue: d?.issuedOn ?? Date())
        _hasExpiry = State(initialValue: d.map { $0.expiresOn != nil } ?? true)
        _expires = State(initialValue: d?.expiresOn ?? inFiveYears)
        _remind = State(initialValue: d?.remind ?? true)
        _note = State(initialValue: d?.note ?? "")
        _isPrivate = State(initialValue: d?.isPrivate ?? false)
        _tags = State(initialValue: d?.tags ?? [])
        _tripIDs = State(initialValue: d?.tripIDs ?? [])
    }

    private var tagChoices: [String] {
        let year = Calendar.current.component(.year, from: Date())
        var result = DocumentTags.suggested(year: year).map { tag in
            tag.hasPrefix("Taxes ") ? String(localized: "Taxes \(year)") : String(localized: String.LocalizationValue(tag))
        }
        for tag in allDocuments.flatMap(\.tags) + tags where !result.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            result.append(tag)
        }
        return result
    }

    private var upcomingTrips: [Trip] {
        let today = Calendar.current.startOfDay(for: Date())
        return trips.filter { $0.endDate >= today || tripIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(DocumentKind.allCases) { k in
                            Label(LocalizedStringKey(k.title), systemImage: k.icon).tag(k)
                        }
                    }
                    TextField("Title (optional)", text: $title)
                    TextField("Number (optional)", text: $number)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
                Section {
                    Picker("Belongs to", selection: $memberID) {
                        Text("Nobody / other person").tag(UUID?.none)
                        ForEach(members) { Text(verbatim: $0.displayName).tag(Optional($0.id)) }
                    }
                    if memberID == nil {
                        TextField("Name, e.g. a child", text: $personName)
                    }
                    if !cars.isEmpty && (kind == .carRegistration || kind == .insurance || kind == .contract || kind == .other || carID != nil) {
                        Picker("Car", selection: $carID) {
                            Text("None").tag(UUID?.none)
                            ForEach(cars) { Text(verbatim: $0.displayName).tag(Optional($0.id)) }
                        }
                    }
                }
                Section {
                    Toggle("Issue date", isOn: $hasIssued.animation())
                    if hasIssued {
                        DatePicker("Issued", selection: $issued, displayedComponents: [.date])
                    }
                    Toggle("Expiry date", isOn: $hasExpiry.animation())
                    if hasExpiry {
                        DatePicker("Valid until", selection: $expires, displayedComponents: [.date])
                        Toggle("Remind me before it expires", isOn: $remind)
                    }
                } footer: {
                    if hasExpiry && remind {
                        Text(kind.reminderDays == [90, 30] ? LocalizedStringKey("Reminder 90 and 30 days before - renewing takes weeks.")
                                                           : LocalizedStringKey("Reminder 30 and 7 days before."))
                    }
                }
                Section {
                    FlowTags(choices: tagChoices, selection: $tags)
                    HStack {
                        TextField("New tag", text: $newTag)
                        Button("Add") {
                            let tag = newTag.trimmingCharacters(in: .whitespaces)
                            if !tag.isEmpty && !tags.contains(tag) { tags.append(tag) }
                            newTag = ""
                        }
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Tags")
                }
                if !upcomingTrips.isEmpty {
                    Section {
                        ForEach(upcomingTrips) { trip in
                            Toggle(isOn: Binding(get: { tripIDs.contains(trip.id) }, set: { on in
                                if on { tripIDs.insert(trip.id) } else { tripIDs.remove(trip.id) }
                            })) {
                                Text(verbatim: trip.name)
                            }
                        }
                    } header: {
                        Text("Needed for trips")
                    } footer: {
                        Text("Shown in the trip's travel documents.")
                    }
                }
                if target.document == nil {
                    Section {
                        if !pending.isEmpty {
                            Text("\(pending.count) pages added")
                        }
                        AddPagesMenu(twoSided: kind.isTwoSided, onScan: { guide = $0 },
                                     importing: $importing, photoItems: $photoItems)
                    } header: {
                        Text("Pages")
                    }
                }
                Section {
                    TextField("Note", text: $note, axis: .vertical).lineLimit(1...4)
                    Toggle(isOn: $isPrivate) {
                        Label("Only on this iPhone", systemImage: "iphone")
                    }
                    .disabled(!canChangePrivacy)
                } footer: {
                    Text(isPrivate ? LocalizedStringKey("Not shared with the family and not stored in iCloud - include it in your own backups.")
                                   : LocalizedStringKey("Shared only with your family through iCloud. Opening documents always needs Face ID or your passcode."))
                }
                if let message {
                    Section { Text(LocalizedStringKey(message)).foregroundStyle(.red) }
                }
                if target.document != nil {
                    Section {
                        Button("Delete document", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(target.document == nil ? LocalizedStringKey("New document") : LocalizedStringKey("Edit document"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .scanGuide(mode: $guide, scanning: $scanMode)
            .fullScreenCover(item: $scanMode) { mode in
                DocumentScannerView(onFinish: { images in
                    scanMode = nil
                    pending += DocumentService.pages(from: images, twoSided: mode != .pages, firstSide: mode == .back ? .back : .front)
                }, onCancel: { scanMode = nil })
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    let imported = PageImport.files(urls)
                    message = imported.tooLarge ? "This PDF is too large (max. 20 MB)." : nil
                    pending += imported.pages
                }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    let new = await PageImport.photos(items)
                    pending += new
                    photoItems = []
                }
            }
            .confirmationDialog("Delete this document and all its pages?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let document = target.document { DocumentService.delete(document, context: context) }
                    sync.scanNow()
                    dismiss()
                }
            }
        }
    }

    /// Taking a shared document off everyone's iPhones is up to whoever
    /// added it (or the owner).
    private var canChangePrivacy: Bool {
        guard let document = target.document, !document.isPrivate else { return true }
        guard let me = session.currentMember else { return false }
        return me.role == .owner || document.createdByMemberID == nil || document.createdByMemberID == me.id
    }

    private func save() {
        let document: FamilyDocument
        if let existing = target.document {
            document = existing
        } else {
            document = FamilyDocument(familyID: family.id, title: "")
            document.createdByMemberID = session.currentMember?.id
            context.insert(document)
        }
        document.title = title.trimmingCharacters(in: .whitespaces)
        document.kind = kind
        document.memberID = memberID
        document.personName = memberID == nil ? personName.trimmingCharacters(in: .whitespaces) : ""
        document.carID = carID
        document.number = number.trimmingCharacters(in: .whitespaces)
        document.issuedOn = hasIssued ? issued : nil
        document.expiresOn = hasExpiry ? expires : nil
        document.remind = hasExpiry && remind
        document.note = note
        document.tags = tags
        document.tripIDs = tripIDs
        document.updatedAt = Date()
        if !pending.isEmpty {
            DocumentService.addPages(pending, to: document, context: context)
        }
        DocumentService.setPrivate(document, isPrivate, context: context)
        try? context.save()
        sync.scanNow()
        let fid = family.id
        Task {
            if hasExpiry && remind { _ = await PlannerNotifications.requestPermissionIfNeeded() }
            await PlannerNotifications.reschedule(context: context)
            await DocumentText.readMissing(familyID: fid, context: context)
        }
        dismiss()
    }
}

/// Tag choices as toggle chips.
struct FlowTags: View {
    let choices: [String]
    @Binding var selection: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(choices, id: \.self) { tag in
                    let isOn = selection.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
                    TagChip(title: tag, isOn: isOn) {
                        if isOn {
                            selection.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
                        } else {
                            selection.append(tag)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}
