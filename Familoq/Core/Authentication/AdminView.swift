import SwiftUI
import FamiloqCore

/// Administration of App Invitations - visible only to the iCloud account
/// that has the FamiloqAdmin role in the CloudKit Console.
@MainActor
final class AdminModel: ObservableObject {
    @Published private(set) var overview = AdminOverview(invitations: [], accounts: [], requests: [])
    @Published private(set) var isLoading = false
    @Published private(set) var newCodes: [String] = []
    @Published var errorMessage: String?

    let backend: AccessBackend

    init(backend: AccessBackend) {
        self.backend = backend
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            overview = try await backend.adminOverview()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(count: Int, days: Int, note: String) async {
        do {
            newCodes = try await backend.createInvitations(count: count, validityDays: days, note: note)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revoke(_ invitation: AdminInvitation) async {
        await perform { try await self.backend.revokeInvitation(codeHash: invitation.codeHash) }
    }

    func setRevoked(_ revoked: Bool, account: AdminAccount) async {
        await perform { try await self.backend.setUserRevoked(revoked, userRecordName: account.userRecordName) }
    }

    func markHandled(_ request: AdminRequest) async {
        await perform { try await self.backend.markRequestHandled(id: request.id) }
    }

    private func perform(_ action: @escaping () async throws -> Void) async {
        do {
            try await action()
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AdminView: View {
    @StateObject private var model: AdminModel
    @State private var count = 1
    @State private var days = AppInvitationRules.defaultValidityDays
    @State private var note = ""
    @State private var isCreating = false

    init(backend: AccessBackend) {
        _model = StateObject(wrappedValue: AdminModel(backend: backend))
    }

    var body: some View {
        List {
            Section {
                Stepper("Codes: \(count)", value: $count, in: 1...AppInvitationRules.maxCodesPerBatch)
                Stepper("Valid for \(days) days", value: $days, in: 1...365)
                TextField("Note, e.g. John & Sarah", text: $note)
                Button {
                    isCreating = true
                    Task {
                        await model.create(count: count, days: days, note: note.trimmingCharacters(in: .whitespaces))
                        note = ""
                        isCreating = false
                    }
                } label: {
                    Label("Create invitation codes", systemImage: "plus.circle.fill")
                }
                .disabled(isCreating)
            } header: {
                Text("New App Invitations")
            } footer: {
                Text("Each code activates Familoq for one iCloud account. Codes are shown only now - only a fingerprint is stored.")
            }

            if !model.newCodes.isEmpty {
                Section("New codes - share them now") {
                    ForEach(model.newCodes, id: \.self) { code in
                        HStack {
                            Text(code)
                                .font(.system(.title3, design: .monospaced).weight(.bold))
                                .textSelection(.enabled)
                            Spacer()
                            ShareLink(item: "Your invitation to Familoq: \(code)\nInstall Familoq, tap \"Enter Invitation Code\" and enter this code.") {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section("Invitations") {
                if model.overview.invitations.isEmpty {
                    Text("No invitations yet.").foregroundStyle(.secondary)
                }
                ForEach(model.overview.invitations) { invitation in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("…\(invitation.hint)").font(.body.monospaced())
                            if !invitation.note.isEmpty { Text(invitation.note) }
                            Spacer()
                            Text(label(for: invitation))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color(for: invitation))
                        }
                        Text(invitation.redeemedAt.map { "Activated \($0.formatted(date: .abbreviated, time: .shortened))" }
                             ?? "Valid until \(invitation.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        if invitation.redeemedBy == nil && invitation.status == .active {
                            Button("Revoke", role: .destructive) { Task { await model.revoke(invitation) } }
                        }
                    }
                }
            }

            Section {
                if model.overview.accounts.isEmpty {
                    Text("No activated accounts yet.").foregroundStyle(.secondary)
                }
                ForEach(model.overview.accounts) { account in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(account.invitationNote?.isEmpty == false ? account.invitationNote! : "…\(account.invitationHint ?? "")")
                            Spacer()
                            if account.isRevoked {
                                Text("Revoked").font(.caption.weight(.semibold)).foregroundStyle(.red)
                            }
                        }
                        Text("\(String(account.userRecordName.prefix(12)))… · \(account.activatedAt?.formatted(date: .abbreviated, time: .omitted) ?? "")")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        if account.isRevoked {
                            Button("Restore") { Task { await model.setRevoked(false, account: account) } }.tint(.green)
                        } else {
                            Button("Revoke", role: .destructive) { Task { await model.setRevoked(true, account: account) } }
                        }
                    }
                }
            } header: {
                Text("Activated accounts")
            } footer: {
                Text("Revoking locks Familoq on that person's iPhone at its next daily check. Their family data is not deleted.")
            }

            Section("Invitation requests") {
                let open = model.overview.requests.filter { !$0.handled }
                if open.isEmpty {
                    Text("No open requests.").foregroundStyle(.secondary)
                }
                ForEach(open) { request in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.name).font(.headline)
                        Text(request.contact).textSelection(.enabled)
                        if !request.message.isEmpty {
                            Text(request.message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Done") { Task { await model.markHandled(request) } }.tint(.green)
                    }
                }
            }

            if let error = model.errorMessage {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Administration")
        .overlay {
            if model.isLoading && model.overview.invitations.isEmpty {
                ProgressView()
            }
        }
        .refreshable { await model.reload() }
        .task { await model.reload() }
    }

    private func label(for invitation: AdminInvitation) -> String {
        if invitation.redeemedBy != nil { return "Used" }
        switch invitation.status {
        case .active: return "Open"
        case .expired: return "Expired"
        case .revoked: return "Revoked"
        case .notFound: return "Missing"
        }
    }

    private func color(for invitation: AdminInvitation) -> Color {
        if invitation.redeemedBy != nil { return .green }
        switch invitation.status {
        case .active: return .accentColor
        case .expired, .notFound: return .secondary
        case .revoked: return .red
        }
    }
}
