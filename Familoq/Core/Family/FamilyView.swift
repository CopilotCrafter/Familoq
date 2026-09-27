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

            Section("About") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Role", value: session.currentMember?.role.displayName ?? "-")
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
    @State private var newName = ""

    init(family: Family) {
        self.family = family
        let fid = family.id
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid }, sort: \FamilyMember.joinedAt)
    }

    private var active: [FamilyMember] { members.filter(\.isActive) }

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
                        if session.isOwner && member.role != .owner {
                            Button("Remove", role: .destructive) {
                                member.isActive = false
                                try? context.save()
                            }
                        }
                    }
                }
            } footer: {
                Text("Maximum \(family.maxMembers) members per family.")
            }

            if session.isOwner {
                Section("Add member") {
                    HStack {
                        TextField("Name", text: $newName)
                        Button("Add") { addMember() }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty
                                      || !FamilyLimits.canAddMember(activeMemberCount: active.count, maxMembers: family.maxMembers))
                    }
                    if !FamilyLimits.canAddMember(activeMemberCount: active.count, maxMembers: family.maxMembers) {
                        Text("This family has reached its member limit.").font(.footnote).foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("Members")
    }

    private func addMember() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, FamilyLimits.canAddMember(activeMemberCount: active.count, maxMembers: family.maxMembers) else { return }
        context.insert(FamilyMember(familyID: family.id, displayName: name, role: .member))
        try? context.save()
        newName = ""
    }
}
