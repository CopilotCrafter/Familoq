import SwiftUI
import SwiftData
import UIKit
import FamiloqCore
import FamiloqBudget

/// What to export: pages of one or several documents.
struct ExportRequest: Identifiable {
    let id = UUID()
    let pages: [ExportPage]
    let name: String
    /// Contains ID cards / licences (front and back).
    let cardLike: Bool
}

/// Download / Share: layout, size, copy stamp, blacked-out areas, password.
struct DocumentExportSheet: View {
    let request: ExportRequest
    @Environment(\.dismiss) private var dismiss
    @AppStorage("documents.stampLanguage") private var stampLanguageRaw = (Bundle.main.preferredLocalizations.first ?? "en") == "de" ? "de" : "en"
    @State private var options: ExportOptions
    @State private var usePassword = false
    @State private var busy = false
    @State private var shareURL: URL?
    @State private var fileDocument: PDFFile?
    @State private var exporting = false
    @State private var message: String?

    init(request: ExportRequest) {
        self.request = request
        var options = ExportOptions(name: request.name)
        options.pairUnlabeled = request.cardLike
        options.twoSidesOnOnePage = request.cardLike && request.pages.contains { $0.side == .back }
        _options = State(initialValue: options)
    }

    private var imageCount: Int { request.pages.filter(\.isImage).count }
    private var boxCount: Int { options.redactions.values.reduce(0) { $0 + $1.count } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("File name", text: $options.name)
                    LabeledContent("Pages", value: "\(request.pages.count)")
                }
                if imageCount >= 2 {
                    Section {
                        Picker("Layout", selection: $options.twoSidesOnOnePage) {
                            Text("One page per side").tag(false)
                            Text("Both sides on one A4 page").tag(true)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        Text("Front & back")
                    } footer: {
                        Text("Both sides on one page is the usual copy for offices, banks and employers.")
                    }
                }
                Section {
                    Toggle(isOn: $options.stamp) {
                        Label("Mark as copy", systemImage: "seal")
                    }
                    if options.stamp {
                        Picker("Language", selection: $stampLanguageRaw) {
                            ForEach(CopyStamp.Language.allCases, id: \.rawValue) { Text(verbatim: $0.title).tag($0.rawValue) }
                        }
                        TextField("Only for, e.g. Bank, Visa, Landlord", text: $options.stampPurpose)
                        Text(verbatim: CopyStamp.text(language: language, purpose: options.stampPurpose, date: Date(), calendar: FamiloqCalendar.make()))
                            .font(.footnote.weight(.semibold)).foregroundStyle(.red)
                    }
                    NavigationLink {
                        RedactionPagesView(pages: request.pages, redactions: $options.redactions)
                    } label: {
                        HStack {
                            Label("Black out areas", systemImage: "rectangle.fill")
                            Spacer()
                            if boxCount > 0 { Text("\(boxCount)").foregroundStyle(.secondary) }
                        }
                    }
                } header: {
                    Text("Copy for someone else")
                } footer: {
                    Text("The stamp shows who the copy is for. On the German ID card you may black out the access number (CAN) and the serial number.")
                }
                Section {
                    Toggle("Smaller file", isOn: $options.smaller)
                    Toggle("Black & white", isOn: $options.blackAndWhite)
                } header: {
                    Text("Size")
                } footer: {
                    Text("For upload limits of online forms.")
                }
                Section {
                    Toggle("Protect with a password", isOn: $usePassword.animation())
                    if usePassword {
                        SecureField("Password", text: $options.password)
                    }
                } footer: {
                    if usePassword {
                        Text("Send the password separately, e.g. by phone or text message.")
                    }
                }
                Section {
                    Button {
                        Task { await share() }
                    } label: {
                        Label("Share / Download PDF", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        Task { await saveToFiles() }
                    } label: {
                        Label("Save to Files", systemImage: "folder")
                    }
                } footer: {
                    if let message { Text(LocalizedStringKey(message)).foregroundStyle(.red) }
                }
                .disabled(busy || options.name.trimmingCharacters(in: .whitespaces).isEmpty || (usePassword && options.password.isEmpty))
            }
            .overlay {
                if busy { ProgressView().controlSize(.large) }
            }
            .navigationTitle("Download / Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .sheet(item: Binding(get: { shareURL.map { SharedFile(url: $0) } }, set: { if $0 == nil { shareURL = nil } })) { item in
                ActivityView(items: [item.url])
            }
            .background(
                // Its own view: one view can present only one file panel.
                Color.clear.fileExporter(isPresented: $exporting, document: fileDocument, contentType: .pdf,
                                         defaultFilename: options.name) { result in
                    if case .failure = result { message = "Could not save the file." }
                }
            )
        }
    }

    private var language: CopyStamp.Language { CopyStamp.Language(rawValue: stampLanguageRaw) ?? .german }

    private var finalOptions: ExportOptions {
        var o = options
        o.stampLanguage = language
        o.name = DocumentService.fileName(o.name)
        if !usePassword { o.password = "" }
        return o
    }

    private func share() async {
        message = nil
        busy = true
        let pages = request.pages
        let o = finalOptions
        let url = await Task.detached(priority: .userInitiated) { DocumentExporter.file(pages, options: o) }.value
        busy = false
        if let url { shareURL = url } else { message = "Could not create the PDF." }
    }

    private func saveToFiles() async {
        message = nil
        busy = true
        let pages = request.pages
        let o = finalOptions
        let data = await Task.detached(priority: .userInitiated) { DocumentExporter.pdf(pages, options: o) }.value
        busy = false
        guard let data else {
            message = "Could not create the PDF."
            return
        }
        fileDocument = PDFFile(data: data)
        exporting = true
    }
}

