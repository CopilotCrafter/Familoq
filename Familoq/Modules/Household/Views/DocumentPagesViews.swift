import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import PDFKit
import UniformTypeIdentifiers
import FamiloqCore
import FamiloqBudget

/// How the camera is used: any pages, a card's front and back, or only the back.
enum ScanMode: String, Identifiable {
    case pages, frontBack, back
    var id: String { rawValue }
}

enum DocumentLimits {
    static let maxPDFBytes = 20 * 1024 * 1024
}

// MARK: - Adding pages

struct AddPagesMenu: View {
    let twoSided: Bool
    let onScan: (ScanMode) -> Void
    @Binding var importing: Bool
    @Binding var photoItems: [PhotosPickerItem]

    var body: some View {
        Menu {
            if DocumentScannerView.isAvailable {
                if twoSided {
                    Button { onScan(.frontBack) } label: { Label("Scan front & back", systemImage: "rectangle.on.rectangle.angled") }
                }
                Button { onScan(.pages) } label: { Label("Scan with camera", systemImage: "doc.viewfinder") }
            }
            PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                Label("Choose photos", systemImage: "photo.on.rectangle")
            }
            Button { importing = true } label: { Label("Import PDF or image file", systemImage: "folder") }
        } label: {
            Label("Add pages", systemImage: "plus.rectangle.on.rectangle")
        }
    }
}

/// Short instructions before scanning a card, then the camera.
private struct ScanGuide: ViewModifier {
    @Binding var mode: ScanMode?
    @Binding var scanning: ScanMode?

    func body(content: Content) -> some View {
        content
            .onChange(of: mode) { _, newValue in
                if newValue == .pages {
                    mode = nil
                    scanning = .pages
                }
            }
            .alert(title, isPresented: Binding(get: { mode == .frontBack || mode == .back }, set: { if !$0 { mode = nil } })) {
                Button("Start scanning") {
                    let chosen = mode
                    mode = nil
                    // Let the alert close before the camera opens.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { scanning = chosen }
                }
                Button("Cancel", role: .cancel) { mode = nil }
            } message: {
                Text(mode == .back
                     ? LocalizedStringKey("Turn the card over and scan the back, then tap Save.")
                     : LocalizedStringKey("Scan the front, turn the card over and scan the back, then tap Save. Both sides are kept as front and back."))
            }
    }

    private var title: LocalizedStringKey {
        mode == .back ? "Back side" : "Front & back"
    }
}

extension View {
    func scanGuide(mode: Binding<ScanMode?>, scanning: Binding<ScanMode?>) -> some View {
        modifier(ScanGuide(mode: mode, scanning: scanning))
    }
}

@MainActor
enum PageImport {
    /// PDFs (one page each) and image files.
    static func files(_ urls: [URL]) -> (pages: [NewPage], tooLarge: Bool) {
        var pages: [NewPage] = []
        var tooLarge = false
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
                guard data.count <= DocumentLimits.maxPDFBytes else {
                    tooLarge = true
                    continue
                }
                pages += DocumentService.pages(fromPDF: data)
            } else if let image = UIImage(data: data), let jpeg = DocumentService.storageJPEG(image) {
                pages.append(NewPage(format: "jpg", data: jpeg))
            }
        }
        return (pages, tooLarge)
    }

    static func photos(_ items: [PhotosPickerItem]) async -> [NewPage] {
        var pages: [NewPage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
               let jpeg = DocumentService.storageJPEG(image) {
                pages.append(NewPage(format: "jpg", data: jpeg))
            }
        }
        return pages
    }
}

// MARK: - Showing pages

