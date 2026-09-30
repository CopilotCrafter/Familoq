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

/// Asks for Face ID / the passcode before showing the vault, and locks again
/// when the app goes to the background.
struct VaultGate<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.scenePhase) private var scenePhase
    @State private var unlocked = false

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
                unlocked = false
                DocumentService.clearExports()
            }
        }
    }

    private func unlock() async {
        guard !unlocked else { return }
        unlocked = await AppLock.shared.authenticate(reason: String(localized: "Open the family documents"))
    }
}

private struct DocumentsList: View {
    let family: Family
    @Query private var documents: [FamilyDocument]
    @Query private var members: [FamilyMember]
    @State private var editing: DocumentEditTarget?
    @State private var search = ""

    init(family: Family) {
        self.family = family
        let fid = family.id
        _documents = Query(filter: #Predicate<FamilyDocument> { $0.familyID == fid }, sort: \FamilyDocument.title)
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid }, sort: \FamilyMember.joinedAt)
    }

    var body: some View {
        let calendar = FamiloqCalendar.make()
        let now = Date()
        let names = MemberNames(members)
        let filtered = documents.filter { matches($0, names: names) }
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
        List {
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
            if !expiring.isEmpty && search.isEmpty {
                Section("Expiring") {
                    ForEach(expiring) { doc in link(doc, names: names, calendar: calendar, now: now) }
                }
            }
            ForEach(owners, id: \.self) { key in
                Section {
                    ForEach(groups[key] ?? []) { doc in link(doc, names: names, calendar: calendar, now: now) }
                } header: {
                    if key.isEmpty { Text("Household") } else { Text(verbatim: key) }
                }
            }
        }
        .searchable(text: $search, prompt: Text("Search documents"))
        .sheet(item: $editing) { target in
            DocumentForm(family: family, target: target)
        }
    }

    private func owner(_ doc: FamilyDocument, names: MemberNames) -> String {
        names.name(doc.memberID) ?? doc.personName
    }

    private func matches(_ doc: FamilyDocument, names: MemberNames) -> Bool {
        let text = search.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return true }
        let haystack = [doc.displayTitle, owner(doc, names: names), doc.number, doc.note,
                        String(localized: String.LocalizationValue(doc.kind.title))].joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(text)
    }

    private func link(_ doc: FamilyDocument, names: MemberNames, calendar: Calendar, now: Date) -> some View {
        NavigationLink {
            LazyView(DocumentDetailView(family: family, document: doc))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: doc.kind.icon).foregroundStyle(.indigo).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(verbatim: doc.displayTitle).font(.body.weight(.medium))
                        if doc.isPrivate { Image(systemName: "iphone").font(.caption).foregroundStyle(.secondary) }
                    }
                    let whose = owner(doc, names: names)
                    if !whose.isEmpty || doc.expiresOn != nil {
                        HStack(spacing: 4) {
                            if !whose.isEmpty { Text(verbatim: whose) }
                            if let expires = doc.expiresOn {
                                Text("valid until \(expires.formatted(date: .abbreviated, time: .omitted))")
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                ExpiryBadge(expiresOn: doc.expiresOn, now: now, calendar: calendar)
            }
        }
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
    @EnvironmentObject private var sync: SyncCoordinator
    @Query private var pages: [DocumentPage]
    @Query private var members: [FamilyMember]
    @Query private var cars: [Car]
    @State private var editing: DocumentEditTarget?
    @State private var exportURL: URL?
    @State private var exporting = false
    @State private var exportFile: PDFFile?
    @State private var scanning = false
    @State private var importing = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var viewing: DocumentPage?
    @State private var deletingPage: DocumentPage?
    @State private var message: String?

    init(family: Family, document: FamilyDocument) {
        self.family = family
        self.document = document
        let did = document.id
        let fid = family.id
        _pages = Query(filter: #Predicate<DocumentPage> { $0.documentID == did }, sort: \DocumentPage.sortOrder)
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid })
        _cars = Query(filter: #Predicate<Car> { $0.familyID == fid })
    }

    var body: some View {
        let calendar = FamiloqCalendar.make()
        List {
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
                                .contextMenu {
                                    Button("Delete page", role: .destructive) { deletingPage = page }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                addPagesMenu
            } header: {
                Text("Pages")
            }

            Section {
                Button {
                    download()
                } label: {
                    Label("Download / Share as PDF", systemImage: "square.and.arrow.down")
                }
                .disabled(pages.isEmpty)
                Button {
                    saveToFiles()
                } label: {
                    Label("Save to Files", systemImage: "folder")
                }
                .disabled(pages.isEmpty)
            } footer: {
                Text("Creates a PDF of all pages - to save in Files, print, mail or send to an office.")
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
                Button("Edit") { editing = DocumentEditTarget(document: document) }
            }
        }
        .sheet(item: $editing) { target in
            DocumentForm(family: family, target: target)
        }
        .sheet(item: Binding(get: { exportURL.map { ExportItem(url: $0) } }, set: { if $0 == nil { exportURL = nil } })) { item in
            ActivityView(items: [item.url])
        }
        .fileExporter(isPresented: $exporting, document: exportFile, contentType: .pdf,
                      defaultFilename: document.displayTitle) { result in
            if case .failure = result { message = "Could not save the file." }
        }
        .fullScreenCover(isPresented: $scanning) {
            DocumentScannerView(onFinish: { images in
                scanning = false
                addImages(images)
            }, onCancel: { scanning = false })
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { importFiles(urls) }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .sheet(item: $viewing) { page in
            PageViewer(page: page)
        }
        .confirmationDialog("Delete this page?", isPresented: Binding(get: { deletingPage != nil }, set: { if !$0 { deletingPage = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let page = deletingPage {
                    context.delete(page)
                    document.updatedAt = Date()
                    try? context.save()
                    sync.scanNow()
                }
                deletingPage = nil
            }
        }
    }

    private var addPagesMenu: some View {
        Menu {
            if DocumentScannerView.isAvailable {
                Button { scanning = true } label: { Label("Scan with camera", systemImage: "doc.viewfinder") }
            }
            PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                Label("Choose photos", systemImage: "photo.on.rectangle")
            }
            Button { importing = true } label: { Label("Import PDF or image file", systemImage: "folder") }
        } label: {
            Label("Add pages", systemImage: "plus.rectangle.on.rectangle")
        }
    }

    private func download() {
        message = nil
        guard let url = DocumentService.exportFile(document, pages: pages) else {
            message = "Could not create the PDF."
            return
        }
        exportURL = url
    }

    private func saveToFiles() {
        message = nil
        guard let data = DocumentService.pdf(of: pages) else {
            message = "Could not create the PDF."
            return
        }
        exportFile = PDFFile(data: data)
        exporting = true
    }

    private func addImages(_ images: [UIImage]) {
        let items = images.compactMap { DocumentService.storageJPEG($0).map { (format: "jpg", data: $0) } }
        guard !items.isEmpty else { return }
        DocumentService.addPages(items, to: document, context: context)
        try? context.save()
        sync.scanNow()
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { images.append(image) }
        }
        photoItems = []
        addImages(images)
    }

    private func importFiles(_ urls: [URL]) {
        var items: [(format: String, data: Data)] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
                guard data.count <= DocumentLimits.maxPDFBytes else {
                    message = "This PDF is too large (max. 20 MB)."
                    continue
                }
                items.append((format: "pdf", data: data))
            } else if let image = UIImage(data: data), let jpeg = DocumentService.storageJPEG(image) {
                items.append((format: "jpg", data: jpeg))
            }
        }
        guard !items.isEmpty else { return }
        DocumentService.addPages(items, to: document, context: context)
        try? context.save()
        sync.scanNow()
    }
}