private struct SharedFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// Pick a page, then drag boxes over what should be hidden.
private struct RedactionPagesView: View {
    let pages: [ExportPage]
    @Binding var redactions: [UUID: [CGRect]]
    @State private var images: [UUID: UIImage] = [:]

    var body: some View {
        List {
            Section {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    NavigationLink {
                        if let image = images[page.id] {
                            RedactionEditor(image: image, boxes: Binding(get: { redactions[page.id] ?? [] },
                                                                         set: { redactions[page.id] = $0 }))
                        } else {
                            ProgressView()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Group {
                                if let image = images[page.id] {
                                    Image(uiImage: image).resizable().scaledToFit()
                                } else {
                                    Color.secondary.opacity(0.12)
                                }
                            }
                            .frame(width: 54, height: 72)
                            Text("Page \(index + 1)")
                            Spacer()
                            let count = redactions[page.id]?.count ?? 0
                            if count > 0 {
                                Label("\(count)", systemImage: "rectangle.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } footer: {
                Text("Only the exported copy is changed. Covered text is really removed - the page is saved as a picture.")
            }
        }
        .navigationTitle("Black out areas")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            for page in pages where images[page.id] == nil {
                let format = page.format, data = page.data, turns = page.quarterTurns
                images[page.id] = await Task.detached(priority: .userInitiated) {
                    PageImage.image(format: format, data: data, quarterTurns: turns, width: 1400)
                }.value
            }
        }
    }
}

// MARK: - Asking for a document

struct DocumentRequestTarget: Identifiable {
    let id = UUID()
    let document: FamilyDocument?
}

/// "Please scan the birth certificate": a family reminder, linked to the
/// document when there is one.
struct DocumentRequestSheet: View {
    let family: Family
    let target: DocumentRequestTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var sync: SyncCoordinator
    @Query private var members: [FamilyMember]
    @State private var title: String
    @State private var who: Set<UUID> = []
    @State private var hasDue = true
    @State private var due: Date
    @State private var note = ""

    init(family: Family, target: DocumentRequestTarget) {
        self.family = family
        self.target = target
        let fid = family.id
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid && $0.isActive == true }, sort: \FamilyMember.joinedAt)
        let name = target.document?.displayTitle ?? ""
        _title = State(initialValue: name.isEmpty ? "" : String(localized: "Please bring or scan: \(name)"))
        _due = State(initialValue: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What is needed, e.g. Please scan the birth certificate", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Note, e.g. for the passport office", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section {
                    MemberChooser(members: members, selection: $who, everyoneLabel: "Everyone")
                } header: {
                    Text("Who")
                }
                Section {
                    Toggle("Needed by", isOn: $hasDue.animation())
                    if hasDue {
                        DatePicker("Date", selection: $due, displayedComponents: [.date])
                    }
                } footer: {
                    Text("Appears in Planner → Reminders, with a link to the document.")
                }
            }
            .navigationTitle("Request a document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let reminder = FamilyReminder(familyID: family.id, title: title.trimmingCharacters(in: .whitespaces))
        reminder.notes = note.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.createdByMemberID = session.currentMember?.id
        let day = Calendar.current.startOfDay(for: due)
        reminder.dueDate = hasDue ? day : nil
        reminder.repeatStart = hasDue ? day : nil
        reminder.assignees = who
        reminder.alertEnabled = true
        // A private document is not on the others' iPhones - no link then.
        if let document = target.document, !document.isPrivate { reminder.documentID = document.id }
        context.insert(reminder)
        try? context.save()
        sync.scanNow()
        Task {
            _ = await PlannerNotifications.requestPermissionIfNeeded()
            await PlannerNotifications.reschedule(context: context)
        }
        dismiss()
    }
}

/// Opens a document by its ID (from a reminder or a trip).
struct DocumentByID: View {
    let family: Family
    @Query private var documents: [FamilyDocument]

    init(family: Family, id: UUID) {
        self.family = family
        _documents = Query(filter: #Predicate<FamilyDocument> { $0.id == id })
    }

    var body: some View {
        if let document = documents.first {
            DocumentDetailView(family: family, document: document)
        } else {
            Text("This document is not on this iPhone.").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Travel documents in a trip

/// Trip → travel documents: passports, insurance cards and bookings needed
/// for the trip. They are stored on the iPhone, so they open without internet.
struct TripDocumentsSection: View {
    let family: Family
    let trip: Trip
    @Query private var documents: [FamilyDocument]
    @State private var choosing = false

    init(family: Family, trip: Trip) {
        self.family = family
        self.trip = trip
        let fid = family.id
        _documents = Query(filter: #Predicate<FamilyDocument> { $0.familyID == fid }, sort: \FamilyDocument.title)
    }

    var body: some View {
        let linked = documents.filter { $0.tripIDs.contains(trip.id) }
        Section {
            ForEach(linked) { doc in
                NavigationLink {
                    LazyView(DocumentDetailView(family: family, document: doc))
                } label: {
                    Label {
                        HStack {
                            Text(verbatim: doc.displayTitle)
                            if !doc.personName.isEmpty { Text(verbatim: doc.personName).foregroundStyle(.secondary) }
                            Spacer()
                            if let expires = doc.expiresOn, expires < trip.endDate {
                                Text("Expires before the trip ends").font(.caption).foregroundStyle(.red)
                            }
                        }
                    } icon: {
                        Image(systemName: doc.kind.icon)
                    }
                }
            }
            Button {
                choosing = true
            } label: {
                Label("Choose documents", systemImage: "doc.badge.plus")
            }
        } header: {
            Text("Travel documents")
        } footer: {
            Text("Opens with Face ID - also without internet, the documents are on this iPhone.")
        }
        .sheet(isPresented: $choosing) {
            VaultGate { TripDocumentPicker(trip: trip, documents: documents) }
        }
    }
}

private struct TripDocumentPicker: View {
    let trip: Trip
    let documents: [FamilyDocument]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sync: SyncCoordinator

    var body: some View {
        NavigationStack {
            List(documents) { doc in
                Button {
                    var ids = doc.tripIDs
                    if ids.contains(trip.id) { ids.remove(trip.id) } else { ids.insert(trip.id) }
                    doc.tripIDs = ids
                    doc.updatedAt = Date()
                    try? context.save()
                    sync.scanNow()
                } label: {
                    HStack {
                        Label {
                            VStack(alignment: .leading) {
                                Text(verbatim: doc.displayTitle)
                                if !doc.personName.isEmpty { Text(verbatim: doc.personName).font(.caption).foregroundStyle(.secondary) }
                            }
                        } icon: {
                            Image(systemName: doc.kind.icon)
                        }
                        Spacer()
                        if doc.tripIDs.contains(trip.id) { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Travel documents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
