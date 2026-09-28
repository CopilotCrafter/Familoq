import SwiftUI
import SwiftData
import FamiloqCore

/// Shown after the App Invitation was redeemed and no family exists on this
/// device yet: create your own family, or join one you were invited to.
struct FamilySetupView: View {
    @EnvironmentObject private var account: AccountService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Welcome!")
                            .font(.title2.weight(.bold))
                        Text("Your invitation is active. Now set up your family space.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    NavigationLink {
                        CreateFamilyView(defaultOwnerName: "")
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Create our family").font(.headline)
                                Text("You become the owner and can invite up to 5 more members.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "house.fill") }
                    }
                    NavigationLink {
                        JoinFamilyView()
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Join a family").font(.headline)
                                Text("Open the invitation link your family's owner sent you.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "person.2.fill") }
                    }
                }
            }
            .navigationTitle("Your family")
        }
    }
}

struct CreateFamilyView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var sync: SyncCoordinator
    @State private var familyName = ""
    @State private var ownerName: String
    @State private var baseCurrency = CurrencyInfo.defaultBaseCurrency
    @State private var error: String?

    init(defaultOwnerName: String) {
        _ownerName = State(initialValue: defaultOwnerName)
    }

    var body: some View {
        Form {
            Section {
                TextField("Family name, e.g. Martin & Carol", text: $familyName)
                TextField("Your name", text: $ownerName)
                    .textContentType(.givenName)
            }
            Section {
                NavigationLink {
                    CurrencyPickerView(selection: $baseCurrency, title: "Base currency")
                } label: {
                    LabeledContent("Base currency", value: "\(baseCurrency) - \(CurrencyNames.name(for: baseCurrency))")
                }
            } footer: {
                Text("Budgets and totals use this currency. Expenses in other currencies are converted automatically. You can change it later.")
            }
            if let error {
                Section { Text(LocalizedStringKey(error)).foregroundStyle(.red) }
            }
            Section {
                Button("Create family") { create() }
                    .font(.headline)
                    .disabled(familyName.trimmingCharacters(in: .whitespaces).isEmpty || ownerName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("Create family")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func create() {
        do {
            try session.createFamily(
                name: familyName.trimmingCharacters(in: .whitespaces),
                ownerName: ownerName.trimmingCharacters(in: .whitespaces),
                baseCurrency: baseCurrency,
                cloudUserRecordName: account.account?.userRecordName ?? "",
                context: context
            )
            sync.scanNow()
        } catch {
            self.error = "Could not create the family: \(error.localizedDescription)"
        }
    }
}

/// Joining = opening the owner's iCloud invitation link on this iPhone.
struct JoinFamilyView: View {
    @EnvironmentObject private var sync: SyncCoordinator

    var body: some View {
        Form {
            Section {
                Label("Ask the family's owner to invite you: Family → Members → Invite, with the e-mail address or phone number of your Apple Account.", systemImage: "1.circle.fill")
                Label("Open the link they send you on this iPhone (Messages, Mail, WhatsApp …).", systemImage: "2.circle.fill")
                Label("Familoq opens and joins the family. Choose the name your family sees.", systemImage: "3.circle.fill")
            } header: {
                Text("How to join")
            } footer: {
                Text("The family's budget is shared between your iPhones through iCloud. Only people the owner invited can open the link.")
            }
            if case .joining = sync.joinState {
                Section { ProgressView("Joining the family…") }
            }
            Section {
                Button("I opened the link - check again") {
                    Task { await sync.refresh() }
                }
                .disabled(!sync.isRunning)
            }
        }
        .navigationTitle("Join a family")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// After joining: the name the family sees for this person.
struct JoinNameView: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var sync: SyncCoordinator
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Welcome to \(family.name.isEmpty ? "the family" : family.name)!")
                            .font(.title2.weight(.bold))
                        Text("You joined the family's shared budget.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    TextField("Your name", text: $name)
                        .textContentType(.givenName)
                } header: {
                    Text("What should your family call you?")
                }
                Section {
                    Button("Continue") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        sync.addMe(to: family.id, name: trimmed)
                        session.refresh(context: context)
                    }
                    .font(.headline)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Your family")
        }
    }
}