struct PageThumbnail: View {
    let page: DocumentPage
    var width: CGFloat = 90
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if page.data == nil {
                    VStack(spacing: 6) {
                        ProgressView()
                        Text("Loading…").font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Color.secondary.opacity(0.12)
                }
            }
            .frame(width: width, height: width * 4 / 3)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            if page.side != .none {
                Text(LocalizedStringKey(page.side.title))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(4)
            } else if page.isPDF {
                Text(verbatim: "PDF")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
                    .padding(4)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
        .task(id: "\(page.id)-\(page.quarterTurns)-\(page.byteCount)-\(page.data != nil)") {
            guard let data = page.data else { image = nil; return }
            let format = page.format
            let turns = page.quarterTurns
            let px = width * 3
            image = await Task.detached(priority: .userInitiated) {
                PageImage.image(format: format, data: data, quarterTurns: turns, width: px)
            }.value
        }
    }
}

/// Full-screen page with zoom (photos and PDFs alike).
struct PageViewer: View {
    let page: DocumentPage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let data = page.data {
                    PDFKitView(document: viewerDocument(data))
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

    private func viewerDocument(_ data: Data) -> PDFDocument? {
        if page.isPDF, let doc = PDFDocument(data: data) {
            for index in 0..<doc.pageCount {
                if let p = doc.page(at: index) { p.rotation = (p.rotation + page.quarterTurns * 90) % 360 }
            }
            return doc
        }
        return PDFDocument.single(image: PageImage.image(format: page.format, data: data, quarterTurns: page.quarterTurns))
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

    func updateUIView(_ view: PDFView, context: Context) {}
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

// MARK: - Page editor

/// Reorder, turn, label (front/back), replace, delete and split pages.
struct PageEditorView: View {
    let family: Family
    let document: FamilyDocument
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sync: SyncCoordinator
    @Query private var pages: [DocumentPage]
    @State private var replacing: DocumentPage?
    @State private var splitting: DocumentPage?
    @State private var deleting: DocumentPage?
    @State private var editMode: EditMode = .inactive

    init(family: Family, document: FamilyDocument) {
        self.family = family
        self.document = document
        let did = document.id
        _pages = Query(filter: #Predicate<DocumentPage> { $0.documentID == did }, sort: \DocumentPage.sortOrder)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        row(page, index: index)
                    }
                    .onMove { from, to in
                        var list = pages
                        list.move(fromOffsets: from, toOffset: to)
                        DocumentService.reorder(list)
                        saved()
                    }
                    .onDelete { offsets in
                        if let index = offsets.first { deleting = pages[index] }
                    }
                } footer: {
                    Text("Tap Reorder to move pages. Swipe to delete. Touch and hold a page to replace it or split the document there.")
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("Edit pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode == .active ? LocalizedStringKey("Done reordering") : LocalizedStringKey("Reorder")) {
                        withAnimation { editMode = editMode == .active ? .inactive : .active }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fullScreenCover(item: $replacing) { page in
                DocumentScannerView(onFinish: { images in
                    replacing = nil
                    replace(page, with: images.first)
                }, onCancel: { replacing = nil })
                .ignoresSafeArea()
            }
            .confirmationDialog("Split the document here?", isPresented: Binding(get: { splitting != nil }, set: { if !$0 { splitting = nil } }),
                                titleVisibility: .visible) {
                Button("Move this and the following pages to a new document") {
                    if let page = splitting {
                        DocumentService.split(document, atPage: page.id, context: context)
                        sync.scanNow()
                    }
                    splitting = nil
                }
            }
            .confirmationDialog("Delete this page?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let page = deleting {
                        context.delete(page)
                        DocumentService.reorder(pages.filter { $0.id != page.id })
                        saved()
                    }
                    deleting = nil
                }
            }
        }
    }

    private func row(_ page: DocumentPage, index: Int) -> some View {
        HStack(spacing: 12) {
            PageThumbnail(page: page, width: 54)
            VStack(alignment: .leading, spacing: 6) {
                Text("Page \(index + 1)").font(.subheadline.weight(.medium))
                Picker("Side", selection: Binding(get: { page.side }, set: { page.side = $0; saved() })) {
                    ForEach(PageSide.allCases, id: \.self) { side in
                        Text(LocalizedStringKey(side == .none ? "Not a card side" : side.title)).tag(side)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            Spacer()
            Button {
                page.quarterTurns = (page.quarterTurns + 3) % 4
                saved()
            } label: {
                Image(systemName: "rotate.left")
            }
            .buttonStyle(.borderless)
            Button {
                page.quarterTurns = (page.quarterTurns + 1) % 4
                saved()
            } label: {
                Image(systemName: "rotate.right")
            }
            .buttonStyle(.borderless)
        }
        .contextMenu {
            if DocumentScannerView.isAvailable {
                Button { replacing = page } label: { Label("Replace with a new scan", systemImage: "camera") }
            }
            if index > 0 {
                Button { splitting = page } label: { Label("Split into a new document from here", systemImage: "scissors") }
            }
            Button(role: .destructive) { deleting = page } label: { Label("Delete page", systemImage: "trash") }
        }
    }

    private func replace(_ page: DocumentPage, with image: UIImage?) {
        guard let image, let data = DocumentService.storageJPEG(image) else { return }
        let new = DocumentPage(familyID: page.familyID, documentID: page.documentID, format: "jpg", data: data, sortOrder: page.sortOrder)
        new.side = page.side
        new.isPrivate = page.isPrivate
        context.insert(new)
        context.delete(page)
        saved()
        let fid = family.id
        Task { await DocumentText.readMissing(familyID: fid, context: context) }
    }

    private func saved() {
        document.updatedAt = Date()
        try? context.save()
        sync.scanNow()
    }
}

// MARK: - Black out areas

/// Draw black boxes over numbers that must not be shared. Only the exported
/// copy is changed - and there the page becomes a picture, so the covered
/// text is really gone.
struct RedactionEditor: View {
    let image: UIImage
    @Binding var boxes: [CGRect]
    @State private var draft: CGRect?

    var body: some View {
        GeometryReader { geo in
            let frame = DocumentExporter.fit(image.size, in: CGRect(origin: .zero, size: geo.size).insetBy(dx: 8, dy: 8))
            ZStack(alignment: .topLeading) {
                Color.clear
                Image(uiImage: image)
                    .resizable()
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                ForEach(Array(boxes.enumerated()), id: \.offset) { _, box in
                    let r = denormalize(box, in: frame)
                    Rectangle().fill(Color.black)
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                }
                if let draft {
                    let r = denormalize(draft, in: frame)
                    Rectangle().fill(Color.black.opacity(0.6))
                        .overlay(Rectangle().stroke(Color.red, lineWidth: 2))
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in draft = normalized(from: value.startLocation, to: value.location, in: frame) }
                    .onEnded { value in
                        let box = normalized(from: value.startLocation, to: value.location, in: frame)
                        if box.width > 0.01 && box.height > 0.005 { boxes.append(box) }
                        draft = nil
                    }
            )
        }
        .navigationTitle("Black out")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    if !boxes.isEmpty { boxes.removeLast() }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(boxes.isEmpty)
                Spacer()
                Text("Drag over what should be hidden").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear", role: .destructive) { boxes.removeAll() }.disabled(boxes.isEmpty)
            }
        }
    }

    private func normalized(from a: CGPoint, to b: CGPoint, in frame: CGRect) -> CGRect {
        func clamp(_ v: CGFloat) -> CGFloat { min(1, max(0, v)) }
        let x1 = clamp((a.x - frame.minX) / frame.width), y1 = clamp((a.y - frame.minY) / frame.height)
        let x2 = clamp((b.x - frame.minX) / frame.width), y2 = clamp((b.y - frame.minY) / frame.height)
        return CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
    }

    private func denormalize(_ box: CGRect, in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + box.minX * frame.width, y: frame.minY + box.minY * frame.height,
               width: box.width * frame.width, height: box.height * frame.height)
    }
}
