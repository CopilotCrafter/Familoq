import SwiftUI
import SwiftData
import CloudKit
import FamiloqCore

struct FamilyView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        NavigationStack {
            if let family = session.family {
                FamilySettingsContent(family: family)
            } else {
                ProgressView()
            }
        }
    }
}

private struct FamilySettingsContent: View {
    @Bindable var family: Family
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var sync: SyncCoordinator
    @Query private var members: [FamilyMember]
    @State private var confirmRemoval = false

    init(family: Family) {
        self.family = family
        let fid = family.id
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid && $0.isActive == true }, sort: \FamilyMember.joinedAt)
    }

    var body: some View {
        Form {
            if session.families.count > 1 {
                Section {
                    ForEach(session.families) { other in
                        Button {
                            session.switchTo(familyID: other.id, context: context)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(other.name.isEmpty ? String(localized: "Family") : other.name)
                                        .foregroundStyle(.primary)
                                    Text(ownerLine(for: other))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if other.id == family.id {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Your families")
                } footer: {
                    Text("Each family's data is kept separate.")
                }
            }

            Section("Family") {
                TextField("Family name", text: $family.name)
                    .disabled(!session.can(.manageSettings))
                    .onSubmit { try? context.save() }
                NavigationLink {
                    BaseCurrencySettingsView(family: family)
                } label: {
                    LabeledContent("Base currency", value: "\(family.baseCurrencyCode) - \(CurrencyNames.name(for: family.baseCurrencyCode))")
                }
                .disabled(!session.can(.manageSettings))
            }

            Section {
                NavigationLink {
                    LazyView(MembersView(family: family))
                } label: {
                    LabeledContent("Members", value: "\(members.count) of \(family.maxMembers)")
                }
            } header: {
                Text("People")
            } footer: {
                Text(LocalizedStringKey(session.isOwner
                     ? "Invite family members with their Apple Account. Everyone sees the same budget, synced through iCloud. Tap a member to allow them to manage budgets, categories or settings."
                     : ((session.currentMember?.grants.isEmpty ?? true)
                        ? "You are a member of this family. The owner manages members, categories and budgets."
                        : "You are a member of this family. The owner also allowed you to manage some settings - see Members.")))
            }

            BudgetSettingsSection(family: family)

            Section {
                NavigationLink {
                    LazyView(NotificationSettingsView())
                } label: {
                    Label("Notifications", systemImage: "bell.badge")
                }
                NavigationLink {
                    LazyView(AppLockSettingsView())
                } label: {
                    Label("Face ID lock", systemImage: "faceid")
                }
                NavigationLink {
                    LazyView(SiriHelpView())
                } label: {
                    Label("Siri & Shortcuts", systemImage: "waveform")
                }
            } header: {
                Text("Settings")
            }

            Section {
                ForEach(FamiloqSpace.allCases) { space in
                    HStack {
                        Image(systemName: space.icon)
                            .foregroundStyle(space.isAvailable ? Color.accentColor : Color.secondary)
                        Text(LocalizedStringKey(space.title))
                        Spacer()
                        Text(LocalizedStringKey(space.isAvailable ? "Active" : "Planned"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Familoq spaces")
            } footer: {
                Text("Familoq grows into your family's shared space. Budget, shopping list, reminders and calendar are available now; travel and health will follow.")
            }

            Section {
                NavigationLink {
                    LazyView(SensitiveGate { ExportBackupView(family: family) })
                } label: {
                    Label("Export & backup", systemImage: "square.and.arrow.up.on.square")
                }
                NavigationLink {
                    LazyView(SensitiveGate { StorageView(family: family) })
                } label: {
                    Label("Storage", systemImage: "internaldrive")
                }
                NavigationLink {
                    LazyView(BankImportView(family: family))
                } label: {
                    Label("Import bank statement", systemImage: "building.columns")
                }
            } header: {
                Text("Your data")
            }

            Section {
                SyncStatusRow()
            } header: {
                Text("iCloud")
            } footer: {
                Text("Your family's data is stored in your own iCloud and shared only with the members you invited. Familoq has no server of its own.")
            }

            Section("Privacy") {
                Label("No ads, no tracking, no analytics", systemImage: "hand.raised.fill")
                Label("Family data: this iPhone + your family's private iCloud area", systemImage: "lock.icloud.fill")
                Label("Exchange-rate lookups send only currency codes and a date", systemImage: "arrow.left.arrow.right")
            }
            .font(.footnote)

            if account.isAdmin {
                Section {
                    NavigationLink {
                        AdminView(backend: account.backend)
                    } label: {
                        Label("Invitations & accounts", systemImage: "person.badge.key.fill")
                    }
                } header: {
                    Text("Administration")
                } footer: {
                    Text("You are the Familoq administrator.")
                }
            }

            Section {
                Button(session.isOwner ? "Delete this family" : "Leave this family", role: .destructive) {
                    confirmRemoval = true
                }
            } footer: {
                Text(LocalizedStringKey(session.isOwner
                     ? "Deletes the family's budget, expenses and receipts for every member, on all devices and in iCloud."
                     : "Removes the family from your iPhone. The owner can invite you again."))
            }

            Section {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Role", value: session.currentMember?.role.displayName ?? "-")
                if let user = account.account?.userRecordName {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud user ID").font(.caption).foregroundStyle(.secondary)
                        Text(user)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text("About")
            } footer: {
                Text("The iCloud user ID is only needed once, when the administrator role is assigned in the CloudKit Console.")
            }
        }
        .navigationTitle("Family")
        .onDisappear { try? context.save() }
        .confirmationDialog(session.isOwner ? "Delete \(family.name) for everyone?" : "Leave \(family.name)?",
                            isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button(session.isOwner ? "Delete family" : "Leave family", role: .destructive) { removeFamily() }
        } message: {
            Text("This cannot be undone.")
        }
        .refreshable { await sync.refresh() }
    }

    /// "Owner: Martin" / "Your own family" - two families can share a name.
    private func ownerLine(for family: Family) -> String {
        let fid = family.id
        let members = (try? context.fetch(FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.familyID == fid }))) ?? []
        guard let owner = members.first(where: { $0.role == .owner }) else { return "Loading from iCloud…" }
        return owner.isCurrentUser ? "Your family" : "Owner: \(owner.displayName)"
    }

    private func removeFamily() {
        let id = family.id
        let context = context
        let session = session
        let sync = sync
        // Switch away first; delete once this screen is gone.
        session.familyWillBeRemoved(id, context: context)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            if sync.isRunning {
                sync.deleteOrLeave(familyID: id)
            } else {
                try? SyncRegistry.deleteAll(familyID: id, context: context)
                try? context.save()
            }
            session.refresh(context: context)
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        return "\(version) (\(build))"
    }
}

private struct SyncStatusRow: View {
    @EnvironmentObject private var sync: SyncCoordinator

    var body: some View {
        switch sync.status {
        case .off:
            Label(sync.isEnabled ? "Sync starts after activation" : "Sync off (demo)", systemImage: "icloud.slash")
        case .syncing:
            Label("Syncing…", systemImage: "arrow.triangle.2.circlepath.icloud")
        case .upToDate(let date):
            Label("Up to date · \(date.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.icloud")
        case .offline:
            Label("Offline - changes are sent when you are back online", systemImage: "icloud.slash")
        case .problem(let message):
            Label(LocalizedStringKey(message), systemImage: "exclamationmark.icloud")
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Members

struct MembersView: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var sync: SyncCoordinator
    @Query private var members: [FamilyMember]
    @State private var newName = ""
    @State private var inviteAddress = ""
    @State private var share: CKShare?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var justInvited: String?
    @State private var editing: MemberEditTarget?

    init(family: Family) {
        self.family = family
        let fid = family.id
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid }, sort: \FamilyMember.joinedAt)
    }

    private var active: [FamilyMember] { members.filter(\.isActive) }
    private var canAddMore: Bool { FamilyLimits.canAddMember(activeMemberCount: active.count, maxMembers: family.maxMembers) }

    /// People added to the family's iCloud share (except the owner).
    private var participants: [CKShare.Participant] {
        (share?.participants ?? []).filter { $0.role != .owner && $0.acceptanceStatus != .removed }
    }

    var body: some View {
        List {
            Section {
                ForEach(active) { member in
                    Button {
                        if canEdit(member) {
                            editing = MemberEditTarget(member: member, iCloudName: iCloudName(of: member))
                        }
                    } label: {
                        HStack {
                            Image(systemName: member.role == .owner ? "crown.fill" : (member.cloudUserRecordName.isEmpty ? "person" : "person.fill"))
                                .foregroundStyle(member.role == .owner ? Color.yellow : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(verbatim: member.displayName.isEmpty ? "-" : member.displayName)
                                        .foregroundStyle(.primary)
                                    if member.isCurrentUser {
                                        Text("(you)").foregroundStyle(.secondary)
                                    }
                                }
                                if member.role != .owner, !member.grants.isEmpty {
                                    Text(verbatim: member.grants.sorted { $0.rawValue < $1.rawValue }
                                        .map { String(localized: String.LocalizationValue($0.title)) }.joined(separator: " · "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(LocalizedStringKey(member.role.displayName)).font(.caption).foregroundStyle(.secondary)
                            if canEdit(member) {
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if session.can(.removeMembers) && member.role != .owner {
                            Button("Remove", role: .destructive) { remove(member) }
                        }
                    }
                }
            } footer: {
                Text("\(active.count) of \(family.maxMembers) members. Members add and edit their own expenses; the owner can allow a member more (tap the member). Tap your own name to change it.")
            }

            if session.can(.inviteMembers) {
                inviteSection
                if !participants.isEmpty {
                    Section("Invitations") {
                        ForEach(participants, id: \.self) { participant in
                            ParticipantRow(participant: participant)
                                .swipeActions {
                                    Button(participant.acceptanceStatus == .accepted ? "Remove" : "Withdraw", role: .destructive) {
                                        Task { await removeParticipant(participant) }
                                    }
                                }
                        }
                    }
                }

                Section {
                    HStack {
                        TextField("Name", text: $newName)
                        Button("Add") { addMember() }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || !canAddMore)
                    }
                } header: {
                    Text("Add a name without an account")
                } footer: {
                    Text("For tagging expenses of someone who does not use Familoq (e.g. a child).")
                }
            }

            if let errorMessage {
                Section { Text(LocalizedStringKey(errorMessage)).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Members")
        .sheet(item: $editing) { target in
            MemberEditSheet(target: target, canGrant: session.isOwner) { name, grants in
                save(target: target, name: name, grants: grants)
            }
        }
        .task { await loadShare() }
        .refreshable {
            await sync.refresh()
            await loadShare()
        }
    }

    @ViewBuilder
    private var inviteSection: some View {
        Section {
            if sync.isRunning {
                TextField("Apple Account e-mail or phone", text: $inviteAddress)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    Task { await invite() }
                } label: {
                    HStack {
                        Label("Invite to family", systemImage: "person.badge.plus")
                        if isWorking { Spacer(); ProgressView() }
                    }
                }
                .disabled(inviteAddress.trimmingCharacters(in: .whitespaces).count < 5 || !canAddMore || isWorking)

                if let url = share?.url, !participants.isEmpty {
                    ShareLink(item: url, subject: Text("Join our family in Familoq"),
                              message: Text("Join our family \"\(family.name)\" in Familoq: open this link on your iPhone (Familoq must be installed and activated).")) {
                        Label(justInvited.map { "Send the link to \($0)" } ?? "Send the invitation link again", systemImage: "square.and.arrow.up")
                    }
                }
            } else {
                Label("Inviting needs iCloud. Check that you are signed in to iCloud and online.", systemImage: "icloud.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Invite to family")
        } footer: {
            Text(LocalizedStringKey(canAddMore
                 ? "Enter the e-mail address or phone number of the person's Apple Account, then send them the link. Only people you invited can open it. They also need their own Familoq invitation to use the app."
                 : "This family has reached its member limit."))
        }
    }

    private func loadShare() async {
        guard sync.isRunning else { return }
        do {
            share = try await sync.existingShare(familyID: family.id)
        } catch {
            // Offline: the list of invitations just stays empty.
        }
        replacePlaceholderName()
    }

    /// Owner edits everyone; a member only their own name.
    private func canEdit(_ member: FamilyMember) -> Bool {
        session.isOwner || member.isCurrentUser
    }

    /// Name of the person's Apple Account, as iCloud shows it to the family
    /// (only known once the family is shared - no extra permission needed).
    private func iCloudName(of member: FamilyMember) -> String? {
        guard let share else { return nil }
        let participant: CKShare.Participant?
        if member.isCurrentUser {
            participant = share.currentUserParticipant
        } else if member.role == .owner {
            participant = share.owner
        } else if !member.cloudUserRecordName.isEmpty {
            participant = share.participants.first { $0.userIdentity.userRecordID?.recordName == member.cloudUserRecordName }
        } else {
            participant = nil
        }
        guard let components = participant?.userIdentity.nameComponents else { return nil }
        let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Older versions named the owner "Me". Use the iCloud name instead.
    private func replacePlaceholderName() {
        guard let me = active.first(where: \.isCurrentUser) else { return }
        let placeholders = ["", "me", "ich"]
        guard placeholders.contains(me.displayName.trimmingCharacters(in: .whitespaces).lowercased()),
              let name = iCloudName(of: me) else { return }
        me.displayName = name
        try? context.save()
        sync.scanNow()
    }

    private func save(target: MemberEditTarget, name: String, grants: Set<FamilyGrant>) {
        guard let member = members.first(where: { $0.id == target.id }), canEdit(member) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { member.displayName = trimmed }
        if session.isOwner, member.role != .owner { member.grants = grants }
        try? context.save()
        session.reloadCurrentMember(context: context)
        sync.scanNow()
    }

    private func invite() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        let address = inviteAddress.trimmingCharacters(in: .whitespaces)
        do {
            share = try await sync.invite(emailOrPhone: address, familyID: family.id, familyName: family.name,
                                          maxMembers: family.maxMembers, activeMembers: active.count)
            justInvited = address
            inviteAddress = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeParticipant(_ participant: CKShare.Participant) async {
        guard let share else { return }
        errorMessage = nil
        do {
            self.share = try await sync.remove(participant, from: share, familyID: family.id)
        } catch {
            errorMessage = "Could not remove: \(error.localizedDescription)"
        }
    }

    private func remove(_ member: FamilyMember) {
        guard session.can(.removeMembers), member.role != .owner else { return }
        member.isActive = false
        try? context.save()
        // A person with an account also loses access to the family's data.
        if !member.cloudUserRecordName.isEmpty,
           let participant = participants.first(where: { $0.userIdentity.userRecordID?.recordName == member.cloudUserRecordName }) {
            Task { await removeParticipant(participant) }
        }
    }

    private func addMember() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard session.can(.inviteMembers), !name.isEmpty, canAddMore else { return }
        context.insert(FamilyMember(familyID: family.id, displayName: name, role: .member))
        try? context.save()
        newName = ""
    }
}

struct MemberEditTarget: Identifiable {
    let id: UUID
    let name: String
    let isOwner: Bool
    let hasAccount: Bool
    let isCurrentUser: Bool
    let grants: Set<FamilyGrant>
    let iCloudName: String?

    init(member: FamilyMember, iCloudName: String?) {
        id = member.id
        name = member.displayName
        isOwner = member.role == .owner
        hasAccount = !member.cloudUserRecordName.isEmpty
        isCurrentUser = member.isCurrentUser
        grants = member.grants
        self.iCloudName = iCloudName
    }
}

/// Rename a person and (owner only) choose what a member may manage.
/// Owns its state and writes back once on Save.
private struct MemberEditSheet: View {
    let target: MemberEditTarget
    let canGrant: Bool
    let onSave: (String, Set<FamilyGrant>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var grants: Set<FamilyGrant>

    init(target: MemberEditTarget, canGrant: Bool, onSave: @escaping (String, Set<FamilyGrant>) -> Void) {
        self.target = target
        self.canGrant = canGrant
        self.onSave = onSave
        _name = State(initialValue: target.name)
        _grants = State(initialValue: target.grants)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    if let iCloudName = target.iCloudName, iCloudName != name {
                        Button {
                            name = iCloudName
                        } label: {
                            Label("Use iCloud name: \(iCloudName)", systemImage: "person.crop.circle")
                        }
                    }
                } header: {
                    Text("Name")
                } footer: {
                    Text("Shown to everyone in the family.")
                }

                if !target.isOwner && target.hasAccount {
                    Section {
                        ForEach(FamilyGrant.allCases, id: \.self) { grant in
                            Toggle(LocalizedStringKey(grant.title), isOn: Binding(
                                get: { grants.contains(grant) },
                                set: { on in if on { grants.insert(grant) } else { grants.remove(grant) } }))
                        }
                        .disabled(!canGrant)
                    } header: {
                        Text(canGrant ? "Allowed to manage" : "The owner allowed you to manage")
                    } footer: {
                        Text("Always: adding expenses and editing their own. Inviting and removing people stays with the owner.")
                    }
                }
            }
            .navigationTitle(target.isCurrentUser ? "Your name" : "Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, grants)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ParticipantRow: View {
    let participant: CKShare.Participant

    private var name: String {
        if let components = participant.userIdentity.nameComponents {
            let formatted = PersonNameComponentsFormatter().string(from: components)
            if !formatted.isEmpty { return formatted }
        }
        return participant.userIdentity.lookupInfo?.emailAddress
            ?? participant.userIdentity.lookupInfo?.phoneNumber
            ?? "Invited person"
    }

    var body: some View {
        HStack {
            Image(systemName: participant.acceptanceStatus == .accepted ? "checkmark.circle.fill" : "envelope")
                .foregroundStyle(participant.acceptanceStatus == .accepted ? Color.green : Color.orange)
            Text(name)
            Spacer()
            Text(LocalizedStringKey(participant.acceptanceStatus == .accepted ? "Joined" : "Invited"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
