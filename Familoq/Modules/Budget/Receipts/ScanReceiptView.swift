import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import FamiloqCore
import FamiloqBudget

/// Scan tab: camera (VisionKit) or photo import -> on-device OCR -> review.
struct ScanReceiptView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        NavigationStack {
            if let family = session.family {
                ScanReceiptContent(family: family)
            } else {
                ProgressView()
            }
        }
    }
}

private struct ScanReceiptContent: View {
    let family: Family

    @EnvironmentObject private var session: AppSession
    @Environment(\.modelContext) private var context
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @Query private var rules: [MerchantRuleRecord]
    @Query private var recentReceipts: [ReceiptRecord]

    @State private var showScanner = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    /// The check screen, shown full screen with its own navigation.
    @State private var review: ReviewRequest?
    /// Read once when the Scan tab is first created (after a crash).
    @State private var interruptedStep: String? = ScanBreadcrumb.current

    init(family: Family) {
        self.family = family
        let fid = family.id
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid }, sort: \ExpenseCategory.sortOrder)
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid }, sort: \ExpenseSubcategory.sortOrder)
        _rules = Query(filter: #Predicate<MerchantRuleRecord> { $0.familyID == fid })
        var recent = FetchDescriptor<ReceiptRecord>(predicate: #Predicate<ReceiptRecord> { $0.familyID == fid },
                                                    sortBy: [SortDescriptor(\ReceiptRecord.createdAt, order: .reverse)])
        recent.fetchLimit = 10
        _recentReceipts = Query(recent)
    }

    var body: some View {
        List {
            if let interrupted = interruptedStep {
                Section {
                    Label("The last scan stopped during: \(interrupted). Please tell the developer (screenshot).", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }
            Section {
                VStack(spacing: 14) {
                    Image(systemName: "doc.viewfinder")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                    Text("Scan a receipt")
                        .font(.title3.weight(.semibold))
                    Text("Merchant, date & time, total, currency, VAT and individual items are read on your iPhone - also receipts from abroad. If the currency is unclear, Familoq asks. You check everything before it is saved.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if DocumentScannerView.isAvailable {
                        Button {
                            showScanner = true
                        } label: {
                            Label("Scan with camera", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose a photo", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)

                    Button("No receipt? Add manually") { session.selectedTab = .add }
                        .font(.footnote)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            if isProcessing {
                Section { ProgressView("Reading receipt…") }
            }
            if let errorMessage {
                Section { Text(LocalizedStringKey(errorMessage)).foregroundStyle(.red) }
            }

            if !recentReceipts.isEmpty {
                Section("Recent receipts") {
                    ForEach(recentReceipts) { receipt in
                        NavigationLink {
                            LazyView(ReceiptDetailView(receipt: receipt))
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(receipt.merchant)
                                    Text(receipt.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(receipt.total.currency(receipt.currencyCode)).monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            // Shown once; a new scan starts with a clean slate.
            if interruptedStep != nil && !isProcessing && review == nil { ScanBreadcrumb.clear() }
        }
        .navigationTitle("Scan")
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { pages in
                showScanner = false
                Task { await process(pages: pages) }
            } onCancel: {
                showScanner = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                defer { photoItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    errorMessage = "The photo could not be loaded."
                    return
                }
                await process(pages: [image])
            }
        }
        .fullScreenCover(item: $review) { request in
            NavigationStack {
                ReceiptReviewView(family: family, draft: request.draft, lookup: request.lookup) {
                    review = nil
                    ScanBreadcrumb.clear()
                }
            }
        }
    }

    private func process(pages: [UIImage]) async {
        errorMessage = nil
        isProcessing = true
        defer { isProcessing = false }
        let size = pages.first.map { "\(Int($0.size.width * $0.scale))x\(Int($0.size.height * $0.scale))" } ?? "-"
        ScanBreadcrumb.set("text recognition (\(pages.count) page(s), \(size))")
        do {
            let fragments = try await ReceiptOCRService.recognize(pages: pages)
            ScanBreadcrumb.set("line assembly (\(fragments.count) text pieces)")
            let lines = ReceiptLineAssembler.lines(from: fragments)
            ScanBreadcrumb.set("reading the receipt (\(lines.count) lines)")
            let parsed = ReceiptParser.parse(lines: lines)
            ScanBreadcrumb.set("storing the image")
            let imageData = pages.first.flatMap { ReceiptOCRService.storageJPEG(from: $0) }
            ScanBreadcrumb.set("preparing the check screen (currency \(parsed.currencyCode ?? "?"))")
            let lookup = CategoryLookup(categories: categories, subcategories: subcategories)
            let fid = family.id
            let itemRules = (try? context.fetch(FetchDescriptor<ItemCategoryRule>(predicate: #Predicate { $0.familyID == fid }))) ?? []
            let newDraft = ReceiptDrafting.draft(
                from: parsed,
                family: family,
                lookup: lookup,
                rules: rules,
                imageData: imageData,
                itemRules: itemRules
            )
            ScanBreadcrumb.set("the check screen (currency \(newDraft.currencyCode), \(newDraft.items.count) items)")
            review = ReviewRequest(draft: newDraft, lookup: lookup)
        } catch {
            ScanBreadcrumb.clear()
            errorMessage = error.localizedDescription
        }
    }
}

/// Stored receipt with its items (opened from Scan or from an expense).
struct ReceiptDetailView: View {
    let receipt: ReceiptRecord
    /// Off when opened from an expense that the edit could replace.
    var allowsEditing = true
    @Query private var items: [ReceiptItemRecord]
    @Query private var categories: [ExpenseCategory]
    @Query private var subcategories: [ExpenseSubcategory]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @State private var showImage = false
    @State private var editRequest: ReviewRequest?
    @State private var warrantyTarget: WarrantyEditTarget?

    init(receipt: ReceiptRecord, allowsEditing: Bool = true) {
        self.allowsEditing = allowsEditing
        self.receipt = receipt
        let rid = receipt.id
        let fid = receipt.familyID
        _items = Query(filter: #Predicate<ReceiptItemRecord> { $0.receiptID == rid }, sort: \ReceiptItemRecord.sortOrder)
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid })
        _subcategories = Query(filter: #Predicate<ExpenseSubcategory> { $0.familyID == fid })
    }

    var body: some View {
        let lookup = CategoryLookup(categories: categories, subcategories: subcategories)
        List {
            Section {
                LabeledContent("Merchant", value: receipt.merchant)
                LabeledContent("Date", value: receipt.date.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Total", value: receipt.total.currency(receipt.currencyCode))
                if !receipt.vatSummary.isEmpty {
                    LabeledContent("VAT", value: receipt.vatSummary)
                }
                Button {
                    warrantyTarget = WarrantyEditTarget(warranty: nil, prefill: WarrantyPrefill(
                        itemName: items.max(by: { $0.amount < $1.amount })?.name ?? receipt.merchant,
                        merchant: receipt.merchant, date: receipt.date, amount: receipt.total,
                        currencyCode: receipt.currencyCode, receiptID: receipt.id, expenseID: nil))
                } label: {
                    Label("Add warranty", systemImage: "checkmark.shield")
                }
            }
            if !items.isEmpty {
                Section("Items") {
                    ForEach(items) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name)
                                Text(lookup.path(categoryID: item.categoryID, subcategoryID: item.subcategoryID))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.amount.currency(receipt.currencyCode)).monospacedDigit()
                        }
                    }
                }
            }
            if let data = receipt.imageData, let image = UIImage(data: data) {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 360)
                        .onTapGesture { showImage = true }
                    Toggle(isOn: Binding(get: { receipt.keepPhoto }, set: { value in
                        receipt.keepPhoto = value
                        try? context.save()
                    })) {
                        Label("Keep photo (warranty or tax)", systemImage: "pin.fill")
                    }
                } header: {
                    Text("Receipt image")
                } footer: {
                    Text("Kept photos are never removed by \"Keep receipt photos\" (Family → Storage). \(PhotoStorage.format(data.count))")
                }
            }
        }
        .navigationTitle("Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if allowsEditing && canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { startEditing(lookup: lookup) }
                }
            }
        }
        .sheet(item: $warrantyTarget) { target in
            if let family = session.family {
                WarrantyForm(family: family, target: target)
            }
        }
        .fullScreenCover(item: $editRequest) { request in
            NavigationStack {
                if let family = session.family {
                    ReceiptReviewView(family: family, draft: request.draft, lookup: request.lookup, editing: receipt) {
                        editRequest = nil
                    }
                }
            }
        }
        .sheet(isPresented: $showImage) {
            if let data = receipt.imageData, let image = UIImage(data: data) {
                ScrollView([.vertical, .horizontal]) {
                    Image(uiImage: image)
                }
            }
        }
    }
}

extension ReceiptDetailView {
    /// Owner, anyone allowed to edit everyone's expenses, or who saved it.
    var canEdit: Bool {
        guard let membership = session.membership else { return false }
        return membership.has(.allExpenses) || receipt.createdByMemberID == session.currentMember?.id
    }

    func startEditing(lookup: CategoryLookup) {
        let fid = receipt.familyID
        let itemRules = (try? context.fetch(FetchDescriptor<ItemCategoryRule>(predicate: #Predicate { $0.familyID == fid }))) ?? []
        editRequest = ReviewRequest(draft: ReceiptDrafting.draft(editing: receipt, items: items, lookup: lookup, itemRules: itemRules),
                                    lookup: lookup)
    }
}

/// Remembers the step a scan is in. If Familoq is closed by a crash, the
/// Scan tab shows where it stopped the next time (no crash log needed).
enum ScanBreadcrumb {
    private static let key = "scan.breadcrumb"

    private static let writesKey = "scan.breadcrumb.writes"
    private static var renders = 0
    private static var writes = 0

    static func set(_ step: String) {
        UserDefaults.standard.set(step, forKey: key)
    }

    /// Counts how often the check screen is built (an endless loop shows up
    /// as a huge number).
    static func render(_ step: String) {
        renders += 1
        if renders % 10 == 1 { set("\(step) (render \(renders), writes \(writes))") }
    }

    /// Which fields of the receipt were changed by the screen itself.
    static func noteWrite(_ fields: String) {
        writes += 1
        if writes <= 5 || writes % 20 == 0 {
            UserDefaults.standard.set("write \(writes): \(fields)", forKey: writesKey)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: writesKey)
        renders = 0
        writes = 0
    }

    static var current: String? {
        guard let step = UserDefaults.standard.string(forKey: key) else { return nil }
        if let lastWrite = UserDefaults.standard.string(forKey: writesKey) { return step + " - last " + lastWrite }
        return step
    }
}

/// One opening of the check screen.
struct ReviewRequest: Identifiable {
    let id = UUID()
    let draft: ReceiptDraft
    let lookup: CategoryLookup
}
