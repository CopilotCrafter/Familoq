import SwiftUI
import FamiloqCore

/// First screen for anyone without access. There is deliberately NO
/// "Sign up", "Create account" or "Continue as guest".
struct OnboardingView: View {
    @State private var showAbout = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "house.and.flag.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text("Familoq")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("Your family's private space")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 12) {
                    NavigationLink {
                        EnterInvitationView()
                    } label: {
                        Text("Enter Invitation Code")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)

                    NavigationLink {
                        RequestInvitationView()
                    } label: {
                        Text("Request an Invitation")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)

                    NavigationLink {
                        RestoreAccessView()
                    } label: {
                        Text("Already activated? Restore access")
                            .font(.subheadline)
                    }
                    .padding(.top, 4)

                    Button("About Familoq") { showAbout = true }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
            .padding()
            .sheet(isPresented: $showAbout) { AboutFamiloqView() }
        }
    }
}

struct AboutFamiloqView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var account: AccountService
    @State private var userID: String?
    @State private var userIDError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Familoq is a private, invite-only space for families - starting with a shared budget: expenses, receipts, budgets and reports.")
                }
                Section("How access works") {
                    Label("You need a personal invitation code to use Familoq.", systemImage: "envelope.badge")
                    Label("Inside Familoq, each family is completely separate. Families never see each other's data.", systemImage: "lock.shield")
                    Label("A family owner invites their own members.", systemImage: "person.2")
                }
                Section("Privacy") {
                    Label("No ads, no tracking, no data selling.", systemImage: "hand.raised")
                    Label("Your financial data stays on your devices and in your own iCloud.", systemImage: "icloud")
                    Label("Uses your iCloud account - no extra password, no e-mail required.", systemImage: "icloud")
                }
                Section {
                    if let userID {
                        Text(userID)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    } else {
                        Text(LocalizedStringKey(userIDError ?? "Checking iCloud…"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Your iCloud user ID")
                } footer: {
                    Text("Only the Familoq administrator needs this once, to set up the admin role.")
                }
            }
            .task {
                do {
                    userID = try await account.backend.currentUserRecordName()
                } catch {
                    userIDError = error.localizedDescription
                }
            }
            .navigationTitle("About Familoq")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct EnterInvitationView: View {
    @EnvironmentObject private var account: AccountService
    @State private var code = ""
    @FocusState private var focused: Bool

    private var isWellFormed: Bool { InvitationCode.isWellFormed(code) }
    private var normalizedLength: Int { InvitationCode.normalize(code).count }

    var body: some View {
        Form {
            Section {
                TextField("XXXX-XXXX-XXXX", text: $code)
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onChange(of: code) { _, newValue in
                        let formatted = InvitationCode.format(String(InvitationCode.normalize(newValue).prefix(InvitationCode.length)))
                        if formatted != newValue { code = formatted }
                    }
                if normalizedLength == InvitationCode.length && !isWellFormed {
                    Label("This code has a typo - please check it.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            } header: {
                Text("Invitation code")
            } footer: {
                Text("You received this code from the Familoq administrator. It can be used once.")
            }

            Section {
                Button {
                    Task { await account.redeem(code: code) }
                } label: {
                    Text("Activate Familoq")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isWellFormed || account.isWorking)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text("The invitation is linked to the iCloud account on this iPhone, so a new iPhone or a reinstall with the same Apple ID restores access automatically.")
            }

            if account.isWorking {
                Section { ProgressView("Checking invitation…") }
            }
            if let message = account.errorMessage {
                Section { Text(LocalizedStringKey(message)).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Invitation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            account.errorMessage = nil
            focused = true
        }
    }
}

struct RestoreAccessView: View {
    @EnvironmentObject private var account: AccountService

    var body: some View {
        Form {
            Section {
                Text("If you already activated Familoq - for example before reinstalling or on your previous iPhone - make sure this iPhone is signed in to iCloud with the same Apple ID, then tap Continue.")
            }
            Section {
                Button {
                    Task { await account.restore() }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(account.isWorking)
                .listRowInsets(EdgeInsets())
            }
            if account.isWorking {
                Section { ProgressView("Checking iCloud…") }
            }
            if let message = account.errorMessage {
                Section { Text(LocalizedStringKey(message)).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Restore access")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { account.errorMessage = nil }
    }
}

struct RequestInvitationView: View {
    @EnvironmentObject private var account: AccountService
    @State private var name = ""
    @State private var contact = ""
    @State private var message = ""
    @State private var sent = false

    var body: some View {
        Form {
            if sent {
                Section {
                    Label("Request sent. You will receive an invitation code if your request is approved.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                Section {
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                    TextField("E-mail or phone", text: $contact)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Who you are / who invited you (optional)", text: $message, axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    Text("Familoq is invite-only. Your request goes only to the administrator and is used only to reply to you. Requires iCloud.")
                }
                Section {
                    Button("Send request") {
                        Task {
                            sent = await account.requestInvitation(
                                name: name.trimmingCharacters(in: .whitespaces),
                                contact: contact.trimmingCharacters(in: .whitespaces),
                                message: message
                            )
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).count < 2 || contact.trimmingCharacters(in: .whitespaces).count < 3 || account.isWorking)
                }
                if let error = account.errorMessage {
                    Section { Text(LocalizedStringKey(error)).foregroundStyle(.red) }
                }
            }
        }
        .navigationTitle("Request an invitation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { account.errorMessage = nil }
    }
}
