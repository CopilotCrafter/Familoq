import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqPlanner

struct ShoppingListScreen: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var lists: [ShoppingList]
    @Query private var items: [ShoppingItem]
    @Query private var members: [FamilyMember]
    @AppStorage("shopping.listID") private var selectedListRaw = ""
    @State private var newText = ""
    @State private var showBought = true
    @State private var editing: ShoppingItem?
    @State private var showLists = false
    @FocusState private var addFocused: Bool

    init(family: Family) {
        self.family = family
        let fid = family.id
        _lists = Query(filter: #Predicate<ShoppingList> { $0.familyID == fid },
                       sort: [SortDescriptor(\ShoppingList.sortOrder), SortDescriptor(\ShoppingList.createdAt)])
        _items = Query(filter: #Predicate<ShoppingItem> { $0.familyID == fid }, sort: \ShoppingItem.createdAt)
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid }, sort: \FamilyMember.joinedAt)
    }

    private var currentList: ShoppingList? {
        lists.first { $0.id.uuidString == selectedListRaw } ?? lists.first
    }

    private var listItems: [ShoppingItem] {
        guard let list = currentList else { return [] }
        return items.filter { $0.listID == list.id && !$0.isCleared }
    }

    private var openItems: [ShoppingItem] { listItems.filter { !$0.isBought } }
    private var bought: [ShoppingItem] { listItems.filter(\.isBought).sorted { ($0.boughtAt ?? .distantPast) > ($1.boughtAt ?? .distantPast) } }

    private struct Aisle: Identifiable {
        let key: String
        let items: [ShoppingItem]
        var id: String { key }
    }

    private var aisles: [Aisle] {
        Dictionary(grouping: openItems) { $0.aisleKey.isEmpty ? ShoppingAisles.other : $0.aisleKey }
            .map { Aisle(key: $0.key, items: $0.value) }
            .sorted { ShoppingAisles.order(of: $0.key) < ShoppingAisles.order(of: $1.key) }
    }

    private var suggestions: [String] {
        let history = items.filter(\.isBought).map { (name: $0.name, date: $0.boughtAt ?? $0.updatedAt) }
        return ShoppingSuggestions.frequent(history: history, excludingOpen: openItems.map(\.name), prefix: newText, limit: 10)
    }

    var body: some View {
        let names = MemberNames(members)
        List {
            Section {
                HStack {
                    TextField("Add, e.g. 2x Milk", text: $newText)
                        .focused($addFocused)
                        .submitLabel(.done)
                        .onSubmit { add(newText, keepFocus: true) }
                    Button {
                        add(newText, keepFocus: true)
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                let chips = suggestions
                if !chips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(chips, id: \.self) { name in
                                Button {
                                    add(name, keepFocus: addFocused)
                                } label: {
                                    Label(name, systemImage: "arrow.counterclockwise")
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .controlSize(.small)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            } footer: {
                if lists.count > 1, let list = currentList {
                    Text("List: \(list.name)")
                }
            }

            if openItems.isEmpty {
                Section {
                    Text(bought.isEmpty
                         ? LocalizedStringKey("The list is empty. Add what the family needs - everyone sees it at once. Items on a scanned receipt are ticked off automatically.")
                         : LocalizedStringKey("Everything is in the cart."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(aisles) { aisle in
                Section(LocalizedStringKey(ShoppingAisles.name(of: aisle.key))) {
                    ForEach(aisle.items) { item in
                        row(item, names: names)
                    }
                }
            }

            if !bought.isEmpty {
                Section {
                    if showBought {
                        ForEach(bought) { item in
                            row(item, names: names)
                        }
                    }
                    Button {
                        withAnimation {
                            if let list = currentList { ShoppingService.clearBought(listID: list.id, context: context) }
                        }
                    } label: {
                        Label("Clear bought items", systemImage: "trash")
                    }
                } header: {
                    HStack {
                        Text("In the cart (\(bought.count))")
                        Spacer()
                        Button(showBought ? LocalizedStringKey("Hide") : LocalizedStringKey("Show")) { withAnimation { showBought.toggle() } }
                            .font(.caption)
                            .textCase(nil)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("List", selection: Binding(get: { currentList?.id.uuidString ?? "" }, set: { selectedListRaw = $0 })) {
                        ForEach(lists) { list in
                            Text(verbatim: list.name.isEmpty ? String(localized: "Shopping") : list.name).tag(list.id.uuidString)
                        }
                    }
                    Divider()
                    Button {
                        showLists = true
                    } label: {
                        Label("Manage lists", systemImage: "list.bullet")
                    }
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
            }
        }
        .sheet(item: $editing) { item in
            ShoppingItemEditor(item: item, lists: lists)
        }
        .sheet(isPresented: $showLists) {
            ShoppingListsEditor(family: family, lists: lists)
        }
        .task {
            if lists.isEmpty {
                _ = ShoppingService.lists(familyID: family.id, context: context)
            }
            ShoppingService.prune(familyID: family.id, context: context)
        }
    }

    private func row(_ item: ShoppingItem, names: MemberNames) -> some View {
        Button {
            withAnimation {
                ShoppingService.setBought(item, !item.isBought, memberID: session.currentMember?.id, context: context)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isBought ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isBought ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(verbatim: item.name)
                            .strikethrough(item.isBought)
                            .foregroundStyle(item.isBought ? .secondary : .primary)
                        if !item.quantity.isEmpty {
                            Text(verbatim: item.quantity)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                    let detail = detailText(item, names: names)
                    if !detail.isEmpty {
                        Text(verbatim: detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                context.delete(item)
                try? context.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                editing = item
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    private func detailText(_ item: ShoppingItem, names: MemberNames) -> String {
        var parts: [String] = []
        if !item.note.isEmpty { parts.append(item.note) }
        if item.isBought, let who = names.name(item.boughtByMemberID), item.boughtByMemberID != session.currentMember?.id {
            parts.append(String(localized: "bought by \(who)"))
        } else if !item.isBought, let who = names.name(item.addedByMemberID), item.addedByMemberID != session.currentMember?.id {
            parts.append(String(localized: "added by \(who)"))
        }
        return parts.joined(separator: " · ")
    }

    private func add(_ text: String, keepFocus: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let listID = currentList?.id ?? ShoppingService.lists(familyID: family.id, context: context).first?.id
        guard let listID else { return }
        withAnimation {
            _ = ShoppingService.add(trimmed, listID: listID, familyID: family.id, memberID: session.currentMember?.id, context: context)
        }
        if text == newText { newText = "" }
        if keepFocus { addFocused = true }
    }
}

/// Edit one item. Keeps its own copy and writes back on Save.
private struct ShoppingItemEditor: View {
    let item: ShoppingItem
    let lists: [ShoppingList]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var quantity: String
    @State private var note: String
    @State private var aisleKey: String
    @State private var listID: UUID

    init(item: ShoppingItem, lists: [ShoppingList]) {
        self.item = item
        self.lists = lists
        _name = State(initialValue: item.name)
        _quantity = State(initialValue: item.quantity)
        _note = State(initialValue: item.note)
        _aisleKey = State(initialValue: item.aisleKey.isEmpty ? ShoppingAisles.other : item.aisleKey)
        _listID = State(initialValue: item.listID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item", text: $name)
                    TextField("Amount, e.g. 2 or 500 g", text: $quantity)
                    TextField("Note, e.g. brand", text: $note)
                }
                Section {
                    Picker("Section", selection: $aisleKey) {
                        ForEach(ShoppingAisles.walkOrder, id: \.self) { key in
                            Text(LocalizedStringKey(ShoppingAisles.name(of: key))).tag(key)
                        }
                    }
                    if lists.count > 1 {
                        Picker("List", selection: $listID) {
                            ForEach(lists) { list in
                                Text(verbatim: list.name).tag(list.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        item.name = name.trimmingCharacters(in: .whitespaces)
        item.quantity = quantity.trimmingCharacters(in: .whitespaces)
        item.note = note.trimmingCharacters(in: .whitespaces)
        item.aisleKey = aisleKey
        item.listID = listID
        item.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}

/// Add, rename and delete shopping lists (e.g. Supermarket, Drugstore).
private struct ShoppingListsEditor: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [Draft]
    @State private var newName = ""
    @State private var deleted: Set<UUID> = []

    struct Draft: Identifiable {
        let id: UUID
        var name: String
        let isNew: Bool
    }

    init(family: Family, lists: [ShoppingList]) {
        self.family = family
        _drafts = State(initialValue: lists.map { Draft(id: $0.id, name: $0.name, isNew: false) })
    }

    private var visible: [Draft] { drafts.filter { !deleted.contains($0.id) } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($drafts) { $draft in
                        if !deleted.contains(draft.id) {
                            TextField("Name", text: $draft.name)
                                .swipeActions {
                                    if visible.count > 1 {
                                        Button("Delete", role: .destructive) { deleted.insert(draft.id) }
                                    }
                                }
                        }
                    }
                } footer: {
                    Text("Swipe to delete a list together with its items.")
                }
                Section("New list") {
                    HStack {
                        TextField("e.g. Drugstore", text: $newName)
                        Button("Add") {
                            drafts.append(Draft(id: UUID(), name: newName.trimmingCharacters(in: .whitespaces), isNew: true))
                            newName = ""
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
        }
    }

    private func save() {
        let existing = ShoppingService.lists(familyID: family.id, context: context, createIfNeeded: false)
        let byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (index, draft) in drafts.enumerated() {
            let name = draft.name.trimmingCharacters(in: .whitespaces)
            if deleted.contains(draft.id) {
                if let list = byID[draft.id] {
                    let lid = list.id
                    let listItems = (try? context.fetch(FetchDescriptor<ShoppingItem>(predicate: #Predicate { $0.listID == lid }))) ?? []
                    for item in listItems { context.delete(item) }
                    context.delete(list)
                }
            } else if let list = byID[draft.id] {
                if !name.isEmpty, list.name != name { list.name = name; list.updatedAt = Date() }
                if list.sortOrder != index { list.sortOrder = index; list.updatedAt = Date() }
            } else if draft.isNew, !name.isEmpty {
                context.insert(ShoppingList(id: draft.id, familyID: family.id, name: name, sortOrder: index))
            }
        }
        try? context.save()
        dismiss()
    }
}
