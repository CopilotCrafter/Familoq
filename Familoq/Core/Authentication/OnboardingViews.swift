import SwiftUI
import AuthenticationServices
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
                        Text("Already invited? Sign in again")
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
                    Label("Sign in with Apple - your e-mail is not required.", systemImage: "apple.logo")
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

/// Reusable "Sign in with Apple" button that yields an `AppleCredential`.
struct AppleSignInButton: View {
    let label: SignInWithAppleButton.Label
    let onCredential: (AppleCredential) -> Void
    var onError: ((String) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var rawNonce = AppleSignIn.randomNonce()

    var body: some View {
        SignInWithAppleButton(label) { request in
            let nonce = AppleSignIn.randomNonce()
            rawNonce = nonce
            request.requestedScopes = [.fullName]
            request.nonce = AppleSignIn.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                if let credential = AppleSignIn.credential(from: authorization, rawNonce: rawNonce) {
                    onCredential(credential)
                } else {
                    onError?("Apple did not return a valid sign-in. Please try again.")
                }
            case .failure(let error):
                if (error as? ASAuthorizationError)?.code != .canceled {
                    onError?(error.localizedDescription)
                }
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 50)
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

            if isWellFormed {
                Section {
                    AppleSignInButton(label: .continue) { credential in
                        Task { await account.redeem(code: code, credential: credential) }
                    } onError: { message in
                        account.errorMessage = message
                    }
                    .disabled(account.isWorking)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Sign in with Apple links the invitation to your Apple ID, so you can restore access on a new iPhone. Familoq does not need your e-mail address.")
                }
            }

            if account.isWorking {
                Section { ProgressView("Checking invitation…") }
            }
            if let message = account.errorMessage {
                Section { Text(message).foregroundStyle(.red) }
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
                Text("If you already redeemed an invitation - for example before reinstalling Familoq or on your new iPhone - sign in with the same Apple ID.")
            }
            Section {
                AppleSignInButton(label: .signIn) { credential in
                    Task { await account.restore(credential: credential) }
                } onError: { message in
                    account.errorMessage = message
                }
                .disabled(account.isWorking)
                .listRowInsets(EdgeInsets())
            }
            if account.isWorking {
                Section { ProgressView("Signing in…") }
            }
            if let message = account.errorMessage {
                Section { Text(message).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Sign in again")
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
                    Text("Familoq is invite-only. Your request goes to the administrator and is used only to reply to you.")
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
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
        }
        .navigationTitle("Request an invitation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { account.errorMessage = nil }
    }
}
