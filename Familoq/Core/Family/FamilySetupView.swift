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
                        Text("Welcome\(firstName.map { ", \($0)" } ?? "")!")
                            .font(.title2.weight(.bold))
                        Text("Your invitation is active. Now set up your family space.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    NavigationLink {
                        CreateFamilyView(defaultOwnerName: account.account?.displayName ?? "")
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
                                Text("Someone in your family sent you a family invitation.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "person.2.fill") }
                    }
                }
            }
            .navigationTitle("Your family")
        }
    }

    private var firstName: String? {
        account.account?.displayName?.split(separator: " ").first.map(String.init)
    }
}

struct CreateFamilyView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
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
                Section { Text(error).foregroundStyle(.red) }
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
                context: context
            )
        } catch {
            self.error = "Could not create the family: \(error.localizedDescription)"
        }
    }
}

/// Joining another person's family means receiving THEIR data, which needs
/// iCloud sharing (Phase 4). The code is validated now; joining completes
/// automatically once sync ships.
struct JoinFamilyView: View {
    @State private var code = ""
    @State private var checked = false

    private var isWellFormed: Bool { InvitationCode.isWellFormed(code) }

    var body: some View {
        Form {
            Section {
                TextField("XXXX-XXXX-XXXX", text: $code)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: code) { _, newValue in
                        let formatted = InvitationCode.format(String(InvitationCode.normalize(newValue).prefix(InvitationCode.length)))
                        if formatted != newValue { code = formatted }
                        checked = false
                    }
            } header: {
                Text("Family invitation code")
            } footer: {
                Text("This is the code from your family's owner - not your personal Familoq invitation.")
            }
            Section {
                Button("Join family") { checked = true }
                    .disabled(!isWellFormed)
            }
            if checked {
                Section {
                    Label {
                        Text("Joining a family shares its budget between your iPhones through iCloud. This arrives with the next Familoq update - keep this code, or ask the owner for a new one then. Until then you can create your own family.")
                    } icon: {
                        Image(systemName: "icloud.and.arrow.down").foregroundStyle(Color.accentColor)
                    }
                    .font(.subheadline)
                }
            }
        }
        .navigationTitle("Join a family")
        .navigationBarTitleDisplayMode(.inline)
    }
}
