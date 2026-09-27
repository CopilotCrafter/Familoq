import SwiftUI
import SwiftData
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
    @Query private var members: [FamilyMember]

    init(family: Family) {
        self.family = family
        let fid = family.id
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid && $0.isActive == true }, sort: \FamilyMember.joinedAt)
    }

    var body: some View {
        Form {
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
                Text("Invite-only accounts and real family invitations arrive in Phase 3. Until then, members are names for tagging expenses on this device.")
            }

            BudgetSettingsSection(family: family)

            Section {
                ForEach(FamiloqSpace.allCases) { space in
                    HStack {
                        Image(systemName: space.icon)
                            .foregroundStyle(space.isAvailable ? Color.accentColor : Color.secondary)
                        Text(space.title)
                        Spacer()
                        Text(space.isAvailable ? "Active" : "Planned")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Familoq spaces")
            } footer: {
                Text("Familoq grows into your family's shared space. Budget is available now; travel, health, plans, reminders and events will follow.")
            }

            Section("Privacy") {
                Label("No ads, no tracking, no analytics", systemImage: "hand.raised.fill")
                Label("Data stays on this iPhone (iCloud sync in Phase 4)", systemImage: "iphone")
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
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        return "\(version) (\(build))"
    }
}

// MARK: - Members

struct MembersView: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var members: [FamilyMember]
    @Query private var invitations: [FamilyInvitationRecord]
    @State private var newName = ""
    @State private var inviteNote = ""
    @State private var lastCreated: FamilyInvitationRecord?

    init(family: Family) {
        self.family = family
        let fid = family.id
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid }, sort: \FamilyMember.joinedAt)
        _invitations = Query(filter: #Predicate<FamilyInvitationRecord> { $0.familyID == fid }, sort: \FamilyInvitationRecord.createdAt, order: .reverse)
    }

    private var active: [FamilyMember] { members.filter(\.isActive) }
    private var canAddMore: Bool { FamilyLimits.canAddMember(activeMemberCount: active.count, maxMembers: family.maxMembers) }

    private var openInvitations: [FamilyInvitationRecord] {
        invitations.filter {
            FamilyInvitationRules.status(of: $0.terms, now: Date(), activeMembers: active.count, maxMembers: family.maxMembers) == .valid
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(active) { member in
                    HStack {
                        Image(systemName: member.role == .owner ? "crown.fill" : "person.fill")
                            .foregroundStyle(member.role == .owner ? Color.yellow : Color.secondary)
                        Text(member.displayName)
                        if member.isCurrentUser {
                            Text("(you)").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(member.role.displayName).font(.caption).foregroundStyle(.secondary)
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
                Section {
                    if let created = lastCreated {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(created.code)
                                .font(.system(.title2, design: .monospaced).weight(.bold))
                                .textSelection(.enabled)
                            Text("Valid until \(created.expiresAt.formatted(date: .abbreviated, time: .shortened)) · one person")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ShareLink(item: shareText(for: created)) {
                                Label("Share invitation", systemImage: "square.and.arrow.up")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    TextField("For whom? (optional, e.g. Carol)", text: $inviteNote)
                    Button {
                        createInvitation()
                    } label: {
                        Label("Create family invitation", systemImage: "person.badge.plus")
                    }
                    .disabled(!canAddMore)
                } header: {
                    Text("Invite to family")
                } footer: {
                    Text(canAddMore
                         ? "The person also needs their own Familoq invitation. Family invitations are valid for \(FamilyInvitationRules.defaultValidityDays) days and work once. Joining shares data via iCloud (next update)."
                         : "This family has reached its member limit.")
                }

                if !openInvitations.isEmpty {
                    Section("Open family invitations") {
                        ForEach(openInvitations) { invitation in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(invitation.code).font(.body.monospaced())
                                    Text("\(invitation.note.isEmpty ? "" : invitation.note + " · ")until \(invitation.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                ShareLink(item: shareText(for: invitation)) { Image(systemName: "square.and.arrow.up") }
                                    .buttonStyle(.borderless)
                            }
                            .swipeActions {
                                Button("Withdraw", role: .destructive) {
                                    invitation.isRevoked = true
                                    try? context.save()
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
        }
        .navigationTitle("Members")
    }

    private func shareText(for invitation: FamilyInvitationRecord) -> String {
        "Join our family \"\(family.name)\" in Familoq with this family code: \(invitation.code) (valid until \(invitation.expiresAt.formatted(date: .abbreviated, time: .omitted)))."
    }

    private func createInvitation() {
        guard session.can(.inviteMembers), canAddMore else { return }
        let expires = Calendar.current.date(byAdding: .day, value: FamilyInvitationRules.defaultValidityDays, to: Date()) ?? Date()
        let invitation = FamilyInvitationRecord(
            familyID: family.id,
            code: InvitationCode.generate(),
            expiresAt: expires,
            createdByMemberID: session.currentMember?.id,
            note: inviteNote.trimmingCharacters(in: .whitespaces)
        )
        context.insert(invitation)
        try? context.save()
        lastCreated = invitation
        inviteNote = ""
    }

    private func remove(_ member: FamilyMember) {
        guard session.can(.removeMembers), member.role != .owner else { return }
        member.isActive = false
        try? context.save()
    }

    private func addMember() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard session.can(.inviteMembers), !name.isEmpty, canAddMore else { return }
        context.insert(FamilyMember(familyID: family.id, displayName: name, role: .member))
        try? context.save()
        newName = ""
    }
}
