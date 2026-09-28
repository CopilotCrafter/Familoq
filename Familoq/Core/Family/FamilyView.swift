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
                    .disabled(!session.isOwner)
                    .onSubmit { try? context.save() }
                NavigationLink {
                    BaseCurrencySettingsView(family: family)
                } label: {
                    LabeledContent("Base currency", value: "\(family.baseCurrencyCode) - \(CurrencyNames.name(for: family.baseCurrencyCode))")
                }
                .disabled(!session.isOwner)
            }

            Section {
                NavigationLink {
                    MembersView(family: family)
                } label: {
                    LabeledContent("Members", value: "\(members.count) of \(family.maxMembers)")
                }
            } header: {
                Text("People")
            } footer: {
                Text(LocalizedStringKey(session.isOwner
                     ? "Invite family members with their Apple Account. Everyone sees the same budget, synced through iCloud."
                     : "You are a member of this family. The owner manages members, categories and budgets."))
            }

            BudgetSettingsSection(family: family)

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
                Text("Familoq grows into your family's shared space. Budget is available now; travel, health, plans, reminders and events will follow.")
            }

            Section {
                NavigationLink {
                    ExportBackupView(family: family)
                } label: {
                    Label("Export & backup", systemImage: "square.and.arrow.up.on.square")
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
                    HStack {
                        Image(systemName: member.role == .owner ? "crown.fill" : (member.cloudUserRecordName.isEmpty ? "person" : "person.fill"))
                            .foregroundStyle(member.role == .owner ? Color.yellow : Color.secondary)
                        Text(LocalizedStringKey(member.displayName))
                        if member.isCurrentUser {
                            Text("(you)").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(LocalizedStringKey(member.role.displayName)).font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        if session.can(.removeMembers) && member.role != .owner {
                            Button("Remove", role: .destructive) { remove(member) }
                        }
                    }
                }
            } footer: {
                Text("\(active.count) of \(family.maxMembers) members. Owners manage members, settings, categories and budgets; members add and edit their own expenses.")
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
        guard session.isOwner, sync.isRunning else { return }
        do {
            share = try await sync.existingShare(familyID: family.id)
        } catch {
            // Offline: the list of invitations just stays empty.
        }
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