enum DocumentLimits {
    static let maxPDFBytes = 20 * 1024 * 1024
}

private struct ExportItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// The share sheet (Save to Files, AirDrop, Mail, Print …).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A PDF for "Save to Files".
struct PDFFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct PageThumbnail: View {
    let page: DocumentPage

    var body: some View {
        Group {
            if page.isPDF {
                VStack(spacing: 6) {
                    Image(systemName: "doc.richtext.fill").font(.largeTitle).foregroundStyle(.red)
                    Text(verbatim: "PDF").font(.caption.weight(.semibold))
                }
                .frame(width: 90, height: 120)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            } else if let data = page.data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 90, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 6) {
                    ProgressView()
                    Text("Loading…").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(width: 90, height: 120)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
    }
}

/// Full-screen page with zoom (photos) or the PDF viewer.
private struct PageViewer: View {
    let page: DocumentPage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let data = page.data {
                    if page.isPDF {
                        PDFKitView(document: PDFDocument(data: data))
                    } else {
                        PDFKitView(document: PDFDocument.single(image: UIImage(data: data)))
                    }
                } else {
                    Text("This page is still downloading from iCloud.").foregroundStyle(.secondary)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

extension PDFDocument {
    /// A one-page PDF of a photo (so photos zoom like PDFs).
    static func single(image: UIImage?) -> PDFDocument? {
        guard let image, let page = PDFPage(image: image) else { return nil }
        let document = PDFDocument()
        document.insert(page, at: 0)
        return document
    }
}

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument?

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
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
    @State private var pending: [(format: String, data: Data)] = []
    @State private var scanning = false
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
                if target.document == nil {
                    Section {
                        if !pending.isEmpty {
                            Text("\(pending.count) pages added")
                        }
                        if DocumentScannerView.isAvailable {
                            Button { scanning = true } label: { Label("Scan with camera", systemImage: "doc.viewfinder") }
                        }
                        PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                            Label("Choose photos", systemImage: "photo.on.rectangle")
                        }
                        Button { importing = true } label: { Label("Import PDF or image file", systemImage: "folder") }
                    } header: {
                        Text("Pages")
                    }
                }
                Section {
                    TextField("Note", text: $note, axis: .vertical).lineLimit(1...4)
                    Toggle(isOn: $isPrivate) {
                        Label("Only on this iPhone", systemImage: "iphone")
                    }
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
            .fullScreenCover(isPresented: $scanning) {
                DocumentScannerView(onFinish: { images in
                    scanning = false
                    pending += images.compactMap { DocumentService.storageJPEG($0).map { (format: "jpg", data: $0) } }
                }, onCancel: { scanning = false })
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { importFiles(urls) }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await importPhotos(items) }
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

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
               let jpeg = DocumentService.storageJPEG(image) {
                pending.append((format: "jpg", data: jpeg))
            }
        }
        photoItems = []
    }

    private func importFiles(_ urls: [URL]) {
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
                guard data.count <= DocumentLimits.maxPDFBytes else {
                    message = "This PDF is too large (max. 20 MB)."
                    continue
                }
                pending.append((format: "pdf", data: data))
            } else if let image = UIImage(data: data), let jpeg = DocumentService.storageJPEG(image) {
                pending.append((format: "jpg", data: jpeg))
            }
        }
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
        document.updatedAt = Date()
        if !pending.isEmpty {
            DocumentService.addPages(pending, to: document, context: context)
        }
        DocumentService.setPrivate(document, isPrivate, context: context)
        try? context.save()
        sync.scanNow()
        Task {
            if hasExpiry && remind { _ = await PlannerNotifications.requestPermissionIfNeeded() }
            await PlannerNotifications.reschedule(context: context)
        }
        dismiss()
    }
}
